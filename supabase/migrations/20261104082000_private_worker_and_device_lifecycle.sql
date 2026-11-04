-- Provision the same random secret in Supabase Vault (kodimali_worker_secret)
-- and Edge secrets (KODIMALI_WORKER_SECRET) before deploying protected workers.
-- No secret is embedded in source or returned to clients.
create or replace function public.dispatch_queued_push_notification()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
declare worker_secret text;
begin
 select decrypted_secret into worker_secret from vault.decrypted_secrets where name='kodimali_worker_secret' limit 1;
 if length(coalesce(worker_secret,''))<32 then
   -- Keep durable work pending. The repair runbook provisions the secret before
   -- function rollout; an absent credential must not become anonymous work.
   return new;
 end if;
 perform net.http_post(
   url:='https://tlhoajedyaeaaqtrjqqh.supabase.co/functions/v1/dispatch-push-notifications',
   headers:=jsonb_build_object('Content-Type','application/json','x-kodimali-worker-secret',worker_secret),
   body:='{}'::jsonb,timeout_milliseconds:=5000);
 return new;
end $$;

-- An installation-scoped unregistration capability lets an offline logout be
-- completed later without retaining an old account session. Only its hash is
-- stored server-side; an account switch clears the old capability atomically.
alter table public.device_tokens add column if not exists unregister_capability_hash text;
alter table public.device_tokens add column if not exists session_id uuid;
create or replace function public.register_push_device_v2(
 p_token text,p_platform text,p_app_surface text,p_device_id text,p_locale text,p_unregister_capability text
) returns uuid language plpgsql security definer set search_path=public,extensions as $$
declare result uuid; claims jsonb;
begin
 if auth.uid() is null or length(coalesce(p_unregister_capability,''))<32 then raise exception 'Authentication and installation capability required' using errcode='42501'; end if;
 result:=public.register_push_device(p_token,p_platform,p_app_surface,p_device_id,p_locale);
 claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
 update public.device_tokens set unregister_capability_hash=encode(extensions.digest(p_unregister_capability,'sha256'),'hex'),
   session_id=nullif(claims->>'session_id','')::uuid where id=result and user_id=auth.uid();
 return result;
end $$;
revoke all on function public.register_push_device_v2(text,text,text,text,text,text) from public,anon;
grant execute on function public.register_push_device_v2(text,text,text,text,text,text) to authenticated;

create or replace function public.unregister_push_installation(p_token text,p_capability text)
returns void language plpgsql security definer set search_path=public,extensions as $$
begin
 if length(coalesce(p_capability,''))<32 then return; end if;
 update public.device_tokens set is_enabled=false,session_id=null,updated_at=now()
 where device_token=p_token and unregister_capability_hash=encode(extensions.digest(p_capability,'sha256'),'hex');
end $$;
revoke all on function public.unregister_push_installation(text,text) from public;
grant execute on function public.unregister_push_installation(text,text) to anon,authenticated,service_role;

create or replace function public.push_registration_has_active_session(p_device_id uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.device_tokens d join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
  where d.id=p_device_id and d.is_enabled and (s.not_after is null or s.not_after>now()))
$$;
revoke all on function public.push_registration_has_active_session(uuid) from public,anon,authenticated;
grant execute on function public.push_registration_has_active_session(uuid) to service_role;
-- Legacy registrations lack a session binding. Preserve them during rollout;
-- their notification text becomes generic in the worker. New versions register
-- a binding and receive no pushes after the Auth session has been revoked.
notify pgrst,'reload schema';
