begin;
select plan(5);
select has_function('public','sync_legacy_access_payment_intent',array[]::text[],'legacy access payment bridge exists');
select has_trigger('public','listing_chat_payments','sync_chat_payment_intent','chat payments are mirrored');
select has_trigger('public','listing_contact_payments','sync_contact_payment_intent','contact payments are mirrored');
select has_index('public','listing_chat_payments','listing_chat_one_open_payment_idx','duplicate open chat payments are prevented');
select is(has_function_privilege('authenticated','public.sync_legacy_access_payment_intent()','EXECUTE'),false,'clients cannot call finance bridge directly');
select * from finish();
rollback;
