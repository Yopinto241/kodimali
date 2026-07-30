alter table public.booking_messages add column if not exists response_code text;

create or replace function public.booking_response_body(p_code text,p_sender_kind text) returns text language sql immutable as $$
 select case
  when p_sender_kind='agent' and p_code='request_received' then 'Request received. I will review it.'
  when p_sender_kind='agent' and p_code='checking_availability' then 'I am checking availability.'
  when p_sender_kind='agent' and p_code='available' then 'The listing is available.'
  when p_sender_kind='agent' and p_code='unavailable' then 'The listing is not available for the requested time.'
  when p_sender_kind='agent' and p_code='will_call' then 'I will call you using the contact supplied with this request.'
  when p_sender_kind='agent' and p_code='viewing_proposed' then 'A viewing has been proposed. Please review the appointment.'
  when p_sender_kind='agent' and p_code='need_more_time' then 'I need more time to confirm this request.'
  when p_sender_kind='customer' and p_code='acknowledged' then 'Okay, I have received this update.'
  when p_sender_kind='customer' and p_code='still_interested' then 'I am still interested.'
  when p_sender_kind='customer' and p_code='confirm_viewing' then 'I confirm the proposed viewing.'
  when p_sender_kind='customer' and p_code='request_reschedule' then 'Please propose another viewing time.'
  when p_sender_kind='customer' and p_code='not_interested' then 'I am no longer interested.'
  else null end;
$$;

create or replace function public.guard_booking_message()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_conversation public.booking_conversations%rowtype;v_agent_profile_id uuid;v_kind text;v_body text;
begin
 if tg_op='UPDATE' and new.conversation_id is not distinct from old.conversation_id and new.sender_id is not distinct from old.sender_id and new.message_type is not distinct from old.message_type and new.body is not distinct from old.body and new.response_code is not distinct from old.response_code and new.client_message_id is not distinct from old.client_message_id and new.edited_at is not distinct from old.edited_at and new.created_at is not distinct from old.created_at then return new; end if;
 if tg_op<>'INSERT' then raise exception 'Request responses are append-only';end if;
 select * into v_conversation from public.booking_conversations where id=new.conversation_id and status='active';
 if not found then raise exception 'Request response channel is not active';end if;
 select profile_id into v_agent_profile_id from public.agents where id=v_conversation.agent_id;
 if auth.uid()=v_conversation.customer_id then v_kind:='customer';elsif auth.uid()=v_agent_profile_id then v_kind:='agent';else raise exception 'Administrators cannot send request responses';end if;
 v_body:=public.booking_response_body(new.response_code,v_kind);
 if v_body is null then raise exception 'This response is not allowed for %',v_kind;end if;
 new.sender_id:=auth.uid();new.message_type:='system';new.body:=v_body;
 return new;
end $$;

create or replace function public.send_booking_response(p_conversation_id uuid,p_response_code text,p_client_message_id uuid default gen_random_uuid())
returns setof public.booking_messages language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_conversation public.booking_conversations%rowtype;v_agent_profile uuid;v_kind text;v_body text;v_id uuid;
begin
 if v_user is null then raise exception 'Authentication is required' using errcode='42501';end if;
 select * into v_conversation from public.booking_conversations where id=p_conversation_id and status='active';
 select profile_id into v_agent_profile from public.agents where id=v_conversation.agent_id;
 if v_user=v_conversation.customer_id then v_kind:='customer';elsif v_user=v_agent_profile then v_kind:='agent';else raise exception 'Only the customer or assigned agent can respond' using errcode='42501';end if;
 v_body:=public.booking_response_body(p_response_code,v_kind);if v_body is null then raise exception 'Unsupported request response';end if;
 insert into public.booking_messages(conversation_id,sender_id,message_type,body,response_code,client_message_id) values(p_conversation_id,v_user,'system',v_body,p_response_code,coalesce(p_client_message_id,gen_random_uuid())) on conflict(conversation_id,sender_id,client_message_id) do nothing returning id into v_id;
 return query select * from public.booking_messages where id=v_id;
end $$;
revoke all on function public.send_booking_message(uuid,text,uuid) from anon,authenticated;
grant execute on function public.send_booking_response(uuid,text,uuid) to authenticated;

comment on function public.send_booking_response(uuid,text,uuid) is 'Structured booking follow-up only. Free text and administrator messages are intentionally prohibited so requests cannot bypass paid chat/contact access.';
