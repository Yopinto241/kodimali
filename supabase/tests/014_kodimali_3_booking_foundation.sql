begin;
select plan(18);

select has_table('public','kodimali_feature_flags','controlled rollout flags exist');
select has_table('public','booking_configurations','booking configuration exists');
select has_table('public','booking_terms_snapshots','immutable booking terms exist');
select has_table('public','booking_state_events','booking event stream exists');
select has_function('public','calculate_booking_split',array['bigint','integer'],'integer-safe split function exists');
select has_function('public','offer_booking_terms',array['uuid','bigint','jsonb','jsonb','jsonb','jsonb','text','timestamp with time zone','text'],'provider offer function exists');
select has_function('public','accept_booking_terms',array['uuid'],'customer acceptance exists');
select has_function('public','valid_booking_transition',array['booking_status','booking_status'],'transition validator exists');
select is((select deposit_minor from public.calculate_booking_split(100000,25)),25000::bigint,'25 percent deposit is exact');
select is((select balance_minor from public.calculate_booking_split(100000,25)),75000::bigint,'75 percent balance is exact');
select is((select deposit_minor+balance_minor from public.calculate_booking_split(99999,25)),99999::bigint,'rounded split always balances');
select ok(public.valid_booking_transition('reserved','confirmed'),'reserved can become confirmed');
select ok(not public.valid_booking_transition('completed','confirmed'),'completed cannot return to confirmed');
select ok(not public.valid_booking_transition('cancelled','confirmed'),'cancelled cannot become confirmed');
select is(public.kodimali_feature_enabled('instant_booking'),false,'instant booking defaults off');
select is(public.kodimali_feature_enabled('automated_refunds'),false,'automated refunds default off');
select is(public.kodimali_feature_enabled('automated_provider_payouts'),false,'automated payouts default off');
select policies_are('public','booking_terms_snapshots',array['booking_terms_participant_read'],'booking terms are participant-readable only');

select * from finish();
rollback;
