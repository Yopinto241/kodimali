-- Keep paid/free publication and private-chat state consistent even when a
-- provider webhook is repeated or an administrator changes a payment toggle.

create or replace function public.release_agent_listing_if_eligible(p_listing_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changed_count integer := 0;
begin
  update public.listings l
  set status = 'active'::public.listing_status,
      publication_requested = false,
      published_at = coalesce(l.published_at, timezone('utc', now()))
  where l.id = p_listing_id
    and l.status = 'inactive'::public.listing_status
    and l.removed_from_market_at is null
    and l.removed_reason is null
    and public.listing_has_publishable_media(l.id)
    and (
      not public.agent_listing_payments_enabled()
      or exists (
        select 1
        from public.agent_listing_payments p
        where p.listing_id = l.id
          and p.agent_id = l.agent_id
          and p.payment_status = 'paid'
      )
    );
  get diagnostics v_changed_count = row_count;
  return v_changed_count > 0;
end;
$$;

revoke all on function public.release_agent_listing_if_eligible(uuid) from public;
grant execute on function public.release_agent_listing_if_eligible(uuid) to service_role;

create or replace function public.release_paid_agent_listing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payment_status = 'paid' then
    perform public.release_agent_listing_if_eligible(new.listing_id);
  end if;
  return new;
end;
$$;

create or replace function public.release_free_agent_listings_after_toggle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing record;
begin
  if new.agent_listing_payments_enabled = false
    and old.agent_listing_payments_enabled is distinct from false
  then
    for v_listing in
      select l.id
      from public.listings l
      where l.status = 'inactive'::public.listing_status
        and l.removed_from_market_at is null
        and l.removed_reason is null
        and public.listing_has_publishable_media(l.id)
    loop
      perform public.release_agent_listing_if_eligible(v_listing.id);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists release_free_agent_listings_after_toggle on public.marketplace_settings;
create trigger release_free_agent_listings_after_toggle
after update of agent_listing_payments_enabled on public.marketplace_settings
for each row execute function public.release_free_agent_listings_after_toggle();

-- Expose unread information and the last message in both participants' chat lists.
drop function if exists public.list_my_listing_conversations();
create function public.list_my_listing_conversations()
returns table(
  id uuid, listing_id uuid, listing_title text, agent_id uuid,
  agent_name text, customer_id uuid, customer_name text,
  last_message_at timestamptz, expires_at timestamptz,
  messages_sent_today integer, daily_limit integer,
  last_message text, unread_count integer
)
language sql
security definer
set search_path = public
as $$
  select c.id, c.listing_id, l.title, c.agent_id,
    coalesce(a.display_name,a.business_name,'Agent'), c.customer_id,
    coalesce(p.full_name,'Customer'), c.last_message_at, x.expires_at,
    (select count(*)::integer from public.listing_chat_messages m
      where m.conversation_id=c.id and m.sender_id=auth.uid()
      and (m.created_at at time zone 'Africa/Dar_es_Salaam')::date=(timezone('Africa/Dar_es_Salaam',now()))::date),
    10,
    (select m.body from public.listing_chat_messages m where m.conversation_id=c.id order by m.created_at desc limit 1),
    (select count(*)::integer from public.listing_chat_messages m
      where m.conversation_id=c.id and m.sender_id<>auth.uid() and m.read_at is null)
  from public.listing_conversations c
  join public.listings l on l.id=c.listing_id
  join public.agents a on a.id=c.agent_id
  join public.profiles p on p.id=c.customer_id
  join public.listing_chat_access x on x.customer_id=c.customer_id and x.agent_id=c.agent_id and x.listing_id=c.listing_id
  where c.customer_id=auth.uid() or a.profile_id=auth.uid()
  order by coalesce(c.last_message_at,c.created_at) desc
$$;

revoke all on function public.list_my_listing_conversations() from public;
grant execute on function public.list_my_listing_conversations() to authenticated;

create or replace function public.mark_listing_chat_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_customer uuid; v_agent_profile uuid;
begin
  select c.customer_id, a.profile_id into v_customer, v_agent_profile
  from public.listing_conversations c join public.agents a on a.id=c.agent_id
  where c.id=p_conversation_id;
  if auth.uid() not in (v_customer, v_agent_profile) then
    raise exception 'Not a conversation participant' using errcode='42501';
  end if;
  update public.listing_chat_messages
  set read_at=coalesce(read_at, timezone('utc',now()))
  where conversation_id=p_conversation_id and sender_id<>auth.uid() and read_at is null;
end;
$$;
revoke all on function public.mark_listing_chat_read(uuid) from public;
grant execute on function public.mark_listing_chat_read(uuid) to authenticated;
