-- Disposable local database only; fixtures and permissions roll back.
\set ON_ERROR_STOP on
begin;
create table public.booking_cancellation_cases (
 id uuid primary key, commission_reversal_status text not null default 'not_applicable',
 private_note text
);
alter table public.booking_cancellation_cases enable row level security;
grant select on public.booking_cancellation_cases to authenticated;
create policy fixture_access on public.booking_cancellation_cases for select to authenticated using (id=md5('allowed')::uuid);
insert into public.booking_cancellation_cases values
 (md5('allowed')::uuid,'pending','PRIVATE'),(md5('denied')::uuid,'completed','PRIVATE');
do $$ begin
 begin
  perform commission_adjustment_status from public.booking_cancellation_cases;
  raise exception 'Legacy query unexpectedly succeeded before repair';
 exception when undefined_column then null; end;
end $$;
\ir ../supabase/migrations/20261030140000_legacy_booking_audit_compatibility.sql
set local role authenticated;
do $$ begin
 if (select count(*) from public.booking_cancellation_cases)<>1 then raise exception 'RLS changed'; end if;
 if (select commission_adjustment_status from public.booking_cancellation_cases)<>'pending' then raise exception 'Alias not populated'; end if;
end $$;
reset role;
update public.booking_cancellation_cases set commission_reversal_status='completed' where id=md5('allowed')::uuid;
do $$ begin
 if exists(select 1 from public.booking_cancellation_cases where commission_adjustment_status is distinct from commission_reversal_status) then raise exception 'Alias diverged'; end if;
 begin
  update public.booking_cancellation_cases set commission_adjustment_status='pending';
  raise exception 'Alias was writable';
 exception when generated_always then null; end;
end $$;
rollback;
\echo PASS: old query reproduced and repaired; alias mirrors live status, cannot be independently written, and preserves RLS.
