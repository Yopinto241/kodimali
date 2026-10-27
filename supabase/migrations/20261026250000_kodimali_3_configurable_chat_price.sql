-- KODIMALI 3.0: an administrator-approved paid-chat price.
alter table public.marketplace_settings
add column if not exists paid_chat_unlock_amount_tzs bigint not null default 500
check (paid_chat_unlock_amount_tzs > 0);

alter table public.listing_chat_payments
drop constraint if exists listing_chat_payments_requested_amount_check;
alter table public.listing_chat_payments
add constraint listing_chat_payments_requested_amount_positive
check (requested_amount > 0);

create or replace function public.paid_chat_unlock_price()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select paid_chat_unlock_amount_tzs
    from public.marketplace_settings
    where id = true
  ), 500::bigint);
$$;

create or replace function public.set_paid_chat_unlock_price(p_amount_tzs bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_admin_permission('payments.manage') then
    raise exception 'Payment management permission required';
  end if;
  if p_amount_tzs <= 0 then
    raise exception 'Paid chat price must be greater than zero';
  end if;

  insert into public.marketplace_settings(id, paid_chat_unlock_amount_tzs, updated_at, updated_by)
  values(true, p_amount_tzs, now(), auth.uid())
  on conflict(id) do update set
    paid_chat_unlock_amount_tzs = excluded.paid_chat_unlock_amount_tzs,
    updated_at = now(),
    updated_by = auth.uid();

  insert into public.audit_logs(actor_id, action, target_table, metadata)
  values(auth.uid(), 'paid_chat_price_changed', 'marketplace_settings', jsonb_build_object('amount_tzs',p_amount_tzs));
  return p_amount_tzs;
end;
$$;

revoke all on function public.paid_chat_unlock_price() from public;
grant execute on function public.paid_chat_unlock_price() to anon, authenticated, service_role;
revoke all on function public.set_paid_chat_unlock_price(bigint) from public, anon, authenticated;
grant execute on function public.set_paid_chat_unlock_price(bigint) to authenticated, service_role;
