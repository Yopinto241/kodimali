begin;
select plan(4);

select has_function(
  'public','get_admin_financial_activity',
  array['timestamptz','timestamptz','text','text','uuid','uuid','text','text','integer'],
  'financial activity reporting function exists'
);
select function_is_definer(
  'public','get_admin_financial_activity',
  array['timestamptz','timestamptz','text','text','uuid','uuid','text','text','integer'],
  'financial activity filters are permission checked server-side'
);
select is(
  has_function_privilege('anon','public.get_admin_financial_activity(timestamptz,timestamptz,text,text,uuid,uuid,text,text,integer)','EXECUTE'),
  false,
  'anonymous users cannot read financial activity'
);
select is(
  has_function_privilege('authenticated','public.get_admin_financial_activity(timestamptz,timestamptz,text,text,uuid,uuid,text,text,integer)','EXECUTE'),
  true,
  'authenticated administrators may invoke the server-side permission check'
);

select * from finish();
rollback;
