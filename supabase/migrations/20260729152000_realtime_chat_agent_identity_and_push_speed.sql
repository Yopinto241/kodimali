-- Always resolve the active agent record when legacy duplicate profile links exist.
create or replace function public.current_agent_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select a.id
  from public.agents a
  where a.profile_id = auth.uid()
  order by (a.account_status = 'active'::public.agent_account_status) desc,
           a.activated_at desc nulls last,
           a.created_at desc
  limit 1
$$;

create or replace function public.get_my_agent_status()
returns table (
  id uuid, profile_id uuid, display_name text, phone_number text,
  contact_email text, nida_number text, location_id uuid,
  public_location_label text, profile_photo_path text, business_name text,
  business_description text, account_status text, verification_status text,
  verified_at timestamptz, activated_at timestamptz,
  deactivated_at timestamptz, deactivation_reason text
)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.profile_id, a.display_name, a.phone_number, a.contact_email,
    a.nida_number, a.location_id, a.public_location_label,
    a.profile_photo_path, a.business_name, a.business_description,
    a.account_status::text, a.verification_status::text, a.verified_at,
    a.activated_at, a.deactivated_at, a.deactivation_reason
  from public.agents a
  where a.profile_id = auth.uid()
  order by (a.account_status = 'active'::public.agent_account_status) desc,
           a.activated_at desc nulls last,
           a.created_at desc
  limit 1
$$;

-- Reliable initial chat history, independent of Realtime subscription startup.
create or replace function public.get_listing_chat_messages(p_conversation_id uuid)
returns table(
  id uuid, conversation_id uuid, sender_id uuid, body text,
  client_message_id uuid, read_at timestamptz, created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, m.conversation_id, m.sender_id, m.body,
    m.client_message_id, m.read_at, m.created_at
  from public.listing_chat_messages m
  join public.listing_conversations c on c.id=m.conversation_id
  join public.agents a on a.id=c.agent_id
  where c.id=p_conversation_id
    and (c.customer_id=auth.uid() or a.profile_id=auth.uid())
  order by m.created_at asc, m.id asc
$$;
revoke all on function public.get_listing_chat_messages(uuid) from public;
grant execute on function public.get_listing_chat_messages(uuid) to authenticated;

-- Publish listing chat changes to both apps; RLS remains authoritative.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime' and not puballtables)
    and not exists(
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='listing_chat_messages'
    )
  then
    alter publication supabase_realtime add table public.listing_chat_messages;
  end if;
end $$;

-- Let the agent form show whether publication is currently free before upload.
create or replace function public.get_agent_listing_publication_mode()
returns table(payment_required boolean, amount_tzs integer)
language sql
stable
security definer
set search_path = public
as $$
  select public.agent_listing_payments_enabled(),
         case when public.agent_listing_payments_enabled() then 1000 else 0 end
$$;
revoke all on function public.get_agent_listing_publication_mode() from public;
grant execute on function public.get_agent_listing_publication_mode() to authenticated;

-- A device registered after sign-in should immediately retry recent skipped pushes.
create or replace function public.retry_recent_push_after_device_registration()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
begin
  update public.notification_delivery_outbox
  set status='pending', next_attempt_at=timezone('utc',now()), last_error=null,
      updated_at=timezone('utc',now())
  where user_id=new.user_id and status in ('skipped','failed')
    and created_at > timezone('utc',now()) - interval '1 hour';

  perform net.http_post(
    url := 'https://tlhoajedyaeaaqtrjqqh.supabase.co/functions/v1/dispatch-push-notifications',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('source','device_registration')
  );
  return new;
end $$;
drop trigger if exists retry_recent_push_after_device_registration on public.device_tokens;
create trigger retry_recent_push_after_device_registration
after insert or update of is_enabled, last_seen_at on public.device_tokens
for each row when (new.is_enabled=true)
execute function public.retry_recent_push_after_device_registration();
