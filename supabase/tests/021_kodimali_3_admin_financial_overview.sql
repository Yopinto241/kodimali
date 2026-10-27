begin;
select plan(3);
select has_function('public','get_admin_financial_overview',array[]::text[],'financial overview RPC exists');
select function_is_definer('public','get_admin_financial_overview',array[]::text[],'financial overview enforces permissions server-side');
select is(has_function_privilege('anon','public.get_admin_financial_overview()','EXECUTE'),false,'anonymous users cannot read financial overview');
select * from finish();
rollback;
