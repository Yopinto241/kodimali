\set ON_ERROR_STOP on
begin;
do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if; end $$;
create type public.location_type as enum('country','region','district','ward','area');
create type public.listing_status as enum('active','inactive');
create type public.availability_status as enum('available','rented');
create type public.agent_account_status as enum('active','inactive');
create table locations(id uuid primary key,parent_id uuid,location_type location_type);
create function pg_temp.id(n int) returns uuid language sql immutable as $$ select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$ begin if value is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function location_ancestor_id(p_id uuid,p_type location_type) returns uuid language sql stable as $$ with recursive tree as(select * from locations where id=p_id union all select l.* from locations l join tree t on t.parent_id=l.id) select id from tree where location_type=p_type limit 1 $$;
create function resolve_location_hierarchy(double precision,double precision) returns table(region_id uuid,district_id uuid,ward_id uuid,area_id uuid) language sql as $$ select null::uuid,null::uuid,null::uuid,null::uuid $$;
create function normalize_listing_media_path(text) returns text language sql immutable as $$ select $1 $$;
create table agents(id uuid primary key,account_status agent_account_status);
create table asset_categories(id uuid primary key,name text,slug text,icon_key text,home_feed_weight integer,is_active boolean);
create table listings(id uuid primary key,agent_id uuid,category_id uuid,location_id uuid,title text,description text,public_location_label text,price_amount numeric,price_period text,status listing_status,availability_status availability_status,removed_from_market_at timestamptz,published_at timestamptz,created_at timestamptz,listing_attributes jsonb);
create table listing_media(listing_id uuid,is_cover boolean,storage_path text);
\ir ../supabase/migrations/20261027193000_enforce_listing_location_hierarchy.sql
insert into locations values(pg_temp.id(1),null,'region'),(pg_temp.id(2),pg_temp.id(1),'district'),(pg_temp.id(3),pg_temp.id(2),'ward'),(pg_temp.id(4),pg_temp.id(3),'area'),(pg_temp.id(5),pg_temp.id(3),'area'),(pg_temp.id(6),pg_temp.id(2),'ward'),(pg_temp.id(7),pg_temp.id(6),'area');
insert into agents values(pg_temp.id(10),'active');
insert into asset_categories values(pg_temp.id(20),'House','house','home',1,true),(pg_temp.id(21),'Car','car','car',1,true);
insert into listings(id,agent_id,category_id,location_id,title,price_amount,price_period,status,availability_status,created_at) values
(pg_temp.id(31),pg_temp.id(10),pg_temp.id(20),pg_temp.id(4),'House area A',100,'month','active','available',now()),
(pg_temp.id(32),pg_temp.id(10),pg_temp.id(20),pg_temp.id(5),'House area B',200,'month','active','available',now()),
(pg_temp.id(33),pg_temp.id(10),pg_temp.id(20),pg_temp.id(7),'Outside ward',300,'month','active','available',now()),
(pg_temp.id(34),pg_temp.id(10),pg_temp.id(21),pg_temp.id(4),'Other category',400,'day','active','available',now());
select pg_temp.ok((select count(*)=2 from search_public_listings_v2('house',null,null,null,pg_temp.id(3),null,null,null,null,'recommended',20,0,null,null,'ward')),'GPS ward search includes both areas in the same ward');
select pg_temp.ok((select count(*)=1 from search_public_listings_v2('house',null,null,null,pg_temp.id(3),pg_temp.id(4),null,null,null,'recommended',20,0,null,null,'ward')),'manual area remains narrower when explicitly selected');
select pg_temp.ok((select count(*)=1 and min(price_amount)=200 from search_public_listings_v2('house',null,null,null,pg_temp.id(3),null,150,null,null,'price_low',20,0,null,null,'ward')),'ward combines independently with category and minimum price');
select 'PASS whole-ward coverage, outside-ward/category exclusion, manual area and independent prices';
rollback;
