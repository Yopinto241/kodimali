-- Supervisor is a permission-scoped staff role, not a new login/account type.
-- Existing Agent Manager assignments are preserved.
insert into public.admin_role_definitions(id,name,description,permissions,rank,is_active)
values ('supervisor','Supervisor','Add agents, review their details, manage service assignments and supervise agent access.',
  '["agents.manage","agent_roles.manage","agent_performance.view"]'::jsonb,65,true)
on conflict(id) do update set name=excluded.name,description=excluded.description,
  permissions=excluded.permissions,rank=excluded.rank,is_active=excluded.is_active;
notify pgrst, 'reload schema';
