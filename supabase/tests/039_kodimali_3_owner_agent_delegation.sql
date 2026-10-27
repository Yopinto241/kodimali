begin;
select plan(9);

select has_table('public','asset_agent_delegations','asset-agent delegation table exists');
select col_is_pk('public','asset_agent_delegations','id','delegations use an immutable identifier');
select has_column('public','asset_agent_delegations','scopes','delegation scopes are explicit');
select has_column('public','asset_agent_delegations','revocation_reason','revocation is documented');
select has_function('public','has_asset_agent_permission',array['uuid','text','uuid'],'asset permission checker exists');
select function_is_definer('public','has_asset_agent_permission',array['uuid','text','uuid'],'permission checker is server authoritative');
select has_function('public','grant_asset_agent_delegation',array['uuid','uuid','text[]','timestamptz'],'owner delegation grant exists');
select has_function('public','revoke_asset_agent_delegation',array['uuid','text'],'delegation revocation exists');
select is(has_function_privilege('anon','public.grant_asset_agent_delegation(uuid,uuid,text[],timestamptz)','EXECUTE'),false,'anonymous users cannot delegate authority');

select * from finish();
rollback;
