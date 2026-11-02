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
insert into locations values(pg_temp.id(1),null,'region'),(pg_temp.id(2),pg_temp.id(1),'district'),(pg_temp.id(3),pg_temp.id(2),'ward'),(pg_temp.id(4),pg_temp.id(3),'area'),(pg_temp.id(5),pg_temp.id(3),'area'),(pg_temp.id(6),pg_temp.id(2),'ward'),(pg_temp.id(7),pg_temp.id(6),'area');
insert into agents values(pg_temp.id(10),'active');
insert into asset_categories values(pg_temp.id(20),'House','house','home',1,true),(pg_temp.id(21),'Car','car','car',1,true);
insert into listings(id,agent_id,category_id,location_id,title,price_amount,price_period,status,availability_status,created_at) values
(pg_temp.id(31),pg_temp.id(10),pg_temp.id(20),pg_temp.id(4),'House area A',100,'month','active','available',now()),
(pg_temp.id(32),pg_temp.id(10),pg_temp.id(20),pg_temp.id(5),'House area B',200,'month','active','available',now()),
(pg_temp.id(33),pg_temp.id(10),pg_temp.id(20),pg_temp.id(7),'Outside ward',300,'month','active','available',now()),
(pg_temp.id(34),pg_temp.id(10),pg_temp.id(21),pg_temp.id(4),'Other category',400,'day','active','available',now());
\ir ../supabase/migrations/20261102190000_home_feed_newest_first.sql
update listings set created_at=now()-interval '3 days' where id=pg_temp.id(31);
update listings set created_at=now()-interval '2 days' where id=pg_temp.id(32);
update listings set created_at=now()-interval '1 day' where id=pg_temp.id(33);
update listings set created_at=now()-interval '4 days',published_at=now() where id=pg_temp.id(34);
select pg_temp.ok((select listing_id=pg_temp.id(34) from get_public_home_feed(p_limit=>1,p_session_seed=>'home')),'newest publication is first before pagination');
select pg_temp.ok((select listing_id=pg_temp.id(33) from get_public_home_feed(p_limit=>1,p_page=>1,p_session_seed=>'other')),'second page uses chronological order independently of seed');
update listings set status='inactive' where id=pg_temp.id(34);
select pg_temp.ok((select listing_id=pg_temp.id(33) from get_public_home_feed(p_limit=>1)),'private listing stays excluded');
update agents set account_status='inactive';
select pg_temp.ok((select count(*)=0 from get_public_home_feed()),'inactive agents stay excluded');
select 'PASS newest homepage order, publication/creation dates, pagination and public visibility';
rollback;
