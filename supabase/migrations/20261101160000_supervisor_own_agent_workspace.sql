-- A supervisor remains an agent. The team boundary must not hide their own
-- agent record from workspace/profile and payment-owner lookups.
drop policy if exists supervisor_exclusive_agents on public.agents;

create policy supervisor_exclusive_agents_select on public.agents
as restrictive for select to authenticated
using (not public.is_scoped_supervisor()
  or profile_id = auth.uid()
  or public.can_manage_supervised_agent(id));

create policy supervisor_self_agent_read on public.agents
for select to authenticated
using (public.is_scoped_supervisor() and profile_id = auth.uid());

-- Preserve the previous write boundary. Reading oneself must not permit
-- changing verification, account status, supervisor assignment or territory.
create policy supervisor_exclusive_agents_insert on public.agents
as restrictive for insert to authenticated
with check (not public.is_scoped_supervisor() or public.can_manage_supervised_agent(id));
create policy supervisor_exclusive_agents_update on public.agents
as restrictive for update to authenticated
using (not public.is_scoped_supervisor() or public.can_manage_supervised_agent(id))
with check (not public.is_scoped_supervisor() or public.can_manage_supervised_agent(id));
create policy supervisor_exclusive_agents_delete on public.agents
as restrictive for delete to authenticated
using (not public.is_scoped_supervisor() or public.can_manage_supervised_agent(id));

notify pgrst, 'reload schema';
