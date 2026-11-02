-- Existing campaigns remain eligible in all categories until an administrator
-- selects categories. Reuse the existing audience, schedule and location rules.
alter table public.platform_promotions add column target_category_ids uuid[] not null default '{}';
create function public.validate_promotion_categories() returns trigger language plpgsql set search_path=public as $$
begin
 if exists(select 1 from unnest(new.target_category_ids) selected(category_id) where selected.category_id is null or not exists(select 1 from asset_categories c where c.id=selected.category_id)) then
  raise exception 'Choose valid sponsored categories.';
 end if;
 return new;
end $$;
create trigger validate_promotion_categories before insert or update of target_category_ids on public.platform_promotions for each row execute function public.validate_promotion_categories();
create function public.get_public_sponsored_promotions(
 p_surface text default 'website',p_placement text default 'global',
 p_category_slug text default null,p_selected_region_id uuid default null,
 p_selected_district_id uuid default null,p_selected_ward_id uuid default null,
 p_selected_area_id uuid default null,p_limit integer default 100,p_offset integer default 0
) returns table(promotion_id uuid,title text,description text,cta_label text,target_url text,
 placement text,visibility_scope text,media_type text,media_path text,thumbnail_path text)
language sql stable security definer set search_path=public as $$
 select r.promotion_id,r.title,r.description,r.cta_label,r.target_url,r.placement,
 r.visibility_scope,r.media_type,r.media_path,r.thumbnail_path
 from public.get_active_platform_promotions(p_surface,p_placement,2147483647,
 p_selected_region_id,p_selected_district_id,p_selected_ward_id,p_selected_area_id) with ordinality r
 join public.platform_promotions p on p.id=r.promotion_id
 where nullif(btrim(p_category_slug),'') is null or cardinality(p.target_category_ids)=0
 or exists(select 1 from public.asset_categories c where c.id=any(p.target_category_ids) and c.slug=p_category_slug)
 order by r.ordinality
 limit greatest(least(coalesce(p_limit,100),100),1) offset greatest(coalesce(p_offset,0),0)
$$;
revoke all on function public.get_public_sponsored_promotions(text,text,text,uuid,uuid,uuid,uuid,integer,integer) from public;
grant execute on function public.get_public_sponsored_promotions(text,text,text,uuid,uuid,uuid,uuid,integer,integer) to anon,authenticated,service_role;
notify pgrst,'reload schema';
