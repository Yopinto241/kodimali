CREATE OR REPLACE FUNCTION public.guard_guest_booking_request_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_agent_id uuid;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.customer_id is null
     and new.customer_id = auth.uid()
     and new.listing_id is not distinct from old.listing_id
     and new.agent_id is not distinct from old.agent_id
     and new.customer_name is not distinct from old.customer_name
     and new.customer_phone_number is not distinct from old.customer_phone_number
     and new.customer_phone_normalized is not distinct from old.customer_phone_normalized
     and new.customer_email is not distinct from old.customer_email
     and new.customer_email_normalized is not distinct from old.customer_email_normalized
     and new.request_reference is not distinct from old.request_reference
     and new.requested_start_at is not distinct from old.requested_start_at
     and new.requested_end_at is not distinct from old.requested_end_at
     and new.guest_count is not distinct from old.guest_count
     and new.request_message is not distinct from old.request_message
     and new.requested_service_codes is not distinct from old.requested_service_codes
     and new.booking_status is not distinct from old.booking_status
     and new.agent_response_due_at is not distinct from old.agent_response_due_at
     and new.first_agent_response_at is not distinct from old.first_agent_response_at
     and new.admin_override is not distinct from old.admin_override
  then
    return new;
  end if;

  if public.is_admin(auth.uid()) then
    if new.listing_id is distinct from old.listing_id
      or new.agent_id is distinct from old.agent_id
      or new.customer_id is distinct from old.customer_id
      or new.customer_name is distinct from old.customer_name
      or new.customer_phone_number is distinct from old.customer_phone_number
      or new.customer_phone_normalized is distinct from old.customer_phone_normalized
      or new.customer_email is distinct from old.customer_email
      or new.customer_email_normalized is distinct from old.customer_email_normalized
      or new.request_reference is distinct from old.request_reference
      or new.requested_start_at is distinct from old.requested_start_at
      or new.requested_end_at is distinct from old.requested_end_at
      or new.guest_count is distinct from old.guest_count
      or new.request_message is distinct from old.request_message
      or new.requested_service_codes is distinct from old.requested_service_codes
    then
      raise exception 'Admin cannot change immutable guest-request fields';
    end if;
  else
    select a.id
    into v_agent_id
    from public.agents a
    where a.profile_id = auth.uid()
      and a.account_status = 'active'::public.agent_account_status
    limit 1;

    if v_agent_id is null or v_agent_id <> old.agent_id then
      raise exception 'Only the assigned active agent can update this request';
    end if;

    if new.listing_id is distinct from old.listing_id
      or new.agent_id is distinct from old.agent_id
      or new.customer_id is distinct from old.customer_id
      or new.customer_name is distinct from old.customer_name
      or new.customer_phone_number is distinct from old.customer_phone_number
      or new.customer_phone_normalized is distinct from old.customer_phone_normalized
      or new.customer_email is distinct from old.customer_email
      or new.customer_email_normalized is distinct from old.customer_email_normalized
      or new.request_reference is distinct from old.request_reference
      or new.requested_start_at is distinct from old.requested_start_at
      or new.requested_end_at is distinct from old.requested_end_at
      or new.guest_count is distinct from old.guest_count
      or new.request_message is distinct from old.request_message
      or new.requested_service_codes is distinct from old.requested_service_codes
      or new.admin_override is distinct from old.admin_override
    then
      raise exception 'Active agents can update only guest inquiry status fields';
    end if;
  end if;

  new.customer_id := old.customer_id;
  new.listing_id := old.listing_id;
  new.agent_id := old.agent_id;
  new.customer_name := old.customer_name;
  new.customer_phone_number := old.customer_phone_number;
  new.customer_phone_normalized := old.customer_phone_normalized;
  new.customer_email := old.customer_email;
  new.customer_email_normalized := old.customer_email_normalized;
  new.request_reference := old.request_reference;
  new.requested_start_at := old.requested_start_at;
  new.requested_end_at := old.requested_end_at;
  new.guest_count := old.guest_count;
  new.request_message := old.request_message;
  new.requested_service_codes := old.requested_service_codes;

  if new.booking_status is distinct from old.booking_status
     and old.first_agent_response_at is null then
    new.first_agent_response_at := timezone('utc', now());
  else
    new.first_agent_response_at := old.first_agent_response_at;
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.apply_listing_booking_mode()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_mode text;
begin
  if new.requested_start_at is null or new.requested_end_at is null then return new; end if;
  select coalesce(c.booking_mode,'request_booking') into v_mode
  from public.booking_configurations c where c.listing_id=new.listing_id;
  v_mode:=coalesce(v_mode,'request_booking');
  if v_mode='not_bookable' then raise exception 'This listing is not accepting bookings'; end if;
  new.booking_kind:='reservation';
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_conversation_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_booking_request_id uuid;
  v_updated integer;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  select c.booking_request_id
  into v_booking_request_id
  from public.booking_conversations c
  where c.id = p_conversation_id;

  if v_booking_request_id is null
     or not public.is_booking_participant(v_booking_request_id, v_user_id) then
    raise exception 'Conversation is not available' using errcode = '42501';
  end if;

  update public.booking_messages m
  set read_at = timezone('utc', now())
  where m.conversation_id = p_conversation_id
    and m.sender_id <> v_user_id
    and m.read_at is null;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$function$;