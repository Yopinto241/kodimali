create or replace function public.auto_link_booking_customer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := public.normalize_contact_email(new.customer_email);
  v_phone text := public.normalize_contact_phone(new.customer_phone_number);
begin
  if new.customer_id is null then
    select p.id into new.customer_id
    from public.profiles p
    where (v_email is not null and public.normalize_contact_email(p.account_email)=v_email)
       or (v_phone is not null and public.normalize_contact_phone(p.phone_number)=v_phone)
    order by case when v_email is not null
      and public.normalize_contact_email(p.account_email)=v_email then 0 else 1 end
    limit 1;
  end if;
  return new;
end;
$$;

