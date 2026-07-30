create or replace function public.get_or_create_listing_conversation(p_listing_id uuid)
returns table(id uuid,listing_id uuid,agent_id uuid,customer_id uuid,status text,expires_at timestamptz,messages_sent_today integer,daily_limit integer)
language plpgsql security definer set search_path = public as $$
declare v_agent uuid; v_access public.listing_chat_access%rowtype; v_conversation public.listing_conversations%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to chat' using errcode='42501'; end if;
  select l.agent_id into v_agent from public.listings l where l.id=p_listing_id and public.is_listing_public(l.id);
  if v_agent is null then raise exception 'Listing chat is unavailable' using errcode='42501'; end if;
  select a.* into v_access from public.listing_chat_access a where a.customer_id=auth.uid() and a.listing_id=p_listing_id and a.agent_id=v_agent and a.revoked_at is null and a.expires_at>timezone('utc',now());
  if v_access.id is null and not public.chat_payments_enabled() then
    insert into public.listing_chat_access(listing_id,agent_id,customer_id,access_source,expires_at)
    values(p_listing_id,v_agent,auth.uid(),'free',timezone('utc',now())+interval '7 days')
    on conflict on constraint listing_chat_access_customer_id_listing_id_agent_id_key
    do update set access_source='free',starts_at=timezone('utc',now()),expires_at=timezone('utc',now())+interval '7 days',revoked_at=null,updated_at=timezone('utc',now()) returning * into v_access;
  end if;
  if v_access.id is null then raise exception 'Chat payment is required' using errcode='42501'; end if;
  insert into public.listing_conversations(listing_id,agent_id,customer_id) values(p_listing_id,v_agent,auth.uid())
  on conflict on constraint listing_conversations_customer_id_listing_id_agent_id_key
  do update set status='active',updated_at=timezone('utc',now()) returning * into v_conversation;
  return query select v_conversation.id,v_conversation.listing_id,v_conversation.agent_id,v_conversation.customer_id,v_conversation.status,v_access.expires_at,
    (select count(*)::integer from public.listing_chat_messages m where m.conversation_id=v_conversation.id and m.sender_id=auth.uid() and (m.created_at at time zone 'Africa/Dar_es_Salaam')::date=(timezone('Africa/Dar_es_Salaam',now()))::date),10;
end $$;
grant execute on function public.get_or_create_listing_conversation(uuid) to authenticated;
