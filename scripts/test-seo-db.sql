-- Run ONLY against a disposable local database. Minimal contract fixtures; never production.
\set ON_ERROR_STOP on
begin;
create role anon;
create role authenticated;
create table public.agents(id uuid primary key, account_status text);
create table public.asset_categories(id uuid primary key, is_active boolean);
create table public.listings(id uuid primary key, agent_id uuid, category_id uuid, status text, availability_status text, removed_from_market_at timestamptz, publication_review_status text, updated_at timestamptz, private_address text);
create table public.event_equipment_items(id uuid primary key, is_active boolean, verification_status text, publication_status text, updated_at timestamptz);
create table public.event_service_profiles(id uuid primary key, is_active boolean, verification_status text, updated_at timestamptz);
create table public.event_service_offerings(id uuid primary key, provider_id uuid, is_active boolean, publication_status text, updated_at timestamptz);
create function public.is_listing_public(p_listing_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.listings l join public.agents a on a.id=l.agent_id join public.asset_categories c on c.id=l.category_id
 where l.id=p_listing_id and l.status='active' and l.availability_status='available' and l.removed_from_market_at is null and a.account_status='active' and c.is_active);
$$;
\ir ../supabase/migrations/20261030120000_public_seo_sitemap.sql
insert into public.agents values(md5('agent')::uuid,'active'),(md5('suspended')::uuid,'suspended');
insert into public.asset_categories values(md5('category')::uuid,true),(md5('hidden category')::uuid,false);
insert into public.listings select md5(n::text)::uuid,md5('agent')::uuid,md5('category')::uuid,'active','available',null,'auto_approved','2026-10-20T10:00:00Z','PRIVATE NOT FOR CRAWLERS' from generate_series(1,1005)n;
insert into public.listings select md5('excluded '||n)::uuid,md5('agent')::uuid,md5('category')::uuid,'active','available',null,'auto_approved','2026-10-20T10:00:00Z','PRIVATE' from generate_series(1,6)n;
update public.listings set status='inactive' where id=md5('excluded 1')::uuid;
update public.listings set availability_status='unavailable' where id=md5('excluded 2')::uuid;
update public.listings set removed_from_market_at=now() where id=md5('excluded 3')::uuid;
update public.listings set publication_review_status='pending' where id=md5('excluded 4')::uuid;
update public.listings set agent_id=md5('suspended')::uuid where id=md5('excluded 5')::uuid;
update public.listings set category_id=md5('hidden category')::uuid where id=md5('excluded 6')::uuid;
insert into public.event_equipment_items values(md5('public equipment')::uuid,true,'verified','published','2026-10-21Z'),(md5('draft equipment')::uuid,true,'verified','draft','2026-10-21Z'),(md5('unverified equipment')::uuid,true,'pending','published','2026-10-21Z');
insert into public.event_service_profiles values(md5('provider')::uuid,true,'verified','2026-10-22Z'),(md5('unverified provider')::uuid,true,'pending','2026-10-22Z');
insert into public.event_service_offerings values(md5('service')::uuid,md5('provider')::uuid,true,'published','2026-10-21Z'),(md5('draft service')::uuid,md5('provider')::uuid,true,'draft','2026-10-21Z'),(md5('unverified service')::uuid,md5('unverified provider')::uuid,true,'published','2026-10-21Z');
set local role anon;
do $$ declare data jsonb; first_page jsonb; second_page jsonb; begin
 data:=public.get_public_seo_sitemap('listings');
 if (data->>'total_count')::integer<>1005 or jsonb_array_length(data->'entries')<>1000 then raise exception 'Pagination or visibility failed'; end if;
 first_page:=data->'entries'; second_page:=public.get_public_seo_sitemap('listings',1000,1000)->'entries';
 if jsonb_array_length(second_page)<>5 then raise exception 'Final page truncated'; end if;
 if exists(select 1 from jsonb_array_elements(first_page)a join jsonb_array_elements(second_page)b on a->>'id'=b->>'id') then raise exception 'Duplicate pagination IDs'; end if;
 if data::text like '%PRIVATE%' or data::text like '%private_address%' then raise exception 'Private data escaped'; end if;
 if exists(select 1 from jsonb_array_elements(first_page)e where e->>'updated_at'<>'2026-10-20T13:00:00+03:00' and (e->>'updated_at')::timestamptz<>'2026-10-20T10:00:00Z'::timestamptz) then raise exception 'Fabricated dates'; end if;
 if (public.get_public_seo_sitemap('equipment')->>'total_count')::integer<>1 then raise exception 'Equipment visibility failed'; end if;
 data:=public.get_public_seo_sitemap('services');
 if (data->>'total_count')::integer<>1 or (data->'entries'->0->>'updated_at')::timestamptz<>'2026-10-22Z'::timestamptz then raise exception 'Service visibility or parent update date failed'; end if;
 begin perform public.get_public_seo_sitemap('private'); raise exception 'Invalid kind allowed'; exception when invalid_parameter_value then null; end;
 begin perform * from public.listings; raise exception 'Anonymous direct table read allowed'; exception when insufficient_privilege then null; end;
 raise notice 'PASS: anonymous public projection, all hidden states, true dates, 1005 URLs, pagination, no private table access';
end $$;
rollback;
