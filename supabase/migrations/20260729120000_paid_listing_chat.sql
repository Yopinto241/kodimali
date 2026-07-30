alter table public.marketplace_settings
  add column if not exists chat_payments_enabled boolean not null default true;

create or replace function public.chat_payments_enabled()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select chat_payments_enabled from public.marketplace_settings where id = true), true)
$$;
revoke all on function public.chat_payments_enabled() from public;
grant execute on function public.chat_payments_enabled() to anon, authenticated, service_role;

create table if not exists public.listing_chat_payments (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  agent_id uuid not null references public.agents(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  order_reference text not null unique,
  payment_provider text not null default 'clickpesa',
  payment_status text not null default 'pending' check (payment_status in ('pending','processing','paid','failed','expired','cancelled')),
  requested_amount numeric(12,2) not null default 500 check (requested_amount = 500),
  requested_currency text not null default 'TZS',
  customer_phone_number text not null,
  provider_payment_id text,
  provider_payment_reference text,
  provider_channel text,
  status_message text,
  provider_response jsonb not null default '{}'::jsonb,
  webhook_payload jsonb not null default '{}'::jsonb,
  webhook_received_at timestamptz,
  reconciliation_status text,
  next_reconcile_at timestamptz,
  paid_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
create index if not exists idx_listing_chat_payments_customer_listing
  on public.listing_chat_payments(customer_id, listing_id, created_at desc);
alter table public.listing_chat_payments enable row level security;
create policy listing_chat_payments_customer_select on public.listing_chat_payments
  for select to authenticated using (customer_id = auth.uid());

create table if not exists public.listing_chat_access (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  agent_id uuid not null references public.agents(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  payment_id uuid references public.listing_chat_payments(id) on delete set null,
  access_source text not null check (access_source in ('paid','free')),
  starts_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique(customer_id, listing_id, agent_id)
);
alter table public.listing_chat_access enable row level security;
create policy listing_chat_access_participant_select on public.listing_chat_access
  for select to authenticated using (
    customer_id = auth.uid() or agent_id in (select id from public.agents where profile_id = auth.uid())
  );

create table if not exists public.listing_conversations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  agent_id uuid not null references public.agents(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check(status in ('active','closed','blocked')),
  last_message_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique(customer_id, listing_id, agent_id)
);
alter table public.listing_conversations enable row level security;
create policy listing_conversations_participant_select on public.listing_conversations
  for select to authenticated using (
    customer_id = auth.uid() or agent_id in (select id from public.agents where profile_id = auth.uid())
  );

create table if not exists public.listing_chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.listing_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check(char_length(trim(body)) between 1 and 1000),
  client_message_id uuid not null default gen_random_uuid(),
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  unique(conversation_id, sender_id, client_message_id)
);
create index if not exists idx_listing_chat_messages_conversation on public.listing_chat_messages(conversation_id, created_at);
alter table public.listing_chat_messages enable row level security;
create policy listing_chat_messages_participant_select on public.listing_chat_messages
  for select to authenticated using (exists (
    select 1 from public.listing_conversations c
    where c.id = conversation_id and (
      c.customer_id = auth.uid() or c.agent_id in (select id from public.agents where profile_id = auth.uid())
    )
  ));

create or replace function public.grant_listing_chat_access(p_payment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare p public.listing_chat_payments%rowtype; v_now timestamptz := timezone('utc', now());
begin
  select * into p from public.listing_chat_payments where id = p_payment_id and payment_status = 'paid';
  if p.id is null then return; end if;
  insert into public.listing_chat_access(listing_id,agent_id,customer_id,payment_id,access_source,starts_at,expires_at,revoked_at)
  values(p.listing_id,p.agent_id,p.customer_id,p.id,'paid',v_now,v_now + interval '7 days',null)
  on conflict(customer_id,listing_id,agent_id) do update set
    payment_id=excluded.payment_id, access_source='paid', starts_at=v_now,
    expires_at=greatest(public.listing_chat_access.expires_at,v_now) + interval '7 days', revoked_at=null, updated_at=v_now;
end $$;

create or replace function public.release_paid_listing_chat()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.payment_status='paid' and old.payment_status is distinct from 'paid' then
    perform public.grant_listing_chat_access(new.id);
  end if;
  return new;
end $$;
create trigger release_paid_listing_chat after update of payment_status on public.listing_chat_payments
for each row execute function public.release_paid_listing_chat();

create or replace function public.get_or_create_listing_conversation(p_listing_id uuid)
returns table(id uuid,listing_id uuid,agent_id uuid,customer_id uuid,status text,expires_at timestamptz,messages_sent_today integer,daily_limit integer)
language plpgsql security definer set search_path = public as $$
declare v_agent uuid; v_access public.listing_chat_access%rowtype; v_conversation public.listing_conversations%rowtype; v_agent_profile uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to chat' using errcode='42501'; end if;
  select l.agent_id into v_agent from public.listings l where l.id=p_listing_id and public.is_listing_public(l.id);
  if v_agent is null then raise exception 'Listing chat is unavailable' using errcode='42501'; end if;
  select * into v_access from public.listing_chat_access a where a.customer_id=auth.uid() and a.listing_id=p_listing_id and a.agent_id=v_agent and a.revoked_at is null and a.expires_at>timezone('utc',now());
  if v_access.id is null and not public.chat_payments_enabled() then
    insert into public.listing_chat_access(listing_id,agent_id,customer_id,access_source,expires_at)
    values(p_listing_id,v_agent,auth.uid(),'free',timezone('utc',now())+interval '7 days')
    on conflict(customer_id,listing_id,agent_id) do update set access_source='free',starts_at=timezone('utc',now()),expires_at=timezone('utc',now())+interval '7 days',revoked_at=null,updated_at=timezone('utc',now()) returning * into v_access;
  end if;
  if v_access.id is null then raise exception 'Chat payment is required' using errcode='42501'; end if;
  insert into public.listing_conversations(listing_id,agent_id,customer_id) values(p_listing_id,v_agent,auth.uid())
  on conflict(customer_id,listing_id,agent_id) do update set status='active',updated_at=timezone('utc',now()) returning * into v_conversation;
  return query select v_conversation.id,v_conversation.listing_id,v_conversation.agent_id,v_conversation.customer_id,v_conversation.status,v_access.expires_at,
    (select count(*)::integer from public.listing_chat_messages m where m.conversation_id=v_conversation.id and m.sender_id=auth.uid() and (m.created_at at time zone 'Africa/Dar_es_Salaam')::date=(timezone('Africa/Dar_es_Salaam',now()))::date),10;
end $$;

create or replace function public.send_listing_chat_message(p_conversation_id uuid,p_body text,p_client_message_id uuid default gen_random_uuid())
returns setof public.listing_chat_messages language plpgsql security definer set search_path=public as $$
declare c public.listing_conversations%rowtype; v_agent_profile uuid; v_count integer; v_access boolean;
begin
  select * into c from public.listing_conversations where id=p_conversation_id for update;
  select profile_id into v_agent_profile from public.agents where id=c.agent_id and account_status='active';
  if c.id is null or c.status<>'active' or auth.uid() not in (c.customer_id,v_agent_profile) then raise exception 'Not a conversation participant' using errcode='42501'; end if;
  select exists(select 1 from public.listing_chat_access a where a.customer_id=c.customer_id and a.agent_id=c.agent_id and a.listing_id=c.listing_id and a.revoked_at is null and a.expires_at>timezone('utc',now())) into v_access;
  if not v_access then raise exception 'Chat access has expired' using errcode='42501'; end if;
  select count(*) into v_count from public.listing_chat_messages m where m.conversation_id=c.id and m.sender_id=auth.uid() and (m.created_at at time zone 'Africa/Dar_es_Salaam')::date=(timezone('Africa/Dar_es_Salaam',now()))::date;
  if v_count>=10 then raise exception 'Daily message limit reached (10 messages)' using errcode='P0001'; end if;
  return query insert into public.listing_chat_messages(conversation_id,sender_id,body,client_message_id)
    values(c.id,auth.uid(),trim(p_body),p_client_message_id) on conflict(conversation_id,sender_id,client_message_id) do update set body=excluded.body returning *;
  update public.listing_conversations set last_message_at=timezone('utc',now()),updated_at=timezone('utc',now()) where id=c.id;
end $$;

create or replace function public.list_my_listing_conversations()
returns table(id uuid,listing_id uuid,listing_title text,agent_id uuid,agent_name text,customer_id uuid,customer_name text,last_message_at timestamptz,expires_at timestamptz,messages_sent_today integer,daily_limit integer)
language sql security definer set search_path=public as $$
 select c.id,c.listing_id,l.title,c.agent_id,coalesce(a.display_name,a.business_name,'Agent'),c.customer_id,coalesce(p.full_name,'Customer'),c.last_message_at,x.expires_at,
 (select count(*)::integer from public.listing_chat_messages m where m.conversation_id=c.id and m.sender_id=auth.uid() and (m.created_at at time zone 'Africa/Dar_es_Salaam')::date=(timezone('Africa/Dar_es_Salaam',now()))::date),10
 from public.listing_conversations c join public.listings l on l.id=c.listing_id join public.agents a on a.id=c.agent_id join public.profiles p on p.id=c.customer_id join public.listing_chat_access x on x.customer_id=c.customer_id and x.agent_id=c.agent_id and x.listing_id=c.listing_id
 where c.customer_id=auth.uid() or a.profile_id=auth.uid() order by coalesce(c.last_message_at,c.created_at) desc
$$;

create or replace function public.get_listing_chat_conversation(p_conversation_id uuid)
returns table(id uuid,listing_id uuid,listing_title text,agent_id uuid,agent_name text,customer_id uuid,customer_name text,expires_at timestamptz,messages_sent_today integer,daily_limit integer)
language sql security definer set search_path=public as $$
 select c.id,c.listing_id,l.title,c.agent_id,coalesce(a.display_name,a.business_name,'Agent'),c.customer_id,coalesce(p.full_name,'Customer'),x.expires_at,
 (select count(*)::integer from public.listing_chat_messages m where m.conversation_id=c.id and m.sender_id=auth.uid() and (m.created_at at time zone 'Africa/Dar_es_Salaam')::date=(timezone('Africa/Dar_es_Salaam',now()))::date),10
 from public.listing_conversations c join public.listings l on l.id=c.listing_id join public.agents a on a.id=c.agent_id join public.profiles p on p.id=c.customer_id join public.listing_chat_access x on x.customer_id=c.customer_id and x.agent_id=c.agent_id and x.listing_id=c.listing_id
 where c.id=p_conversation_id and (c.customer_id=auth.uid() or a.profile_id=auth.uid())
$$;

revoke all on function public.get_or_create_listing_conversation(uuid),public.send_listing_chat_message(uuid,text,uuid),public.list_my_listing_conversations(),public.get_listing_chat_conversation(uuid) from public;
grant execute on function public.get_or_create_listing_conversation(uuid),public.send_listing_chat_message(uuid,text,uuid),public.list_my_listing_conversations(),public.get_listing_chat_conversation(uuid) to authenticated;
grant select on public.listing_conversations,public.listing_chat_messages,public.listing_chat_access,public.listing_chat_payments to authenticated;

alter table public.listing_contact_payments add column if not exists access_expires_at timestamptz;
update public.listing_contact_payments set access_expires_at=coalesce(paid_at,contact_revealed_at,created_at)+interval '24 hours' where payment_status='paid' and access_expires_at is null;
