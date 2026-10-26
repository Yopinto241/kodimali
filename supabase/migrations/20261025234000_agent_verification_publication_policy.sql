-- Verified agents publish after the configured fee rule. Unverified agents
-- additionally require one admin approval for each listing.

alter table public.listings
  add column if not exists publication_review_status text not null default 'pending';

alter table public.listings
  drop constraint if exists listings_publication_review_status_check;
alter table public.listings
  add constraint listings_publication_review_status_check
  check (publication_review_status in ('pending','auto_approved','admin_approved','rejected'));

set local session_replication_role = replica;

update public.listings l
set publication_review_status = case
  when ag.verification_status = 'approved' and ag.account_status = 'active'
    then 'auto_approved'
  when l.status = 'active' then 'admin_approved'
  else 'pending'
end
from public.agents ag
where ag.id = l.agent_id;

set local session_replication_role = origin;

create or replace function public.prepare_listing_publication_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.agents ag
    where ag.id = new.agent_id
      and ag.verification_status = 'approved'
      and ag.account_status = 'active'
  ) then
    if new.publication_review_status in ('pending','rejected') then
      new.publication_review_status := 'auto_approved';
    end if;
  elsif tg_op = 'INSERT' or new.agent_id is distinct from old.agent_id then
    new.publication_review_status := 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists prepare_listing_publication_review on public.listings;
create trigger prepare_listing_publication_review
before insert or update of agent_id on public.listings
for each row execute function public.prepare_listing_publication_review();

create or replace function public.release_listings_after_agent_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_listing record;
begin
  if new.verification_status = 'approved' and new.account_status = 'active'
    and (old.verification_status is distinct from 'approved'
      or old.account_status is distinct from 'active') then
    update public.listings
    set publication_review_status = 'auto_approved'
    where agent_id = new.id
      and publication_review_status in ('pending','rejected');

    for v_listing in
      select id from public.listings
      where agent_id = new.id and status = 'inactive'
        and removed_from_market_at is null and removed_reason is null
    loop
      perform public.release_agent_listing_if_eligible(v_listing.id);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists release_listings_after_agent_verification on public.agents;
create trigger release_listings_after_agent_verification
after update of verification_status, account_status on public.agents
for each row execute function public.release_listings_after_agent_verification();

create or replace function public.release_agent_listing_if_eligible(p_listing_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_changed_count integer := 0;
begin
  update public.listings l
  set status = 'active'::public.listing_status,
      publication_requested = false,
      removed_from_market_at = null,
      removed_reason = null,
      published_at = coalesce(l.published_at, timezone('utc', now()))
  from public.agents ag
  where l.id = p_listing_id
    and ag.id = l.agent_id
    and l.status = 'inactive'::public.listing_status
    and l.removed_from_market_at is null
    and l.removed_reason is null
    and public.listing_has_publishable_media(l.id)
    and (
      (ag.verification_status = 'approved' and ag.account_status = 'active')
      or l.publication_review_status = 'admin_approved'
    )
    and (
      not public.agent_listing_payments_enabled()
      or exists (
        select 1 from public.agent_listing_payments p
        where p.listing_id = l.id
          and p.agent_id = l.agent_id
          and p.payment_status = 'paid'
      )
    );
  get diagnostics v_changed_count = row_count;
  return v_changed_count > 0;
end;
$$;

revoke all on function public.release_agent_listing_if_eligible(uuid) from public;
grant execute on function public.release_agent_listing_if_eligible(uuid) to service_role;

create or replace function public.admin_set_listing_marketplace_status(
  p_listing_id uuid,
  p_status public.listing_status,
  p_availability_status public.availability_status default 'available',
  p_removed_reason text default null,
  p_moderation_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing public.listings%rowtype;
  v_image_id uuid;
  v_payment_required boolean;
  v_payment_satisfied boolean;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;

  select * into v_listing from public.listings
  where id = p_listing_id for update;
  if not found then
    raise exception 'Listing not found.' using errcode = 'P0002';
  end if;

  if p_status = 'active'::public.listing_status then
    select id into v_image_id
    from public.listing_media
    where listing_id = p_listing_id and media_type::text = 'image'
    order by is_cover desc, display_order asc, created_at asc
    limit 1;
    if v_image_id is null then
      raise exception 'Upload at least one image before activating this listing.';
    end if;

    update public.listing_media set is_cover = (id = v_image_id)
    where listing_id = p_listing_id;

    v_payment_required := public.agent_listing_payments_enabled();
    v_payment_satisfied := not v_payment_required or exists (
      select 1 from public.agent_listing_payments p
      where p.listing_id = p_listing_id
        and p.agent_id = v_listing.agent_id
        and p.payment_status = 'paid'
    );

    update public.listings
    set publication_review_status = 'admin_approved',
        status = case when v_payment_satisfied
          then 'active'::public.listing_status
          else 'inactive'::public.listing_status end,
        availability_status = coalesce(p_availability_status, 'available'::public.availability_status),
        publication_requested = not v_payment_satisfied,
        removed_from_market_at = null,
        removed_reason = null,
        published_at = case when v_payment_satisfied
          then timezone('utc', now()) else published_at end
    where id = p_listing_id
    returning * into v_listing;
  else
    if p_removed_reason is not null
      and p_removed_reason not in ('admin_removed', 'suspended', 'rented') then
      raise exception 'Invalid admin removal reason.';
    end if;
    update public.listings
    set status = p_status,
        availability_status = case
          when p_removed_reason = 'rented' then 'rented'::public.availability_status
          else coalesce(p_availability_status, availability_status)
        end,
        publication_requested = false,
        removed_from_market_at = timezone('utc', now()),
        removed_reason = coalesce(p_removed_reason, 'admin_removed')
    where id = p_listing_id
    returning * into v_listing;
  end if;

  insert into public.audit_logs(actor_id, action, target_table, target_id, metadata)
  values (auth.uid(), 'update_listing_marketplace_status', 'listings', p_listing_id,
    jsonb_build_object('status', v_listing.status,
      'requestedStatus', p_status,
      'reviewStatus', v_listing.publication_review_status,
      'paymentRequired', coalesce(v_payment_required, false),
      'paymentSatisfied', coalesce(v_payment_satisfied, true),
      'removedReason', p_removed_reason,
      'moderationNote', p_moderation_note));

  return jsonb_build_object(
    'success', true,
    'listingId', v_listing.id,
    'status', v_listing.status,
    'availabilityStatus', v_listing.availability_status,
    'reviewStatus', v_listing.publication_review_status,
    'paymentRequired', coalesce(v_payment_required, false),
    'paymentSatisfied', coalesce(v_payment_satisfied, true),
    'message', case
      when p_status = 'active' and not coalesce(v_payment_satisfied, true)
        then 'Listing approved. Agent payment is still required before publication.'
      when p_status = 'active' then 'Listing approved and activated.'
      else 'Listing marketplace status updated.'
    end
  );
end;
$$;

revoke all on function public.admin_set_listing_marketplace_status(uuid, public.listing_status, public.availability_status, text, text) from public, anon;
grant execute on function public.admin_set_listing_marketplace_status(uuid, public.listing_status, public.availability_status, text, text) to authenticated, service_role;

drop function if exists public.get_agent_listing_publication_mode();
create function public.get_agent_listing_publication_mode()
returns table(
  payment_required boolean,
  amount_tzs integer,
  agent_verified boolean,
  admin_approval_required boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    public.agent_listing_payments_enabled(),
    case when public.agent_listing_payments_enabled() then
      coalesce((
        select p.publication_fee_tzs
        from public.agent_subscriptions s
        join public.agent_subscription_plans p on p.id = s.plan_id
        where s.agent_id = ag.id and s.status = 'active'
          and (s.expires_at is null or s.expires_at > now())
        limit 1
      ), 1000)
    else 0 end,
    coalesce(ag.verification_status = 'approved' and ag.account_status = 'active', false),
    not coalesce(ag.verification_status = 'approved' and ag.account_status = 'active', false)
  from (select 1) seed
  left join public.agents ag on ag.profile_id = auth.uid()
  limit 1;
$$;

revoke all on function public.get_agent_listing_publication_mode() from public;
grant execute on function public.get_agent_listing_publication_mode() to authenticated;

