begin;
set local statement_timeout = '30s';
-- Run in a transaction and roll back. Uses existing profile IDs only as
-- foreign-key parents; all fixture rows and temporary role assignments roll back.
do $$
<<fixture>>
declare
 owner_user uuid; customer_user uuid; owner_id uuid; asset_id uuid;
 listing_id uuid; agent_id uuid; booking_id uuid; milestone_id uuid;
 invitation jsonb; accepted public.tenant_invitations;
 configured public.booking_configurations; confirmed public.fulfillment_milestones;
 role_row record; permissions jsonb; denied boolean; result jsonb;
 public_listing uuid; policy_id uuid; cancellation_id uuid; agreement_id uuid;
 conversation_id uuid; report_id uuid; visible_count integer; original_role text:=current_user;
begin
 select p.id into owner_user from public.profiles p
 where not exists(select 1 from public.owner_profiles o where o.profile_id=p.id)
   and not exists(select 1 from public.admin_role_assignments a where a.user_id=p.id)
 order by p.id limit 1;
 select p.id into customer_user from public.profiles p
 where p.id<>owner_user and not exists(select 1 from public.admin_role_assignments a where a.user_id=p.id)
 order by p.id limit 1;
 if owner_user is null or customer_user is null then raise exception 'Two non-staff test parents are required'; end if;
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated')::text,true);

 -- Validate every active administrative assignment through the server predicate.
 for role_row in select r.id,r.permissions from public.admin_role_definitions r where r.is_active loop
   insert into public.admin_role_assignments(user_id,role_id) values(owner_user,role_row.id);
   permissions:=public.get_my_admin_permissions();
   if permissions is distinct from role_row.permissions and not
      (permissions @> role_row.permissions and role_row.permissions @> permissions) then
     raise exception 'Permission mismatch for %: %',role_row.id,permissions;
   end if;
   if role_row.id<>'super_admin' and public.has_admin_permission('*') then
     raise exception 'Role % inherited Super Admin',role_row.id;
   end if;
   denied:=false;
   begin update public.marketplace_settings set updated_at=updated_at where id=true;
   exception when insufficient_privilege then denied:=true; end;
   if denied<>(role_row.id<>'super_admin') then
     raise exception 'Global settings boundary failed for %',role_row.id;
   end if;
   delete from public.admin_role_assignments where user_id=owner_user and role_id=role_row.id;
 end loop;
 if public.get_my_admin_permissions()<>'[]'::jsonb then raise exception 'Unassigned user received permissions'; end if;

 insert into public.owner_profiles(profile_id,owner_type,display_name,phone_number,verification_status)
 values(owner_user,'individual','Role repair test owner','+255700000000','verified') returning id into owner_id;
 insert into public.rental_assets(category,fingerprint,display_name,verification_status,owner_advertising_authorized,verified_at)
 values('house','role-repair-'||gen_random_uuid(),'Role repair test asset','verified',true,now()) returning id into asset_id;
 insert into public.owner_asset_claims(owner_id,asset_id,authority_type,status)
 values(owner_id,asset_id,'owner','verified');

 invitation:=public.invite_tenant(asset_id,'role-repair@example.invalid',null);
 if length(invitation->>'token')<>48 then raise exception 'Invitation token was not generated'; end if;
 if exists(select 1 from public.tenant_invitations where id=(invitation->>'id')::uuid and token_hash=invitation->>'token') then
   raise exception 'Raw invitation token was persisted';
 end if;
 perform set_config('request.jwt.claim.sub',customer_user::text,true);
 accepted:=public.accept_tenant_invitation(invitation->>'token');
 if accepted.status<>'accepted' or accepted.accepted_by<>customer_user then raise exception 'Invitation not accepted'; end if;
 denied:=false;
 begin perform public.accept_tenant_invitation(invitation->>'token'); exception when others then denied:=true; end;
 if not denied then raise exception 'Invitation replay accepted'; end if;

 -- Clone only public listing attributes for a disposable listing.
 insert into public.listings(agent_id,category_id,title,description,location_id,public_location_label,price_amount,price_period,asset_id,status,publication_review_status)
 select l.agent_id,l.category_id,'Role repair test listing','Disposable role workflow fixture',l.location_id,l.public_location_label,10000,l.price_period,fixture.asset_id,'active','admin_approved'
 from public.listings l where public.is_listing_public(l.id) and (select c.slug from public.asset_categories c where c.id=l.category_id)<>'apartment' limit 1 returning id,public.listings.agent_id into listing_id,agent_id;
 if listing_id is null then raise exception 'A listing parent is required'; end if;
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 configured:=public.configure_owned_listing_booking(listing_id,'request_booking');
 if configured.authorized_by_owner_id<>owner_id then raise exception 'Owner authority not recorded'; end if;
 perform set_config('request.jwt.claim.sub',customer_user::text,true);
 denied:=false;
 begin perform public.configure_owned_listing_booking(listing_id,'instant_booking'); exception when others then denied:=true; end;
 if not denied then raise exception 'Unrelated customer configured owner listing'; end if;

 -- Exercise the full instant-booking branch and quote fingerprint. This one
 -- listing's asset link and rollout flags are visible only in this transaction.
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 select l.id into public_listing from public.listings l
 where public.is_listing_public(l.id) and l.price_amount>0 limit 1;
 perform set_config('request.jwt.claim.role','service_role',true);
 update public.listings l set asset_id=fixture.asset_id,publication_review_status='admin_approved' where l.id=public_listing;
 perform set_config('request.jwt.claim.role','authenticated',true);
 select v.id into cancellation_id from public.cancellation_policy_versions v
 where v.is_active and v.effective_from<=now() and (v.effective_until is null or v.effective_until>now()) limit 1;
 if cancellation_id is null then
   insert into public.cancellation_policy_versions(code,version,title,is_active,effective_from)
   values('role-repair-'||gen_random_uuid(),1,'Role repair cancellation',true,now()-interval '1 day') returning id into cancellation_id;
 end if;
 insert into public.booking_policies(category,version,title,body,active_from,is_active,cancellation_policy_version_id)
 values('house',987654,'Role repair policy','Role repair test terms',now()-interval '1 day',true,cancellation_id) returning id into policy_id;
 select v.id into agreement_id from public.owner_booking_agreement_versions v
 where v.is_active and v.effective_from<=now() limit 1;
 if agreement_id is null then
   insert into public.owner_booking_agreement_versions(version,title,body,is_active,effective_from)
   values(987654,'Role repair agreement','Role repair agreement terms',true,now()-interval '1 day') returning id into agreement_id;
 end if;
 insert into public.owner_booking_agreement_acceptances(owner_id,agreement_version_id,accepted_by)
 values(owner_id,agreement_id,owner_user);
 configured:=public.configure_owned_listing_booking(public_listing,'instant_booking',policy_id,true,true);
 if configured.booking_mode<>'instant_booking' then raise exception 'Owner instant booking failed'; end if;
 update public.kodimali_feature_flags set enabled=true where key in ('instant_booking','booking_deposit_payments');
 result:=public.get_public_listing_booking_quote(public_listing,now()+interval '30 days',now()+interval '31 days');
 if result->>'booking_mode'<>'instant_booking' or length(result->>'quote_fingerprint')<>64
    or (result->>'total_tzs')::bigint<>(result->>'deposit_tzs')::bigint+(result->>'balance_tzs')::bigint then
   raise exception 'Invalid deterministic quote: %',result;
 end if;
 perform set_config('request.jwt.claim.sub',customer_user::text,true);

 insert into public.booking_requests(listing_id,agent_id,customer_id,customer_name,request_reference,customer_phone_number)
 select l.id,l.agent_id,customer_user,'Role repair test customer','ROLE-'||gen_random_uuid(),'+255700000001'
 from public.listings l join public.asset_categories c on c.id=l.category_id
 where public.is_listing_public(l.id) and c.slug<>'apartment' limit 1 returning id into booking_id;
 update public.booking_requests b set customer_id=customer_user where b.id=booking_id;
 insert into public.fulfillment_milestones(booking_request_id,milestone_kind)
 values(booking_id,'handover') returning id into milestone_id;
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 denied:=false;
 begin perform public.confirm_customer_fulfillment_milestone(milestone_id); exception when others then denied:=true; end;
 if not denied then raise exception 'Unrelated owner confirmed customer fulfillment'; end if;
 perform set_config('request.jwt.claim.sub',customer_user::text,true);
 confirmed:=public.confirm_customer_fulfillment_milestone(milestone_id);
 if confirmed.status<>'customer_confirmed' then raise exception 'Customer confirmation failed'; end if;
 confirmed:=public.confirm_customer_fulfillment_milestone(milestone_id);
 if confirmed.customer_confirmed_at is null then raise exception 'Confirmation retry lost timestamp'; end if;

 result:=public.agent_trust_summary(agent_id);
 if not result ? 'complaints' then raise exception 'Trust summary missing complaints'; end if;
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 insert into public.admin_role_assignments(user_id,role_id) values(owner_user,'support_admin');
 select c.id into conversation_id from public.listing_conversations c limit 1;
 if conversation_id is not null then
   select count(*) into visible_count from public.get_admin_listing_chat_conversation(conversation_id);
   if visible_count<>1 then raise exception 'Support could not open existing conversation'; end if;
 end if;
 begin
   perform public.get_admin_listing_chat_conversation(gen_random_uuid());
   raise exception 'Missing chat should fail';
 exception when no_data_found then null;
 end;
 delete from public.admin_role_assignments where user_id=owner_user;
 denied:=false;
 begin perform public.get_admin_listing_chat_conversation(gen_random_uuid()); exception when insufficient_privilege then denied:=true; end;
 if not denied then raise exception 'Non-support user accessed staff chat'; end if;
 -- Verify actual report RLS, not just dashboard visibility.
 insert into public.reports(listing_id,reported_by,report_reason)
 values(public_listing,owner_user,'Role repair test report') returning id into report_id;
 perform set_config('request.jwt.claim.sub',customer_user::text,true);
 execute 'set local role authenticated';
 select count(*) into visible_count from public.reports r where r.id=report_id;
 if visible_count<>0 then raise exception 'Another customer read a private report'; end if;
 denied:=false;
 begin
   insert into public.reports(listing_id,reported_by,report_reason)
   values(public_listing,owner_user,'Forged reporter');
 exception when insufficient_privilege then denied:=true;
 end;
 if not denied then raise exception 'Customer forged a report identity'; end if;
 execute format('set local role %I',original_role);
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 insert into public.admin_role_assignments(user_id,role_id) values(owner_user,'listing_moderator');
 execute 'set local role authenticated';
 update public.reports r set status='resolved' where r.id=report_id;
 get diagnostics visible_count=row_count;
 if visible_count<>1 then raise exception 'Moderator could not review report'; end if;
 execute format('set local role %I',original_role);

end $$;

select 'PASS: all active admin roles/global settings boundaries, owner authority, tenant token/replay, instant booking/quote fingerprint, customer fulfillment/retry, agent trust and support authorization and report RLS' as result;

rollback;
