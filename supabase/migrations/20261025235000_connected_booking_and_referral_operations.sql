-- Connect signed-in bookings to customer accounts and make both booking and
-- referral work continue through payment, completion and reward tracking.

alter table public.booking_requests
  add column if not exists accepted_at timestamptz,
  add column if not exists payment_ready_at timestamptz,
  add column if not exists completed_at timestamptz;

create or replace function public.auto_link_booking_customer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.customer_id is null then
    select p.id into new.customer_id
    from public.profiles p
    where (
      new.customer_email_normalized is not null
      and public.normalize_contact_email(p.account_email) = new.customer_email_normalized
    ) or (
      new.customer_phone_normalized is not null
      and public.normalize_contact_phone(p.phone_number) = new.customer_phone_normalized
    )
    order by case
      when new.customer_email_normalized is not null
       and public.normalize_contact_email(p.account_email) = new.customer_email_normalized
      then 0 else 1 end
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists auto_link_booking_customer on public.booking_requests;
create trigger auto_link_booking_customer
before insert or update of customer_email, customer_phone_number
on public.booking_requests
for each row execute function public.auto_link_booking_customer();

update public.booking_requests br
set customer_id = (
  select p.id as profile_id
  from public.profiles p
  where (
    br.customer_email_normalized is not null
    and public.normalize_contact_email(p.account_email) = br.customer_email_normalized
  ) or (
    br.customer_phone_normalized is not null
    and public.normalize_contact_phone(p.phone_number) = br.customer_phone_normalized
  )
  order by case
    when br.customer_email_normalized is not null
     and public.normalize_contact_email(p.account_email) = br.customer_email_normalized
    then 0 else 1 end
  limit 1
)
where br.customer_id is null
  and exists (
    select 1 from public.profiles p
    where (br.customer_email_normalized is not null
      and public.normalize_contact_email(p.account_email)=br.customer_email_normalized)
       or (br.customer_phone_normalized is not null
      and public.normalize_contact_phone(p.phone_number)=br.customer_phone_normalized)
  );

create or replace function public.apply_booking_lifecycle_times()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.booking_status in ('checking_availability','contacted','viewing_scheduled','reserved','confirmed','completed')
     and new.accepted_at is null then
    new.accepted_at := now();
  end if;
  if new.accepted_at is not null
     and new.owner_approval_status in ('not_required','approved')
     and new.payment_ready_at is null then
    new.payment_ready_at := now();
  end if;
  if new.booking_status = 'completed' and new.completed_at is null then
    new.completed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists apply_booking_lifecycle_times on public.booking_requests;
create trigger apply_booking_lifecycle_times
before insert or update of booking_status, owner_approval_status
on public.booking_requests
for each row execute function public.apply_booking_lifecycle_times();

create or replace function public.notify_customer_booking_progress()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_title text;
begin
  if new.customer_id is null then return new; end if;
  select title into v_title from public.listings where id = new.listing_id;
  if new.booking_status is distinct from old.booking_status then
    insert into public.notifications(user_id,booking_request_id,type,title,body,payload)
    values(new.customer_id,new.id,'booking_status_changed','Booking update',
      case
        when new.booking_status='checking_availability' then 'Your booking was accepted. Availability is being confirmed.'
        when new.booking_status='reserved' then 'Your booking is ready for payment.'
        when new.booking_status='confirmed' then 'Payment is confirmed and your booking is secured.'
        when new.booking_status='completed' then 'This booking has been completed.'
        when new.booking_status='rejected' then 'This booking could not be accepted.'
        when new.booking_status='cancelled' then 'This booking was cancelled.'
        else 'Your booking status is now '||replace(new.booking_status::text,'_',' ')||'.'
      end,
      jsonb_build_object('bookingId',new.id,'listingTitle',v_title,
        'status',new.booking_status,'paymentReady',new.payment_ready_at is not null));
  elsif new.payment_ready_at is distinct from old.payment_ready_at
    and new.payment_ready_at is not null then
    insert into public.notifications(user_id,booking_request_id,type,title,body,payload)
    values(new.customer_id,new.id,'booking_status_changed','Booking ready for payment',
      'The required approvals are complete. Open your booking and pay to secure it.',
      jsonb_build_object('bookingId',new.id,'listingTitle',v_title,'paymentReady',true));
  end if;
  return new;
end;
$$;

drop trigger if exists notify_customer_booking_progress on public.booking_requests;
create trigger notify_customer_booking_progress
after update of booking_status, payment_ready_at on public.booking_requests
for each row execute function public.notify_customer_booking_progress();

alter table public.rental_information_submissions
  add column if not exists linked_listing_id uuid references public.listings(id) on delete set null,
  add column if not exists marketing_started_at timestamptz,
  add column if not exists target_completion_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists outcome text,
  add column if not exists outcome_notes text;

alter table public.rental_information_submissions
  drop constraint if exists rental_information_outcome_check;
alter table public.rental_information_submissions
  add constraint rental_information_outcome_check
  check (outcome is null or outcome in ('rented','sold','owner_declined','duplicate','not_available','invalid','cancelled'));

create index if not exists information_marketing_deadline_idx
on public.rental_information_submissions(target_completion_at)
where status in ('published','verified','publication_review');

create or replace function public.manage_information_submission(
  p_submission_id uuid,
  p_status text,
  p_follow_up_note text,
  p_next_follow_up_at timestamptz default null,
  p_assigned_agent_id uuid default null,
  p_linked_listing_id uuid default null,
  p_eligibility_status text default null,
  p_outcome text default null
)
returns public.rental_information_submissions
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.rental_information_submissions;
begin
  if not (public.is_information_admin() or public.is_admin()) then
    raise exception 'Information administration permission required';
  end if;
  if p_status not in ('submitted','triage','duplicate_review','contacting_owner','field_verification','verified','publication_review','published','ineligible','closed') then
    raise exception 'Invalid information status';
  end if;
  if p_status='published' and p_linked_listing_id is null
     and not exists(select 1 from public.rental_information_submissions where id=p_submission_id and linked_listing_id is not null) then
    raise exception 'Link the published listing before marking this information published';
  end if;
  if p_status='closed' and nullif(trim(coalesce(p_outcome,'')),'') is null then
    raise exception 'Select a business outcome before closing this information';
  end if;

  update public.rental_information_submissions
  set status=p_status,
      assigned_information_admin_id=coalesce(assigned_information_admin_id,auth.uid()),
      assigned_agent_id=coalesce(p_assigned_agent_id,assigned_agent_id),
      linked_listing_id=coalesce(p_linked_listing_id,linked_listing_id),
      eligibility_status=coalesce(p_eligibility_status,eligibility_status),
      next_follow_up_at=p_next_follow_up_at,
      marketing_started_at=case when p_status='published'
        then coalesce(marketing_started_at,now()) else marketing_started_at end,
      target_completion_at=case when p_status='published'
        then coalesce(target_completion_at,now()+interval '30 days') else target_completion_at end,
      closed_at=case when p_status='closed' then now() else closed_at end,
      outcome=coalesce(nullif(trim(p_outcome),''),outcome),
      outcome_notes=case when p_status='closed' then nullif(trim(p_follow_up_note),'') else outcome_notes end,
      updated_at=now()
  where id=p_submission_id
  returning * into v_row;
  if v_row.id is null then raise exception 'Information submission not found'; end if;

  insert into public.information_follow_ups(submission_id,kind,summary,due_at,created_by)
  values(v_row.id,'status_change',coalesce(nullif(trim(p_follow_up_note),''),'Status changed to '||p_status),p_next_follow_up_at,auth.uid());
  return v_row;
end;
$$;

revoke all on function public.manage_information_submission(uuid,text,text,timestamptz,uuid,uuid,text,text) from public;
grant execute on function public.manage_information_submission(uuid,text,text,timestamptz,uuid,uuid,text,text) to authenticated;

create or replace function public.create_referral_reward_after_completion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_submission uuid;v_agreement public.referral_agreements;v_fee numeric;v_reward numeric;
begin
  if new.booking_status <> 'completed' or old.booking_status = 'completed' then return new; end if;
  select s.id into v_submission from public.rental_information_submissions s
  where s.linked_listing_id=new.listing_id and s.status in ('published','closed') limit 1;
  if v_submission is null then return new; end if;
  select * into v_agreement from public.referral_agreements where submission_id=v_submission;
  if v_agreement.id is null then return new; end if;
  select coalesce(sum(amount_tzs),0) into v_fee from public.booking_payment_transactions
  where booking_request_id=new.id and status='paid';
  v_reward:=case when v_agreement.reward_type='fixed' then v_agreement.fixed_amount_tzs
    else round(v_fee*v_agreement.percentage_rate/100.0,2) end;
  if v_reward is null or v_reward<=0 then return new; end if;
  insert into public.referral_rewards(agreement_id,booking_request_id,responsible_agent_id,eligible_fee_collected_tzs,reward_amount_tzs,status)
  values(v_agreement.id,new.id,new.agent_id,v_fee,v_reward,'pending_review')
  on conflict(agreement_id,booking_request_id) do nothing;
  update public.rental_information_submissions
  set status='closed',outcome=coalesce(outcome,'rented'),closed_at=coalesce(closed_at,now()),updated_at=now()
  where id=v_submission;
  return new;
end;
$$;

drop trigger if exists create_referral_reward_after_completion on public.booking_requests;
create trigger create_referral_reward_after_completion
after update of booking_status on public.booking_requests
for each row execute function public.create_referral_reward_after_completion();

