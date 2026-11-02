-- Prepared for review only. No table or financial workflow changes.
create or replace function public.search_manage_customers(
  p_search text default null,
  p_confirmation text default null,
  p_offset integer default 0,
  p_limit integer default 20,
  p_id uuid default null
)
returns table(id uuid, full_name text, account_email text, phone_number text,
  preferred_language text, email_confirmed_at timestamptz, created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) or not public.has_admin_permission('users.view') then
    raise exception 'Customer directory access required' using errcode = '42501';
  end if;
  return query
  select p.id, p.full_name, p.account_email, p.phone_number, p.preferred_language,
    p.account_email_confirmed_at, p.created_at, p.updated_at
  from public.profiles p
  where (p_id is null or p.id = p_id)
    and exists(select 1 from public.user_roles r where r.profile_id=p.id and r.role='customer'::public.app_role)
    and not exists(select 1 from public.user_roles r where r.profile_id=p.id and r.role in ('admin'::public.app_role,'agent'::public.app_role))
    and (nullif(btrim(p_search),'') is null or
      strpos(lower(concat_ws(' ',p.full_name,p.account_email,p.phone_number)),lower(btrim(p_search))) > 0)
    and (nullif(p_confirmation,'') is null
      or p_confirmation='confirmed' and p.account_email_confirmed_at is not null
      or p_confirmation='pending' and p.account_email_confirmed_at is null)
  order by p.created_at desc, p.id
  offset greatest(coalesce(p_offset,0),0)
  limit least(greatest(coalesce(p_limit,20),1),100);
end;
$$;
revoke all on function public.search_manage_customers(text,text,integer,integer,uuid) from public;
grant execute on function public.search_manage_customers(text,text,integer,integer,uuid) to authenticated;

create or replace function public.manage_delete_unused_location(p_location_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare ref record; referenced boolean;
begin
  if not public.is_admin(auth.uid()) or not (
    public.has_admin_permission('health.view') or public.has_admin_permission('agents.manage')
  ) then
    raise exception 'Location management access required' using errcode='42501';
  end if;
  -- Serialize location mutations, including inserts into the self-referencing hierarchy.
  lock table public.locations in share row exclusive mode;
  if not exists(select 1 from public.locations where id=p_location_id) then
    raise exception 'Location not found';
  end if;
  -- Discover every existing FK, including event and future modules. Check under
  -- the definer so hidden references cannot be silently cleared by SET NULL.
  for ref in
    select n.nspname, t.relname, a.attname
    from pg_constraint c join pg_class t on t.oid=c.conrelid
      join pg_namespace n on n.oid=t.relnamespace
      join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
    where c.contype='f' and c.confrelid='public.locations'::regclass
    order by c.conrelid, a.attnum
  loop
    execute format('lock table %I.%I in share row exclusive mode',ref.nspname,ref.relname);
    execute format('select exists(select 1 from %I.%I where %I=$1)',ref.nspname,ref.relname,ref.attname)
      into referenced using p_location_id;
    if referenced then
      raise exception 'This location is in use. Remove its references before deleting.' using errcode='23503';
    end if;
  end loop;
  delete from public.locations where id=p_location_id;
end;
$$;
revoke all on function public.manage_delete_unused_location(uuid) from public;
grant execute on function public.manage_delete_unused_location(uuid) to authenticated;
notify pgrst, 'reload schema';
