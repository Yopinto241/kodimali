do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'customer_phone_normalized'
      and is_nullable = 'NO'
  ) then
    execute '
      alter table public.booking_requests
      alter column customer_phone_normalized drop not null
    ';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'booking_requests'
      and column_name = 'customer_email_normalized'
      and is_nullable = 'NO'
  ) then
    execute '
      alter table public.booking_requests
      alter column customer_email_normalized drop not null
    ';
  end if;
end
$$;
