-- Admin-only customer account directory for the browser management workspace.
create or replace function public.get_admin_customer_users(
  p_offset integer default 0,
  p_limit integer default 20
)
returns table (
  id uuid,
  full_name text,
  account_email text,
  phone_number text,
  preferred_language text,
  email_confirmed_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Administrator access required';
  end if;

  return query
  select p.id, p.full_name, p.account_email, p.phone_number,
         p.preferred_language, p.account_email_confirmed_at,
         p.created_at, p.updated_at
  from public.profiles p
  where exists (
    select 1 from public.user_roles ur
    where ur.profile_id = p.id and ur.role = 'customer'::public.app_role
  )
  and not exists (
    select 1 from public.user_roles ur
    where ur.profile_id = p.id and ur.role in ('admin'::public.app_role, 'agent'::public.app_role)
  )
  order by p.created_at desc
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

revoke all on function public.get_admin_customer_users(integer, integer) from public;
grant execute on function public.get_admin_customer_users(integer, integer) to authenticated;

comment on function public.get_admin_customer_users(integer, integer) is
  'Lists ordinary registered customer accounts for administrators only.';
