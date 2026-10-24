-- KODIMALI Ceremonies & Events: advisor, canonical rental links and fulfilment.
create table public.event_templates(
 id uuid primary key default gen_random_uuid(),slug text not null unique,name_sw text not null,name_en text not null,
 event_type_id uuid references public.event_types(id),setting text not null check(setting in('indoor','outdoor','either')),
 description_sw text,description_en text,recommendation_rules jsonb not null default '[]'::jsonb,
 milestone_rules jsonb not null default '[]'::jsonb,is_approved boolean not null default false,
 created_by uuid references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
insert into public.event_templates(slug,name_sw,name_en,setting,description_sw,description_en,recommendation_rules,milestone_rules,is_approved) values
('outdoor-wedding','Harusi ya nje','Outdoor wedding','outdoor','Mapendekezo ya awali kwa harusi ya nje.','Starting guidance for an outdoor wedding.','[{"category":"chairs_tables","formula":"guests","reason_sw":"Kila mgeni anahitaji nafasi ya kukaa.","reason_en":"Every guest needs seating."},{"category":"tents_structures","formula":"weather_cover","reason_sw":"Mpango mbadala wa mvua au jua kali.","reason_en":"Contingency for rain or strong sun."},{"service":"mc_host","reason_sw":"Kuongoza ratiba ya tukio.","reason_en":"To guide the event programme."}]','[{"days_before":30,"title_sw":"Thibitisha venue na suppliers muhimu","title_en":"Confirm venue and essential suppliers"},{"days_before":1,"title_sw":"Thibitisha delivery na setup","title_en":"Confirm delivery and setup"}]',true),
('indoor-wedding','Harusi ya ndani','Indoor wedding','indoor','Mwongozo wa harusi ya ukumbini.','Guidance for an indoor wedding.','[{"category":"chairs_tables","formula":"guests","reason_sw":"Hakikisha idadi na mpangilio wa viti.","reason_en":"Confirm seating quantity and layout."},{"service":"decorator","reason_sw":"Mapambo yaendane na venue.","reason_en":"Decoration should fit the venue."}]','[{"days_before":21,"title_sw":"Kagua uwezo wa ukumbi","title_en":"Check venue capacity"}]',true),
('school-graduation','Mahafali ya shule','School graduation','either','Mwongozo wa mahafali.','Graduation planning guidance.','[{"category":"chairs_tables","formula":"guests","reason_sw":"Viti kwa wageni na wahitimu.","reason_en":"Seating for guests and graduates."},{"category":"sound_lighting","formula":"one_system","reason_sw":"Hotuba zisikike vizuri.","reason_en":"So speeches are clearly heard."},{"service":"photographer","reason_sw":"Kuhifadhi kumbukumbu za tukio.","reason_en":"To capture the occasion."}]','[{"days_before":14,"title_sw":"Thibitisha mpangilio na sauti","title_en":"Confirm layout and sound"}]',true),
('funeral-memorial','Msiba au kumbukumbu','Funeral or memorial','either','Mwongozo wa maandalizi ya haraka na yenye heshima.','Respectful guidance for time-sensitive arrangements.','[{"category":"chairs_tables","formula":"guests","reason_sw":"Maandalizi ya kukaa kwa wageni.","reason_en":"Seating for attendees."},{"category":"tents_structures","formula":"weather_cover","reason_sw":"King protection kulingana na hali ya hewa.","reason_en":"Weather protection where needed."}]','[{"days_before":1,"title_sw":"Thibitisha delivery, setup na mawasiliano","title_en":"Confirm delivery, setup and contacts"}]',true),
('birthday','Sherehe ya kuzaliwa','Birthday','either','Mwongozo wa birthday.','Birthday planning guidance.','[{"service":"decorator","reason_sw":"Mandhari ya sherehe.","reason_en":"Event styling."},{"service":"dj","reason_sw":"Muziki na burudani.","reason_en":"Music and entertainment."}]','[]',true),
('conference','Mkutano','Conference','indoor','Mwongozo wa mkutano wa kikazi.','Conference planning guidance.','[{"category":"sound_lighting","formula":"one_system","reason_sw":"Sauti kwa wazungumzaji.","reason_en":"Audio for speakers."},{"service":"photographer","reason_sw":"Nyaraka za tukio ikiwa zinahitajika.","reason_en":"Event documentation where required."}]','[{"days_before":7,"title_sw":"Kagua vifaa na accessibility","title_en":"Check equipment and accessibility"}]',true),
('community-celebration','Sherehe ya jamii','Community celebration','either','Mwongozo wa tukio la jamii.','Community event guidance.','[{"category":"chairs_tables","formula":"guests","reason_sw":"Idadi ya viti kulingana na wageni.","reason_en":"Seating based on attendance."},{"service":"cleaning_team","reason_sw":"Usafi kabla na baada ya tukio.","reason_en":"Pre- and post-event cleaning."}]','[]',true)
on conflict(slug) do nothing;
update public.event_templates t set event_type_id=e.id from public.event_types e where e.slug=case
 when t.slug in('outdoor-wedding','indoor-wedding')then'wedding'
 when t.slug='school-graduation'then'graduation'
 when t.slug='funeral-memorial'then'memorial'
 when t.slug='birthday'then'birthday'
 when t.slug='conference'then'corporate'
 when t.slug='community-celebration'then'religious-community'end and t.event_type_id is null;

alter table public.event_plans add column if not exists template_id uuid references public.event_templates(id);
alter table public.event_plans add column if not exists setting text check(setting is null or setting in('indoor','outdoor'));
alter table public.event_plans add column if not exists venue_status text check(venue_status is null or venue_status in('needed','shortlisted','booked_elsewhere','booked_kodimali'));
alter table public.event_plans add column if not exists accessibility_requirements text;
alter table public.event_plans add column if not exists weather_contingency text;
alter table public.event_plans add column if not exists assigned_coordinator_id uuid references public.profiles(id);

create table public.event_plan_rental_assets(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id) on delete cascade,
 listing_id uuid not null references public.listings(id) on delete restrict,asset_id uuid not null references public.rental_assets(id) on delete restrict,
 booking_request_id uuid references public.booking_requests(id) on delete restrict,
 asset_kind text not null check(asset_kind in('venue','vehicle','other')),is_required boolean not null default true,
 status text not null default 'shortlisted' check(status in('shortlisted','requested','held','confirmed','declined','cancelled','completed')),
 created_at timestamptz not null default now(),unique(plan_id,asset_id)
);
create table public.event_advisor_recommendations(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id) on delete cascade,
 recommendation_kind text not null check(recommendation_kind in('equipment_category','service_category','milestone','question','venue','vehicle')),
 reference_key text,title_sw text not null,title_en text not null,reason_sw text not null,reason_en text not null,
 suggested_quantity numeric(12,2),estimate_tzs numeric(14,2),estimate_source text,status text not null default 'suggested' check(status in('suggested','accepted','dismissed','fulfilled')),
 created_at timestamptz not null default now(),check(estimate_tzs is null or estimate_tzs>=0)
);
create table public.event_tasks(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id) on delete cascade,plan_item_id uuid references public.event_plan_items(id),
 task_kind text not null check(task_kind in('planning','delivery','pickup','setup','teardown','staff','run_of_show','handover','return','inspection','support')),
 title text not null,details text,assigned_profile_id uuid references public.profiles(id),due_at timestamptz,starts_at timestamptz,ends_at timestamptz,
 status text not null default 'pending' check(status in('pending','assigned','in_progress','blocked','completed','cancelled')),
 customer_visible boolean not null default true,completed_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.event_incidents(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.event_plans(id),plan_item_id uuid references public.event_plan_items(id),
 reported_by uuid not null references public.profiles(id),incident_kind text not null check(incident_kind in('delay','damage','missing_item','safety','provider_absence','customer_support','other')),
 severity text not null check(severity in('low','medium','high','critical')),summary text not null,evidence_paths jsonb not null default '[]'::jsonb,
 status text not null default 'open' check(status in('open','investigating','actioned','resolved','closed')),resolution text,created_at timestamptz not null default now(),resolved_at timestamptz
);

create index event_rental_assets_plan_idx on public.event_plan_rental_assets(plan_id,status);
create index event_recommendations_plan_idx on public.event_advisor_recommendations(plan_id,status);
create index event_tasks_schedule_idx on public.event_tasks(plan_id,due_at,status);
create index event_incidents_plan_idx on public.event_incidents(plan_id,status);

alter table public.event_templates enable row level security;alter table public.event_plan_rental_assets enable row level security;
alter table public.event_advisor_recommendations enable row level security;alter table public.event_tasks enable row level security;alter table public.event_incidents enable row level security;
create policy event_templates_public on public.event_templates for select using(is_approved);
create policy event_templates_admin on public.event_templates for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));
create policy event_rental_assets_participants on public.event_plan_rental_assets for select to authenticated using(exists(select 1 from public.event_plans p where p.id=plan_id and(p.customer_id=auth.uid() or public.has_admin_permission('events.manage'))));
create policy event_rental_assets_customer_insert on public.event_plan_rental_assets for insert to authenticated with check(exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid() and p.status='draft'));
create policy event_advisor_customer on public.event_advisor_recommendations for select to authenticated using(exists(select 1 from public.event_plans p where p.id=plan_id and(p.customer_id=auth.uid() or public.has_admin_permission('events.manage'))));
create policy event_tasks_participants on public.event_tasks for select to authenticated using(exists(select 1 from public.event_plans p where p.id=plan_id and(p.customer_id=auth.uid() or assigned_profile_id=auth.uid() or public.has_admin_permission('events.manage'))));
create policy event_tasks_coordinator on public.event_tasks for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));
create policy event_incidents_participants on public.event_incidents for select to authenticated using(reported_by=auth.uid() or exists(select 1 from public.event_plans p where p.id=plan_id and(p.customer_id=auth.uid() or public.has_admin_permission('events.manage'))));
create policy event_incidents_insert on public.event_incidents for insert to authenticated with check(reported_by=auth.uid() and exists(select 1 from public.event_plans p where p.id=plan_id and p.customer_id=auth.uid()));
create policy event_incidents_coordinator on public.event_incidents for all to authenticated using(public.has_admin_permission('events.manage')) with check(public.has_admin_permission('events.manage'));

create or replace function public.run_event_advisor(p_plan_id uuid,p_template_id uuid,p_setting text,p_venue_status text,p_accessibility text default null,p_weather_contingency text default null)
returns setof public.event_advisor_recommendations language plpgsql security definer set search_path=public as $$declare p public.event_plans;t public.event_templates;r jsonb;m jsonb;q numeric;begin
 select * into p from public.event_plans where id=p_plan_id and customer_id=auth.uid() and status='draft' for update;if p.id is null then raise exception 'Editable customer event plan required';end if;
 select * into t from public.event_templates where id=p_template_id and is_approved;if t.id is null then raise exception 'Approved event template required';end if;
 update public.event_plans set template_id=t.id,setting=p_setting,venue_status=p_venue_status,accessibility_requirements=nullif(trim(p_accessibility),''),weather_contingency=nullif(trim(p_weather_contingency),''),updated_at=now()where id=p.id;
 delete from public.event_advisor_recommendations where plan_id=p.id and status='suggested';
 for r in select value from jsonb_array_elements(t.recommendation_rules)loop q:=case when r->>'formula'='guests'then p.attendance when r->>'formula'='weather_cover'then ceil(p.attendance/10.0) else null end;insert into public.event_advisor_recommendations(plan_id,recommendation_kind,reference_key,title_sw,title_en,reason_sw,reason_en,suggested_quantity,estimate_source)values(p.id,case when r?'category'then'equipment_category'else'service_category'end,coalesce(r->>'category',r->>'service'),coalesce(r->>'category',r->>'service'),coalesce(r->>'category',r->>'service'),r->>'reason_sw',r->>'reason_en',q,'No price assumed; choose a live approved offering');end loop;
 for m in select value from jsonb_array_elements(t.milestone_rules)loop insert into public.event_advisor_recommendations(plan_id,recommendation_kind,reference_key,title_sw,title_en,reason_sw,reason_en)values(p.id,'milestone',m->>'days_before',m->>'title_sw',m->>'title_en','Hatua ya maandalizi kutoka template iliyothibitishwa.','Planning milestone from an approved template.');end loop;
 return query select * from public.event_advisor_recommendations where plan_id=p.id order by created_at;end$$;

-- Owner/authorized-manager registration survives email-confirmation flows.
create or replace function public.handle_owner_self_registration()returns trigger language plpgsql security definer set search_path=public,auth as $$declare m jsonb:=coalesce(new.raw_user_meta_data,'{}'::jsonb);ot text;begin
 if coalesce((m->>'register_as_owner')::boolean,false)is not true then return new;end if;ot:=coalesce(nullif(m->>'owner_type',''),'individual');if ot not in('individual','vehicle_owner','venue_owner','equipment_owner','authorized_manager')then raise exception 'Invalid owner type';end if;
 insert into public.owner_applications(applicant_id,owner_type,legal_name,phone_number,authorization_summary,document_paths)values(new.id,ot,coalesce(nullif(trim(m->>'full_name'),''),'KODIMALI applicant'),coalesce(nullif(trim(m->>'phone_number'),''),'pending'),coalesce(nullif(trim(m->>'authorization_summary'),''),'Verification documents pending'),'[]'::jsonb)on conflict do nothing;return new;end$$;
drop trigger if exists zz_handle_owner_self_registration on auth.users;
create trigger zz_handle_owner_self_registration after insert on auth.users for each row execute function public.handle_owner_self_registration();

revoke all on function public.run_event_advisor(uuid,uuid,text,text,text,text) from public;
grant execute on function public.run_event_advisor(uuid,uuid,text,text,text,text) to authenticated;
