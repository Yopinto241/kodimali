create extension if not exists pg_net with schema extensions;

create or replace function public.dispatch_queued_push_notification()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin
 perform net.http_post(
   url := 'https://tlhoajedyaeaaqtrjqqh.supabase.co/functions/v1/dispatch-push-notifications',
   headers := '{"Content-Type":"application/json"}'::jsonb,
   body := '{}'::jsonb,
   timeout_milliseconds := 5000
 );
 return new;
end $$;
drop trigger if exists dispatch_queued_push_notification on public.notifications;
create trigger dispatch_queued_push_notification after insert on public.notifications
for each row execute function public.dispatch_queued_push_notification();
