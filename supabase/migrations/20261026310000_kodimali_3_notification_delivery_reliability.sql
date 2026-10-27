-- KODIMALI 3.0: make the existing push outbox recoverable and auditable.
-- Delivery remains driven by the existing dispatcher; this migration does not
-- create a scheduler or activate a new external integration.

alter table public.notification_delivery_outbox
  add column if not exists last_attempt_at timestamptz,
  add column if not exists terminal_at timestamptz;

alter table public.notification_delivery_outbox
  drop constraint if exists notification_delivery_outbox_attempt_count_check;
alter table public.notification_delivery_outbox
  add constraint notification_delivery_outbox_attempt_count_check
  check (attempt_count >= 0);

drop index if exists public.idx_notification_outbox_pending;
create index idx_notification_outbox_pending
  on public.notification_delivery_outbox(next_attempt_at, created_at)
  where status in ('pending','failed') and terminal_at is null;

comment on column public.notification_delivery_outbox.last_attempt_at is
'Timestamp of the most recent dispatcher claim, including attempts that did not reach Firebase.';
comment on column public.notification_delivery_outbox.terminal_at is
'Set when delivery is complete, intentionally skipped, or has exhausted its bounded retry policy.';

-- Preserve the existing device-registration recovery path. A newly registered
-- device makes a recent no-device failure retryable again.
create or replace function public.retry_recent_push_after_device_registration()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
begin
  update public.notification_delivery_outbox
  set status='pending',
      attempt_count=0,
      next_attempt_at=timezone('utc',now()),
      last_attempt_at=null,
      terminal_at=null,
      processed_at=null,
      last_error=null,
      updated_at=timezone('utc',now())
  where user_id=new.user_id and status in ('skipped','failed')
    and created_at > timezone('utc',now()) - interval '1 hour';

  perform net.http_post(
    url := 'https://tlhoajedyaeaaqtrjqqh.supabase.co/functions/v1/dispatch-push-notifications',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('source','device_registration')
  );
  return new;
end;
$$;

