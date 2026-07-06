create or replace function public.notify_agent_of_inquiry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile uuid;
  v_title text;
  v_contact text;
begin
  select a.profile_id, l.title
  into v_profile, v_title
  from public.agents a
  join public.listings l on l.agent_id = a.id
  where a.id = new.agent_id
    and l.id = new.listing_id;

  if v_profile is not null and tg_op = 'INSERT' then
    v_contact := coalesce(
      nullif(btrim(new.customer_phone_number), ''),
      nullif(btrim(new.customer_email), ''),
      nullif(btrim(new.customer_name), ''),
      'Guest'
    );

    insert into public.notifications (
      user_id,
      booking_request_id,
      type,
      title,
      body,
      payload
    )
    values (
      v_profile,
      new.id,
      'booking_created'::public.notification_type,
      'New inquiry received',
      coalesce(v_title, 'Listing') || ' | ' || coalesce(new.customer_name, 'Guest') || ' | ' || v_contact,
      jsonb_build_object(
        'booking_request_id', new.id,
        'listing_id', new.listing_id,
        'request_reference', new.request_reference
      )
    );
  end if;

  return new;
end;
$$;
