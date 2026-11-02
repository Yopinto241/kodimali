begin;
set local statement_timeout='30s';
select set_config('request.jwt.claim.role','service_role',true);
do $$
declare e public.event_equipment_items; r record; before_count integer; fixture_owner uuid; s timestamptz:=now()+interval '50 days'; t timestamptz:=now()+interval '50 days 2 hours'; failed boolean;
begin
  select count(*) into before_count from public.event_plans;
  select * into r from public.check_public_event_selection('[{"kind":"equipment","id":"00000000-0000-0000-0000-000000000000","quantity":1}]',s,t,null);
  if r.is_available or r.available_quantity<>0 then raise exception 'Missing equipment exposed'; end if;
  select id into fixture_owner from public.owner_profiles limit 1;
  if fixture_owner is null then
    insert into public.owner_profiles(profile_id,owner_type,display_name,phone_number,verification_status) select id,'equipment_owner','Rollback test owner','255700000000','verified' from public.profiles limit 1 returning id into fixture_owner;
  end if;
  insert into public.event_equipment_items(owner_id,category_id,name,condition,total_quantity,price_amount_tzs,price_unit,verification_status,publication_status)
  select fixture_owner,id,'Rollback availability fixture','good',10,1000,'item_day','verified','published' from public.event_equipment_categories limit 1 returning * into e;
  select * into r from public.check_public_event_selection(jsonb_build_array(jsonb_build_object('kind','equipment','id',e.id,'quantity',1)),s,t,null);
  if not r.is_available or r.available_quantity<>10 then raise exception 'Published stock did not match'; end if;
  select * into r from public.check_public_event_selection(jsonb_build_array(jsonb_build_object('kind','equipment','id',e.id,'quantity',e.total_quantity+1)),s,t,null);
  if r.is_available then raise exception 'Overstock was allowed'; end if;
  select * into r from public.check_public_event_selection(jsonb_build_array(jsonb_build_object('kind','equipment','id',e.id,'quantity',0)),s,t,null);
  if r.is_available then raise exception 'Zero quantity was allowed'; end if;
  update public.event_equipment_items set publication_status='draft' where id=e.id;
  select * into r from public.check_public_event_selection(jsonb_build_array(jsonb_build_object('kind','equipment','id',e.id,'quantity',1)),s,t,null);
  if r.is_available or r.available_quantity<>0 then raise exception 'Unpublished equipment exposed'; end if;
  failed:=false; begin perform public.check_public_event_selection('[]',t,s,null);exception when others then failed:=true;end;
  if not failed then raise exception 'Invalid period accepted'; end if;
  failed:=false; begin perform public.check_public_event_selection('{}',s,t,null);exception when others then failed:=true;end;
  if not failed then raise exception 'Invalid selection accepted'; end if;
  if (select count(*) from public.event_plans)<>before_count then raise exception 'Preview wrote a plan'; end if;
  raise notice 'PASS: public preview hides unpublished/missing equipment, rejects invalid periods and quantities, and writes no plans';
end $$;
set local role anon;
select * from public.check_public_event_selection('[{"kind":"service","id":"00000000-0000-0000-0000-000000000000"}]',now()+interval '50 days',now()+interval '50 days 2 hours',null);
rollback;
