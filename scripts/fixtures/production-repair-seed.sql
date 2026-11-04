-- ONLY for the disposable metadata-only localhost fixture database.
-- No realistic customer identifiers, phone numbers or provider transactions.
begin;
set local session_replication_role=replica;
insert into auth.users(id,email,role,aud) select md5('repair-'||name)::uuid,name||'@example.invalid','authenticated','authenticated'
from unnest(array['customer','owner','agent','analyst','marketing','support','finance','supervisor','superadmin','unrelated','other-agent','coordinator']) name on conflict do nothing;
insert into public.profiles(id,full_name) select id,'Fixture '||split_part(email,'@',1) from auth.users where email like '%@example.invalid' on conflict do nothing;
insert into public.admin_role_definitions(id,name,description,permissions,rank) values
('super_admin','Fixture Super Admin','Fixture','["*"]',100),
('analyst','Fixture Analyst','Fixture','["analytics.view","dashboard.view","payments.view"]',20),
('marketing_admin','Fixture Marketing','Fixture','["promotions.manage","boosts.manage","analytics.view"]',50),
('support_admin','Fixture Support','Fixture','["users.view","bookings.manage","support.manage"]',50),
('finance_admin','Fixture Finance','Fixture','["payments.manage","refunds.manage","wallets.manage","subscriptions.manage"]',80),
('events_admin','Fixture Events','Fixture','["events.manage","events.quotes","events.escalations"]',60),
('supervisor','Fixture Supervisor','Fixture','["agents.manage","supervisor.scoped"]',50)
on conflict(id) do update set permissions=excluded.permissions;
insert into public.user_roles(profile_id,role) select md5('repair-'||name)::uuid,
 case when name in ('customer','unrelated') then 'customer' when name='owner' then 'owner' when name in ('agent','other-agent') then 'agent' else 'admin' end::public.app_role
from unnest(array['customer','owner','agent','analyst','marketing','support','finance','supervisor','superadmin','unrelated','other-agent','coordinator']) name on conflict do nothing;
insert into public.admin_role_assignments(user_id,role_id) values
(md5('repair-analyst')::uuid,'analyst'),(md5('repair-marketing')::uuid,'marketing_admin'),
(md5('repair-support')::uuid,'support_admin'),(md5('repair-finance')::uuid,'finance_admin'),
(md5('repair-coordinator')::uuid,'events_admin'),(md5('repair-supervisor')::uuid,'supervisor'),(md5('repair-superadmin')::uuid,'super_admin') on conflict do nothing;
insert into public.locations(id,parent_id,name,location_type) values
(md5('repair-country')::uuid,null,'Fixture country','country'),
(md5('repair-region')::uuid,md5('repair-country')::uuid,'Fixture region','region'),
(md5('repair-district')::uuid,md5('repair-region')::uuid,'Fixture district','district'),
(md5('repair-ward')::uuid,md5('repair-district')::uuid,'Fixture ward','ward'),
(md5('repair-area')::uuid,md5('repair-ward')::uuid,'Fixture area','area') on conflict do nothing;
insert into public.supervisor_territories(supervisor_id,location_id,is_active) values(md5('repair-supervisor')::uuid,md5('repair-ward')::uuid,true) on conflict do nothing;
insert into public.agents(id,profile_id,business_name,account_status,verification_status,location_id,supervisor_id) values
(md5('repair-agent-id')::uuid,md5('repair-agent')::uuid,'Fixture Agent','active','approved',md5('repair-area')::uuid,md5('repair-supervisor')::uuid),
(md5('repair-other-agent-id')::uuid,md5('repair-other-agent')::uuid,'Other Fixture Agent','active','approved',md5('repair-area')::uuid,null) on conflict do nothing;
insert into public.owner_profiles(id,profile_id,owner_type,display_name,phone_number,verification_status) values(md5('repair-owner-id')::uuid,md5('repair-owner')::uuid,'individual','Fixture Owner','000000000000','verified') on conflict do nothing;
insert into public.asset_categories(id,name,slug) values(md5('repair-category')::uuid,'Fixture House','repair-house') on conflict do nothing;
insert into public.agent_service_categories(agent_id,category_id,is_primary) values(md5('repair-agent-id')::uuid,md5('repair-category')::uuid,true) on conflict do nothing;
insert into public.rental_assets(id,category,fingerprint,display_name) values(md5('repair-asset')::uuid,'house','repair-fixture','Fixture Asset') on conflict do nothing;
insert into public.owner_asset_claims(owner_id,asset_id,authority_type,status) values(md5('repair-owner-id')::uuid,md5('repair-asset')::uuid,'owner','verified') on conflict do nothing;
insert into public.listings(id,agent_id,category_id,title,description,location_id,public_location_label,price_amount,price_period,status,asset_id) values
(md5('repair-listing')::uuid,md5('repair-agent-id')::uuid,md5('repair-category')::uuid,'Fixture Listing','Fixture description only',md5('repair-area')::uuid,'Fixture area',10000,'month','active',md5('repair-asset')::uuid),
(md5('repair-other-listing')::uuid,md5('repair-other-agent-id')::uuid,md5('repair-category')::uuid,'Other Fixture Listing','Other fixture description',md5('repair-area')::uuid,'Fixture area',10000,'month','active',null) on conflict do nothing;
insert into public.booking_requests(id,listing_id,agent_id,customer_id,customer_name,customer_phone_number,request_reference,requested_start_at,requested_end_at,booking_kind) values
(md5('repair-booking')::uuid,md5('repair-listing')::uuid,md5('repair-agent-id')::uuid,md5('repair-customer')::uuid,'Fixture Customer','000000000000','REPAIR-ONE',now()+interval '90 days',now()+interval '91 days','reservation'),
(md5('repair-other-booking')::uuid,md5('repair-other-listing')::uuid,md5('repair-other-agent-id')::uuid,md5('repair-unrelated')::uuid,'Other Fixture Customer','000000000001','REPAIR-TWO',now()+interval '90 days',now()+interval '91 days','reservation') on conflict do nothing;
insert into public.marketplace_settings(id,chat_payments_enabled,contact_payments_enabled,booking_payments_enabled,event_payments_enabled,subscription_payments_enabled,listing_boost_payments_enabled) values(true,true,true,true,true,false,true) on conflict do nothing;
insert into public.kodimali_feature_flags(key,enabled,approved_by,approved_at) select name,true,md5('repair-superadmin')::uuid,now() from unnest(array['instant_booking','booking_deposit_payments','booking_balance_payments','event_deposit_payments','event_balance_payments','paid_chat_unlock_v3','contact_unlock_v3']) name on conflict do nothing;
insert into public.event_types(id,slug,name_en,name_sw) values(md5('repair-event-type')::uuid,'repair-fixture','Fixture','Jaribio') on conflict do nothing;
insert into public.event_plans(id,customer_id,event_type_id,title,event_period,attendance) values(md5('repair-plan')::uuid,md5('repair-customer')::uuid,md5('repair-event-type')::uuid,'Fixture event',tstzrange(now()+interval '90 days',now()+interval '91 days'),10) on conflict do nothing;
insert into public.event_tasks(id,plan_id,task_kind,title,assigned_profile_id) values(md5('repair-task')::uuid,md5('repair-plan')::uuid,'delivery','Fixture delivery',md5('repair-agent')::uuid) on conflict do nothing;
insert into public.event_disputes(id,plan_id,opened_by,reason) values(md5('repair-dispute')::uuid,md5('repair-plan')::uuid,md5('repair-customer')::uuid,'Fixture issue') on conflict do nothing;
-- A pending receipt is inserted without triggering any charge or entitlement.
insert into public.listing_chat_payments(id,listing_id,agent_id,customer_id,order_reference,payment_provider,requested_amount,customer_phone_number,provider_payment_id)
values(md5('repair-chat')::uuid,md5('repair-listing')::uuid,md5('repair-agent-id')::uuid,md5('repair-customer')::uuid,'FIXTURE-CHAT','sonicpesa',1000,'000000000000','sp_fixture_chat') on conflict do nothing;
commit;
