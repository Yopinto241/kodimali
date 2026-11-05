-- Use a stable scheduler owner, not the temporary CLI login role.
set role postgres;

-- Immediate dispatch remains in place. Wake durable retries even in quiet periods.
create or replace function public.wake_push_dispatcher()
returns void language plpgsql security definer set search_path=public,extensions as $$
declare worker_secret text;
begin
 if not exists (
   select 1 from public.notification_delivery_outbox
   where terminal_at is null and (
     (status in ('pending','failed') and attempt_count < 8 and next_attempt_at <= now())
     or (status='processing' and updated_at < now()-interval '5 minutes')
   )
 ) then return;end if;
 select decrypted_secret into worker_secret from vault.decrypted_secrets
 where name='kodimali_worker_secret' limit 1;
 if length(coalesce(worker_secret,'')) < 32 then return;end if;
 perform net.http_post(
   url:='https://tlhoajedyaeaaqtrjqqh.supabase.co/functions/v1/dispatch-push-notifications',
   headers:=jsonb_build_object('Content-Type','application/json','x-kodimali-worker-secret',worker_secret),
   body:='{}'::jsonb,timeout_milliseconds:=5000);
end $$;
revoke all on function public.wake_push_dispatcher() from public,anon,authenticated;
grant execute on function public.wake_push_dispatcher() to service_role;

create or replace function public.retry_recent_push_after_device_registration()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 -- Heartbeats must not reset exhausted attempts or revive preference-disabled
 -- notifications. Only a missing-device skip is recoverable by registration.
 update public.notification_delivery_outbox
 set status='pending',attempt_count=0,next_attempt_at=now(),last_attempt_at=null,
     terminal_at=null,processed_at=null,last_error=null,updated_at=now()
 where user_id=new.user_id and status='skipped' and last_error='No active device'
   and created_at > now()-interval '1 hour';
 perform public.wake_push_dispatcher();
 return new;
end $$;
revoke all on function public.retry_recent_push_after_device_registration() from public,anon,authenticated;

-- Reuses the existing pg_cron extension. No secret appears in the cron command.
select cron.schedule('kodimali-push-retry','* * * * *','select public.wake_push_dispatcher();');

reset role;
