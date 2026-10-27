begin;
select plan(5);
select has_function('public','prepare_event_payment_intent',array['uuid','text','text'],'typed event payment preparation exists');
select col_has_check('public','payment_intents','product','typed intents include constrained event products');
select is(public.kodimali_feature_enabled('event_deposit_payments'),false,'event deposit collection remains disabled');
select is(public.kodimali_feature_enabled('event_balance_payments'),false,'event balance collection remains disabled');
select is((select deposit_minor from public.calculate_booking_split(100000,25)),25000::bigint,'Events use the standard 25 percent deposit');
select * from finish();
rollback;
