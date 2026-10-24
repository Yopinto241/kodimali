-- A listing can be removed permanently without erasing append-only customer,
-- booking, payment, or conversation history.

alter table public.booking_requests
  drop constraint if exists booking_requests_listing_id_fkey;

alter table public.booking_requests
  alter column listing_id drop not null;

alter table public.booking_requests
  add constraint booking_requests_listing_id_fkey
  foreign key (listing_id) references public.listings(id) on delete set null;

create or replace function public.admin_permanently_delete_listing(
  p_listing_id uuid,
  p_confirm_delete_with_inquiries boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inquiry_count integer;
  v_media_paths jsonb;
  v_title text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;

  select title into v_title
  from public.listings
  where id = p_listing_id
  for update;

  if not found then
    raise exception 'Listing not found.' using errcode = 'P0002';
  end if;

  select count(*) into v_inquiry_count
  from public.booking_requests
  where listing_id = p_listing_id;

  if v_inquiry_count > 0 and not p_confirm_delete_with_inquiries then
    raise exception 'Listings with inquiries require explicit confirmation.';
  end if;

  select coalesce(jsonb_agg(path), '[]'::jsonb) into v_media_paths
  from (
    select distinct regexp_replace(value, '^listing-media/', '') as path
    from public.listing_media lm
    cross join lateral unnest(array[lm.storage_path, lm.thumbnail_path]) value
    where lm.listing_id = p_listing_id
      and value is not null
      and btrim(value) <> ''
  ) paths;

  -- Event plans remain as history, but their optional link to the deleted
  -- marketplace listing must be removed before the restrictive FK is checked.
  delete from public.event_plan_rental_assets
  where listing_id = p_listing_id;

  delete from public.listings
  where id = p_listing_id;

  insert into public.audit_logs(actor_id, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin_delete_listing', 'listings', p_listing_id,
    jsonb_build_object(
      'listingId', p_listing_id,
      'title', v_title,
      'inquiryCount', v_inquiry_count,
      'confirmDeleteWithInquiries', p_confirm_delete_with_inquiries,
      'bookingHistoryPreserved', true
    )
  );

  return jsonb_build_object(
    'success', true,
    'listingId', p_listing_id,
    'listing_id', p_listing_id,
    'inquiryCount', v_inquiry_count,
    'mediaPaths', v_media_paths,
    'bookingHistoryPreserved', true
  );
end;
$$;

revoke all on function public.admin_permanently_delete_listing(uuid, boolean) from public, anon;
grant execute on function public.admin_permanently_delete_listing(uuid, boolean) to authenticated, service_role;

