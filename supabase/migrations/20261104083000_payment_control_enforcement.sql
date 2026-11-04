-- Never resets or enables a flag, changes a price, or reprocesses an old order.
create or replace function public.payment_feature_enabled(p_purpose text)
returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select case
   when p_purpose='booking_reservation' then booking_payments_enabled and public.kodimali_feature_enabled('instant_booking')
   when p_purpose='booking_deposit' then booking_payments_enabled and public.kodimali_feature_enabled('booking_deposit_payments')
   when p_purpose='booking_balance' then booking_payments_enabled and public.kodimali_feature_enabled('booking_balance_payments')
   when p_purpose='event_deposit' then event_payments_enabled and public.kodimali_feature_enabled('event_deposit_payments')
   when p_purpose='event_balance' then event_payments_enabled and public.kodimali_feature_enabled('event_balance_payments')
   when p_purpose='paid_chat' then chat_payments_enabled
   when p_purpose='contact' then contact_payments_enabled
   when p_purpose='publication' then agent_listing_payments_enabled
   when p_purpose='subscription' then subscription_payments_enabled
   when p_purpose='listing_boost' then listing_boost_payments_enabled
   else false end from public.marketplace_settings where id=true),false)
$$;
alter function public.prepare_booking_payment_intent(uuid,text,text) rename to prepare_booking_payment_intent_before_controls;
revoke all on function public.prepare_booking_payment_intent_before_controls(uuid,text,text) from public,anon,authenticated,service_role;
create function public.prepare_booking_payment_intent(p_booking_id uuid,p_product text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.payment_feature_enabled(p_product) then raise exception 'This payment product is currently disabled'; end if;
 return public.prepare_booking_payment_intent_before_controls(p_booking_id,p_product,p_idempotency_key);
end $$;
revoke all on function public.prepare_booking_payment_intent(uuid,text,text) from public,anon;
grant execute on function public.prepare_booking_payment_intent(uuid,text,text) to authenticated,service_role;
alter function public.prepare_event_payment_intent(uuid,text,text) rename to prepare_event_payment_intent_before_controls;
revoke all on function public.prepare_event_payment_intent_before_controls(uuid,text,text) from public,anon,authenticated,service_role;
create function public.prepare_event_payment_intent(p_plan_id uuid,p_product text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.payment_feature_enabled(p_product) then raise exception 'This payment product is currently disabled'; end if;
 return public.prepare_event_payment_intent_before_controls(p_plan_id,p_product,p_idempotency_key);
end $$;
revoke all on function public.prepare_event_payment_intent(uuid,text,text) from public,anon;
grant execute on function public.prepare_event_payment_intent(uuid,text,text) to authenticated,service_role;
notify pgrst,'reload schema';
