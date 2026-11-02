-- Global payment/rollout controls must not inherit the broad base admin role.
create or replace function public.guard_marketplace_settings_admin()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if auth.role()='service_role' or public.is_super_admin() or (
   session_user in ('postgres','supabase_admin') and auth.uid() is null
   and nullif(current_setting('request.jwt.claims',true),'') is null
   and coalesce(auth.role(),'')=''
 ) then
   return new;
 end if;
 raise exception 'Only a Super Admin can change global marketplace settings' using errcode='42501';
end $$;
revoke all on function public.guard_marketplace_settings_admin() from public,anon,authenticated;
create trigger guard_marketplace_settings_admin
before insert or update on public.marketplace_settings
for each row execute function public.guard_marketplace_settings_admin();
