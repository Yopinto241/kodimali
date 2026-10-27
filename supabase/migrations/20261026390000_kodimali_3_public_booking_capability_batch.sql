-- Batch form avoids per-card booking capability queries in public feeds.

create or replace function public.get_public_listing_booking_capabilities(
  p_listing_ids uuid[]
)
returns table(listing_id uuid, capability jsonb)
language sql
stable
security definer
set search_path = public
as $$
  select requested.id,resolved.capability
  from (
    select distinct id
    from unnest(coalesce(p_listing_ids,'{}'::uuid[])) id
    limit 100
  ) requested
  cross join lateral (
    select public.get_public_listing_booking_capability(requested.id) capability
  ) resolved
  where resolved.capability is not null
$$;

revoke all on function public.get_public_listing_booking_capabilities(uuid[]) from public;
grant execute on function public.get_public_listing_booking_capabilities(uuid[])
to anon,authenticated,service_role;

