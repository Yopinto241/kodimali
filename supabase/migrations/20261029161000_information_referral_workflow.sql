-- Separate private lead review from finance payout controls.
alter table public.referral_agreements
 add column contributor_accepted_at timestamptz,
 add column contributor_accepted_by uuid references public.profiles(id);

revoke insert,update,delete on public.rental_information_submissions,public.referral_agreements,public.referral_rewards,public.referral_payouts from authenticated,anon;
drop policy if exists agreements_admin_manage on public.referral_agreements;
drop policy if exists rewards_admin_manage on public.referral_rewards;
create policy referral_agreements_finance_read on public.referral_agreements for select to authenticated
 using(public.has_admin_permission('payments.manage'));
create policy referral_rewards_finance_read on public.referral_rewards for select to authenticated
 using(public.has_admin_permission('payments.manage'));
create policy referral_payouts_finance_read on public.referral_payouts for select to authenticated
 using(public.has_admin_permission('payments.manage'));

create or replace function public.set_information_referral_terms(
 p_submission_id uuid,p_reward_type text,p_amount numeric,p_terms text
) returns public.referral_agreements language plpgsql security definer set search_path=public as $$
declare s public.rental_information_submissions; r public.referral_agreements;
begin
 if not public.has_admin_permission('referrals.manage') then raise exception 'Referral administration permission required' using errcode='42501'; end if;
 select * into s from public.rental_information_submissions where id=p_submission_id for update;
 if s.id is null then raise exception 'Submission not found'; end if;
 if s.eligibility_status='ineligible' or s.status='ineligible' then raise exception 'This submission is not eligible for referral terms'; end if;
 if p_reward_type not in ('fixed','percentage') or p_amount is null or p_amount<=0 or (p_reward_type='percentage' and p_amount>100)
    or length(trim(coalesce(p_terms,'')))<10 then raise exception 'Provide valid reward terms and a positive amount or percentage'; end if;
 select * into r from public.referral_agreements where submission_id=s.id for update;
 if r.id is not null and (r.contributor_accepted_at is not null or exists(select 1 from public.referral_rewards where agreement_id=r.id)) then
   raise exception 'Accepted or rewarded terms cannot be changed';
 end if;
 insert into public.referral_agreements(submission_id,reward_type,fixed_amount_tzs,percentage_rate,terms,agreed_by)
 values(s.id,p_reward_type,case when p_reward_type='fixed' then p_amount end,
   case when p_reward_type='percentage' then p_amount end,trim(p_terms),auth.uid())
 on conflict(submission_id) do update set reward_type=excluded.reward_type,fixed_amount_tzs=excluded.fixed_amount_tzs,
   percentage_rate=excluded.percentage_rate,terms=excluded.terms,terms_version=public.referral_agreements.terms_version+1,
   agreed_by=auth.uid(),agreed_at=now()
 returning * into r;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
 values(auth.uid(),'information_referral_terms_recorded','referral_agreements',r.id,jsonb_build_object('submission_id',s.id,'version',r.terms_version));
 insert into public.notifications(user_id,type,title,body,payload)
 values(s.contributor_id,'announcement','Masharti ya zawadi yako','Soma na ukubali masharti ya zawadi kwa taarifa '||s.reference||'.',jsonb_build_object('submission_id',s.id,'route','/account?section=information'));
 return r;
end $$;

create or replace function public.referral_collected_service_fee(p_booking_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select case when exists(select 1 from public.payment_intents where resource_type='booking_request' and resource_id=p_booking_id and product='booking_service_fee')
 then coalesce((select sum(amount_minor) from public.payment_intents where resource_type='booking_request' and resource_id=p_booking_id and product='booking_service_fee' and status='verified_paid' and verified_at is not null),0)
 else coalesce((select sum(amount_tzs) from public.booking_payment_transactions where booking_request_id=p_booking_id and kind='service_fee' and status='paid' and verified_at is not null),0) end
$$;

create or replace function public.refresh_information_referral_reward(p_booking_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare b public.booking_requests; s public.rental_information_submissions; a public.referral_agreements; fee numeric; amount numeric;
begin
 select * into b from public.booking_requests where id=p_booking_id;
 if b.id is null or b.booking_status<>'completed' then return; end if;
 select lead.* into s from public.rental_information_submissions lead
 where lead.linked_listing_id=b.listing_id and lead.status in ('published','closed') and lead.eligibility_status in ('eligible','paid')
   and (lead.outcome is null or lead.outcome in ('rented','sold'))
 order by lead.submitted_at limit 1;
 if s.id is null then return; end if;
 select * into a from public.referral_agreements where submission_id=s.id;
 if a.id is null or a.contributor_accepted_by is distinct from s.contributor_id or a.contributor_accepted_at is null then return; end if;
 fee:=public.referral_collected_service_fee(b.id);
 if fee<=0 then return; end if;
 amount:=case when a.reward_type='fixed' then a.fixed_amount_tzs else round(fee*a.percentage_rate/100,2) end;
 if amount is null or amount<=0 then return; end if;
 insert into public.referral_rewards(agreement_id,booking_request_id,responsible_agent_id,eligible_fee_collected_tzs,reward_amount_tzs,status)
 values(a.id,b.id,b.agent_id,fee,amount,'pending_review')
 on conflict(agreement_id,booking_request_id) do update
 set eligible_fee_collected_tzs=excluded.eligible_fee_collected_tzs,reward_amount_tzs=excluded.reward_amount_tzs,
   status=case when public.referral_rewards.reward_amount_tzs<>excluded.reward_amount_tzs then 'pending_review' else public.referral_rewards.status end,
   approved_by=case when public.referral_rewards.reward_amount_tzs<>excluded.reward_amount_tzs then null else public.referral_rewards.approved_by end,
   approved_at=case when public.referral_rewards.reward_amount_tzs<>excluded.reward_amount_tzs then null else public.referral_rewards.approved_at end,updated_at=now()
 where public.referral_rewards.status not in ('paid','rejected');
 update public.rental_information_submissions set status='closed',outcome=coalesce(outcome,'rented'),closed_at=coalesce(closed_at,now()) where id=s.id;
 if s.eligibility_status='paid' and exists(select 1 from public.referral_rewards where agreement_id=a.id and status not in ('paid','rejected')) then
   update public.rental_information_submissions set eligibility_status='eligible' where id=s.id;
 end if;
end $$;

create or replace function public.accept_information_referral_terms(p_agreement_id uuid,p_terms_version integer)
returns public.referral_agreements language plpgsql security definer set search_path=public as $$
declare a public.referral_agreements; b record;
begin
 select agreement.* into a from public.referral_agreements agreement
 join public.rental_information_submissions s on s.id=agreement.submission_id
 where agreement.id=p_agreement_id and s.contributor_id=auth.uid() for update of agreement;
 if a.id is null then raise exception 'Your referral agreement was not found' using errcode='42501'; end if;
 if a.terms_version<>p_terms_version then raise exception 'Terms changed. Refresh and read the current version'; end if;
 update public.referral_agreements set contributor_accepted_at=coalesce(contributor_accepted_at,now()),contributor_accepted_by=auth.uid()
 where id=a.id returning * into a;
 for b in select br.id from public.booking_requests br join public.rental_information_submissions s on s.linked_listing_id=br.listing_id
 where s.id=a.submission_id and br.booking_status='completed' loop perform public.refresh_information_referral_reward(b.id); end loop;
 return a;
end $$;

create or replace function public.create_referral_reward_after_completion()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.booking_status='completed' then perform public.refresh_information_referral_reward(new.id); end if;
 return new;
end $$;
create or replace function public.refresh_referral_reward_after_payment()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.resource_type='booking_request' and new.product='booking_service_fee' then perform public.refresh_information_referral_reward(new.resource_id); end if;
 return new;
end $$;
create or replace function public.refresh_referral_reward_after_legacy_payment()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.kind='service_fee' then perform public.refresh_information_referral_reward(new.booking_request_id); end if;
 return new;
end $$;
create trigger referral_reward_after_verified_intent after insert or update on public.payment_intents
for each row execute function public.refresh_referral_reward_after_payment();
create trigger referral_reward_after_verified_legacy_payment after insert or update on public.booking_payment_transactions
for each row execute function public.refresh_referral_reward_after_legacy_payment();

create or replace function public.review_information_referral_reward(p_reward_id uuid,p_action text,p_note text)
returns public.referral_rewards language plpgsql security definer set search_path=public as $$
declare r public.referral_rewards; a public.referral_agreements; s public.rental_information_submissions; fee numeric;
begin
 if not public.has_admin_permission('payments.manage') then raise exception 'Finance permission required' using errcode='42501'; end if;
 if p_action not in ('approved','on_hold','rejected') or length(trim(coalesce(p_note,'')))<5 then raise exception 'Choose a valid review action and explain the decision'; end if;
 select * into r from public.referral_rewards where id=p_reward_id for update;
 if r.id is null or r.status in ('paid','rejected') then raise exception 'This reward cannot be reviewed'; end if;
 if p_action='approved' then
   select * into a from public.referral_agreements where id=r.agreement_id;
   select * into s from public.rental_information_submissions where id=a.submission_id;
   fee:=public.referral_collected_service_fee(r.booking_request_id);
   if a.contributor_accepted_at is null or s.eligibility_status not in ('eligible','paid') or (s.outcome is not null and s.outcome not in ('rented','sold')) or fee<=0
      or not exists(select 1 from public.booking_requests where id=r.booking_request_id and booking_status='completed') then
     raise exception 'Accepted terms, eligible information, completed booking and verified service fee are required';
   end if;
   if r.reward_amount_tzs is distinct from (case when a.reward_type='fixed' then a.fixed_amount_tzs else round(fee*a.percentage_rate/100,2) end) then
     raise exception 'The reward basis changed. Refresh the reward before approval';
   end if;
   if exists(select 1 from public.booking_disputes where booking_request_id=r.booking_request_id and status in ('open','investigating'))
     or exists(select 1 from public.refund_obligations where booking_request_id=r.booking_request_id and status not in ('declined','rejected','cancelled')) then
     raise exception 'A dispute or refund blocks reward approval';
   end if;
 end if;
 update public.referral_rewards set status=p_action,approved_by=case when p_action='approved' then auth.uid() end,
 approved_at=case when p_action='approved' then now() end,updated_at=now() where id=r.id returning * into r;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
 values(auth.uid(),'information_referral_reward_reviewed','referral_rewards',r.id,jsonb_build_object('status',p_action,'note',trim(p_note)));
 return r;
end $$;

create or replace function public.record_referral_payout(p_reward_id uuid,p_transaction_reference text,p_payment_method text,p_notes text default null)
returns public.referral_payouts language plpgsql security definer set search_path=public as $$
declare r public.referral_rewards; result public.referral_payouts; a public.referral_agreements; fee numeric;
begin
 if not public.has_admin_permission('payments.manage') then raise exception 'Finance permission required' using errcode='42501'; end if;
 if length(trim(coalesce(p_transaction_reference,'')))<3 or length(trim(coalesce(p_payment_method,'')))<2 then raise exception 'Provide the completed payment reference and method'; end if;
 select * into r from public.referral_rewards where id=p_reward_id for update;
 if r.id is null then raise exception 'Reward not found'; end if;
 select * into result from public.referral_payouts where reward_id=r.id;
 if result.id is not null then
   if result.transaction_reference=trim(p_transaction_reference) and result.payment_method=trim(p_payment_method) then return result; end if;
   raise exception 'This reward already has a different recorded payout';
 end if;
 if r.status<>'approved' then raise exception 'Finance must approve this reward before recording payment'; end if;
 select * into a from public.referral_agreements where id=r.agreement_id;
 fee:=public.referral_collected_service_fee(r.booking_request_id);
 if fee<=0 or a.contributor_accepted_at is null or not exists(
   select 1 from public.rental_information_submissions where id=a.submission_id and eligibility_status in ('eligible','paid') and (outcome is null or outcome in ('rented','sold'))
 ) or r.reward_amount_tzs is distinct from
   (case when a.reward_type='fixed' then a.fixed_amount_tzs else round(fee*a.percentage_rate/100,2) end)
   or not exists(select 1 from public.booking_requests where id=r.booking_request_id and booking_status='completed') then
   raise exception 'The verified reward basis is no longer valid';
 end if;
 if exists(select 1 from public.booking_disputes where booking_request_id=r.booking_request_id and status in ('open','investigating'))
   or exists(select 1 from public.refund_obligations where booking_request_id=r.booking_request_id and status not in ('declined','rejected','cancelled')) then
   raise exception 'A dispute or refund blocks payout recording';
 end if;
 insert into public.referral_payouts(reward_id,amount_tzs,transaction_reference,payment_method,paid_by,notes)
 values(r.id,r.reward_amount_tzs,trim(p_transaction_reference),trim(p_payment_method),auth.uid(),nullif(trim(p_notes),'')) returning * into result;
 update public.referral_rewards set status='paid',updated_at=now() where id=r.id;
 update public.rental_information_submissions s set eligibility_status=case when exists(
   select 1 from public.referral_rewards other where other.agreement_id=a.id and other.status not in ('paid','rejected')
 ) then 'eligible' else 'paid' end where s.id=a.submission_id;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
 values(auth.uid(),'information_referral_payout_recorded','referral_payouts',result.id,jsonb_build_object('reward_id',r.id,'amount_tzs',r.reward_amount_tzs));
 return result;
end $$;

revoke all on function public.referral_collected_service_fee(uuid),public.refresh_information_referral_reward(uuid),public.refresh_referral_reward_after_payment(),public.refresh_referral_reward_after_legacy_payment() from public,anon,authenticated;
revoke all on function public.set_information_referral_terms(uuid,text,numeric,text),public.accept_information_referral_terms(uuid,integer),public.review_information_referral_reward(uuid,text,text) from public,anon;
grant execute on function public.set_information_referral_terms(uuid,text,numeric,text),public.accept_information_referral_terms(uuid,integer),public.review_information_referral_reward(uuid,text,text) to authenticated;

create or replace function public.get_information_finance_rewards()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.has_admin_permission('payments.manage') then raise exception 'Finance permission required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(row_data order by created_at desc) from (
   select r.created_at,jsonb_build_object('id',r.id,'status',r.status,'reward_amount_tzs',r.reward_amount_tzs,
     'eligible_fee_collected_tzs',r.eligible_fee_collected_tzs,'booking_request_id',r.booking_request_id,
     'submission_reference',s.reference,'contributor_name',p.full_name,'contributor_phone',p.phone_number,
     'contributor_email',p.account_email,'payout',(select to_jsonb(payout) from public.referral_payouts payout where payout.reward_id=r.id)) row_data
   from public.referral_rewards r join public.referral_agreements a on a.id=r.agreement_id
   join public.rental_information_submissions s on s.id=a.submission_id join public.profiles p on p.id=s.contributor_id
   order by r.created_at desc limit 200
 ) rows),'[]'::jsonb);
end $$;
revoke all on function public.get_information_finance_rewards() from public,anon;
grant execute on function public.get_information_finance_rewards() to authenticated;

create or replace function public.notify_information_workflow()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='INSERT' then
   insert into public.notifications(user_id,type,title,body,payload)
   select distinct a.user_id,'announcement'::public.notification_type,'New private information submission',new.reference||' is ready for verification.',jsonb_build_object('submission_id',new.id,'route','/admin')
   from public.admin_role_assignments a join public.admin_role_definitions r on r.id=a.role_id
   where r.is_active and (r.permissions ? 'information.manage' or r.permissions ? '*');
 elsif new.status is distinct from old.status or new.eligibility_status is distinct from old.eligibility_status then
   insert into public.notifications(user_id,type,title,body,payload)
   values(new.contributor_id,'announcement','Taarifa yako imepata hatua mpya',new.reference||': '||replace(new.status,'_',' ')||'. Angalia taarifa na zawadi kwenye akaunti yako.',jsonb_build_object('submission_id',new.id,'route','/account?section=information'));
 end if;
 return new;
end $$;
revoke all on function public.notify_information_workflow() from public,anon,authenticated;
create trigger notify_information_workflow after insert or update of status,eligibility_status on public.rental_information_submissions
for each row execute function public.notify_information_workflow();
CREATE OR REPLACE FUNCTION public.manage_information_submission(p_submission_id uuid, p_status text, p_follow_up_note text, p_next_follow_up_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_assigned_agent_id uuid DEFAULT NULL::uuid, p_linked_listing_id uuid DEFAULT NULL::uuid, p_eligibility_status text DEFAULT NULL::text, p_outcome text DEFAULT NULL::text)
 RETURNS rental_information_submissions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_row public.rental_information_submissions; v_listing public.listings;
begin
  if not public.is_information_admin() then
    raise exception 'Information administration permission required';
  end if;
  select * into v_row from public.rental_information_submissions where id=p_submission_id for update;
  if v_row.id is null then raise exception 'Information submission not found'; end if;
  if p_eligibility_status='paid' and v_row.eligibility_status<>'paid' then
    raise exception 'Paid status requires a recorded finance payout';
  end if;
  if p_assigned_agent_id is not null and not exists(select 1 from public.agents where id=p_assigned_agent_id and account_status='active' and verification_status='approved') then
    raise exception 'Choose an active verified agent';
  end if;
  if coalesce(p_linked_listing_id,v_row.linked_listing_id) is not null then
    select * into v_listing from public.listings where id=coalesce(p_linked_listing_id,v_row.linked_listing_id) for update;
    if v_listing.id is null then raise exception 'Linked listing not found'; end if;
    if p_status='published' and not public.is_listing_public(v_listing.id) then raise exception 'The linked listing is not published'; end if;
    if coalesce(p_assigned_agent_id,v_row.assigned_agent_id) is not null and coalesce(p_assigned_agent_id,v_row.assigned_agent_id)<>v_listing.agent_id then
      raise exception 'The assigned agent must manage the linked listing';
    end if;
    if exists(select 1 from public.rental_information_submissions other where other.linked_listing_id=v_listing.id and other.id<>v_row.id and other.eligibility_status<>'ineligible' and other.status<>'ineligible') then
      raise exception 'This listing is already linked to another information submission';
    end if;
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
      linked_asset_id=coalesce(v_listing.asset_id,linked_asset_id),

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
$function$
;
