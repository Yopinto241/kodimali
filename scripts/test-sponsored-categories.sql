\set ON_ERROR_STOP on
begin;
create table public.asset_categories(id uuid primary key,slug text);
create table public.platform_promotions(id uuid primary key,title text, is_active boolean default true,visibility_scope text default 'public');
create function public.get_active_platform_promotions(text,text,integer,uuid,uuid,uuid,uuid)
returns table(promotion_id uuid,title text,description text,cta_label text,target_url text,placement text,visibility_scope text,media_type text,media_path text,thumbnail_path text)
language sql as $$ select id,title,null::text,null::text,null::text,'global',visibility_scope,null::text,null::text,null::text from platform_promotions where is_active and visibility_scope='public' order by id limit $3 $$;
do $$ begin
 if not exists(select from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
\ir ../supabase/migrations/20261031210000_sponsored_category_cards.sql
insert into asset_categories values ('00000000-0000-4000-8000-000000000001','house'),('00000000-0000-4000-8000-000000000002','car');
insert into platform_promotions(id,title,target_category_ids) values
 ('10000000-0000-4000-8000-000000000001','Global','{}'),
 ('10000000-0000-4000-8000-000000000002','House A',array['00000000-0000-4000-8000-000000000001']::uuid[]),
 ('10000000-0000-4000-8000-000000000003','House B',array['00000000-0000-4000-8000-000000000001']::uuid[]),
 ('10000000-0000-4000-8000-000000000004','Car',array['00000000-0000-4000-8000-000000000002']::uuid[]);
insert into platform_promotions(id,title,is_active,visibility_scope) values ('10000000-0000-4000-8000-000000000005','Private',true,'admin'),('10000000-0000-4000-8000-000000000006','Paused',false,'public');
do $$ begin
 assert (select count(*)=3 from get_public_sponsored_promotions(p_category_slug=>'house')),'All dedicated house ads plus global campaign';
 assert (select count(*)=2 from get_public_sponsored_promotions(p_category_slug=>'car')),'Category isolation';
 assert (select count(*)=4 from get_public_sponsored_promotions()),'All categories when no filter';
 update platform_promotions set target_category_ids=array['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[] where title='House B';
 assert (select count(*)=3 from get_public_sponsored_promotions(p_category_slug=>'car')),'A campaign can be dedicated to multiple categories';
 assert (select count(*)=2 from get_public_sponsored_promotions(p_category_slug=>'house',p_limit=>2));
 assert (select count(*)=1 from get_public_sponsored_promotions(p_category_slug=>'house',p_limit=>2,p_offset=>2));
 begin
  update platform_promotions set target_category_ids=array['00000000-0000-4000-8000-000000000099']::uuid[];
  raise exception 'Expected invalid category rejection';
 exception when raise_exception then
  if sqlerrm='Expected invalid category rejection' then raise; end if;
 end;
end $$;
insert into platform_promotions(id,title,target_category_ids) select ('20000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Extra',array['00000000-0000-4000-8000-000000000001']::uuid[] from generate_series(1,103) n;
set local role anon;
do $$ begin
 assert (select count(*)=100 from get_public_sponsored_promotions(p_category_slug=>'house'));
 assert (select count(*)=6 from get_public_sponsored_promotions(p_category_slug=>'house',p_offset=>100)),'Pagination retains every eligible campaign';
 assert not exists(select 1 from get_public_sponsored_promotions() where title in ('Private','Paused')),'Existing audience/activation eligibility retained';
end $$;
reset role;
rollback;
