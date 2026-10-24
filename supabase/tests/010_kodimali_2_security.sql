begin;
select plan(11);

select has_table('public','rental_information_submissions','private submissions exist');
select has_table('public','rental_assets','central inventory exists');
select has_table('public','asset_reservations','atomic reservations exist');
select has_table('public','referral_payouts','manual payout ledger exists');
select has_table('public','payment_webhook_events','idempotent webhook store exists');
select col_is_fk('public','listings','asset_id','listing links to canonical asset');
select col_is_fk('public','booking_requests','policy_id','booking records accepted policy');
select has_function('public','submit_rental_information',array['listing_category','uuid','text','text','numeric','price_period','timestamp with time zone','text','jsonb','jsonb','boolean','text','text','boolean'],'trusted submission RPC exists');
select has_function('public','confirm_asset_reservation',array['uuid'],'trusted reservation RPC exists');
select has_function('public','record_referral_payout',array['uuid','text','text','text'],'manual payout RPC exists');
select policies_are('public','payment_webhook_events',array['webhook_service_only'],'webhook events are service-only');

select * from finish();
rollback;
