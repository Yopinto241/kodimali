-- Independent accommodation operations. No links to marketplace bookings,
-- payment_intents, financial ledgers or payment-provider functions.
begin;
set local search_path=public,extensions,pg_temp;
create extension if not exists btree_gist with schema extensions;

insert into public.asset_categories(name,slug,description,icon_key,display_order,field_schema)
values ('Lodges & Guesthouses','lodges-guesthouses','Independent accommodation. Enquire directly with the lodge.','hotel',65,'[]')
on conflict(slug) do nothing;

create table public.lodges (
 id uuid primary key default gen_random_uuid(), authorized_owner uuid not null references public.profiles(id),
 name text not null check(length(trim(name)) between 2 and 120), location_id uuid not null references public.locations(id),
 location_label text not null check(length(trim(location_label)) between 2 and 240),
 phone text not null check(length(trim(phone)) between 6 and 40), email text, description text not null default '' check(length(description)<=10000),
 facilities text[] not null default '{}' check(cardinality(facilities)<=100), photos text[] not null default '{}' check(cardinality(photos)<=20),
 check_in_policy text not null default '' check(length(check_in_policy)<=2000), check_out_policy text not null default '' check(length(check_out_policy)<=2000),
 timezone text not null default 'Africa/Dar_es_Salaam', allow_same_day_turnover boolean not null default true,
 publish_availability boolean not null default false, published boolean not null default false,
 verification_status text not null default 'pending' check(verification_status in('pending','verified','rejected')),
 review_notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(not published or verification_status='verified')
);
create table public.lodge_members (
 lodge_id uuid not null references public.lodges(id), profile_id uuid not null references public.profiles(id),
 role text not null check(role in('owner','manager','receptionist','housekeeping')),
 permissions text[] not null default '{}', active boolean not null default true, created_at timestamptz not null default now(),
 primary key(lodge_id,profile_id)
);
create table public.lodge_access_applications (
 id uuid primary key default gen_random_uuid(), lodge_id uuid not null references public.lodges(id),
 applicant_id uuid not null references public.profiles(id), notes text not null check(length(trim(notes)) between 10 and 2000),
 status text not null default 'pending' check(status in('pending','approved','rejected')),
 reviewed_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create unique index lodge_one_pending_application on public.lodge_access_applications(lodge_id,applicant_id) where status='pending';
create table public.lodge_invitations (
 id uuid primary key default gen_random_uuid(), lodge_id uuid not null references public.lodges(id), email text not null,
 role text not null check(role in('manager','receptionist','housekeeping')), permissions text[] not null default '{}',
 invited_by uuid not null references public.profiles(id), expires_at timestamptz not null default now()+interval '7 days',
 status text not null default 'pending' check(status in('pending','accepted','revoked')), created_at timestamptz not null default now()
);
create unique index lodge_pending_invitation on public.lodge_invitations(lodge_id,lower(email)) where status='pending';
create table public.lodge_room_types (
 id uuid primary key default gen_random_uuid(), lodge_id uuid not null references public.lodges(id),
 name text not null check(length(trim(name)) between 1 and 100), description text not null default '' check(length(description)<=10000),
 main_image text, nightly_rate numeric(14,2) not null check(nightly_rate>=0), currency text not null default 'TZS' check(currency ~ '^[A-Z]{3}$'),
 facilities text[] not null default '{}' check(cardinality(facilities)<=100), beds text not null default '',
 max_occupancy integer not null check(max_occupancy between 1 and 100), active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(id,lodge_id)
);
create unique index lodge_unique_type_name on public.lodge_room_types(lodge_id,lower(trim(name)));
create table public.lodge_rooms (
 id uuid primary key default gen_random_uuid(), lodge_id uuid not null references public.lodges(id),
 room_type_id uuid not null, foreign key(room_type_id,lodge_id) references public.lodge_room_types(id,lodge_id),
 code text not null check(length(trim(code)) between 1 and 60), room_type text not null check(length(trim(room_type)) between 1 and 100),
 beds text not null default '', max_occupancy integer not null check(max_occupancy between 1 and 100),
 nightly_rate numeric(14,2) not null check(nightly_rate>=0), currency text not null default 'TZS' check(currency ~ '^[A-Z]{3}$'),
 facilities text[] not null default '{}' check(cardinality(facilities)<=100), photos text[] not null default '{}' check(cardinality(photos)<=20), active boolean not null default true,
 condition text not null default 'ready' check(condition in('ready','occupied','cleaning','maintenance','out_of_service')),
 maintenance_notes text not null default '', created_at timestamptz not null default now(), unique(id,lodge_id)
);
create unique index lodge_unique_room_code on public.lodge_rooms(lodge_id,lower(trim(code)));
create table public.lodge_guests (
 id uuid primary key default gen_random_uuid(), lodge_id uuid not null references public.lodges(id),
 full_name text not null check(length(trim(full_name)) between 2 and 160), phone text, email text,
 created_at timestamptz not null default now(), unique(id,lodge_id)
);
create table public.lodge_reservations (
 id uuid primary key default gen_random_uuid(), group_id uuid not null default gen_random_uuid(), lodge_id uuid not null references public.lodges(id),
 room_id uuid not null, room_type_id uuid not null, accepted_terms jsonb not null default '{}', accepted_at timestamptz,
 foreign key(room_type_id,lodge_id) references public.lodge_room_types(id,lodge_id), guest_id uuid, arrival date not null, departure date not null,
 stay daterange generated always as (daterange(arrival,departure,'[)')) stored,
 guests integer not null default 1 check(guests between 1 and 100),
 status text not null default 'pending' check(status in('pending','confirmed','checked_in','checked_out','cancelled','blocked')),
 channel text not null check(channel in('walk_in','phone','whatsapp','direct','kodimali_enquiry','other')),
 total_amount numeric(14,2) not null check(total_amount>=0), currency text not null check(currency ~ '^[A-Z]{3}$'), notes text not null default '',
 checked_in_at timestamptz, checked_out_at timestamptz, created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(id,lodge_id),
 foreign key(room_id,lodge_id) references public.lodge_rooms(id,lodge_id),
 foreign key(guest_id,lodge_id) references public.lodge_guests(id,lodge_id),
 check(departure>arrival), check(departure-arrival<=730), check(status in('blocked','cancelled') or guest_id is not null),
 exclude using gist(room_id with =,stay with &&) where(status in('confirmed','checked_in','checked_out','blocked'))
);
create index lodge_reservation_pages on public.lodge_reservations(lodge_id,arrival,id);
create index lodge_guests_pages on public.lodge_guests(lodge_id,full_name,id);
create table public.lodge_payments (
 id uuid primary key default gen_random_uuid(), lodge_id uuid not null references public.lodges(id), reservation_id uuid not null,
 amount numeric(14,2) not null check(amount<>0), currency text not null check(currency ~ '^[A-Z]{3}$'),
 method text not null check(length(trim(method)) between 1 and 100), reference text,
 received_at timestamptz not null default now(), recorded_at timestamptz not null default now(), recorded_by uuid not null references public.profiles(id),
 reverses_id uuid unique references public.lodge_payments(id), corrects_id uuid unique references public.lodge_payments(id), reason text,
 foreign key(reservation_id,lodge_id) references public.lodge_reservations(id,lodge_id),
 check((reverses_id is null and amount>0) or (reverses_id is not null and amount<0 and length(trim(reason))>=5))
);
create unique index lodge_receipt_reference on public.lodge_payments(lodge_id,reference) where reference is not null and reverses_id is null;
create index lodge_payment_reporting on public.lodge_payments(lodge_id,received_at);
create table public.lodge_enquiries (
 id uuid primary key default gen_random_uuid(), lodge_id uuid not null references public.lodges(id), profile_id uuid not null references public.profiles(id),
 room_type_id uuid not null, quoted_terms jsonb not null, reservation_id uuid references public.lodge_reservations(id),
 foreign key(room_type_id,lodge_id) references public.lodge_room_types(id,lodge_id),
 arrival date not null, departure date not null, guests integer not null check(guests between 1 and 100),
 message text not null check(length(trim(message)) between 5 and 2000), contact_phone text not null check(length(trim(contact_phone)) between 6 and 40),
 status text not null default 'new' check(status in('new','contacted','closed')), created_at timestamptz not null default now(), check(departure>arrival and departure-arrival<=730)
);
create table public.lodge_audit_log (
 id bigint generated always as identity primary key, lodge_id uuid not null references public.lodges(id), actor_id uuid references public.profiles(id),
 action text not null, entity_id uuid, details jsonb not null default '{}', created_at timestamptz not null default now()
);

create table public.lodge_operation_requests (
 lodge_id uuid not null references public.lodges(id), request_id uuid not null, actor_id uuid not null references public.profiles(id),
 action text not null, payload_hash text not null, response jsonb not null, created_at timestamptz not null default now(), primary key(lodge_id,request_id)
);
alter table public.lodge_operation_requests enable row level security;
revoke all on public.lodge_operation_requests from public,anon,authenticated;
create function public.lodge_finish(p_lodge uuid,p_action text,p_request uuid,p_hash text,p_response jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_request is not null then insert into public.lodge_operation_requests(lodge_id,request_id,actor_id,action,payload_hash,response) values(p_lodge,p_request,auth.uid(),p_action,p_hash,p_response);end if;
 return p_response;
end $$;

create function public.lodge_has_permission(p_lodge uuid,p_permission text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null and (public.is_super_admin(auth.uid()) or exists(
 select 1 from public.lodge_members where lodge_id=p_lodge and profile_id=auth.uid() and active
 and (role='owner' or p_permission=any(permissions))));
$$;
create function public.lodge_default_permissions(p_role text) returns text[] language sql immutable set search_path=public,pg_temp as $$
 select case p_role when 'owner' then array['*'] when 'manager' then array['rooms.read','rooms.write','reservations.read','reservations.write','guests.read','guests.write','payments.read','payments.write','payments.reverse','staff.read','staff.manage','settings.read','settings.write','reports.read','audit.read']
 when 'receptionist' then array['rooms.read','reservations.read','reservations.write','guests.read','guests.write','payments.read','payments.write']
 when 'housekeeping' then array['rooms.read','rooms.condition'] else '{}'::text[] end;
$$;
create function public.lodge_require(p_lodge uuid,p_permission text) returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
begin if not public.lodge_has_permission(p_lodge,p_permission) then raise exception 'Lodge permission denied' using errcode='42501'; end if; end $$;
create function public.lodge_audit() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into public.lodge_audit_log(lodge_id,actor_id,action,entity_id,details)
 values(new.lodge_id,auth.uid(),tg_table_name||'.'||lower(tg_op),coalesce((to_jsonb(new)->>'id')::uuid,(to_jsonb(new)->>'profile_id')::uuid),jsonb_build_object('before',case when tg_op='UPDATE' then to_jsonb(old)-array['full_name','phone','email','message','contact_phone','notes','maintenance_notes'] else null end,'after',to_jsonb(new)-array['full_name','phone','email','message','contact_phone','notes','maintenance_notes']));
 return new;
end $$;
do $$ declare t text; begin
 foreach t in array array['lodge_room_types','lodge_rooms','lodge_guests','lodge_reservations','lodge_payments','lodge_members','lodge_invitations','lodge_access_applications','lodge_enquiries'] loop
 execute format('create trigger lodge_audit after insert or update on public.%I for each row execute function public.lodge_audit()',t);
 end loop;
end $$;
create function public.lodge_immutable() returns trigger language plpgsql set search_path=public,pg_temp as $$
begin raise exception 'Append-only operational audit: record a reversal instead'; end $$;
create trigger lodge_payments_immutable before update or delete on public.lodge_payments for each row execute function public.lodge_immutable();
create trigger lodge_audit_immutable before update or delete on public.lodge_audit_log for each row execute function public.lodge_immutable();


create function public.lodge_room_projection() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.lodge_room_types; begin
 select * into t from public.lodge_room_types where id=new.room_type_id and lodge_id=new.lodge_id;
 if not found then raise exception 'Choose a room type belonging to this lodge'; end if;
 new.room_type:=t.name;new.beds:=t.beds;new.max_occupancy:=t.max_occupancy;new.nightly_rate:=t.nightly_rate;new.currency:=t.currency;new.facilities:=t.facilities;new.photos:=case when t.main_image is null then '{}'::text[] else array[t.main_image] end;
 return new;
end $$;
create trigger lodge_room_projection before insert or update on public.lodge_rooms for each row execute function public.lodge_room_projection();
create function public.lodge_type_projection() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin update public.lodge_rooms set room_type_id=new.id where room_type_id=new.id;return new;end $$;
create trigger lodge_type_projection after update on public.lodge_room_types for each row execute function public.lodge_type_projection();
create function public.lodge_reservation_terms() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.lodge_rooms; t public.lodge_room_types; l public.lodges; begin
 select * into r from public.lodge_rooms where id=new.room_id and lodge_id=new.lodge_id;
 select * into t from public.lodge_room_types where id=r.room_type_id;
 if tg_op='UPDATE' and old.accepted_at is not null then
  if new.status='pending' or new.guests<>old.guests or new.total_amount<>old.total_amount or new.currency<>old.currency or new.arrival<>old.arrival or (new.departure<>old.departure and new.status<>'checked_out') or r.room_type_id<>old.room_type_id or new.accepted_terms<>old.accepted_terms or new.accepted_at is distinct from old.accepted_at then
   raise exception 'Accepted reservation price, room type and terms cannot be changed';
  end if;
 end if;
 new.room_type_id:=r.room_type_id;
 if new.status in('confirmed','checked_in') and new.accepted_at is null then
  select * into l from public.lodges where id=new.lodge_id;
  new.accepted_terms:=jsonb_build_object('room_type_id',t.id,'room_type',t.name,'description',t.description,'facilities',t.facilities,'beds',t.beds,'max_occupancy',t.max_occupancy,'nightly_rate',t.nightly_rate,'currency',new.currency,'total_amount',new.total_amount,'arrival',new.arrival,'departure',new.departure,'check_in_policy',l.check_in_policy,'check_out_policy',l.check_out_policy);
  new.accepted_at:=now();
 end if;
 return new;
end $$;
create trigger lodge_reservation_terms before insert or update on public.lodge_reservations for each row execute function public.lodge_reservation_terms();
create function public.lodge_room_bookable(p_room uuid,p_arrival date,p_departure date,p_except uuid default null) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.lodge_rooms r join public.lodge_room_types t on t.id=r.room_type_id join public.lodges l on l.id=r.lodge_id
 where r.id=p_room and r.active and t.active and p_departure>p_arrival and p_departure-p_arrival<=730 and p_arrival>=(now() at time zone l.timezone)::date
 and r.condition not in('maintenance','out_of_service') and (p_arrival>(now() at time zone l.timezone)::date or r.condition='ready')
 and not exists(select 1 from public.lodge_reservations b where b.room_id=r.id and b.id is distinct from p_except and b.status in('confirmed','checked_in','checked_out','blocked')
 and (b.stay&&daterange(p_arrival,p_departure,'[)') or (not l.allow_same_day_turnover and (b.departure=p_arrival or b.arrival=p_departure)))));
$$;

create function public.lodge_guard_marketplace_listing() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if exists(select 1 from public.asset_categories where id=new.category_id and slug='lodges-guesthouses') then raise exception 'Register lodges through the dedicated Lodge workspace, not rental checkout'; end if;
 return new;
end $$;
create trigger lodge_independent_inventory before insert or update of category_id on public.listings for each row execute function public.lodge_guard_marketplace_listing();

-- No client may mutate tables directly: all mutations pass through the same
-- permission checks, tenant locks, audit and validation operations on every app.
do $$ declare t text; perm text; begin
 foreach t in array array['lodges','lodge_members','lodge_invitations','lodge_access_applications','lodge_room_types','lodge_rooms','lodge_guests','lodge_reservations','lodge_payments','lodge_enquiries','lodge_audit_log'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 if t='lodges' then
 execute 'create policy lodge_read on public.lodges for select to authenticated using(authorized_owner=auth.uid() or lodge_has_permission(id,''rooms.read''))';
 else
 perm:=case t when 'lodge_members' then 'staff.read' when 'lodge_invitations' then 'staff.read' when 'lodge_access_applications' then 'staff.read' when 'lodge_room_types' then 'rooms.read' when 'lodge_rooms' then 'rooms.read' when 'lodge_guests' then 'guests.read' when 'lodge_reservations' then 'reservations.read' when 'lodge_payments' then 'payments.read' when 'lodge_enquiries' then 'reservations.read' else 'audit.read' end;
 execute format('create policy lodge_read on public.%I for select to authenticated using(public.lodge_has_permission(lodge_id,%L))',t,perm);
 end if;
 end loop;
end $$;

revoke select on public.lodges from authenticated;
grant select(id,authorized_owner,name,location_id,location_label,phone,email,description,facilities,photos,timezone,allow_same_day_turnover,publish_availability,published,verification_status,created_at,updated_at) on public.lodges to authenticated;

create function public.lodge_register(p_data jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; begin
 if auth.uid() is null then raise exception 'Sign in to register a lodge' using errcode='42501'; end if;
 if not exists(select 1 from public.locations where id=(p_data->>'location_id')::uuid and is_active) then raise exception 'Choose an active KODIMALI location'; end if;
 insert into public.lodges(authorized_owner,name,location_id,location_label,phone,email,description,facilities)
 values(auth.uid(),trim(p_data->>'name'),(p_data->>'location_id')::uuid,trim(p_data->>'location_label'),trim(p_data->>'phone'),nullif(trim(p_data->>'email'),''),coalesce(p_data->>'description',''),array(select jsonb_array_elements_text(coalesce(p_data->'facilities','[]')))) returning id into v_id;
 insert into public.lodge_members(lodge_id,profile_id,role,permissions) values(v_id,auth.uid(),'owner',array['*']);
 insert into public.lodge_audit_log(lodge_id,actor_id,action,entity_id) values(v_id,auth.uid(),'lodge.registered',v_id);
 return v_id;
end $$;

create function public.lodge_command(p_lodge uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare l public.lodges; r public.lodge_rooms; b public.lodge_reservations; pay public.lodge_payments; inv public.lodge_invitations; rt public.lodge_room_types; enquiry public.lodge_enquiries;
 v_id uuid; g uuid; v_request uuid; v_hash text; previous public.lodge_operation_requests; grp uuid:=gen_random_uuid(); ids jsonb:='[]'; item text; role_name text; grants text[]; me text; today date; next_status text; arrival_date date; departure_date date;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 -- Serialize operational decisions within a lodge; GiST remains the final
 -- cross-transaction arbiter even for privileged/direct database inserts.
 select * into l from public.lodges where id=p_lodge for update;
 if not found then raise exception 'Lodge not found'; end if;
 today:=(now() at time zone l.timezone)::date;
 if p_action='block_room' then p_action:='reserve';p_data:=p_data||'{"status":"blocked","channel":"other","guests":1}'::jsonb; end if;
 if p_action in('reserve','record_payment','reverse_payment','correct_payment') and p_data?'request_id' then
  v_request:=(p_data->>'request_id')::uuid; v_hash:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  select * into previous from public.lodge_operation_requests where lodge_id=p_lodge and request_id=v_request;
  if found then
   if previous.actor_id<>auth.uid() or previous.action<>p_action or previous.payload_hash<>v_hash then raise exception 'This request was already processed. Refresh before making changes'; end if;
   perform public.lodge_require(p_lodge,case when p_action='reserve' then 'reservations.write' when p_action in('reverse_payment','correct_payment') then 'payments.reverse' else 'payments.write' end);
   return previous.response;
  end if;
 end if;
 if p_action='apply_access' then
  if (select count(*) from public.lodge_access_applications where applicant_id=auth.uid() and created_at>now()-interval '1 hour')>=5 then raise exception 'Please wait before applying again'; end if;
  insert into public.lodge_access_applications(lodge_id,applicant_id,notes) values(p_lodge,auth.uid(),trim(p_data->>'notes')) returning id into v_id;
 elsif p_action='accept_invitation' then
  select * into inv from public.lodge_invitations where id=(p_data->>'id')::uuid and lodge_id=p_lodge and status='pending' and expires_at>now() for update;
  if not found or not exists(select 1 from auth.users where id=auth.uid() and lower(email)=lower(inv.email)) then raise exception 'Invitation unavailable for this account' using errcode='42501'; end if;
  if exists(select 1 from public.lodge_members where lodge_id=p_lodge and profile_id=auth.uid() and role='owner') then raise exception 'Owner access cannot be replaced'; end if;
  insert into public.lodge_members(lodge_id,profile_id,role,permissions) values(p_lodge,auth.uid(),inv.role,inv.permissions) on conflict(lodge_id,profile_id) do update set role=excluded.role,permissions=excluded.permissions,active=true;
  update public.lodge_invitations set status='accepted' where id=inv.id; v_id:=inv.id;
 elsif p_action='review' then
  if not public.is_super_admin(auth.uid()) then raise exception 'Super Admin required' using errcode='42501'; end if;
  update public.lodges set verification_status=case when (p_data->>'approved')::boolean then 'verified' else 'rejected' end,published=coalesce((p_data->>'approved')::boolean,false),review_notes=p_data->>'notes',updated_at=now() where id=p_lodge;
  insert into public.lodge_audit_log(lodge_id,actor_id,action,entity_id) values(p_lodge,auth.uid(),'lodge.reviewed',p_lodge);
 elsif p_action='settings' then
  perform public.lodge_require(p_lodge,'settings.write');
  if not exists(select 1 from pg_timezone_names where name=coalesce(p_data->>'timezone',l.timezone)) then raise exception 'Choose a valid IANA timezone'; end if;
  if not exists(select 1 from public.locations where id=coalesce((p_data->>'location_id')::uuid,l.location_id) and is_active) then raise exception 'Choose an active location'; end if;
  if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'photos','[]')) x where x not like p_lodge::text||'/%') then raise exception 'Photo belongs to a different lodge'; end if;
  update public.lodges set name=coalesce(trim(p_data->>'name'),name),description=coalesce(p_data->>'description',description),phone=coalesce(trim(p_data->>'phone'),phone),email=coalesce(p_data->>'email',email),location_id=coalesce((p_data->>'location_id')::uuid,location_id),location_label=coalesce(p_data->>'location_label',location_label),check_in_policy=coalesce(p_data->>'check_in_policy',check_in_policy),check_out_policy=coalesce(p_data->>'check_out_policy',check_out_policy),timezone=coalesce(p_data->>'timezone',timezone),allow_same_day_turnover=coalesce((p_data->>'allow_same_day_turnover')::boolean,allow_same_day_turnover),publish_availability=coalesce((p_data->>'publish_availability')::boolean,publish_availability),facilities=case when p_data?'facilities' then array(select jsonb_array_elements_text(p_data->'facilities')) else facilities end,photos=case when p_data?'photos' then array(select jsonb_array_elements_text(p_data->'photos')) else photos end,updated_at=now() where id=p_lodge;
  insert into public.lodge_audit_log(lodge_id,actor_id,action,entity_id) values(p_lodge,auth.uid(),'lodge.settings',p_lodge);
 elsif p_action='save_room_type' then
  perform public.lodge_require(p_lodge,'rooms.write');v_id:=coalesce((p_data->>'id')::uuid,gen_random_uuid());
  if exists(select 1 from public.lodge_room_types where id=v_id and lodge_id<>p_lodge) then raise exception 'Room type permission denied' using errcode='42501';end if;
  if nullif(p_data->>'main_image','') is not null and not exists(select 1 from storage.objects where bucket_id='lodge-media' and name=p_data->>'main_image' and name like p_lodge::text||'/%') then raise exception 'Choose an authorized lodge image';end if;
  if exists(select 1 from public.lodge_reservations where room_type_id=v_id and status in('confirmed','checked_in') and departure>today and guests>(p_data->>'max_occupancy')::int) then raise exception 'Resolve upcoming reservations before reducing room capacity';end if;
  if exists(select 1 from public.lodge_reservations where room_type_id=v_id and status in('confirmed','checked_in') and departure>today and not coalesce((p_data->>'active')::boolean,true)) then raise exception 'Resolve upcoming reservations before deactivating a room type';end if;
  insert into public.lodge_room_types(id,lodge_id,name,description,main_image,nightly_rate,currency,facilities,beds,max_occupancy,active)
  values(v_id,p_lodge,trim(p_data->>'name'),coalesce(p_data->>'description',''),nullif(p_data->>'main_image',''),(p_data->>'nightly_rate')::numeric,upper(coalesce(p_data->>'currency','TZS')),array(select jsonb_array_elements_text(coalesce(p_data->'facilities','[]'))),coalesce(p_data->>'beds',''),(p_data->>'max_occupancy')::int,coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set name=excluded.name,description=excluded.description,main_image=excluded.main_image,nightly_rate=excluded.nightly_rate,currency=excluded.currency,facilities=excluded.facilities,beds=excluded.beds,max_occupancy=excluded.max_occupancy,active=excluded.active,updated_at=now();
 elsif p_action='confirm_enquiry' then
  perform public.lodge_require(p_lodge,'reservations.write');perform public.lodge_require(p_lodge,'guests.write');
  select * into enquiry from public.lodge_enquiries where id=(p_data->>'id')::uuid and lodge_id=p_lodge for update;
  if not found or enquiry.status='closed' then raise exception 'Request unavailable';end if;
  if enquiry.reservation_id is not null then return jsonb_build_object('id',enquiry.reservation_id,'ok',true);end if;
  select * into r from public.lodge_rooms where lodge_id=p_lodge and room_type_id=enquiry.room_type_id and public.lodge_room_bookable(id,enquiry.arrival,enquiry.departure) order by lower(code),id limit 1 for update;
  if not found or enquiry.guests>r.max_occupancy then raise exception 'No eligible room is available for these dates' using errcode='23P01';end if;
  select * into rt from public.lodge_room_types where id=enquiry.room_type_id;
  select full_name into me from public.profiles where id=enquiry.profile_id;
  insert into public.lodge_guests(lodge_id,full_name,phone) values(p_lodge,coalesce(nullif(me,''),'KODIMALI guest'),enquiry.contact_phone) returning id into g;
  insert into public.lodge_reservations(lodge_id,room_id,guest_id,arrival,departure,guests,status,channel,total_amount,currency,notes,created_by,accepted_at,accepted_terms)
  values(p_lodge,r.id,g,enquiry.arrival,enquiry.departure,enquiry.guests,'confirmed','kodimali_enquiry',(enquiry.quoted_terms->>'total_amount')::numeric,enquiry.quoted_terms->>'currency',enquiry.message,auth.uid(),now(),enquiry.quoted_terms) returning id into v_id;
  update public.lodge_enquiries set reservation_id=v_id,status='contacted' where id=enquiry.id;
 elsif p_action='save_room' then
  perform public.lodge_require(p_lodge,'rooms.write');
  v_id:=coalesce((p_data->>'id')::uuid,gen_random_uuid());
  if exists(select 1 from public.lodge_rooms where id=v_id and lodge_id<>p_lodge) then raise exception 'Room permission denied' using errcode='42501'; end if;
  if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'photos','[]')) x where x not like p_lodge::text||'/%') then raise exception 'Photo belongs to a different lodge'; end if;
  if exists(select 1 from public.lodge_reservations where room_id=v_id and status in('confirmed','checked_in') and departure>today and (not coalesce((p_data->>'active')::boolean,true) or room_type_id is distinct from (p_data->>'room_type_id')::uuid)) then raise exception 'Resolve upcoming reservations before deactivating or reducing room capacity'; end if;
  insert into public.lodge_rooms(id,lodge_id,code,room_type_id,room_type,beds,max_occupancy,nightly_rate,currency,facilities,photos,active,maintenance_notes)
  values(v_id,p_lodge,trim(p_data->>'code'),(p_data->>'room_type_id')::uuid,trim(p_data->>'room_type'),coalesce(p_data->>'beds',''),(p_data->>'max_occupancy')::int,(p_data->>'nightly_rate')::numeric,upper(coalesce(p_data->>'currency','TZS')),array(select jsonb_array_elements_text(coalesce(p_data->'facilities','[]'))),array(select jsonb_array_elements_text(coalesce(p_data->'photos','[]'))),coalesce((p_data->>'active')::boolean,true),coalesce(p_data->>'maintenance_notes',''))
  on conflict(id) do update set code=excluded.code,room_type_id=excluded.room_type_id,room_type=excluded.room_type,beds=excluded.beds,max_occupancy=excluded.max_occupancy,nightly_rate=excluded.nightly_rate,currency=excluded.currency,facilities=excluded.facilities,photos=excluded.photos,active=excluded.active,maintenance_notes=excluded.maintenance_notes;
 elsif p_action='save_guest' then
  perform public.lodge_require(p_lodge,'guests.write');
  v_id:=(p_data->>'id')::uuid;
  update public.lodge_guests set full_name=trim(p_data->>'full_name'),phone=p_data->>'phone',email=p_data->>'email' where lodge_id=p_lodge and id=v_id;
  if not found then raise exception 'Guest not found'; end if;
 elsif p_action='room_condition' then
  if not(public.lodge_has_permission(p_lodge,'rooms.write') or public.lodge_has_permission(p_lodge,'rooms.condition')) then raise exception 'Room permission denied' using errcode='42501'; end if;
  next_status:=p_data->>'condition';
  if next_status not in('ready','cleaning','maintenance','out_of_service') then raise exception 'Occupied status is managed by check-in'; end if;
  if exists(select 1 from public.lodge_reservations where lodge_id=p_lodge and room_id=(p_data->>'id')::uuid and status='checked_in') then raise exception 'Check out the guest before changing the room condition'; end if;
  update public.lodge_rooms set condition=next_status,maintenance_notes=coalesce(p_data->>'maintenance_notes',maintenance_notes) where id=(p_data->>'id')::uuid and lodge_id=p_lodge returning id into v_id;
  if not found then raise exception 'Room not found'; end if;
 elsif p_action='reserve' then
  perform public.lodge_require(p_lodge,'reservations.write');
  arrival_date:=(p_data->>'arrival')::date;departure_date:=(p_data->>'departure')::date;next_status:=coalesce(p_data->>'status','confirmed');
  if arrival_date is null or departure_date is null or departure_date<=arrival_date or arrival_date<today or departure_date-arrival_date>730 or next_status not in('pending','confirmed','blocked') then raise exception 'Invalid stay dates or initial status'; end if;
  if next_status<>'blocked' then
   perform public.lodge_require(p_lodge,'guests.write');
   insert into public.lodge_guests(lodge_id,full_name,phone,email) values(p_lodge,trim(p_data->>'guest_name'),p_data->>'guest_phone',p_data->>'guest_email') returning id into g;
  end if;
  if jsonb_array_length(coalesce(p_data->'room_ids','[]')) not between 1 and 50 then raise exception 'Choose between 1 and 50 rooms'; end if;
  for item in select jsonb_array_elements_text(p_data->'room_ids') loop
   select * into r from public.lodge_rooms where id=item::uuid and lodge_id=p_lodge and active;
   if not found then raise exception 'Room is unavailable'; end if;
   if (p_data->>'guests')::int>r.max_occupancy then raise exception 'Guest count exceeds room capacity'; end if;
   if not l.allow_same_day_turnover and exists(select 1 from public.lodge_reservations where room_id=r.id and status in('confirmed','checked_in','checked_out','blocked') and (departure=arrival_date or arrival=departure_date)) then raise exception 'Same-day turnover is disabled'; end if;
   if next_status<>'blocked' and not public.lodge_room_bookable(r.id,arrival_date,departure_date) then raise exception 'Room is unavailable for these dates' using errcode='23P01';end if;
   insert into public.lodge_reservations(group_id,lodge_id,room_id,guest_id,arrival,departure,guests,status,channel,total_amount,currency,notes,created_by)
   values(grp,p_lodge,r.id,g,arrival_date,departure_date,coalesce((p_data->>'guests')::int,1),next_status,p_data->>'channel',coalesce((p_data->>'total_amount')::numeric,r.nightly_rate*(departure_date-arrival_date)),r.currency,coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
   ids:=ids||jsonb_build_array(v_id);
  end loop;
  return public.lodge_finish(p_lodge,p_action,v_request,v_hash,jsonb_build_object('ids',ids,'group_id',grp));
 elsif p_action in('reservation_update','check_in','check_out','cancel') then
  perform public.lodge_require(p_lodge,'reservations.write');
  select * into b from public.lodge_reservations where id=(p_data->>'id')::uuid and lodge_id=p_lodge for update;
  if not found then raise exception 'Reservation not found'; end if;
  select * into r from public.lodge_rooms where id=b.room_id;
  if p_action='check_in' then
   if b.status<>'confirmed' or today<b.arrival or today>=b.departure or r.condition<>'ready' or not r.active then raise exception 'Check-in requires a confirmed stay today and a ready, active room'; end if;
   update public.lodge_reservations set status='checked_in',checked_in_at=now(),updated_at=now() where id=b.id;
   update public.lodge_rooms set condition='occupied' where id=b.room_id;
  elsif p_action='check_out' then
   if b.status<>'checked_in' then raise exception 'Only checked-in guests can check out'; end if;
   update public.lodge_reservations set status='checked_out',checked_out_at=now(),departure=least(departure,greatest(arrival+1,today)),updated_at=now() where id=b.id;
   update public.lodge_rooms set condition='cleaning' where id=b.room_id;
  elsif p_action='cancel' then
   if b.status not in('pending','confirmed','blocked') or length(trim(coalesce(p_data->>'reason','')))<5 then raise exception 'Cancellation requires a reason and an open reservation'; end if;
   update public.lodge_reservations set status='cancelled',notes=notes||E'\nCancellation: '||(p_data->>'reason'),updated_at=now() where id=b.id;
  else
   if b.status not in('pending','confirmed','blocked') then raise exception 'Only upcoming reservations can be modified'; end if;
   arrival_date:=coalesce((p_data->>'arrival')::date,b.arrival);departure_date:=coalesce((p_data->>'departure')::date,b.departure);next_status:=coalesce(p_data->>'status',b.status);
   if arrival_date<today or next_status not in('pending','confirmed','blocked') or (b.status='blocked')<>(next_status='blocked') then raise exception 'Invalid reservation change'; end if;
   select * into r from public.lodge_rooms where id=coalesce((p_data->>'room_id')::uuid,b.room_id) and lodge_id=p_lodge and active;
   if not found or coalesce((p_data->>'guests')::int,b.guests)>r.max_occupancy or (b.accepted_at is null and r.currency<>b.currency) then raise exception 'Room capacity or currency mismatch'; end if;
   if not l.allow_same_day_turnover and exists(select 1 from public.lodge_reservations where room_id=r.id and id<>b.id and status in('confirmed','checked_in','checked_out','blocked') and (departure=arrival_date or arrival=departure_date)) then raise exception 'Same-day turnover is disabled'; end if;
   if next_status<>'blocked' and not public.lodge_room_bookable(r.id,arrival_date,departure_date,b.id) then raise exception 'Room is unavailable for these dates' using errcode='23P01';end if;
   update public.lodge_reservations set room_id=r.id,arrival=arrival_date,departure=departure_date,guests=coalesce((p_data->>'guests')::int,guests),status=next_status,total_amount=coalesce((p_data->>'total_amount')::numeric,total_amount),notes=coalesce(p_data->>'notes',notes),updated_at=now() where id=b.id;
  end if;v_id:=b.id;
 elsif p_action='record_payment' then
  perform public.lodge_require(p_lodge,'payments.write');
  select * into b from public.lodge_reservations where id=(p_data->>'reservation_id')::uuid and lodge_id=p_lodge;
  if not found or b.status='blocked' then raise exception 'Reservation not found'; end if;
  if coalesce((p_data->>'amount')::numeric,0)<=0 or coalesce(p_data->>'currency',b.currency)<>b.currency then raise exception 'Positive amount in the reservation currency required'; end if;
  insert into public.lodge_payments(lodge_id,reservation_id,amount,currency,method,reference,received_at,recorded_by)
  values(p_lodge,b.id,(p_data->>'amount')::numeric,b.currency,trim(p_data->>'method'),nullif(trim(p_data->>'reference'),''),coalesce((p_data->>'received_at')::timestamptz,now()),auth.uid()) returning id into v_id;
 elsif p_action in('reverse_payment','correct_payment') then
  perform public.lodge_require(p_lodge,'payments.reverse');
  select * into pay from public.lodge_payments where id=(p_data->>'id')::uuid and lodge_id=p_lodge and reverses_id is null;
  if not found then raise exception 'Original payment not found'; end if;
  if p_action='correct_payment' then perform public.lodge_require(p_lodge,'payments.write'); end if;
  insert into public.lodge_payments(lodge_id,reservation_id,amount,currency,method,recorded_by,reverses_id,reason,received_at)
  values(p_lodge,pay.reservation_id,-pay.amount,pay.currency,'reversal',auth.uid(),pay.id,trim(p_data->>'reason'),case when p_action='correct_payment' then pay.received_at else now() end) returning id into v_id;
  if p_action='correct_payment' then
   if coalesce((p_data->>'amount')::numeric,0)<=0 then raise exception 'Positive correction amount required'; end if;
   insert into public.lodge_payments(lodge_id,reservation_id,amount,currency,method,reference,received_at,recorded_by,corrects_id,reason)
   values(p_lodge,pay.reservation_id,(p_data->>'amount')::numeric,pay.currency,trim(p_data->>'method'),case when nullif(trim(p_data->>'reference'),'')=pay.reference then pay.reference||'/C-'||gen_random_uuid()::text else nullif(trim(p_data->>'reference'),'') end,coalesce((p_data->>'received_at')::timestamptz,pay.received_at),auth.uid(),pay.id,trim(p_data->>'reason')) returning id into v_id;
  end if;
 elsif p_action in('invite','set_staff','remove_staff','revoke_invitation','review_access') then
  perform public.lodge_require(p_lodge,'staff.manage');
  if p_action in('invite','set_staff') then
   role_name:=p_data->>'role';
   if role_name not in('manager','receptionist','housekeeping') then raise exception 'Invalid staff role'; end if;
   if role_name='manager' and not(public.is_super_admin(auth.uid()) or l.authorized_owner=auth.uid()) then raise exception 'Only the lodge owner can appoint managers' using errcode='42501'; end if;
   grants:=case when p_data?'permissions' then array(select jsonb_array_elements_text(p_data->'permissions')) else public.lodge_default_permissions(role_name) end;
   foreach me in array grants loop
    if me='*' or not(me=any(public.lodge_default_permissions('manager')) or me='rooms.condition') or not(public.lodge_has_permission(p_lodge,me) or (me='rooms.condition' and public.lodge_has_permission(p_lodge,'rooms.write'))) then raise exception 'Cannot grant this permission' using errcode='42501'; end if;
   end loop;
   if not('rooms.read'=any(grants)) then raise exception 'Staff needs room access to open the workspace'; end if;
   if p_action='invite' then
    if trim(p_data->>'email') !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Valid invitation email required'; end if;
    if exists(select 1 from public.lodge_members m join auth.users u on u.id=m.profile_id where m.lodge_id=p_lodge and lower(u.email)=lower(trim(p_data->>'email')) and (m.role='owner' or (m.role='manager' and l.authorized_owner<>auth.uid() and not public.is_super_admin(auth.uid())))) then raise exception 'Owner approval required to change this member'; end if;
    insert into public.lodge_invitations(lodge_id,email,role,permissions,invited_by) values(p_lodge,lower(trim(p_data->>'email')),role_name,grants,auth.uid()) returning id into v_id;
   else
    v_id:=(p_data->>'profile_id')::uuid;
    if v_id=l.authorized_owner or exists(select 1 from public.lodge_members where lodge_id=p_lodge and profile_id=v_id and role='manager' and l.authorized_owner<>auth.uid() and not public.is_super_admin(auth.uid())) then raise exception 'Owner access cannot be changed by this operation'; end if;
    update public.lodge_members set role=role_name,permissions=grants where lodge_id=p_lodge and profile_id=v_id and active;
    if not found then raise exception 'Active staff member not found'; end if;
   end if;
  elsif p_action='remove_staff' then
   if (p_data->>'profile_id')::uuid=l.authorized_owner then raise exception 'Owner access cannot be removed'; end if;
   if exists(select 1 from public.lodge_members where lodge_id=p_lodge and profile_id=(p_data->>'profile_id')::uuid and role='manager') and not(public.is_super_admin(auth.uid()) or l.authorized_owner=auth.uid()) then raise exception 'Only owner can remove managers'; end if;
   update public.lodge_members set active=false where lodge_id=p_lodge and profile_id=(p_data->>'profile_id')::uuid;
   update public.lodge_invitations set status='revoked' where lodge_id=p_lodge and status='pending' and lower(email)=(select lower(email) from auth.users where id=(p_data->>'profile_id')::uuid);
  elsif p_action='revoke_invitation' then
   update public.lodge_invitations set status='revoked' where id=(p_data->>'id')::uuid and lodge_id=p_lodge;
  else
   if not(public.is_super_admin(auth.uid()) or l.authorized_owner=auth.uid()) then raise exception 'Owner review required'; end if;
   update public.lodge_access_applications set status=case when (p_data->>'approved')::boolean then 'approved' else 'rejected' end,reviewed_by=auth.uid() where id=(p_data->>'id')::uuid and lodge_id=p_lodge and status='pending' returning applicant_id into v_id;
   if not found then raise exception 'Pending application not found'; end if;
   if (p_data->>'approved')::boolean then
    insert into public.lodge_members(lodge_id,profile_id,role,permissions) values(p_lodge,v_id,'manager',public.lodge_default_permissions('manager')) on conflict(lodge_id,profile_id) do update set role='manager',permissions=excluded.permissions,active=true where lodge_members.role<>'owner';
   end if;
  end if;
 elsif p_action='enquiry_status' then
  perform public.lodge_require(p_lodge,'reservations.write');
  update public.lodge_enquiries set status=p_data->>'status' where id=(p_data->>'id')::uuid and lodge_id=p_lodge returning id into v_id;
 else raise exception 'Unknown lodge operation';
 end if;
 return public.lodge_finish(p_lodge,p_action,v_request,v_hash,jsonb_build_object('id',v_id,'ok',true));
end $$;

-- Paginated read API returns only section-specific, permission-scoped data.
create function public.lodge_workspace(p_lodge uuid default null,p_section text default 'dashboard',p_start date default null,p_end date default null,p_offset integer default 0,p_limit integer default 30,p_query text default '',p_room_type text default '')
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare l public.lodges; result jsonb; rows jsonb; n bigint; start_day date; end_day date; perms text[];
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if p_limit not between 1 and 100 or p_offset<0 or length(p_query)>160 or length(p_room_type)>100 then raise exception 'Invalid page'; end if;
 if p_lodge is null then
  return jsonb_build_object('lodges',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'location_label',x.location_label,'verification_status',x.verification_status)) from public.lodges x where public.is_super_admin(auth.uid()) or exists(select 1 from public.lodge_members m where m.lodge_id=x.id and m.profile_id=auth.uid() and m.active)),'[]'),
   'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'lodge_id',i.lodge_id,'name',d.name,'role',i.role)) from public.lodge_invitations i join public.lodges d on d.id=i.lodge_id where i.status='pending' and i.expires_at>now() and lower(i.email)=(select lower(email) from auth.users where id=auth.uid())),'[]'), 'super_admin',public.is_super_admin(auth.uid()));
 end if;
 perform public.lodge_require(p_lodge,'rooms.read'); select * into l from public.lodges where id=p_lodge;
 start_day:=coalesce(p_start,(now() at time zone l.timezone)::date);end_day:=coalesce(p_end,start_day+30);
 if end_day<=start_day or end_day-start_day>730 then raise exception 'Select a date range of 1 to 730 nights'; end if;
 select case when public.is_super_admin(auth.uid()) or l.authorized_owner=auth.uid() then array['*'] else permissions end into perms from public.lodge_members where lodge_id=p_lodge and profile_id=auth.uid();
 if public.is_super_admin(auth.uid()) then perms:=array['*']; end if;
 result:=jsonb_build_object('lodge',to_jsonb(l)-'review_notes','permissions',perms,'super_admin',public.is_super_admin(auth.uid()),'start',start_day,'end',end_day);
 if p_section='room-types' then
  select count(*) into n from public.lodge_room_types where lodge_id=p_lodge;
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into rows from(select t.*,(select count(*) from public.lodge_rooms r where r.room_type_id=t.id and r.active) total_rooms,
  (select count(*) from public.lodge_rooms r where r.room_type_id=t.id and public.lodge_room_bookable(r.id,start_day,end_day)) available_rooms,
  (select count(*) from public.lodge_rooms r where r.room_type_id=t.id and r.active and r.condition='occupied') occupied_rooms,
  (select count(*) from public.lodge_rooms r where r.room_type_id=t.id and public.lodge_room_bookable(r.id,(now() at time zone l.timezone)::date,(now() at time zone l.timezone)::date+1)) ready_now
  from public.lodge_room_types t where lodge_id=p_lodge order by lower(name),id offset p_offset limit p_limit)t;
  result:=result||jsonb_build_object('rows',rows,'total',n);
 elsif p_section in('rooms','calendar') then
  select count(*) into n from public.lodge_rooms where lodge_id=p_lodge and (p_query='' or code ilike '%'||p_query||'%') and (p_room_type='' or room_type ilike '%'||p_room_type||'%');
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into rows from(select * from public.lodge_rooms where lodge_id=p_lodge and (p_query='' or code ilike '%'||p_query||'%') and (p_room_type='' or room_type ilike '%'||p_room_type||'%') order by lower(code),id offset p_offset limit p_limit)t;
  result:=result||jsonb_build_object('rows',rows,'total',n);
  if p_section='calendar' then
   result:=result||jsonb_build_object('stays',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'room_id',b.room_id,'arrival',b.arrival,'departure',b.departure,'status',b.status)) from public.lodge_reservations b where b.lodge_id=p_lodge and b.status in('confirmed','checked_in','checked_out','blocked') and b.stay&&daterange(start_day,end_day,'[)') and b.room_id in(select (x->>'id')::uuid from jsonb_array_elements(rows)x)),'[]'));
  end if;
 elsif p_section='reservations' then
  perform public.lodge_require(p_lodge,'reservations.read');
  select count(*) into n from public.lodge_reservations b join public.lodge_rooms r on r.id=b.room_id left join public.lodge_guests g on g.id=b.guest_id and public.lodge_has_permission(p_lodge,'guests.read') where b.lodge_id=p_lodge and b.stay&&daterange(start_day,end_day,'[)') and (p_query='' or concat_ws(' ',r.code,g.full_name,g.phone) ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(case when public.lodge_has_permission(p_lodge,'guests.read') then to_jsonb(t) else to_jsonb(t)-array['notes','guest_id'] end),'[]') into rows from(select b.*,r.code,r.room_type,g.full_name,g.phone,case when public.lodge_has_permission(p_lodge,'payments.read') then (select coalesce(sum(amount),0) from public.lodge_payments where reservation_id=b.id) else null end paid from public.lodge_reservations b join public.lodge_rooms r on r.id=b.room_id left join public.lodge_guests g on g.id=b.guest_id and public.lodge_has_permission(p_lodge,'guests.read') where b.lodge_id=p_lodge and b.stay&&daterange(start_day,end_day,'[)') and (p_query='' or concat_ws(' ',r.code,g.full_name,g.phone) ilike '%'||p_query||'%') order by b.arrival,b.id offset p_offset limit p_limit)t;
  result:=result||jsonb_build_object('rows',rows,'total',n,'enquiries',coalesce((select jsonb_agg(case when public.lodge_has_permission(p_lodge,'guests.read') then to_jsonb(e) else to_jsonb(e)-array['profile_id','message','contact_phone'] end) from(select * from public.lodge_enquiries where lodge_id=p_lodge and status<>'closed' order by created_at desc offset p_offset limit p_limit)e),'[]'));
 elsif p_section='guests' then
  perform public.lodge_require(p_lodge,'guests.read');
  select count(*) into n from public.lodge_guests where lodge_id=p_lodge and (p_query='' or concat_ws(' ',full_name,phone,email) ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into rows from(select * from public.lodge_guests where lodge_id=p_lodge and (p_query='' or concat_ws(' ',full_name,phone,email) ilike '%'||p_query||'%') order by full_name,id offset p_offset limit p_limit)t;
  result:=result||jsonb_build_object('rows',rows,'total',n);
 elsif p_section='payments' then
  perform public.lodge_require(p_lodge,'payments.read');
  select count(*) into n from public.lodge_payments where lodge_id=p_lodge and (p_query='' or concat_ws(' ',reference,method,reservation_id::text) ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('reversed',exists(select 1 from public.lodge_payments p where p.reverses_id=t.id))),'[]') into rows from(select * from public.lodge_payments where lodge_id=p_lodge and (p_query='' or concat_ws(' ',reference,method,reservation_id::text) ilike '%'||p_query||'%') order by recorded_at desc,id offset p_offset limit p_limit)t;
  result:=result||jsonb_build_object('rows',rows,'total',n);
 elsif p_section='staff' then
  perform public.lodge_require(p_lodge,'staff.read');
  result:=result||jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(t)) from(select m.*,p.full_name from public.lodge_members m join public.profiles p on p.id=m.profile_id where lodge_id=p_lodge)t),'[]'),'invitations',coalesce((select jsonb_agg(to_jsonb(i)) from public.lodge_invitations i where lodge_id=p_lodge and status='pending'),'[]'),'applications',coalesce((select jsonb_agg(to_jsonb(a)) from public.lodge_access_applications a where lodge_id=p_lodge and status='pending'),'[]'));
 elsif p_section='settings' then
  perform public.lodge_require(p_lodge,'settings.read');
 elsif p_section in('dashboard','reports') then
  if p_section='reports' then perform public.lodge_require(p_lodge,'reports.read'); end if;
  result:=result||jsonb_build_object('stats',(select jsonb_build_object('total_rooms',count(*),'ready_rooms',count(*) filter(where active and condition='ready' and not exists(select 1 from public.lodge_reservations b where b.room_id=r.id and b.status in('confirmed','checked_in','blocked') and b.stay @> (now() at time zone l.timezone)::date)),'occupied_rooms',count(*) filter(where condition='occupied'),'cleaning_rooms',count(*) filter(where condition='cleaning'),'maintenance_rooms',count(*) filter(where condition in('maintenance','out_of_service'))) from public.lodge_rooms r where lodge_id=p_lodge));
  if public.lodge_has_permission(p_lodge,'reservations.read') then
   result:=result||jsonb_build_object('arrivals',(select count(*) from public.lodge_reservations where lodge_id=p_lodge and arrival>=start_day and arrival<end_day and status='confirmed'),'departures',(select count(*) from public.lodge_reservations where lodge_id=p_lodge and departure>=start_day and departure<end_day and status in('confirmed','checked_in')),'pending',(select count(*) from public.lodge_reservations where lodge_id=p_lodge and status='pending'));
  end if;
  if public.lodge_has_permission(p_lodge,'reports.read') then
   result:=result||jsonb_build_object('occupied_room_nights',(select coalesce(sum(least(departure,end_day)-greatest(arrival,start_day)),0) from public.lodge_reservations where lodge_id=p_lodge and status in('confirmed','checked_in','checked_out') and stay&&daterange(start_day,end_day,'[)')),'capacity_room_nights',(select coalesce(sum(end_day-greatest(start_day,(created_at at time zone l.timezone)::date)),0) from public.lodge_rooms where lodge_id=p_lodge and (created_at at time zone l.timezone)::date<end_day));
  end if;
  if public.lodge_has_permission(p_lodge,'payments.read') then
   result:=result||jsonb_build_object('revenue',coalesce((select jsonb_agg(to_jsonb(t)) from(select currency,sum(amount) net_recorded from public.lodge_payments where lodge_id=p_lodge and received_at>=start_day::timestamp at time zone l.timezone and received_at<end_day::timestamp at time zone l.timezone group by currency)t),'[]'));
  end if;
 else raise exception 'Unknown workspace page'; end if;
 return result;
end $$;

create function public.public_lodges(p_search text default '',p_location uuid default null,p_id uuid default null,p_offset integer default 0,p_limit integer default 20,p_arrival date default null,p_departure date default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare rows jsonb; n bigint; begin
 if p_limit not between 1 and 100 or p_offset<0 or length(p_search)>160 then raise exception 'Invalid search page'; end if;
 if (p_arrival is null)<>(p_departure is null) or (p_arrival is not null and (p_departure<=p_arrival or p_departure-p_arrival>730)) then raise exception 'Choose valid arrival and departure dates'; end if;
 select count(*) into n from public.lodges l where published and verification_status='verified' and (p_id is null or l.id=p_id) and (coalesce(trim(p_search),'')='' or public.marketplace_matches_search(l.name||' '||l.location_label||' '||l.description||' '||array_to_string(l.facilities,' ')||' lodge lodges guesthouse guesthouses malazi nyumba za wageni',p_search)) and (p_location is null or l.location_id in(with recursive loc as(select id from public.locations where id=p_location union select x.id from public.locations x join loc on x.parent_id=loc.id) select id from loc));
 select coalesce(jsonb_agg(to_jsonb(t)),'[]') into rows from(select l.id,l.name,l.location_id,l.location_label,l.description,l.facilities,l.photos,case when not public.contact_payments_enabled() then l.phone end phone,case when not public.contact_payments_enabled() then l.email end email,l.timezone,l.publish_availability,l.verification_status,
 (select coalesce(jsonb_agg(to_jsonb(rt)),'[]') from(select t.id,t.name room_type,t.description,t.main_image,t.facilities,t.currency,t.nightly_rate from_price,t.max_occupancy,t.beds,
 (select count(*) from public.lodge_rooms r where r.room_type_id=t.id and r.active) total_rooms,
 case when l.publish_availability and p_arrival is not null then (select count(*) from public.lodge_rooms r where r.room_type_id=t.id and public.lodge_room_bookable(r.id,p_arrival,p_departure)) else null end available_rooms
 from public.lodge_room_types t where t.lodge_id=l.id and t.active order by t.nightly_rate,t.name) rt) room_types,
 l.check_in_policy,l.check_out_policy,
 (select jsonb_build_object('selected_dates_available',case when l.publish_availability and p_arrival is not null then count(*) filter(where public.lodge_room_bookable(r.id,p_arrival,p_departure)) else null end,'total_active',count(*) filter(where active),'occupied',count(*) filter(where active and condition='occupied'),'cleaning',count(*) filter(where active and condition='cleaning'),'maintenance',count(*) filter(where active and condition in('maintenance','out_of_service')),'ready_now',count(*) filter(where public.lodge_room_bookable(r.id,(now() at time zone l.timezone)::date,(now() at time zone l.timezone)::date+1))) from public.lodge_rooms r where r.lodge_id=l.id) room_counts
 from public.lodges l where published and verification_status='verified' and (p_id is null or l.id=p_id) and (coalesce(trim(p_search),'')='' or public.marketplace_matches_search(l.name||' '||l.location_label||' '||l.description||' '||array_to_string(l.facilities,' ')||' lodge lodges guesthouse guesthouses malazi nyumba za wageni',p_search)) and (p_location is null or l.location_id in(with recursive loc as(select id from public.locations where id=p_location union select x.id from public.locations x join loc on x.parent_id=loc.id) select id from loc)) order by lower(l.name),l.id offset p_offset limit p_limit)t;
 return jsonb_build_object('rows',rows,'total',n,'availability_checked_at',case when p_arrival is not null then now() else null end);
end $$;
create function public.lodge_enquire(p_lodge uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; l public.lodges; t public.lodge_room_types; quote jsonb; begin
 if auth.uid() is null then raise exception 'Sign in to send a reservation enquiry' using errcode='42501'; end if;
 select * into l from public.lodges where id=p_lodge and published and verification_status='verified';
 if not found then raise exception 'Lodge is unavailable'; end if;
 if (p_data->>'arrival')::date<(now() at time zone l.timezone)::date then raise exception 'Arrival cannot be in the past'; end if;
 if (select count(*) from public.lodge_enquiries where profile_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then raise exception 'Please wait before sending more enquiries'; end if;
 select * into t from public.lodge_room_types where id=(p_data->>'room_type_id')::uuid and lodge_id=p_lodge and active;
 if not found or (p_data->>'guests')::int>t.max_occupancy then raise exception 'Choose an available room type and valid guest count';end if;
 if not exists(select 1 from public.lodge_rooms r where r.room_type_id=t.id and public.lodge_room_bookable(r.id,(p_data->>'arrival')::date,(p_data->>'departure')::date)) then raise exception 'No eligible room is available for these dates' using errcode='23P01';end if;
 quote:=jsonb_build_object('room_type_id',t.id,'room_type',t.name,'description',t.description,'facilities',t.facilities,'beds',t.beds,'max_occupancy',t.max_occupancy,'nightly_rate',t.nightly_rate,'currency',t.currency,'total_amount',t.nightly_rate*((p_data->>'departure')::date-(p_data->>'arrival')::date),'arrival',p_data->>'arrival','departure',p_data->>'departure','check_in_policy',l.check_in_policy,'check_out_policy',l.check_out_policy);
 insert into public.lodge_enquiries(lodge_id,profile_id,room_type_id,quoted_terms,arrival,departure,guests,message,contact_phone) values(p_lodge,auth.uid(),t.id,quote,(p_data->>'arrival')::date,(p_data->>'departure')::date,(p_data->>'guests')::int,trim(p_data->>'message'),trim(p_data->>'contact_phone')) returning id into v_id;
 return v_id;
end $$;

-- Customer confirmation/status is private to the requesting account.
create function public.lodge_my_requests(p_lodge uuid) returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'arrival',e.arrival,'departure',e.departure,'room_type',e.quoted_terms->>'room_type','terms',e.quoted_terms,'status',case when e.reservation_id is not null then b.status else e.status end,'confirmed',e.reservation_id is not null) order by e.created_at desc),'[]')
 from public.lodge_enquiries e left join public.lodge_reservations b on b.id=e.reservation_id where e.lodge_id=p_lodge and e.profile_id=auth.uid();
$$;
-- Reuse the existing durable notification/outbox pipeline. No guest details in push bodies.
create function public.lodge_notify_request() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_op='INSERT' then
  insert into public.notifications(user_id,type,title,body,payload)
  select m.profile_id,'announcement','Lodge reservation request','A new accommodation request is ready for review.',jsonb_build_object('eventType','lodge_request','lodgeId',new.lodge_id,'route','lodges/'||new.lodge_id||'/reservations')
  from public.lodge_members m where m.lodge_id=new.lodge_id and m.active and (m.role='owner' or 'reservations.read'=any(m.permissions));
 elsif old.reservation_id is null and new.reservation_id is not null then
  insert into public.notifications(user_id,type,title,body,payload)values(new.profile_id,'announcement','Reservation confirmed','The lodge has confirmed your accommodation request. Open KODIMALI to review the agreed details.',jsonb_build_object('eventType','lodge_confirmation','lodgeId',new.lodge_id,'route','lodges/'||new.lodge_id));
 elsif new.status='closed' and old.status<>'closed' and new.reservation_id is null then
  insert into public.notifications(user_id,type,title,body,payload)values(new.profile_id,'announcement','Accommodation request updated','The lodge has closed your request. Open KODIMALI to review its status.',jsonb_build_object('eventType','lodge_request_closed','lodgeId',new.lodge_id,'route','lodges/'||new.lodge_id));
 end if;return new;
end $$;
create trigger lodge_notify_request after insert or update on public.lodge_enquiries for each row execute function public.lodge_notify_request();
create function public.lodge_notify_reservation() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.status='cancelled' and old.status<>new.status then
  insert into public.notifications(user_id,type,title,body,payload)select e.profile_id,'announcement','Reservation cancelled','The lodge cancelled your accommodation reservation. Open KODIMALI to review its status.',jsonb_build_object('eventType','lodge_cancellation','lodgeId',new.lodge_id,'route','lodges/'||new.lodge_id) from public.lodge_enquiries e where e.reservation_id=new.id;
 end if;return new;
end $$;
create trigger lodge_notify_reservation after update on public.lodge_reservations for each row execute function public.lodge_notify_reservation();
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('lodge-media','lodge-media',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy lodge_media_read on storage.objects for select to anon,authenticated using(bucket_id='lodge-media' and exists(select 1 from public.lodges l where l.id::text=(storage.foldername(name))[1] and ((l.published and l.verification_status='verified') or public.lodge_has_permission(l.id,'rooms.read'))));
-- Policy helper avoids a public SELECT grant on operational lodge records.
create function public.lodge_media_visible(p_path text) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.lodges l where l.id::text=split_part(p_path,'/',1) and ((l.published and l.verification_status='verified') or public.lodge_has_permission(l.id,'rooms.read')));
$$;
drop policy lodge_media_read on storage.objects;
create policy lodge_media_read on storage.objects for select to anon,authenticated using(bucket_id='lodge-media' and public.lodge_media_visible(name));
create policy lodge_media_insert on storage.objects for insert to authenticated with check(bucket_id='lodge-media' and exists(select 1 from public.lodges l where l.id::text=(storage.foldername(name))[1] and public.lodge_has_permission(l.id,'rooms.write')));
-- Immutable object names avoid stale caches and accidental loss of linked photos.

do $$ declare r record; begin
 for r in select p.oid::regprocedure sig,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'lodge_%' or p.proname='public_lodges') loop
 execute format('revoke all on function %s from public,anon,authenticated',r.sig);
 if r.proname in('lodge_register','lodge_command','lodge_workspace','lodge_enquire','lodge_my_requests','lodge_has_permission') then execute format('grant execute on function %s to authenticated',r.sig); end if;
 if r.proname in('public_lodges','lodge_media_visible') then execute format('grant execute on function %s to anon,authenticated',r.sig); end if;
 end loop;
end $$;
commit;
