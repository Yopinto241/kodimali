-- KODIMALI Events foundation. Additive only; no payment collection is enabled.
create extension if not exists btree_gist;

insert into public.admin_role_definitions(id,name,description,permissions,rank)
values('event_coordinator','Event Coordinator','Coordinates event plans, provider confirmations, quotations and emergency substitutions.',
 '["events.manage","events.quotes","events.escalations","bookings.manage"]'::jsonb,60)
on conflict(id) do update set name=excluded.name,description=excluded.description,permissions=excluded.permissions,rank=excluded.rank,is_active=true;

insert into public.asset_categories(name,slug,description,icon_key,display_order,is_active)
values('Sherehe na Matukio','events','Vifaa na wataalamu wa sherehe na matukio.','celebration',70,true)
on conflict(slug) do update set name=excluded.name,description=excluded.description,icon_key=excluded.icon_key,is_active=true;

create table public.event_types(
 id uuid primary key default gen_random_uuid(),slug text not null unique,name_sw text not null,name_en text not null,
 description_sw text,description_en text,is_custom boolean not null default false,is_approved boolean not null default true,
 created_by uuid references public.profiles(id),display_order integer not null default 0,created_at timestamptz not null default now()
);
insert into public.event_types(slug,name_sw,name_en,display_order) values
('wedding','Harusi na utambulisho','Weddings and introductions',10),('graduation','Mahafali na sherehe za shule','Graduations and school ceremonies',20),
('memorial','Misiba na kumbukumbu','Funerals and memorials',30),('birthday','Siku za kuzaliwa na maadhimisho','Birthdays and anniversaries',40),
('religious-community','Sherehe za dini na jamii','Religious and community celebrations',50),('corporate','Mikutano na makongamano','Corporate meetings and conferences',60)
on conflict(slug) do update set name_sw=excluded.name_sw,name_en=excluded.name_en,display_order=excluded.display_order;

create table public.event_equipment_categories(
 id uuid primary key default gen_random_uuid(),slug text not null unique,name_sw text not null,name_en text not null,
 display_order integer not null default 0,is_active boolean not null default true
);
insert into public.event_equipment_categories(slug,name_sw,name_en,display_order) values
('chairs','Viti','Chairs',10),('tables','Meza','Tables',20),('tents','Mahema','Tents',30),('stages','Majukwaa','Stages',40),
('speakers','Spika','Speakers',50),('microphones','Maikrofoni','Microphones',60),('mixers','Mixers','Mixers',70),
('lighting','Taa za matukio','Lighting',80),('projectors','Projectors','Projectors',90),('generators','Jenereta','Generators',100),
('decorations','Mapambo na mandhari','Decorations and backdrops',110),('furniture','Mazulia na samani','Carpets and furniture',120),
('catering-equipment','Vifaa vya jikoni na upishi','Kitchen and catering equipment',130),('other','Vifaa vingine','Other equipment',999)
on conflict(slug) do update set name_sw=excluded.name_sw,name_en=excluded.name_en,display_order=excluded.display_order;

create table public.event_equipment_items(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.owner_profiles(id) on delete restrict,
 category_id uuid not null references public.event_equipment_categories(id),location_id uuid references public.locations(id),
 name text not null,description text,condition text not null check(condition in('new','excellent','good','fair','maintenance')),
 total_quantity integer not null check(total_quantity>0),price_amount_tzs numeric(14,2) not null check(price_amount_tzs>=0),
 price_unit text not null check(price_unit in('item_hour','item_day','item_event','fixed')),
 setup_minutes integer not null default 0 check(setup_minutes>=0),return_buffer_minutes integer not null default 0 check(return_buffer_minutes>=0),
 transport_configuration jsonb not null default '{}'::jsonb,cleaning_configuration jsonb not null default '{}'::jsonb,
 return_procedure text,media_paths jsonb not null default '[]'::jsonb,is_bundle boolean not null default false,
 verification_status text not null default 'pending' check(verification_status in('pending','verified','rejected','suspended')),
 is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.event_equipment_bundle_components(
 bundle_id uuid not null references public.event_equipment_items(id) on delete cascade,
 component_id uuid not null references public.event_equipment_items(id) on delete restrict,
 quantity_per_bundle integer not null check(quantity_per_bundle>0),primary key(bundle_id,component_id),check(bundle_id<>component_id)
);

create table public.event_service_profiles(
 id uuid primary key default gen_random_uuid(),profile_id uuid not null unique references public.profiles(id) on delete cascade,
 display_name text not null,provider_kind text not null check(provider_kind in('mc_host','dj','performer','choir_group','photographer','videographer','planner','decorator','caterer','cook','usher','hospitality','cleaning_team','transport_delivery','other')),
 biography text,experience_years integer check(experience_years>=0),service_requirements text,portfolio_media jsonb not null default '[]'::jsonb,
 contact_phone text,contact_email text,verification_status text not null default 'pending' check(verification_status in('pending','verified','rejected','suspended')),
 is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.event_service_areas(profile_id uuid not null references public.event_service_profiles(id) on delete cascade,location_id uuid not null references public.locations(id),primary key(profile_id,location_id));
create table public.event_service_offerings(
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references public.event_service_profiles(id) on delete cascade,
 title text not null,description text,pricing_mode text not null check(pricing_mode in('fixed','from','custom_quote')),
 price_amount_tzs numeric(14,2) check(price_amount_tzs is null or price_amount_tzs>=0),duration_minutes integer check(duration_minutes is null or duration_minutes>0),
 requirements jsonb not null default '{}'::jsonb,is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.rental_information_submissions add column if not exists event_lead_kind text check(event_lead_kind is null or event_lead_kind in('equipment','venue','professional_service','owner_manager'));
alter table public.rental_information_submissions add column if not exists linked_event_equipment_id uuid references public.event_equipment_items(id) on delete set null;
alter table public.rental_information_submissions add column if not exists linked_event_provider_id uuid references public.event_service_profiles(id) on delete set null;
create table public.event_provider_unavailability(
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references public.event_service_profiles(id) on delete cascade,
 unavailable_period tstzrange not null,reason text,created_at timestamptz not null default now(),check(not isempty(unavailable_period))
);

create table public.event_plans(
 id uuid primary key default gen_random_uuid(),reference text not null unique default('EV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 customer_id uuid not null references public.profiles(id),event_type_id uuid not null references public.event_types(id),title text,
 location_id uuid references public.locations(id),private_location_details text,event_period tstzrange not null,attendance integer not null check(attendance>0),
 budget_tzs numeric(14,2) check(budget_tzs is null or budget_tzs>=0),status text not null default 'draft' check(status in('draft','quote_requested','provider_review','partially_confirmed','fully_confirmed','agreement_pending','confirmed','in_progress','completed','cancelled','disputed')),
 required_component_count integer not null default 0 check(required_component_count>=0),accepted_quote_revision_id uuid,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(not isempty(event_period))
);
create table public.event_plan_items(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id) on delete cascade,
 item_kind text not null check(item_kind in('equipment','service')),equipment_id uuid references public.event_equipment_items(id),
 offering_id uuid references public.event_service_offerings(id),requested_quantity integer check(requested_quantity is null or requested_quantity>0),
 is_required boolean not null default true,requirements text,status text not null default 'requested' check(status in('requested','quoted','provider_confirmed','provider_declined','substitution_proposed','customer_accepted','cancelled','completed')),
 created_at timestamptz not null default now(),check((item_kind='equipment' and equipment_id is not null and offering_id is null and requested_quantity is not null) or(item_kind='service' and offering_id is not null and equipment_id is null and requested_quantity is null))
);
create table public.event_equipment_allocations(
 id uuid primary key default gen_random_uuid(),plan_item_id uuid not null references public.event_plan_items(id) on delete cascade,
 equipment_id uuid not null references public.event_equipment_items(id),quantity integer not null check(quantity>0),occupied_period tstzrange not null,
 status text not null default 'held' check(status in('held','confirmed','completed','cancelled','expired')),
 expires_at timestamptz,created_at timestamptz not null default now(),check(not isempty(occupied_period)),unique(plan_item_id,equipment_id)
);
create table public.event_service_bookings(
 id uuid primary key default gen_random_uuid(),plan_item_id uuid not null unique references public.event_plan_items(id) on delete cascade,
 provider_id uuid not null references public.event_service_profiles(id),service_period tstzrange not null,
 status text not null default 'pending' check(status in('pending','held','confirmed','completed','declined','cancelled','expired')),
 expires_at timestamptz,travel_buffer_minutes integer not null default 0 check(travel_buffer_minutes>=0),created_at timestamptz not null default now(),check(not isempty(service_period))
);

create table public.event_quote_revisions(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id) on delete cascade,
 revision integer not null,subtotal_tzs numeric(14,2) not null check(subtotal_tzs>=0),additional_costs_tzs numeric(14,2) not null default 0 check(additional_costs_tzs>=0),
 total_tzs numeric(14,2) generated always as(subtotal_tzs+additional_costs_tzs) stored,currency text not null default 'TZS',
 status text not null default 'draft' check(status in('draft','sent','accepted','rejected','expired','superseded')),
 expires_at timestamptz not null,created_by uuid not null references public.profiles(id),accepted_at timestamptz,created_at timestamptz not null default now(),unique(plan_id,revision)
);
alter table public.event_plans add constraint event_plans_accepted_quote_fkey foreign key(accepted_quote_revision_id) references public.event_quote_revisions(id);
create table public.event_quote_items(
 id uuid primary key default gen_random_uuid(),quote_revision_id uuid not null references public.event_quote_revisions(id) on delete cascade,
 plan_item_id uuid references public.event_plan_items(id),provider_profile_id uuid references public.profiles(id),description text not null,
 quantity numeric(12,2) not null default 1 check(quantity>0),unit_price_tzs numeric(14,2) not null check(unit_price_tzs>=0),line_total_tzs numeric(14,2) generated always as(quantity*unit_price_tzs) stored
);
create table public.event_payment_obligations(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id),quote_item_id uuid references public.event_quote_items(id),
 provider_profile_id uuid references public.profiles(id),kind text not null check(kind in('deposit','balance','transport','setup','cleaning','service_fee','refund')),
 amount_tzs numeric(14,2) not null check(amount_tzs>0),due_at timestamptz,status text not null default 'inactive' check(status in('inactive','pending','paid','waived','refundable','refunded','disputed')),
 collection_enabled boolean not null default false,external_reference text,created_at timestamptz not null default now(),check(collection_enabled=false)
);
create table public.event_audit_log(id bigint generated always as identity primary key,plan_id uuid not null references public.event_plans(id),actor_id uuid references public.profiles(id),action text not null,details jsonb not null default '{}'::jsonb,created_at timestamptz not null default now());
create table public.event_disputes(id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id),plan_item_id uuid references public.event_plan_items(id),opened_by uuid not null references public.profiles(id),reason text not null,details text,status text not null default 'open' check(status in('open','investigating','resolved','rejected')),resolution text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.event_emergency_escalations(id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id),plan_item_id uuid references public.event_plan_items(id),reported_by uuid not null references public.profiles(id),reason text not null,status text not null default 'open' check(status in('open','coordinating','substituted','resolved','closed')),assigned_admin_id uuid references public.profiles(id),created_at timestamptz not null default now(),resolved_at timestamptz);

create index event_allocations_overlap on public.event_equipment_allocations using gist(equipment_id,occupied_period) where(status in('held','confirmed'));
create index event_service_bookings_overlap on public.event_service_bookings using gist(provider_id,service_period) where(status in('held','confirmed'));
create index event_plans_customer on public.event_plans(customer_id,created_at desc);

alter table public.event_types enable row level security;alter table public.event_equipment_categories enable row level security;
alter table public.event_equipment_items enable row level security;alter table public.event_equipment_bundle_components enable row level security;
alter table public.event_service_profiles enable row level security;alter table public.event_service_areas enable row level security;alter table public.event_service_offerings enable row level security;alter table public.event_provider_unavailability enable row level security;
alter table public.event_plans enable row level security;alter table public.event_plan_items enable row level security;alter table public.event_equipment_allocations enable row level security;alter table public.event_service_bookings enable row level security;
alter table public.event_quote_revisions enable row level security;alter table public.event_quote_items enable row level security;alter table public.event_payment_obligations enable row level security;alter table public.event_audit_log enable row level security;alter table public.event_disputes enable row level security;alter table public.event_emergency_escalations enable row level security;

create policy event_taxonomy_public on public.event_types for select using(is_approved);
create policy event_equipment_categories_public on public.event_equipment_categories for select using(is_active);
create policy event_equipment_public on public.event_equipment_items for select using(verification_status='verified' and is_active);
create policy event_equipment_owner on public.event_equipment_items for all to authenticated using(owner_id=public.current_owner_id() or public.is_admin()) with check(owner_id=public.current_owner_id() or public.is_admin());
create policy event_bundles_public on public.event_equipment_bundle_components for select using(exists(select 1 from public.event_equipment_items e where e.id=bundle_id and e.verification_status='verified' and e.is_active));
create policy event_bundles_owner_manage on public.event_equipment_bundle_components for all to authenticated using(exists(select 1 from public.event_equipment_items e where e.id=bundle_id and(e.owner_id=public.current_owner_id() or public.is_admin()))) with check(exists(select 1 from public.event_equipment_items e where e.id=bundle_id and(e.owner_id=public.current_owner_id() or public.is_admin())));
create policy event_services_public on public.event_service_profiles for select using(verification_status='verified' and is_active);
create policy event_services_self on public.event_service_profiles for all to authenticated using(profile_id=auth.uid() or public.is_admin()) with check(profile_id=auth.uid() or public.is_admin());
create policy event_areas_public on public.event_service_areas for select using(true);create policy event_areas_provider_manage on public.event_service_areas for all to authenticated using(exists(select 1 from public.event_service_profiles p where p.id=profile_id and(p.profile_id=auth.uid() or public.is_admin()))) with check(exists(select 1 from public.event_service_profiles p where p.id=profile_id and(p.profile_id=auth.uid() or public.is_admin())));
create policy event_offerings_public on public.event_service_offerings for select using(is_active);create policy event_offerings_provider_manage on public.event_service_offerings for all to authenticated using(exists(select 1 from public.event_service_profiles p where p.id=provider_id and(p.profile_id=auth.uid() or public.is_admin()))) with check(exists(select 1 from public.event_service_profiles p where p.id=provider_id and(p.profile_id=auth.uid() or public.is_admin())));
create policy event_provider_unavailability_self on public.event_provider_unavailability for all to authenticated using(exists(select 1 from public.event_service_profiles p where p.id=provider_id and(p.profile_id=auth.uid() or public.is_admin()))) with check(exists(select 1 from public.event_service_profiles p where p.id=provider_id and(p.profile_id=auth.uid() or public.is_admin())));
create policy event_plans_customer_admin on public.event_plans for select to authenticated using(customer_id=auth.uid() or public.is_admin() or exists(select 1 from public.event_plan_items i left join public.event_equipment_items e on e.id=i.equipment_id left join public.event_service_offerings o on o.id=i.offering_id left join public.event_service_profiles s on s.id=o.provider_id where i.plan_id=event_plans.id and(e.owner_id=public.current_owner_id() or s.profile_id=auth.uid())));
create policy event_plan_items_participants on public.event_plan_items for select to authenticated using(exists(select 1 from public.event_plans p where p.id=plan_id and(p.customer_id=auth.uid() or public.is_admin())) or exists(select 1 from public.event_equipment_items e where e.id=equipment_id and e.owner_id=public.current_owner_id()) or exists(select 1 from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id where o.id=offering_id and s.profile_id=auth.uid()));
create policy event_operational_admin_read on public.event_equipment_allocations for select to authenticated using(public.is_admin() or exists(select 1 from public.event_plan_items i join public.event_plans p on p.id=i.plan_id where i.id=plan_item_id and p.customer_id=auth.uid()));
create policy event_service_bookings_participants on public.event_service_bookings for select to authenticated using(public.is_admin() or exists(select 1 from public.event_service_profiles s where s.id=provider_id and s.profile_id=auth.uid()) or exists(select 1 from public.event_plan_items i join public.event_plans p on p.id=i.plan_id where i.id=plan_item_id and p.customer_id=auth.uid()));
create policy event_quotes_participants on public.event_quote_revisions for select to authenticated using(public.is_admin() or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_quote_items_participants on public.event_quote_items for select to authenticated using(public.is_admin() or provider_profile_id=auth.uid() or exists(select 1 from public.event_quote_revisions q join public.event_plans p on p.id=q.plan_id where q.id=quote_revision_id and p.customer_id=auth.uid()));
create policy event_financial_participants on public.event_payment_obligations for select to authenticated using(public.is_admin() or provider_profile_id=auth.uid() or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_audit_participants on public.event_audit_log for select to authenticated using(public.is_admin() or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_disputes_participants on public.event_disputes for select to authenticated using(public.is_admin() or opened_by=auth.uid() or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_escalations_participants on public.event_emergency_escalations for select to authenticated using(public.is_admin() or reported_by=auth.uid() or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_coordinator_plans on public.event_plans for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));
create policy event_coordinator_items on public.event_plan_items for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));
create policy event_coordinator_quotes on public.event_quote_revisions for all to authenticated using(public.has_admin_permission('events.quotes')) with check(public.has_admin_permission('events.quotes'));
create policy event_coordinator_quote_items on public.event_quote_items for all to authenticated using(public.has_admin_permission('events.quotes')) with check(public.has_admin_permission('events.quotes'));
create policy event_coordinator_escalations on public.event_emergency_escalations for all to authenticated using(public.has_admin_permission('events.escalations')) with check(public.has_admin_permission('events.escalations'));

create or replace function public.create_event_plan(p_event_type_id uuid,p_start_at timestamptz,p_end_at timestamptz,p_location_id uuid,p_private_location_details text,p_attendance integer,p_budget_tzs numeric,p_title text default null)
returns public.event_plans language plpgsql security definer set search_path=public as $$declare r public.event_plans;begin
 if auth.uid() is null then raise exception 'Authentication required';end if;if p_end_at<=p_start_at then raise exception 'Event end must be after start';end if;if p_attendance<=0 then raise exception 'Attendance must be positive';end if;
 insert into public.event_plans(customer_id,event_type_id,title,location_id,private_location_details,event_period,attendance,budget_tzs)
 values(auth.uid(),p_event_type_id,nullif(trim(p_title),''),p_location_id,nullif(trim(p_private_location_details),''),tstzrange(p_start_at,p_end_at,'[)'),p_attendance,p_budget_tzs)returning * into r;
 insert into public.event_audit_log(plan_id,actor_id,action)values(r.id,auth.uid(),'plan.created');return r;end$$;

create or replace function public.add_event_plan_item(p_plan_id uuid,p_item_kind text,p_equipment_id uuid default null,p_offering_id uuid default null,p_quantity integer default null,p_required boolean default true,p_requirements text default null)
returns public.event_plan_items language plpgsql security definer set search_path=public as $$declare r public.event_plan_items;begin
 if not exists(select 1 from public.event_plans where id=p_plan_id and customer_id=auth.uid() and status='draft') then raise exception 'Editable event plan required';end if;
 insert into public.event_plan_items(plan_id,item_kind,equipment_id,offering_id,requested_quantity,is_required,requirements)values(p_plan_id,p_item_kind,p_equipment_id,p_offering_id,p_quantity,p_required,nullif(trim(p_requirements),''))returning * into r;
 update public.event_plans set required_component_count=(select count(*) from public.event_plan_items where plan_id=p_plan_id and is_required),updated_at=now() where id=p_plan_id;return r;end$$;

create or replace function public.confirm_event_equipment_item(p_plan_item_id uuid,p_hold_minutes integer default 1440)
returns setof public.event_equipment_allocations language plpgsql security definer set search_path=public as $$declare i public.event_plan_items;p public.event_plans;e public.event_equipment_items;c record;needed integer;used integer;period tstzrange;begin
 select * into i from public.event_plan_items where id=p_plan_item_id for update;if i.id is null or i.item_kind<>'equipment' then raise exception 'Equipment plan item required';end if;
 select * into p from public.event_plans where id=i.plan_id for update;select * into e from public.event_equipment_items where id=i.equipment_id;
 if not(e.owner_id=public.current_owner_id() or public.is_admin()) then raise exception 'Equipment owner access required';end if;
 period:=tstzrange(lower(p.event_period)-make_interval(mins=>e.setup_minutes),upper(p.event_period)+make_interval(mins=>e.return_buffer_minutes),'[)');
 for c in select e.id equipment_id,i.requested_quantity quantity union all select b.component_id,b.quantity_per_bundle*i.requested_quantity from public.event_equipment_bundle_components b where b.bundle_id=e.id loop
  perform pg_advisory_xact_lock(hashtextextended(c.equipment_id::text,0));select total_quantity into needed from public.event_equipment_items where id=c.equipment_id for update;
  select coalesce(sum(a.quantity),0)::integer into used from public.event_equipment_allocations a where a.equipment_id=c.equipment_id and a.status in('held','confirmed') and a.occupied_period&&period and(a.expires_at is null or a.expires_at>now());
  if used+c.quantity>needed then raise exception 'Insufficient equipment quantity for requested period' using errcode='23P01';end if;
  insert into public.event_equipment_allocations(plan_item_id,equipment_id,quantity,occupied_period,status,expires_at)values(i.id,c.equipment_id,c.quantity,period,'held',now()+make_interval(mins=>greatest(p_hold_minutes,15))) on conflict(plan_item_id,equipment_id)do update set quantity=excluded.quantity,occupied_period=excluded.occupied_period,status='held',expires_at=excluded.expires_at;
 end loop;update public.event_plan_items set status='provider_confirmed' where id=i.id;update public.event_plans set status=case when not exists(select 1 from public.event_plan_items x where x.plan_id=p.id and x.is_required and x.status<>'provider_confirmed') then 'fully_confirmed' else 'partially_confirmed' end,updated_at=now() where id=p.id;return query select * from public.event_equipment_allocations where plan_item_id=i.id;end$$;

create or replace function public.confirm_event_service_item(p_plan_item_id uuid,p_travel_buffer_minutes integer default 0,p_hold_minutes integer default 1440)
returns public.event_service_bookings language plpgsql security definer set search_path=public as $$declare i public.event_plan_items;p public.event_plans;s public.event_service_profiles;r public.event_service_bookings;period tstzrange;begin
 select * into i from public.event_plan_items where id=p_plan_item_id for update;select * into p from public.event_plans where id=i.plan_id for update;select sp.* into s from public.event_service_offerings o join public.event_service_profiles sp on sp.id=o.provider_id where o.id=i.offering_id;
 if s.profile_id<>auth.uid() and not public.is_admin() then raise exception 'Service provider access required';end if;perform pg_advisory_xact_lock(hashtextextended(s.id::text,0));period:=tstzrange(lower(p.event_period)-make_interval(mins=>greatest(p_travel_buffer_minutes,0)),upper(p.event_period)+make_interval(mins=>greatest(p_travel_buffer_minutes,0)),'[)');
 if exists(select 1 from public.event_provider_unavailability u where u.provider_id=s.id and u.unavailable_period&&period) or exists(select 1 from public.event_service_bookings b where b.provider_id=s.id and b.status in('held','confirmed') and b.service_period&&period and(b.expires_at is null or b.expires_at>now()) and b.plan_item_id<>i.id) then raise exception 'Provider is unavailable for requested period' using errcode='23P01';end if;
 insert into public.event_service_bookings(plan_item_id,provider_id,service_period,status,expires_at,travel_buffer_minutes)values(i.id,s.id,period,'held',now()+make_interval(mins=>greatest(p_hold_minutes,15)),greatest(p_travel_buffer_minutes,0))on conflict(plan_item_id)do update set service_period=excluded.service_period,status='held',expires_at=excluded.expires_at,travel_buffer_minutes=excluded.travel_buffer_minutes returning * into r;update public.event_plan_items set status='provider_confirmed' where id=i.id;update public.event_plans set status=case when not exists(select 1 from public.event_plan_items x where x.plan_id=p.id and x.is_required and x.status<>'provider_confirmed') then 'fully_confirmed' else 'partially_confirmed' end,updated_at=now() where id=p.id;return r;end$$;

create or replace function public.request_event_quote(p_plan_id uuid)returns public.event_plans language plpgsql security definer set search_path=public as $$declare r public.event_plans;begin update public.event_plans set status='quote_requested',updated_at=now() where id=p_plan_id and customer_id=auth.uid() and status='draft' and exists(select 1 from public.event_plan_items where plan_id=p_plan_id)returning * into r;if r.id is null then raise exception 'Draft event plan with at least one item required';end if;insert into public.event_audit_log(plan_id,actor_id,action)values(r.id,auth.uid(),'quote.requested');return r;end$$;

create or replace function public.accept_event_quote(p_quote_revision_id uuid)returns public.event_plans language plpgsql security definer set search_path=public as $$declare q public.event_quote_revisions;p public.event_plans;confirmed integer;begin select * into q from public.event_quote_revisions where id=p_quote_revision_id for update;select * into p from public.event_plans where id=q.plan_id and customer_id=auth.uid() for update;if p.id is null or q.status<>'sent' or q.expires_at<=now() then raise exception 'Quotation is unavailable or expired';end if;select count(*) into confirmed from public.event_plan_items where plan_id=p.id and is_required and status='provider_confirmed';if confirmed<p.required_component_count then raise exception 'Required providers have not all confirmed';end if;update public.event_quote_revisions set status='superseded' where plan_id=p.id and id<>q.id and status in('draft','sent');update public.event_quote_revisions set status='accepted',accepted_at=now() where id=q.id;update public.event_plans set accepted_quote_revision_id=q.id,status='agreement_pending',updated_at=now() where id=p.id returning * into p;insert into public.event_audit_log(plan_id,actor_id,action,details)values(p.id,auth.uid(),'quote.accepted',jsonb_build_object('quote_revision_id',q.id));return p;end$$;

create or replace function public.create_event_quote_revision(p_plan_id uuid,p_expires_at timestamptz,p_items jsonb,p_additional_costs_tzs numeric default 0)
returns public.event_quote_revisions language plpgsql security definer set search_path=public as $$declare q public.event_quote_revisions;entry jsonb;subtotal numeric:=0;next_revision integer;customer uuid;begin
 if not public.has_admin_permission('events.quotes') then raise exception 'Event quotation permission required';end if;if p_expires_at<=now() then raise exception 'Quotation expiry must be in the future';end if;if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one quotation item is required';end if;
 select customer_id into customer from public.event_plans where id=p_plan_id for update;if customer is null then raise exception 'Event plan not found';end if;
 for entry in select value from jsonb_array_elements(p_items) loop if coalesce((entry->>'quantity')::numeric,0)<=0 or coalesce((entry->>'unit_price_tzs')::numeric,-1)<0 or nullif(trim(entry->>'description'),'') is null then raise exception 'Invalid quotation item';end if;subtotal:=subtotal+((entry->>'quantity')::numeric*(entry->>'unit_price_tzs')::numeric);end loop;
 select coalesce(max(revision),0)+1 into next_revision from public.event_quote_revisions where plan_id=p_plan_id;update public.event_quote_revisions set status='superseded' where plan_id=p_plan_id and status in('draft','sent');
 insert into public.event_quote_revisions(plan_id,revision,subtotal_tzs,additional_costs_tzs,status,expires_at,created_by)values(p_plan_id,next_revision,subtotal,greatest(coalesce(p_additional_costs_tzs,0),0),'sent',p_expires_at,auth.uid())returning * into q;
 for entry in select value from jsonb_array_elements(p_items) loop insert into public.event_quote_items(quote_revision_id,plan_item_id,provider_profile_id,description,quantity,unit_price_tzs)values(q.id,nullif(entry->>'plan_item_id','')::uuid,nullif(entry->>'provider_profile_id','')::uuid,trim(entry->>'description'),(entry->>'quantity')::numeric,(entry->>'unit_price_tzs')::numeric);end loop;
 update public.event_plans set status='provider_review',updated_at=now() where id=p_plan_id;
 insert into public.notifications(user_id,type,title,body,payload)values(customer,'announcement','Event quotation ready','Your itemized KODIMALI Events quotation is ready to review.',jsonb_build_object('eventType','event_quote_ready','eventPlanId',p_plan_id,'quoteRevisionId',q.id,'route','account/events'));
 insert into public.event_audit_log(plan_id,actor_id,action,details)values(p_plan_id,auth.uid(),'quote.sent',jsonb_build_object('quote_revision_id',q.id,'revision',q.revision));return q;end$$;

create or replace function public.notify_event_plan_item_provider()returns trigger language plpgsql security definer set search_path=public as $$declare recipient uuid;ref text;begin
 if new.item_kind='equipment' then select o.profile_id into recipient from public.event_equipment_items e join public.owner_profiles o on o.id=e.owner_id where e.id=new.equipment_id;else select s.profile_id into recipient from public.event_service_offerings f join public.event_service_profiles s on s.id=f.provider_id where f.id=new.offering_id;end if;
 select reference into ref from public.event_plans where id=new.plan_id;if recipient is not null then insert into public.notifications(user_id,type,title,body,payload)values(recipient,'announcement','New event request','A customer selected your equipment or service for event '||ref||'.',jsonb_build_object('eventType','event_provider_request','eventPlanId',new.plan_id,'planItemId',new.id,'route','events-workspace'));end if;return new;end$$;
create trigger notify_event_plan_item_provider after insert on public.event_plan_items for each row execute function public.notify_event_plan_item_provider();
create or replace function public.notify_event_item_status()returns trigger language plpgsql security definer set search_path=public as $$declare customer uuid;ref text;begin if new.status is not distinct from old.status then return new;end if;select customer_id,reference into customer,ref from public.event_plans where id=new.plan_id;insert into public.notifications(user_id,type,title,body,payload)values(customer,'announcement','Event provider update','A provider updated an item for event '||ref||' to '||replace(new.status,'_',' ')||'.',jsonb_build_object('eventType','event_item_status','eventPlanId',new.plan_id,'planItemId',new.id,'status',new.status,'route','account/events'));return new;end$$;
create trigger notify_event_item_status after update of status on public.event_plan_items for each row execute function public.notify_event_item_status();

create table public.event_agreements(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id),quote_revision_id uuid not null references public.event_quote_revisions(id),
 version integer not null,terms text not null,status text not null default 'sent' check(status in('draft','sent','accepted','superseded','cancelled')),
 created_by uuid not null references public.profiles(id),sent_at timestamptz,accepted_by uuid references public.profiles(id),accepted_at timestamptz,created_at timestamptz not null default now(),unique(plan_id,version)
);
create table public.event_substitution_proposals(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id),replaces_plan_item_id uuid not null references public.event_plan_items(id),
 proposed_equipment_id uuid references public.event_equipment_items(id),proposed_offering_id uuid references public.event_service_offerings(id),reason text not null,
 price_change_tzs numeric(14,2) not null default 0,status text not null default 'proposed' check(status in('proposed','accepted','rejected','expired')),
 proposed_by uuid not null references public.profiles(id),expires_at timestamptz not null,decided_at timestamptz,created_at timestamptz not null default now(),
 check((proposed_equipment_id is not null and proposed_offering_id is null)or(proposed_equipment_id is null and proposed_offering_id is not null))
);
create table public.event_cancellations(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id),plan_item_id uuid references public.event_plan_items(id),
 requested_by uuid not null references public.profiles(id),party text not null check(party in('customer','provider','coordinator')),reason text not null,
 status text not null default 'submitted' check(status in('submitted','reviewing','approved','declined','completed')),
 refundable_amount_tzs numeric(14,2) check(refundable_amount_tzs is null or refundable_amount_tzs>=0),resolution text,resolved_by uuid references public.profiles(id),resolved_at timestamptz,created_at timestamptz not null default now()
);
alter table public.event_agreements enable row level security;alter table public.event_substitution_proposals enable row level security;alter table public.event_cancellations enable row level security;
create policy event_agreements_participants on public.event_agreements for select to authenticated using(public.has_admin_permission('events.manage') or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_agreements_coordinator on public.event_agreements for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));
create policy event_substitutions_participants on public.event_substitution_proposals for select to authenticated using(public.has_admin_permission('events.manage') or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_substitutions_coordinator on public.event_substitution_proposals for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));
create policy event_cancellations_participants on public.event_cancellations for select to authenticated using(public.has_admin_permission('events.manage') or requested_by=auth.uid() or exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_cancellations_coordinator on public.event_cancellations for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));

create or replace function public.send_event_agreement(p_plan_id uuid,p_terms text)returns public.event_agreements language plpgsql security definer set search_path=public as $$declare p public.event_plans;q public.event_quote_revisions;r public.event_agreements;v integer;begin if not public.has_admin_permission('events.manage') then raise exception 'Event coordinator permission required';end if;select * into p from public.event_plans where id=p_plan_id for update;select * into q from public.event_quote_revisions where id=p.accepted_quote_revision_id and status='accepted';if q.id is null then raise exception 'Accepted quotation required';end if;select coalesce(max(version),0)+1 into v from public.event_agreements where plan_id=p.id;update public.event_agreements set status='superseded' where plan_id=p.id and status in('draft','sent');insert into public.event_agreements(plan_id,quote_revision_id,version,terms,status,created_by,sent_at)values(p.id,q.id,v,trim(p_terms),'sent',auth.uid(),now())returning * into r;insert into public.notifications(user_id,type,title,body,payload)values(p.customer_id,'announcement','Event agreement ready','Review and accept your final event agreement.',jsonb_build_object('eventType','event_agreement_ready','eventPlanId',p.id,'agreementId',r.id,'route','account/events'));return r;end$$;

create or replace function public.accept_event_agreement(p_agreement_id uuid)returns public.event_plans language plpgsql security definer set search_path=public as $$declare a public.event_agreements;p public.event_plans;begin select * into a from public.event_agreements where id=p_agreement_id for update;select * into p from public.event_plans where id=a.plan_id and customer_id=auth.uid() for update;if p.id is null or a.status<>'sent' then raise exception 'Event agreement is unavailable';end if;update public.event_agreements set status='accepted',accepted_by=auth.uid(),accepted_at=now() where id=a.id;update public.event_equipment_allocations x set status='confirmed',expires_at=null from public.event_plan_items i where i.id=x.plan_item_id and i.plan_id=p.id and x.status='held';update public.event_service_bookings b set status='confirmed',expires_at=null from public.event_plan_items i where i.id=b.plan_item_id and i.plan_id=p.id and b.status='held';update public.event_plans set status='confirmed',updated_at=now() where id=p.id returning * into p;insert into public.event_audit_log(plan_id,actor_id,action,details)values(p.id,auth.uid(),'agreement.accepted',jsonb_build_object('agreement_id',a.id));return p;end$$;

create or replace function public.provider_cancel_event_item(p_plan_item_id uuid,p_reason text)returns public.event_cancellations language plpgsql security definer set search_path=public as $$declare i public.event_plan_items;p public.event_plans;r public.event_cancellations;authorized boolean:=false;begin select * into i from public.event_plan_items where id=p_plan_item_id for update;select * into p from public.event_plans where id=i.plan_id for update;if i.item_kind='equipment' then select exists(select 1 from public.event_equipment_items e where e.id=i.equipment_id and e.owner_id=public.current_owner_id())into authorized;else select exists(select 1 from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id where o.id=i.offering_id and s.profile_id=auth.uid())into authorized;end if;if not authorized then raise exception 'Provider access required';end if;update public.event_plan_items set status='cancelled' where id=i.id;update public.event_equipment_allocations set status='cancelled' where plan_item_id=i.id and status in('held','confirmed');update public.event_service_bookings set status='cancelled' where plan_item_id=i.id and status in('pending','held','confirmed');update public.event_plans set status='partially_confirmed',updated_at=now() where id=p.id;insert into public.event_cancellations(plan_id,plan_item_id,requested_by,party,reason)values(p.id,i.id,auth.uid(),'provider',trim(p_reason))returning * into r;insert into public.event_emergency_escalations(plan_id,plan_item_id,reported_by,reason)values(p.id,i.id,auth.uid(),'Essential provider cancellation: '||trim(p_reason));insert into public.notifications(user_id,type,title,body,payload)values(p.customer_id,'announcement','Event supplier cancelled','An event supplier cancelled. KODIMALI coordination has been alerted.',jsonb_build_object('eventType','event_provider_cancelled','eventPlanId',p.id,'planItemId',i.id,'route','account/events'));return r;end$$;

revoke all on function public.send_event_agreement(uuid,text),public.accept_event_agreement(uuid),public.provider_cancel_event_item(uuid,text) from public;
grant execute on function public.send_event_agreement(uuid,text),public.accept_event_agreement(uuid),public.provider_cancel_event_item(uuid,text) to authenticated;

revoke all on function public.create_event_plan(uuid,timestamptz,timestamptz,uuid,text,integer,numeric,text),public.add_event_plan_item(uuid,text,uuid,uuid,integer,boolean,text),public.confirm_event_equipment_item(uuid,integer),public.confirm_event_service_item(uuid,integer,integer),public.request_event_quote(uuid),public.accept_event_quote(uuid),public.create_event_quote_revision(uuid,timestamptz,jsonb,numeric) from public;
grant execute on function public.create_event_plan(uuid,timestamptz,timestamptz,uuid,text,integer,numeric,text),public.add_event_plan_item(uuid,text,uuid,uuid,integer,boolean,text),public.confirm_event_equipment_item(uuid,integer),public.confirm_event_service_item(uuid,integer,integer),public.request_event_quote(uuid),public.accept_event_quote(uuid),public.create_event_quote_revision(uuid,timestamptz,jsonb,numeric) to authenticated;
