create table if not exists public.agent_service_categories (
  agent_id uuid not null references public.agents(id) on delete cascade,
  category_id uuid not null references public.asset_categories(id) on delete cascade,
  is_primary boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (agent_id, category_id)
);

create unique index if not exists agent_service_categories_one_primary_idx
on public.agent_service_categories (agent_id)
where is_primary;

create index if not exists agent_service_categories_category_idx
on public.agent_service_categories (category_id);

alter table public.agent_service_categories enable row level security;

create or replace function public.normalize_agent_service_category_primary()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_primary then
    update public.agent_service_categories
    set is_primary = false
    where agent_id = new.agent_id
      and category_id <> new.category_id
      and is_primary = true;
  elsif not exists (
    select 1
    from public.agent_service_categories ascg
    where ascg.agent_id = new.agent_id
      and ascg.category_id <> new.category_id
      and ascg.is_primary = true
  ) then
    new.is_primary := true;
  end if;

  return new;
end;
$$;

create or replace function public.guard_active_agent_primary_category()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  agent_is_active boolean;
begin
  select a.account_status = 'active'::public.agent_account_status
  into agent_is_active
  from public.agents a
  where a.id = coalesce(new.agent_id, old.agent_id);

  if not coalesce(agent_is_active, false) then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    if old.is_primary
       and not exists (
         select 1
         from public.agent_service_categories ascg
         where ascg.agent_id = old.agent_id
           and ascg.category_id <> old.category_id
           and ascg.is_primary = true
       ) then
      raise exception 'Active agents must keep one primary category assignment';
    end if;
    return old;
  end if;

  if old.is_primary
     and new.is_primary = false
     and not exists (
       select 1
       from public.agent_service_categories ascg
       where ascg.agent_id = new.agent_id
         and ascg.category_id <> new.category_id
         and ascg.is_primary = true
     ) then
    raise exception 'Active agents must keep one primary category assignment';
  end if;

  return new;
end;
$$;

create or replace function public.ensure_agent_activation_has_primary_category()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.account_status = 'active'::public.agent_account_status
     and not exists (
       select 1
       from public.agent_service_categories ascg
       where ascg.agent_id = new.id
         and ascg.is_primary = true
     ) then
    raise exception 'Active agents must have one primary service category';
  end if;

  return new;
end;
$$;

create or replace function public.agent_has_service_category(
  p_agent_id uuid,
  p_category_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.agent_service_categories ascg
    where ascg.agent_id = p_agent_id
      and ascg.category_id = p_category_id
  );
$$;

create or replace function public.guard_agent_listing_category_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  request_role text := current_setting('request.jwt.claim.role', true);
begin
  if request_role = 'service_role' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.agent_id is not distinct from old.agent_id
     and new.category_id is not distinct from old.category_id then
    return new;
  end if;

  if not public.agent_has_service_category(new.agent_id, new.category_id) then
    raise exception 'This agent is not assigned to the selected category';
  end if;

  return new;
end;
$$;

drop trigger if exists set_agent_service_categories_updated_at on public.agent_service_categories;
create trigger set_agent_service_categories_updated_at
before update on public.agent_service_categories
for each row execute function public.set_updated_at();

drop trigger if exists normalize_agent_service_category_primary on public.agent_service_categories;
create trigger normalize_agent_service_category_primary
before insert or update on public.agent_service_categories
for each row execute function public.normalize_agent_service_category_primary();

drop trigger if exists guard_active_agent_primary_category on public.agent_service_categories;
create trigger guard_active_agent_primary_category
before update or delete on public.agent_service_categories
for each row execute function public.guard_active_agent_primary_category();

drop trigger if exists ensure_agent_activation_has_primary_category on public.agents;
create trigger ensure_agent_activation_has_primary_category
before insert or update on public.agents
for each row execute function public.ensure_agent_activation_has_primary_category();

drop trigger if exists guard_agent_listing_category_assignment on public.listings;
create trigger guard_agent_listing_category_assignment
before insert or update of agent_id, category_id on public.listings
for each row execute function public.guard_agent_listing_category_assignment();

drop policy if exists "agent_service_categories_admin_all" on public.agent_service_categories;
create policy "agent_service_categories_admin_all"
on public.agent_service_categories
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "agent_service_categories_self_select" on public.agent_service_categories;
create policy "agent_service_categories_self_select"
on public.agent_service_categories
for select
to authenticated
using (
  public.is_admin()
  or agent_id = public.current_agent_id()
);

revoke all on public.agent_service_categories from public, anon;
grant select, insert, update, delete on public.agent_service_categories to authenticated, service_role;

revoke all on function public.agent_has_service_category(uuid, uuid) from public, anon;
grant execute on function public.agent_has_service_category(uuid, uuid) to authenticated, service_role;

drop policy if exists "user_roles_self_or_admin_select" on public.user_roles;
create policy "user_roles_self_or_admin_select"
on public.user_roles
for select
to authenticated
using (
  public.is_admin()
  or profile_id = auth.uid()
);
