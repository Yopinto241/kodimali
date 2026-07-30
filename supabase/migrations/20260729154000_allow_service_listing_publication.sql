-- Server-side payment/free-publication functions update a completed listing
-- with the service-role JWT. Listing workflow guards previously treated that
-- request as a signed-out customer and raised "Only active agents can manage
-- listings" even though the owning agent was active.
create or replace function public.is_admin(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select current_setting('request.jwt.claim.role', true) = 'service_role'
    or exists (
      select 1
      from public.user_roles
      where profile_id = check_user
        and role = 'admin'
    )
$$;

revoke all on function public.is_admin(uuid) from public, anon;
grant execute on function public.is_admin(uuid) to authenticated, service_role;
