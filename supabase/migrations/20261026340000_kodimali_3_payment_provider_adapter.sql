-- KODIMALI 3.0: persist the collection provider on every platform order so
-- status checks and callbacks never guess which adapter owns an order.

alter table public.platform_payment_orders
  add column if not exists provider text;

update public.platform_payment_orders
set provider='sonicpesa'
where provider is null and provider_order_id like 'sp\_%' escape '\';

create index if not exists platform_payment_orders_provider_order_idx
on public.platform_payment_orders(provider,provider_order_id)
where provider_order_id is not null;

comment on column public.platform_payment_orders.provider is
'Server-selected payment-provider adapter that created this order; null is retained only for historical orders whose provider cannot be proven.';

