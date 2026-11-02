\set ON_ERROR_STOP on
begin;
create table public.agents(id uuid primary key, phone_number text);
create table public.listings(id uuid primary key,agent_id uuid references agents,status text);
create function public.is_listing_public(uuid) returns boolean language sql stable as $$ select status='approved' from listings where id=$1 $$;
create function public.get_public_listing_booking_capability(uuid) returns jsonb language sql stable as $$ select jsonb_build_object('booking_mode','request_booking','can_book',true) from listings where id=$1 and status='approved' $$;
do $$ begin
 if not exists(select from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
\ir ../supabase/migrations/20261031120000_listing_whatsapp_availability.sql
insert into agents values ('00000000-0000-4000-8000-000000000001','0712 345 678'),('00000000-0000-4000-8000-000000000002',null);
insert into listings values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','approved'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','approved'),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','pending');
do $$ declare result jsonb; begin
 assert normalize_whatsapp_number('0712 345 678')='255712345678';
 assert normalize_whatsapp_number('+255 (712) 345-678')='255712345678';
 assert normalize_whatsapp_number('00255 712345678')='255712345678';
 assert normalize_whatsapp_number('712345678')='255712345678';
 assert normalize_whatsapp_number('+44 7700 900123')='447700900123';
 assert normalize_whatsapp_number('255712') is null;
 assert normalize_whatsapp_number('abc0712345678') is null;
 assert normalize_whatsapp_number(null) is null;
 select jsonb_agg(to_jsonb(c)) into result from get_public_listing_booking_capabilities(array['10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003']::uuid[]) c;
 assert jsonb_array_length(result)=2,'Private listings excluded and repeated IDs deduplicated';
 assert result::text not like '%712345678%' and result::text not like '%phone%','Public feed exposes no number';
 assert (select capability->>'has_whatsapp'='true' and capability->>'booking_mode'='request_booking' from get_public_listing_booking_capabilities(array['10000000-0000-4000-8000-000000000001']::uuid[]));
 assert (select capability->>'has_whatsapp'='false' from get_public_listing_booking_capabilities(array['10000000-0000-4000-8000-000000000002']::uuid[]));
 assert (select count(*)=0 from get_public_listing_booking_capabilities(null));
end $$;
set local role anon;
select * from get_public_listing_booking_capabilities(array['10000000-0000-4000-8000-000000000001']::uuid[]);
reset role;
rollback;
