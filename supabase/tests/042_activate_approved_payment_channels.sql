begin;

select plan(4);

select ok(
  (select booking_payments_enabled and event_payments_enabled
   from public.marketplace_settings where id = true),
  'booking and event payment channels are enabled'
);

select ok(
  (select contact_payments_enabled and chat_payments_enabled
          and agent_listing_payments_enabled and subscription_payments_enabled
          and listing_boost_payments_enabled
   from public.marketplace_settings where id = true),
  'commercial payment channels are enabled'
);

select is(
  (select count(*) from public.kodimali_feature_flags
   where key in (
     'instant_booking', 'booking_deposit_payments',
     'booking_balance_payments', 'paid_chat_unlock_v3',
     'contact_unlock_v3', 'event_deposit_payments',
     'event_balance_payments'
   ) and enabled),
  7::bigint,
  'approved KODIMALI 3 payment flags are enabled'
);

select ok(
  not public.kodimali_feature_enabled('automated_refunds')
  and not public.kodimali_feature_enabled('automated_provider_payouts'),
  'autonomous refunds and payouts remain disabled'
);

select * from finish();
rollback;
