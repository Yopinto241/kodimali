\set ON_ERROR_STOP on
begin;
create table public.admin_role_definitions(
  id text primary key,name text not null,description text not null,
  permissions jsonb not null,rank integer not null,is_active boolean default true
);
\ir ../supabase/migrations/20261031100000_agent_supervisor_role.sql
-- Reapplying is safe and preserves the exact restricted permission set.
\ir ../supabase/migrations/20261031100000_agent_supervisor_role.sql
do $$ declare definition public.admin_role_definitions; begin
  select * into strict definition from public.admin_role_definitions where id='supervisor';
  if not definition.is_active or definition.permissions <> '["agents.manage","agent_roles.manage","agent_performance.view"]'::jsonb then
    raise exception 'FAIL: Supervisor permissions changed or role disabled';
  end if;
  if definition.permissions ?| array['*','payments.manage','users.view','roles.manage'] then
    raise exception 'FAIL: Supervisor has unrelated privileged access';
  end if;
end $$;
rollback;
