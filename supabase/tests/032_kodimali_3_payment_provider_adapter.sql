begin;
select plan(3);

select has_column('public','platform_payment_orders','provider','platform orders retain their payment provider');
select col_is_null('public','platform_payment_orders','provider','unprovable historical provider values may remain null');
select has_index('public','platform_payment_orders','platform_payment_orders_provider_order_idx','provider order lookup is indexed');

select * from finish();
rollback;

