-- The current production listings table uses status/availability/removal state
-- as its publication authority. approval_status existed only in legacy history.
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

    update public.listings
    set status = 'active'::public.listing_status,
        availability_status = coalesce(p_availability_status, 'available'::public.availability_status),
        publication_requested = false,
        removed_from_market_at = null,
        removed_reason = null,
        published_at = timezone('utc', now())
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
    jsonb_build_object('status', p_status, 'availabilityStatus', p_availability_status,
      'removedReason', p_removed_reason, 'moderationNote', p_moderation_note));

  return jsonb_build_object('success', true, 'listingId', v_listing.id,
    'status', v_listing.status, 'availabilityStatus', v_listing.availability_status);
end;
$$;

revoke all on function public.admin_set_listing_marketplace_status(uuid, public.listing_status, public.availability_status, text, text) from public, anon;
grant execute on function public.admin_set_listing_marketplace_status(uuid, public.listing_status, public.availability_status, text, text) to authenticated, service_role;

