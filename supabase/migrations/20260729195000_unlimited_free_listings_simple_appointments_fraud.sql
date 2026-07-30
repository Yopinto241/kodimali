-- Free has no monthly charge and no listing-count cap. Each publication still
-- uses the configured 1,000 TZS pay-per-listing workflow.
update public.agent_subscription_plans
set listing_limit=null,publication_fee_tzs=1000,
    features='["Unlimited listings","1,000 TZS per published listing"]'::jsonb,
    updated_at=now()
where id='free';

create or replace function public.strip_viewing_appointment_notes()
returns trigger language plpgsql as $$
begin new.location_note:=null;new.response_note:=null;return new;end $$;
drop trigger if exists z_strip_viewing_appointment_notes on public.viewing_appointments;
create trigger z_strip_viewing_appointment_notes before insert or update on public.viewing_appointments
for each row execute function public.strip_viewing_appointment_notes();
update public.viewing_appointments set location_note=null,response_note=null where location_note is not null or response_note is not null;

create or replace function public.flag_repeated_failed_payment()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_count bigint;v_phone text;
begin
 if new.payment_status='failed' and old.payment_status is distinct from 'failed' then
  v_phone:=regexp_replace(coalesce(new.customer_phone_number,''),'[^0-9]','','g');
  if length(v_phone)>=9 then
   execute format('select count(*) from public.%I where payment_status=''failed'' and regexp_replace(coalesce(customer_phone_number,''''),''[^0-9]'','''',''g'')=$1 and created_at>now()-interval ''24 hours''',tg_table_name) into v_count using v_phone;
   if v_count>=3 and not exists(select 1 from public.platform_risk_flags where entity_type='payment' and entity_id=new.id and risk_type='repeated_payment_failures') then
    insert into public.platform_risk_flags(entity_type,entity_id,risk_type,severity,reason,evidence)
    values('payment',new.id,'repeated_payment_failures',case when v_count>=6 then 'high' else 'medium' end,'The same phone number produced repeated failed payments within 24 hours',jsonb_build_object('failure_count',v_count,'payment_table',tg_table_name));
   end if;
  end if;
 end if;return new;
end $$;
drop trigger if exists flag_failed_contact_payment on public.listing_contact_payments;
create trigger flag_failed_contact_payment after update of payment_status on public.listing_contact_payments for each row execute function public.flag_repeated_failed_payment();
drop trigger if exists flag_failed_chat_payment on public.listing_chat_payments;
create trigger flag_failed_chat_payment after update of payment_status on public.listing_chat_payments for each row execute function public.flag_repeated_failed_payment();
drop trigger if exists flag_failed_listing_payment on public.agent_listing_payments;
create trigger flag_failed_listing_payment after update of payment_status on public.agent_listing_payments for each row execute function public.flag_repeated_failed_payment();
drop trigger if exists flag_failed_commercial_payment on public.agent_commercial_payments;
create trigger flag_failed_commercial_payment after update of payment_status on public.agent_commercial_payments for each row execute function public.flag_repeated_failed_payment();
