do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'customer_phone_number'
      and is_nullable = 'NO'
  ) then
    execute '
      alter table public.booking_requests
      alter column customer_phone_number drop not null
    ';
  end if;
end
$$;
