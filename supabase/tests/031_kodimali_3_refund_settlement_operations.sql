begin;
select plan(20);

select function_is_definer('public','post_cancellation_allocation',array[]::text[],'cancellation allocation is posted server-side');
select function_is_definer('public','prepare_refund_execution',array['uuid','text'],'refund preparation is server-side');
select function_is_definer('public','record_refund_provider_result',array['uuid','boolean','text','text','jsonb'],'refund provider result is server-side');
select function_is_definer('public','create_provider_settlement_batch',array['uuid[]','text'],'settlement batches are created server-side');
select function_is_definer('public','approve_provider_settlement_batch',array['uuid','text'],'settlement approval is server-side');
select function_is_definer('public','record_settlement_provider_result',array['uuid','boolean','text','text','jsonb'],'settlement provider result is server-side');
select function_is_definer('public','release_failed_settlement_payable',array['uuid','text'],'failed settlement recovery is server-side');
select is(has_function_privilege('anon','public.prepare_refund_execution(uuid,text)','EXECUTE'),false,'anonymous users cannot prepare refunds');
select is(has_function_privilege('anon','public.create_provider_settlement_batch(uuid[],text)','EXECUTE'),false,'anonymous users cannot create settlement batches');
select is(has_function_privilege('anon','public.approve_provider_settlement_batch(uuid,text)','EXECUTE'),false,'anonymous users cannot approve settlement batches');
select is(has_function_privilege('authenticated','public.record_refund_provider_result(uuid,boolean,text,text,jsonb)','EXECUTE'),false,'clients cannot record provider refund success');
select is(has_function_privilege('authenticated','public.record_settlement_provider_result(uuid,boolean,text,text,jsonb)','EXECUTE'),false,'clients cannot record provider payout success');
select has_index('public','settlement_batch_items','settlement_item_provider_transaction_idx','provider settlement transaction IDs are unique');
select has_index('public','settlement_batch_items','settlement_active_payable_idx','only one active settlement item may use a payable');
select has_column('public','refund_obligations','provider','refund keeps its execution provider');
select has_column('public','refund_obligations','provider_transaction_id','refund keeps its provider transaction ID');
select has_column('public','refund_obligations','provider_payload','refund keeps its provider response for reconciliation');
select has_column('public','settlement_batch_items','provider_payload','settlement item keeps its provider response');
select has_column('public','settlement_batch_items','provider','settlement item keeps its execution provider');
select has_index('public','refund_obligations','refund_obligation_provider_transaction_idx','refund provider transaction identities are unique');

select * from finish();
rollback;
