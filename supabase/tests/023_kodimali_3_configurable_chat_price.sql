begin;
select plan(5);
select has_column('public','marketplace_settings','paid_chat_unlock_amount_tzs','paid chat price is configurable');
select has_function('public','paid_chat_unlock_price',array[]::text[],'public price reader exists');
select has_function('public','set_paid_chat_unlock_price',array['bigint'],'controlled price writer exists');
select is(has_function_privilege('anon','public.set_paid_chat_unlock_price(bigint)','EXECUTE'),false,'anonymous users cannot change price');
select col_has_check('public','listing_chat_payments','requested_amount','chat payment amount remains positive');
select * from finish();
rollback;
