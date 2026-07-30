create or replace function public.get_active_featured_listing_ids(p_limit integer default 100)
returns table(listing_id uuid,placement text,ends_at timestamptz)
language sql stable security definer set search_path=public as $$
 select b.listing_id,b.placement,b.ends_at
 from public.listing_boosts b join public.listings l on l.id=b.listing_id
 where b.status='active' and b.ends_at>now() and public.is_listing_public(l.id)
 order by case b.placement when 'homepage' then 0 when 'search_top' then 1 when 'featured' then 2 else 3 end,b.starts_at desc
 limit greatest(1,least(coalesce(p_limit,100),500))
$$;
grant execute on function public.get_active_featured_listing_ids(integer) to anon,authenticated,service_role;
