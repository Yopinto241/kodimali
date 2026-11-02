-- Disposable local database only. No production listing or payment is touched.
\set ON_ERROR_STOP on
begin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
create function public.is_admin(p_user uuid default auth.uid()) returns boolean language sql stable as $$
 select p_user=md5('admin')::uuid;
$$;
create type public.agent_account_status as enum ('active','inactive');
create table public.agents(id uuid primary key,profile_id uuid,account_status public.agent_account_status);
create table public.listings(id uuid primary key);
create table public.booking_configurations(listing_id uuid,booking_mode text);
create table public.booking_requests(
 id uuid primary key,listing_id uuid references public.listings on delete set null,
 agent_id uuid,customer_id uuid,customer_name text,customer_phone_number text,
 customer_phone_normalized text,customer_email text,customer_email_normalized text,
 request_reference text,requested_start_at timestamptz,requested_end_at timestamptz,
 guest_count integer,request_message text,requested_service_codes text[],booking_status text,
 agent_response_due_at timestamptz,first_agent_response_at timestamptz,admin_override boolean,
 booking_kind text,updated_at timestamptz default now()
);
create table public.booking_conversations(id uuid primary key,booking_request_id uuid references public.booking_requests on delete cascade);
create table public.booking_messages(id uuid primary key,conversation_id uuid,sender_id uuid,read_at timestamptz,body text);
create table public.booking_payment_transactions(id uuid primary key,booking_request_id uuid references public.booking_requests on delete restrict,amount integer);
create function public.is_booking_participant(p_booking uuid,p_user uuid) returns boolean language sql stable as $$
 select exists(select 1 from public.booking_requests b left join public.agents a on a.id=b.agent_id where b.id=p_booking and (b.customer_id=p_user or a.profile_id=p_user));
$$;
\ir fixtures/booking-workflow-before-repair.sql
create trigger a_apply_listing_booking_mode before update of listing_id,requested_start_at,requested_end_at on public.booking_requests for each row execute function public.apply_listing_booking_mode();
create trigger guard_guest_booking_request_update before update on public.booking_requests for each row execute function public.guard_guest_booking_request_update();
insert into public.agents values(md5('agent')::uuid,md5('agent user')::uuid,'active');
insert into public.listings values(md5('listing')::uuid);
insert into public.booking_requests(id,listing_id,agent_id,customer_id,customer_name,booking_status,booking_kind,requested_start_at,requested_end_at)
 values(md5('booking')::uuid,md5('listing')::uuid,md5('agent')::uuid,md5('customer')::uuid,'Original customer','new','inquiry',now(),now()+interval '1 day');
insert into public.booking_conversations values(md5('conversation')::uuid,md5('booking')::uuid);
insert into public.booking_messages values(md5('message')::uuid,md5('conversation')::uuid,md5('agent user')::uuid,null,'Original response');
insert into public.booking_payment_transactions values(md5('payment')::uuid,md5('booking')::uuid,12000);
select set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
do $$ begin
 begin
  delete from public.listings where id=md5('listing')::uuid;
  raise exception 'Baseline deletion unexpectedly succeeded';
 exception when others then
  if sqlerrm not like '%immutable guest-request fields%' then raise; end if;
 end;
 begin
  perform public.mark_conversation_read(md5('conversation')::uuid);
  raise exception 'Baseline audit read unexpectedly succeeded';
 exception when insufficient_privilege then null; end;
end $$;
\ir ../supabase/migrations/20261030130000_listing_deletion_and_admin_audit.sql
do $$ begin
 begin
  update public.booking_requests set listing_id=null where id=md5('booking')::uuid;
  raise exception 'Direct unlink unexpectedly succeeded';
 exception when others then
  if sqlerrm not like '%immutable guest-request fields%' then raise; end if;
 end;
 begin
  update public.booking_requests set customer_name='Tampered' where id=md5('booking')::uuid;
  raise exception 'Immutable name change unexpectedly succeeded';
 exception when others then
  if sqlerrm not like '%immutable guest-request fields%' then raise; end if;
 end;
 if public.mark_conversation_read(md5('conversation')::uuid)<>0 then raise exception 'Admin audit mutated read state'; end if;
 if exists(select 1 from public.booking_messages where read_at is not null) then raise exception 'Admin consumed unread messages'; end if;
 begin
  perform public.mark_conversation_read(md5('missing conversation')::uuid);
  raise exception 'Missing conversation unexpectedly allowed';
 exception when insufficient_privilege then null; end;
end $$;
-- Actual FK-triggered detachment must preserve all other stored request fields.
create temporary table original_request as select to_jsonb(b)-'listing_id'-'updated_at' as snapshot from public.booking_requests b;
delete from public.listings where id=md5('listing')::uuid;
do $$ begin
 if (select listing_id is not null from public.booking_requests where id=md5('booking')::uuid) then raise exception 'Listing link was restored'; end if;
 if (select to_jsonb(b)-'listing_id'-'updated_at' from public.booking_requests b) is distinct from (select snapshot from original_request) then raise exception 'Request history changed'; end if;
 if (select count(*) from public.booking_payment_transactions where amount=12000)<>1 then raise exception 'Payment lost'; end if;
 if (select count(*) from public.booking_conversations)<>1 or (select count(*) from public.booking_messages where body='Original response')<>1 then raise exception 'Conversation history lost'; end if;
end $$;
select set_config('request.jwt.claim.sub',md5('outsider')::uuid::text,true);
do $$ begin
 begin
  perform public.mark_conversation_read(md5('conversation')::uuid);
  raise exception 'Unrelated user unexpectedly allowed';
 exception when insufficient_privilege then null; end;
 begin
  update public.booking_requests set booking_status='contacted';
  raise exception 'Unrelated status edit unexpectedly allowed';
 exception when others then
  if sqlerrm not like '%Only the assigned active agent%' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub',md5('customer')::uuid::text,true);
do $$ begin
 if public.mark_conversation_read(md5('conversation')::uuid)<>1 then raise exception 'Customer cannot read'; end if;
 if public.mark_conversation_read(md5('conversation')::uuid)<>0 then raise exception 'Read is not idempotent'; end if;
end $$;
select set_config('request.jwt.claim.sub',md5('agent user')::uuid::text,true);
update public.booking_requests set booking_status='contacted';
do $$ begin
 if not exists(select 1 from public.booking_requests where booking_status='contacted' and first_agent_response_at is not null) then raise exception 'Agent workflow broken'; end if;
end $$;
rollback;
\echo PASS: reproduced both original failures; deletion preserves requests/payments/messages; admin audits do not mark participant messages read; immutable fields and participant access remain protected.
