-- Integration check against a linked schema. Both image and video tests roll back completely.
-- All rows and simulated storage metadata are rolled back; nothing is published
-- outside this transaction and no object is uploaded to the storage service.
begin;
set local role postgres;
create temporary table publication_probe as
select a.profile_id,a.id agent_id,l.category_id,l.location_id,l.description,
 l.price_amount,l.price_period,l.listing_attributes,null::uuid listing_id
from agents a join lateral(select * from listings where agent_id=a.id order by created_at desc limit 1) l on true
where a.account_status='active' and a.verification_status='approved' limit 1;
do $$ begin if not exists(select 1 from publication_probe) then raise exception 'No verified active agent available for rolled-back check'; end if; end $$;
grant all on publication_probe to authenticated,service_role;
select set_config('request.jwt.claim.sub',(select profile_id::text from publication_probe),true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims',(select jsonb_build_object('sub',profile_id,'role','authenticated')::text from publication_probe),true);
set local role authenticated;
update publication_probe set listing_id=public.create_agent_listing_draft(category_id,location_id,'Rolled back publication verification',description,price_amount,price_period,listing_attributes);
do $$ begin if not exists(select 1 from listings where id=(select listing_id from publication_probe) and status='draft') then raise exception 'Agent cannot read own draft'; end if; raise notice 'PASS real authenticated draft creation and visibility'; end $$;
-- Simulate the metadata written by a completed storage upload, without external storage effects.
set local role postgres;
insert into storage.objects(bucket_id,name,owner,metadata)
select 'listing-media',profile_id::text||'/'||listing_id::text||'/probe.jpg',profile_id,jsonb_build_object('mimetype','image/jpeg','size',100) from publication_probe;
set local role authenticated;
insert into listing_media(listing_id,media_type,storage_path,display_order,is_cover)
select listing_id,'image',profile_id::text||'/'||listing_id::text||'/probe.jpg',0,true from publication_probe;
update listings set status='inactive' where id=(select listing_id from publication_probe) and status='draft';
do $$ begin if not exists(select 1 from listings where id=(select listing_id from publication_probe) and status='inactive') then raise exception 'Agent cannot stage own listing'; end if; raise notice 'PASS real authenticated media insertion and staging'; end $$;
set local role postgres;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select public.assert_agent_plan_listing_capacity(agent_id,listing_id) from publication_probe;
do $$ declare published boolean; begin
 if public.agent_listing_publication_fee((select agent_id from publication_probe))<>0 then raise exception 'Current mode is paid; free-publication test not applicable'; end if;
 published:=public.release_agent_listing_if_eligible((select listing_id from publication_probe));
 if not published then raise exception 'Eligible listing did not publish'; end if;
 if not exists(select 1 from listings where id=(select listing_id from publication_probe) and status='active') then raise exception 'Publication did not persist inside transaction'; end if;
 raise notice 'PASS real service publication, fee/capacity/media/agent guards';
end $$;
set local role postgres;
do $$ begin if not exists(select 1 from get_public_home_feed(p_limit=>50) where listing_id=(select listing_id from publication_probe)) then raise exception 'Published listing missing from public feed'; end if; raise notice 'PASS released listing visible to public home feed'; end $$;
rollback;

-- All rows and simulated storage metadata are rolled back; nothing is published
-- outside this transaction and no object is uploaded to the storage service.
begin;
set local role postgres;
create temporary table publication_probe as
select a.profile_id,a.id agent_id,l.category_id,l.location_id,l.description,
 l.price_amount,l.price_period,l.listing_attributes,null::uuid listing_id
from agents a join lateral(select * from listings where agent_id=a.id order by created_at desc limit 1) l on true
where a.account_status='active' and a.verification_status='approved' limit 1;
do $$ begin if not exists(select 1 from publication_probe) then raise exception 'No verified active agent available for rolled-back check'; end if; end $$;
grant all on publication_probe to authenticated,service_role;
select set_config('request.jwt.claim.sub',(select profile_id::text from publication_probe),true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims',(select jsonb_build_object('sub',profile_id,'role','authenticated')::text from publication_probe),true);
set local role authenticated;
update publication_probe set listing_id=public.create_agent_listing_draft(category_id,location_id,'Rolled back publication verification',description,price_amount,price_period,listing_attributes);
do $$ begin if not exists(select 1 from listings where id=(select listing_id from publication_probe) and status='draft') then raise exception 'Agent cannot read own draft'; end if; raise notice 'PASS real authenticated draft creation and visibility'; end $$;
-- Simulate the metadata written by a completed storage upload, without external storage effects.
set local role postgres;
insert into storage.objects(bucket_id,name,owner,metadata)
select 'listing-media',profile_id::text||'/'||listing_id::text||'/probe.mp4',profile_id,jsonb_build_object('mimetype','video/mp4','size',100) from publication_probe;
set local role authenticated;
insert into listing_media(listing_id,media_type,storage_path,display_order,is_cover)
select listing_id,'video',profile_id::text||'/'||listing_id::text||'/probe.mp4',0,true from publication_probe;
set local role postgres;
insert into storage.objects(bucket_id,name,owner,metadata) select 'listing-media',profile_id::text||'/'||listing_id::text||'/fallback.jpg',profile_id,jsonb_build_object('mimetype','image/jpeg','size',100) from publication_probe;
set local role authenticated;
insert into listing_media(listing_id,media_type,storage_path,display_order,is_cover) select listing_id,'image',profile_id::text||'/'||listing_id::text||'/fallback.jpg',1,false from publication_probe;
update listings set status='inactive' where id=(select listing_id from publication_probe) and status='draft';
do $$ begin if not exists(select 1 from listings where id=(select listing_id from publication_probe) and status='inactive') then raise exception 'Agent cannot stage own listing'; end if; raise notice 'PASS real authenticated media insertion and staging'; end $$;
set local role postgres;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select public.assert_agent_plan_listing_capacity(agent_id,listing_id) from publication_probe;
do $$ declare published boolean; begin
 if public.agent_listing_publication_fee((select agent_id from publication_probe))<>0 then raise exception 'Current mode is paid; free-publication test not applicable'; end if;
 published:=public.release_agent_listing_if_eligible((select listing_id from publication_probe));
 if not published then raise exception 'Eligible listing did not publish'; end if;
 if not exists(select 1 from listings where id=(select listing_id from publication_probe) and status='active') then raise exception 'Publication did not persist inside transaction'; end if;
 raise notice 'PASS real service publication, fee/capacity/media/agent guards';
end $$;
set local role postgres;
do $$ begin if not exists(select 1 from get_public_home_feed(p_limit=>50) where listing_id=(select listing_id from publication_probe)) then raise exception 'Published listing missing from public feed'; end if; raise notice 'PASS released listing visible to public home feed'; end $$;
rollback;
