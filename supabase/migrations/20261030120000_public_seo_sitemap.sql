-- Read-only public projection for crawler discovery. Does not change inventory, RLS, or booking/payment functions.
create or replace function public.get_public_seo_sitemap(
  p_kind text, p_offset integer default 0, p_limit integer default 1000
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
  if p_kind not in ('listings','equipment','services') or p_kind is null then
    raise exception 'Unsupported public sitemap kind' using errcode = '22023';
  end if;
  with eligible as materialized (
    select l.id, l.updated_at
    from public.listings l
    where p_kind = 'listings' and public.is_listing_public(l.id)
      and l.publication_review_status in ('auto_approved','admin_approved')
    union all
    select e.id, e.updated_at from public.event_equipment_items e
    where p_kind = 'equipment' and e.is_active and e.verification_status = 'verified' and e.publication_status = 'published'
    union all
    select o.id, greatest(o.updated_at, p.updated_at) from public.event_service_offerings o
    join public.event_service_profiles p on p.id = o.provider_id
    where p_kind = 'services' and o.is_active and o.publication_status = 'published'
      and p.is_active and p.verification_status = 'verified'
  ), page as (
    select id, updated_at from eligible order by id
    limit least(greatest(coalesce(p_limit,1000),1),1000)
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object('total_count', (select count(*) from eligible),
    'entries', coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from page),'[]'::jsonb)) into result;
  return result;
end;
$$;
revoke all on function public.get_public_seo_sitemap(text,integer,integer) from public;
grant execute on function public.get_public_seo_sitemap(text,integer,integer) to anon, authenticated;
comment on function public.get_public_seo_sitemap(text,integer,integer) is 'Public IDs and genuine modification dates only; paginated published inventory for XML sitemaps.';
