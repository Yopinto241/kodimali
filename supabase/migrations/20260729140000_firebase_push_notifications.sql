alter table public.device_tokens
  add column if not exists app_surface text not null default 'customer',
  add column if not exists device_id text,
  add column if not exists locale text not null default 'sw',
  add column if not exists is_enabled boolean not null default true,
  add column if not exists last_seen_at timestamptz not null default timezone('utc',now());

create index if not exists idx_device_tokens_user_enabled on public.device_tokens(user_id,is_enabled,app_surface);

create or replace function public.register_push_device(p_token text,p_platform text,p_app_surface text,p_device_id text default null,p_locale text default 'sw')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if length(trim(p_token))<20 then raise exception 'Invalid push token'; end if;
 insert into public.device_tokens(user_id,device_token,platform,app_surface,device_id,locale,is_enabled,last_seen_at)
 values(auth.uid(),trim(p_token),lower(trim(p_platform)),case when p_app_surface='manage' then 'manage' else 'customer' end,nullif(trim(p_device_id),''),case when p_locale='en' then 'en' else 'sw' end,true,timezone('utc',now()))
 on conflict(device_token) do update set user_id=auth.uid(),platform=excluded.platform,app_surface=excluded.app_surface,device_id=excluded.device_id,locale=excluded.locale,is_enabled=true,last_seen_at=timezone('utc',now()),updated_at=timezone('utc',now()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.unregister_push_device(p_token text)
returns void language sql security definer set search_path=public as $$
 update public.device_tokens set is_enabled=false,updated_at=timezone('utc',now()) where user_id=auth.uid() and device_token=p_token
$$;
revoke all on function public.register_push_device(text,text,text,text,text),public.unregister_push_device(text) from public;
grant execute on function public.register_push_device(text,text,text,text,text),public.unregister_push_device(text) to authenticated;

create table if not exists public.notification_delivery_outbox(
 id uuid primary key default gen_random_uuid(),
 notification_id uuid not null unique references public.notifications(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','processing','sent','failed','skipped')),
 attempt_count integer not null default 0,
 next_attempt_at timestamptz not null default timezone('utc',now()),
 firebase_message_ids jsonb not null default '[]'::jsonb,
 last_error text,
 processed_at timestamptz,
 created_at timestamptz not null default timezone('utc',now()),
 updated_at timestamptz not null default timezone('utc',now())
);
create index if not exists idx_notification_outbox_pending on public.notification_delivery_outbox(status,next_attempt_at,created_at);
alter table public.notification_delivery_outbox enable row level security;

create or replace function public.queue_notification_for_push()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.notification_delivery_outbox(notification_id,user_id) values(new.id,new.user_id) on conflict(notification_id) do nothing;
 return new;
end $$;
drop trigger if exists queue_notification_for_push on public.notifications;
create trigger queue_notification_for_push after insert on public.notifications for each row execute function public.queue_notification_for_push();

create or replace function public.notify_listing_chat_participant()
returns trigger language plpgsql security definer set search_path=public as $$
declare c public.listing_conversations%rowtype; v_agent_profile uuid; v_recipient uuid; v_sender_name text; v_title text;
begin
 select * into c from public.listing_conversations where id=new.conversation_id;
 select profile_id into v_agent_profile from public.agents where id=c.agent_id;
 v_recipient:=case when new.sender_id=c.customer_id then v_agent_profile else c.customer_id end;
 select coalesce(full_name,'KODIMALI user') into v_sender_name from public.profiles where id=new.sender_id;
 select title into v_title from public.listings where id=c.listing_id;
 if v_recipient is not null then
  insert into public.notifications(user_id,type,title,body,payload)
  values(v_recipient,'announcement',coalesce(v_sender_name,'New message'),left(new.body,120),jsonb_build_object('eventType','listing_chat_message','route','chat/'||c.id,'conversationId',c.id,'listingId',c.listing_id,'listingTitle',v_title));
 end if;
 return new;
end $$;
drop trigger if exists notify_listing_chat_participant on public.listing_chat_messages;
create trigger notify_listing_chat_participant after insert on public.listing_chat_messages for each row execute function public.notify_listing_chat_participant();

create or replace function public.notify_chat_payment_result()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.payment_status in ('paid','failed') and old.payment_status is distinct from new.payment_status then
  insert into public.notifications(user_id,type,title,body,payload) values(new.customer_id,'announcement',case when new.payment_status='paid' then 'Chat payment confirmed' else 'Chat payment failed' end,case when new.payment_status='paid' then 'Your private chat is available for 7 days.' else coalesce(new.status_message,'Please try the chat payment again.') end,jsonb_build_object('eventType','chat_payment_'||new.payment_status,'listingId',new.listing_id,'paymentId',new.id));
 end if; return new;
end $$;
drop trigger if exists notify_chat_payment_result on public.listing_chat_payments;
create trigger notify_chat_payment_result after update of payment_status on public.listing_chat_payments for each row execute function public.notify_chat_payment_result();

create or replace function public.notify_agent_listing_payment_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_profile uuid;
begin
 if new.payment_status in ('paid','failed') and old.payment_status is distinct from new.payment_status then
  select profile_id into v_profile from public.agents where id=new.agent_id;
  if v_profile is not null then insert into public.notifications(user_id,type,title,body,payload) values(v_profile,'announcement',case when new.payment_status='paid' then 'Listing payment confirmed' else 'Listing payment failed' end,case when new.payment_status='paid' then 'Your listing is now published.' else coalesce(new.status_message,'Please retry the listing payment.') end,jsonb_build_object('eventType','agent_listing_payment_'||new.payment_status,'listingId',new.listing_id,'paymentId',new.id)); end if;
 end if; return new;
end $$;
drop trigger if exists notify_agent_listing_payment_result on public.agent_listing_payments;
create trigger notify_agent_listing_payment_result after update of payment_status on public.agent_listing_payments for each row execute function public.notify_agent_listing_payment_result();
