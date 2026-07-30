-- PostgREST versions expose JWT role either as request.jwt.claim.role or
-- inside request.jwt.claims. Accept both so Edge service clients can perform
-- guarded publication updates.
create or replace function public.is_admin(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select current_setting('request.jwt.claim.role', true) = 'service_role'
    or coalesce(
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role') = 'service_role',
      false
    )
    or exists (
      select 1
      from public.user_roles
      where profile_id = check_user
        and role = 'admin'
    )
$$;
