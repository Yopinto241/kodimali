begin;
select plan(4);

select has_function('public','review_financial_reconciliation',array['uuid','text','text'],'reconciliation review function exists');
select function_is_definer('public','review_financial_reconciliation',array['uuid','text','text'],'reconciliation review permission is server-side');
select is(has_function_privilege('anon','public.review_financial_reconciliation(uuid,text,text)','EXECUTE'),false,'anonymous users cannot review reconciliation cases');
select is(has_function_privilege('authenticated','public.review_financial_reconciliation(uuid,text,text)','EXECUTE'),true,'authenticated administrators may invoke the permission check');

select * from finish();
rollback;
