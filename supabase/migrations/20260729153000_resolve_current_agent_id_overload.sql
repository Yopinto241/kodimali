-- The live database contains both current_agent_id() and
-- current_agent_id(uuid default auth.uid()). A zero-argument call therefore
-- has two candidates and fails with PostgreSQL 42725. Keep both useful
-- signatures, but make the UUID overload explicitly require its argument.
alter function public.current_agent_id(uuid)
  rename to current_agent_id_for_user;

create or replace function public.current_agent_id_for_user(
  check_user uuid default auth.uid()
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select a.id
  from public.agents a
  where a.profile_id = check_user
  order by (a.account_status = 'active'::public.agent_account_status) desc,
           a.activated_at desc nulls last,
           a.created_at desc
  limit 1
$$;

revoke all on function public.current_agent_id_for_user(uuid) from public, anon;
grant execute on function public.current_agent_id_for_user(uuid) to authenticated, service_role;

-- Re-assert the zero-argument function used by listing and request workflows.
create or replace function public.current_agent_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select public.current_agent_id_for_user(auth.uid())
$$;

revoke all on function public.current_agent_id() from public, anon;
grant execute on function public.current_agent_id() to authenticated, service_role;
