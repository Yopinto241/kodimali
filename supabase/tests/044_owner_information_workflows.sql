begin;
set local statement_timeout='45s';
do $$
<<fixture>>
declare
 owner_user uuid; contributor uuid; info_user uuid; finance_user uuid; manager_user uuid;
 agent_user uuid; agent_id uuid; category_id uuid; location_id uuid; public_listing uuid; draft uuid; asset uuid; owner_id uuid;
 attrs jsonb; lead public.rental_information_submissions; terms public.referral_agreements; reward public.referral_rewards; payout public.referral_payouts;
 suggestion public.owner_agent_recommendations; suggestion2 public.owner_agent_recommendations;
 delegation public.asset_agent_delegations; booking uuid; payment uuid; dispute uuid; contact uuid;
 failed boolean; cnt integer; original_role text:=current_user;
begin
 select user_id into info_user from public.admin_role_assignments where role_id='information_admin' limit 1;
 select user_id into finance_user from public.admin_role_assignments where role_id='finance_admin' limit 1;
 select user_id into manager_user from public.admin_role_assignments where role_id='agent_manager' limit 1;
 select p.id into owner_user from public.profiles p where not exists(select 1 from public.owner_profiles o where o.profile_id=p.id)
 and not exists(select 1 from public.admin_role_assignments a where a.user_id=p.id) order by p.id limit 1;
 select p.id into contributor from public.profiles p where p.id<>owner_user
 and not exists(select 1 from public.admin_role_assignments a where a.user_id=p.id) order by p.id limit 1;
 if info_user is null or finance_user is null or manager_user is null or owner_user is null or contributor is null then raise exception 'Required staff and customer parents are missing'; end if;
 select l.id,l.agent_id,a.profile_id,l.category_id,l.location_id,l.listing_attributes into public_listing,agent_id,agent_user,category_id,location_id,attrs
 from public.listings l join public.agents a on a.id=l.agent_id join public.asset_categories c on c.id=l.category_id
 where public.is_listing_public(l.id) and c.slug<>'apartment' and a.verification_status='approved' and public.agent_has_service_category(a.id,l.category_id)
 and not exists(select 1 from public.rental_information_submissions s where s.linked_listing_id=l.id and s.eligibility_status<>'ineligible') limit 1;
 if public_listing is null then raise exception 'A public listing parent is required'; end if;

 perform set_config('request.jwt.claim.sub',agent_user::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',agent_user,'role','authenticated')::text,true);
 draft:=public.create_agent_listing_draft(category_id,location_id,'Owner information test','Private workflow test listing',1000,'day',attrs);
 if (select l.owner_id from public.listings l where l.id=draft) is not null then raise exception 'Optional owner unexpectedly created'; end if;
 contact:=public.save_agent_listing_owner(draft,'Private test owner','+255700000099','Private contact only');
 if contact is null or not exists(select 1 from public.listings l where l.id=draft and l.owner_id=contact) then raise exception 'Owner contact was not attached'; end if;
 if public.save_agent_listing_owner(draft,'Private test owner','+255700000099','Private contact only')<>contact then raise exception 'Unchanged contact was duplicated'; end if;
 perform public.save_agent_listing_owner(draft,null,null,null);
 if (select l.owner_id from public.listings l where l.id=draft) is not null then raise exception 'Owner contact was not detached'; end if;
 perform public.manage_save_listing_with_owner(draft,jsonb_build_object('title','Atomic listing update','description','Updated private listing description','price_amount',2000,'price_period','week','availability_status','available','listing_attributes',attrs,'private_owner',jsonb_build_object('name','Atomic owner','phone','+255700000097','notes','Private owner record')));
 failed:=false;begin perform public.manage_save_listing_with_owner(draft,jsonb_build_object('title','Must not be saved','description','Invalid owner should roll back','price_amount',999,'availability_status','available','private_owner',jsonb_build_object('name','Incomplete owner')));exception when others then failed:=true;end;
 if not failed or (select l.title from public.listings l where l.id=draft)<>'Atomic listing update' then raise exception 'Owner validation did not preserve atomic listing edits'; end if;
 perform set_config('request.jwt.claim.sub',contributor::text,true);
 failed:=false;begin perform public.save_agent_listing_owner(draft,'Forged owner','+255700000000',null);exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Unrelated customer changed listing owner'; end if;

 insert into public.owner_profiles(profile_id,owner_type,display_name,phone_number,verification_status)
 values(owner_user,'individual','Test controlling owner','+255700000001','verified') returning id into owner_id;
 select l.asset_id into asset from public.listings l where l.id=draft;
 insert into public.owner_asset_claims(owner_id,asset_id,authority_type,status) values(owner_id,asset,'owner','verified');
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 select count(*) into cnt from public.get_assignable_verified_agents();if cnt=0 then raise exception 'Owner cannot find verified agents'; end if;
 suggestion:=public.recommend_owner_agent('Recommended test agent','+255700000098','Owner nomination');
 suggestion2:=public.recommend_owner_agent('Recommended test agent','+255700000098','Owner nomination');
 if suggestion.id<>suggestion2.id then raise exception 'Recommendation retry duplicated'; end if;
 delegation:=public.grant_asset_agent_delegation(asset,agent_id);
 if not public.has_asset_agent_permission(asset,'bookings.manage',agent_user) then raise exception 'Chosen agent did not receive authority'; end if;
 perform public.revoke_asset_agent_delegation(delegation.id,'Owner withdrew permission');
 if public.has_asset_agent_permission(asset,'bookings.manage',agent_user) then raise exception 'Revoked authority remains active'; end if;
 perform set_config('request.jwt.claim.sub',manager_user::text,true);
 failed:=false;begin perform public.review_owner_agent_recommendation(suggestion.id,'accepted',null,'No verified registration');exception when others then failed:=true;end;
 if not failed then raise exception 'Unregistered agent recommendation was accepted'; end if;
 suggestion:=public.review_owner_agent_recommendation(suggestion.id,'accepted',agent_id,'Verified registration linked');
 if suggestion.status<>'accepted' then raise exception 'Agent Manager review failed'; end if;

 perform set_config('request.jwt.claim.sub',contributor::text,true);
 failed:=false;begin perform public.submit_rental_information('house',null,'Private test location','Private referral description',null,null,null,'owner','{}','[]',false,'Owner','+255700000099',false);exception when others then failed:=true;end;
 if not failed then raise exception 'Owner contacts accepted without consent'; end if;
 lead:=public.submit_rental_information('house',null,'Private test location','Private referral description',1000,'day',null,'owner','{}','[]',false,'Owner','+255700000099',true);
 perform set_config('request.jwt.claim.sub',finance_user::text,true);
 failed:=false;begin perform public.manage_information_submission(lead.id,'triage','Finance must not change private lead');exception when others then failed:=true;end;
 if not failed then raise exception 'Finance gained information administration'; end if;
 perform set_config('request.jwt.claim.sub',info_user::text,true);
 failed:=false;begin perform public.manage_information_submission(lead.id,'triage','Cannot invent paid reward',null,null,null,'paid');exception when others then failed:=true;end;
 if not failed then raise exception 'Information Admin forged paid status'; end if;
 lead:=public.manage_information_submission(lead.id,'published','Owner contacted and public listing linked',null,agent_id,public_listing,'eligible');
 terms:=public.set_information_referral_terms(lead.id,'percentage',10,'Ten percent of the verified collected service fee after completion and Finance approval.');
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 failed:=false;begin perform public.accept_information_referral_terms(terms.id,terms.terms_version);exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Another customer accepted contributor terms'; end if;
 perform set_config('request.jwt.claim.sub',contributor::text,true);
 failed:=false;begin perform public.accept_information_referral_terms(terms.id,terms.terms_version+1);exception when others then failed:=true;end;
 if not failed then raise exception 'Stale terms accepted'; end if;
 terms:=public.accept_information_referral_terms(terms.id,terms.terms_version);
 insert into public.booking_requests(listing_id,agent_id,customer_name,customer_phone_number,request_reference)
 values(public_listing,agent_id,'Referral test customer','+2557'||lpad(trunc(random()*100000000)::text,8,'0'),'REF-'||gen_random_uuid()) returning id into booking;
 update public.booking_requests b set customer_id=contributor where b.id=booking;
 perform set_config('request.jwt.claim.sub',agent_user::text,true);
 update public.booking_requests b set booking_status='completed' where b.id=booking;
 insert into public.booking_payment_transactions(booking_request_id,provider,provider_reference,kind,amount_tzs,status,verified_at)
 values(booking,'test','deposit-'||gen_random_uuid(),'deposit',5000,'paid',now());
 if exists(select 1 from public.referral_rewards where agreement_id=terms.id) then raise exception 'Deposit incorrectly generated referral commission'; end if;
 insert into public.booking_payment_transactions(booking_request_id,provider,provider_reference,kind,amount_tzs,status)
 values(booking,'test','service-'||gen_random_uuid(),'service_fee',1000,'created') returning id into payment;
 if exists(select 1 from public.referral_rewards where agreement_id=terms.id) then raise exception 'Unverified fee generated commission'; end if;
 update public.booking_payment_transactions set status='paid',verified_at=now() where id=payment;
 select * into reward from public.referral_rewards where agreement_id=terms.id and booking_request_id=booking;
 if reward.id is null or reward.reward_amount_tzs<>100 or reward.eligible_fee_collected_tzs<>1000 then raise exception 'Late verified service fee failed to generate correct reward'; end if;
 perform set_config('request.jwt.claim.sub',info_user::text,true);
 failed:=false;begin perform public.review_information_referral_reward(reward.id,'approved','Not a finance account');exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Information Admin approved its own payout'; end if;
 perform set_config('request.jwt.claim.sub',finance_user::text,true);
 insert into public.booking_disputes(booking_request_id,opened_by,reason) values(booking,contributor,'Test disputed booking') returning id into dispute;
 failed:=false;begin perform public.review_information_referral_reward(reward.id,'approved','Disputed booking');exception when others then failed:=true;end;
 if not failed then raise exception 'Disputed reward was approved'; end if;
 update public.booking_disputes set status='resolved' where id=dispute;
 insert into public.refund_obligations(booking_request_id,customer_id,amount_minor,reason,status)
 values(booking,contributor,10,'Declined test request','declined');
 reward:=public.review_information_referral_reward(reward.id,'approved','Verified completed booking and fee');
 payout:=public.record_referral_payout(reward.id,'TEST-'||reward.id,'test-provider','Test only; transaction rolls back');
 if payout.amount_tzs<>100 then raise exception 'Payout amount does not match reward'; end if;
 if (public.record_referral_payout(reward.id,payout.transaction_reference,'test-provider',null)).id<>payout.id then raise exception 'Payout retry duplicated'; end if;
 failed:=false;begin perform public.record_referral_payout(reward.id,'ANOTHER-REFERENCE','test-provider',null);exception when others then failed:=true;end;
 if not failed then raise exception 'Duplicate payout with another reference accepted'; end if;

 -- Modern verified intents are authoritative; never double-count the mirrored
 -- legacy service fee. A second pending reward clears the aggregate paid label.
 perform set_config('request.jwt.claim.sub',contributor::text,true);
 insert into public.booking_requests(listing_id,agent_id,customer_name,customer_phone_number,request_reference)
 values(public_listing,agent_id,'Second referral fixture','+2557'||lpad(trunc(random()*100000000)::text,8,'0'),'REF-'||gen_random_uuid()) returning id into booking;
 update public.booking_requests b set customer_id=contributor where b.id=booking;
 perform set_config('request.jwt.claim.sub',agent_user::text,true);
 update public.booking_requests b set booking_status='completed' where b.id=booking;
 insert into public.booking_payment_transactions(booking_request_id,provider,provider_reference,kind,amount_tzs,status,verified_at)
 values(booking,'test','mirror-'||gen_random_uuid(),'service_fee',1000,'paid',now());
 insert into public.payment_intents(customer_id,product,resource_type,resource_id,amount_minor,status,idempotency_key,verified_at)
 values(contributor,'booking_service_fee','booking_request',booking,2000,'verified_paid','referral-fixture-'||gen_random_uuid(),now());
 select * into reward from public.referral_rewards where agreement_id=terms.id and booking_request_id=booking;
 if reward.reward_amount_tzs<>200 or public.referral_collected_service_fee(booking)<>2000 then raise exception 'Modern service fee was double-counted or failed to refresh'; end if;
 if (select eligibility_status from public.rental_information_submissions where id=lead.id)<>'eligible' then raise exception 'Pending reward still labeled paid'; end if;

 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 execute 'set local role authenticated';
 select count(*) into cnt from public.rental_information_submissions s where s.id=lead.id;
 if cnt<>0 then raise exception 'Another customer can read private lead'; end if;
 execute format('set local role %I',original_role);
 perform set_config('request.jwt.claim.sub',info_user::text,true);
 execute 'set local role authenticated';
 failed:=false;begin update public.referral_rewards set status='paid' where id=reward.id;exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Direct client update bypassed finance controls'; end if;
 execute format('set local role %I',original_role);
end $$;
select 'PASS: optional/private owner contacts; verified agent selection, recommendation review and revocation; private lead review; contributor consent; verified-service-fee reward basis; finance-only approval, dispute holds and idempotent payout' result;
rollback;
