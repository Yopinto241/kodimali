begin;
select plan(6);

select has_column('public','booking_configurations','hold_duration_minutes','booking configuration has a bounded hold duration');
select col_has_check('public','booking_configurations','hold_duration_minutes','hold duration is database constrained');
select has_function('public','resolve_booking_hold_minutes',array['uuid','text'],'server hold-duration resolver exists');
select is(public.resolve_booking_hold_minutes(null,null),30,'hold duration defaults to 30 minutes');
select is(public.resolve_booking_hold_minutes(null,'event_deposit_payments'),30,'Events deposit hold defaults to 30 minutes');
select function_is_definer('public','resolve_booking_hold_minutes',array['uuid','text'],'hold configuration is resolved server-side');

select * from finish();
rollback;
