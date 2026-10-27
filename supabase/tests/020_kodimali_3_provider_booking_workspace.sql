begin;
select plan(5);

select has_function(
  'public',
  'confirm_provider_fulfillment_milestone',
  array['uuid'],
  'provider fulfillment confirmation RPC exists'
);
select function_lang_is(
  'public',
  'confirm_provider_fulfillment_milestone',
  array['uuid'],
  'plpgsql',
  'provider confirmation is implemented server-side'
);
select function_is_definer(
  'public',
  'confirm_provider_fulfillment_milestone',
  array['uuid'],
  'provider confirmation uses controlled definer authorization'
);
select policies_are(
  'public',
  'payment_intents',
  array['payment_intents_assigned_provider_read','payment_intents_customer_finance_read'],
  'payment intents expose only customer, assigned-provider or finance-authorized reads'
);
select is(
  has_table_privilege('authenticated','public.financial_postings','UPDATE'),
  false,
  'providers cannot edit posted financial records'
);

select * from finish();
rollback;
