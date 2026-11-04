-- Forward-only: replace installed legacy predicates, including policies absent
-- from historical source. Ownership/participant clauses and restrictive
-- supervisor policies are retained. No business rows or payment flags change.
create or replace function public.has_domain_permission(
  p_domain text, p_command text default 'SELECT', check_user uuid default auth.uid()
) returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(auth.role()='service_role',false) or public.is_super_admin(check_user) or (
   not public.is_scoped_supervisor(check_user) and exists (
     select 1 from (values
       ('profiles','SELECT','users.view'),
       ('agents','ALL','agents.manage'),('agent_documents','ALL','agents.manage'),
       ('agent_service_categories','ALL','agents.manage'),
       ('locations','ALL','health.view'),('locations','ALL','agents.manage'),
       ('asset_categories','ALL','listings.manage'),('asset_categories','ALL','promotions.manage'),
       ('owners','ALL','inventory.manage'),('owner_profiles','ALL','inventory.manage'),
       ('owner_applications','ALL','inventory.manage'),('owner_asset_claims','ALL','inventory.manage'),
       ('rental_assets','ALL','inventory.manage'),('rental_agreements','ALL','inventory.manage'),
       ('tenant_invitations','ALL','inventory.manage'),('tenant_move_out_notices','ALL','inventory.manage'),
       ('owner_booking_agreement_versions','ALL','inventory.manage'),('owner_booking_agreement_acceptances','ALL','inventory.manage'),
       ('owner_statement_entries','ALL','payments.manage'),
       ('listings','ALL','listings.manage'),('listing_private_locations','ALL','listings.manage'),
       ('listing_media','ALL','listings.manage'),('availability_blocks','ALL','listings.manage'),
       ('booking_requests','ALL','bookings.manage'),('booking_status_history','ALL','bookings.manage'),
       ('booking_terms_snapshots','ALL','bookings.manage'),('booking_state_events','ALL','bookings.manage'),
       ('booking_amendments','ALL','bookings.manage'),('fulfillment_milestones','ALL','bookings.manage'),
       ('fulfillment_evidence','ALL','bookings.manage'),('booking_cancellation_cases','ALL','bookings.manage'),
       ('booking_incidents','ALL','bookings.manage'),('booking_substitution_proposals','ALL','bookings.manage'),
       ('booking_completion_windows','ALL','bookings.manage'),('asset_reservations','ALL','bookings.manage'),
       ('booking_disputes','ALL','bookings.manage'),('booking_policies','ALL','inventory.manage'),
       ('booking_payment_transactions','ALL','payments.manage'),('platform_payment_orders','ALL','payments.manage'),
       ('agent_wallet_transactions','ALL','wallets.manage'),
       ('cancellation_policy_versions','ALL','refunds.manage'),('cancellation_policy_bands','ALL','refunds.manage'),
       ('platform_promotions','ALL','promotions.manage'),('platform_promotion_media','ALL','promotions.manage'),
       ('platform_promotion_events','SELECT','analytics.view'),('business_events','SELECT','analytics.view'),
       ('agent_subscription_plans','ALL','subscriptions.manage'),('agent_lead_notes','ALL','support.manage'),
       ('notifications','ALL','support.manage'),('audit_logs','SELECT','reports.manage'),
       ('event_equipment_items','ALL','events.manage'),('event_equipment_bundle_components','ALL','events.manage'),
       ('event_service_profiles','ALL','events.manage'),('event_service_areas','ALL','events.manage'),
       ('event_service_offerings','ALL','events.manage'),('event_provider_unavailability','ALL','events.manage'),
       ('event_equipment_allocations','ALL','events.manage'),('event_service_bookings','ALL','events.manage'),
       ('event_quote_revisions','ALL','events.manage'),('event_quote_items','ALL','events.manage'),
       ('event_audit_log','ALL','events.manage'),('event_disputes','ALL','events.manage'),
       ('event_emergency_escalations','ALL','events.manage'),('event_individual_bookings','ALL','events.manage'),
       ('event_payment_obligations','ALL','payments.manage'),
       ('dashboard','SELECT','dashboard.view'),('analytics','SELECT','analytics.view')
     ) scopes(domain,command,permission)
     where scopes.domain=p_domain and scopes.command in ('ALL',upper(p_command))
       and public.has_admin_permission(scopes.permission,check_user)
   )
 );
$$;
revoke all on function public.has_domain_permission(text,text,uuid) from public;
grant execute on function public.has_domain_permission(text,text,uuid) to anon,authenticated,service_role;

-- Administrative settings and role assignment remain Super Admin only: they
-- deliberately have no generic staff domain entry above.
do $repair$
declare r record; q text; c text; replacement text; command_name text;
begin
 for r in select * from pg_policies where schemaname in ('public','storage')
   and (coalesce(qual,'')||coalesce(with_check,'')) ~ '\mis_admin\(' loop
   command_name:=case when r.cmd='ALL' then 'UPDATE' else r.cmd end;
   replacement:=format('public.has_domain_permission(%L,%L)',
     case when r.schemaname='storage' then 'listings' else r.tablename end,command_name);
   -- Storage's bucket-specific participant clauses stay intact; staff access
   -- is tightened to Super Admin below rather than granting listing moderators
   -- access to unrelated agent-document objects.
   if r.schemaname='storage' then replacement:='public.is_super_admin()'; end if;
   q:=replace(replace(r.qual,'public.is_admin()' ,replacement),'is_admin()',replacement);
   c:=replace(replace(r.with_check,'public.is_admin()',replacement),'is_admin()',replacement);
   execute format('alter policy %I on %I.%I %s %s',r.policyname,r.schemaname,r.tablename,
     case when q is not null then 'using ('||q||')' else '' end,
     case when c is not null then 'with check ('||c||')' else '' end);
 end loop;
end $repair$;

-- Tighten the old role predicate itself. Granular staff work is authorized
-- explicitly by domain in the companion function repair below.
create or replace function public.is_admin(check_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(auth.role()='service_role',false) or public.is_super_admin(check_user)
$$;

-- Existing RPC/trigger implementations retain their body, ownership clauses,
-- argument/return contracts and privileges; only the legacy admin bypass changes.
do $repair$
declare r record; body text; domain_name text;
begin
 for r in select p.oid,p.proname,pg_get_functiondef(p.oid) definition
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prokind='f' and p.proname<>'is_admin'
     and pg_get_functiondef(p.oid) like '%public.is_admin(%' loop
   domain_name:=case
     when r.proname in ('guard_listing_media_object','guard_listing_workflow','manage_update_listing_basic','admin_permanently_delete_listing','admin_set_listing_marketplace_status','get_listing_inquiry_counts') then 'listings'
     when r.proname in ('protect_agent_verification_fields','guard_agent_account_update','guard_agent_listing_category_assignment') then 'agents'
     when r.proname in ('get_active_platform_promotions','viewer_can_access_promotion') then 'platform_promotions'
     when r.proname='get_manage_dashboard_counts' then 'dashboard'
     when r.proname='manage_save_category_fields' then 'asset_categories'
     when r.proname in ('get_admin_customer_users','search_manage_customers') then 'profiles'
     when r.proname in ('get_admin_business_analytics','get_admin_profitability_breakdown','get_platform_promotion_performance','get_admin_growth_operations') then 'analytics'
     when r.proname='get_admin_payment_operations' then 'platform_payment_orders'
     when r.proname in ('review_owner_application','review_owner_asset_claim') then 'owner_asset_claims'
     when r.proname='prepare_verified_review' then 'listings'
     when r.proname='guard_notification_update' then 'notifications'
     when r.proname='respond_individual_event_booking' then 'event_individual_bookings'
     when r.proname='declare_external_deal' then 'platform_payment_orders'
     when r.proname='manage_delete_unused_location' then 'locations'
     when r.proname in ('guard_booking_request_update','manage_update_booking_status','guard_guest_booking_request_update','create_guest_booking_notification','set_booking_conversation_status','get_or_create_booking_conversation','mark_conversation_read','prepare_viewing_appointment','respond_to_viewing_appointment','has_booking_provider_permission') then 'booking_requests'
     else null end;
   if domain_name is null then continue; end if;
   body:=r.definition;
   body:=replace(body,'public.is_admin(auth.uid())',format('public.has_domain_permission(%L)',domain_name));
   body:=replace(body,'public.is_admin()',format('public.has_domain_permission(%L)',domain_name));
   body:=replace(body,'public.is_admin(v_user_id)',format('public.has_domain_permission(%L,''SELECT'',v_user_id)',domain_name));
   body:=replace(body,'public.is_admin(p_user_id)',format('public.has_domain_permission(%L,''SELECT'',p_user_id)',domain_name));
   execute body;
 end loop;
end $repair$;

-- Auditable settings changes. No UPDATE of settings/flags is performed here.
create or replace function public.audit_marketplace_control_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if to_jsonb(new) is distinct from to_jsonb(old) then
   insert into public.audit_logs(actor_id,action,target_table,metadata)
   values(auth.uid(),'marketplace_controls_changed',tg_table_name,
     jsonb_build_object('before',to_jsonb(old)-'updated_by','after',to_jsonb(new)-'updated_by'));
 end if;
 return new;
end $$;
drop trigger if exists audit_marketplace_controls on public.marketplace_settings;
create trigger audit_marketplace_controls after update on public.marketplace_settings
for each row execute function public.audit_marketplace_control_change();
notify pgrst,'reload schema';
