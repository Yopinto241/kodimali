begin;
select plan(12);

select has_table('public','event_individual_bookings','individual bookings share the event domain');
select has_column('public','event_equipment_items','publication_status','equipment has explicit publication state');
select has_column('public','event_equipment_items','security_deposit_tzs','equipment supports deposits');
select has_column('public','event_equipment_items','damage_rules','equipment supports damage rules');
select has_column('public','event_service_offerings','publication_status','services have explicit publication state');
select has_column('public','event_service_offerings','travel_configuration','services support travel configuration');
select has_function('public','search_public_event_equipment',array['text','uuid','uuid','timestamp with time zone','timestamp with time zone','numeric','numeric','text','integer','integer'],'equipment catalog search exists');
select has_function('public','search_public_event_services',array['text','text','uuid','timestamp with time zone','timestamp with time zone','numeric','numeric','text','integer','integer'],'service catalog search exists');
select has_function('public','create_individual_event_booking',array['text','uuid','uuid','timestamp with time zone','timestamp with time zone','integer','text'],'single item booking RPC exists');
select has_function('public','respond_individual_event_booking',array['uuid','boolean','text'],'provider response RPC exists');
select has_function('public','send_individual_booking_quote',array['uuid','numeric','text','timestamp with time zone'],'individual quotation RPC exists');
select col_is_fk('public','event_individual_bookings','plan_item_id','individual bookings reuse event plan items');

select * from finish();
rollback;
