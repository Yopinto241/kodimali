-- Entered owner contacts are private records, not verified owner accounts.
create policy agents_self_read on public.agents for select to authenticated using(profile_id=auth.uid());
create or replace function public.save_agent_listing_owner(
 p_listing_id uuid,p_full_name text default null,p_phone_number text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare l public.listings; v_owner_id uuid; n text:=nullif(trim(p_full_name),''); ph text:=nullif(trim(p_phone_number),'');
begin
 select * into l from public.listings where id=p_listing_id for update;
 if l.id is null then raise exception 'Listing not found'; end if;
 if auth.uid() is null or not (public.has_admin_permission('listings.manage') or
   (l.agent_id=public.current_agent_id() and public.is_agent_active())) then
   raise exception 'Listing agent permission required' using errcode='42501';
 end if;
 if n is null and ph is null and nullif(trim(p_notes),'') is null then
   if l.owner_id is not null then update public.listings set owner_id=null where id=l.id; end if;
   return null;
 end if;
 if n is null or ph is null then raise exception 'Provide both owner name and phone, or leave owner details empty'; end if;
 if exists(select 1 from public.owners o where o.id=l.owner_id and o.full_name=n and o.phone_number=ph and coalesce(o.notes,'')=coalesce(trim(p_notes),'')) then return l.owner_id; end if;
 -- A new contact record avoids changing another listing's shared owner contact.
 insert into public.owners(agent_id,full_name,phone_number,location_id,notes)
 values(l.agent_id,n,ph,l.location_id,nullif(trim(p_notes),'')) returning id into v_owner_id;
 update public.listings set owner_id=v_owner_id where id=l.id;
 return v_owner_id;
end $$;
revoke all on function public.save_agent_listing_owner(uuid,text,text,text) from public,anon;
grant execute on function public.save_agent_listing_owner(uuid,text,text,text) to authenticated;

create or replace function public.manage_save_listing_with_owner(p_listing_id uuid,p_values jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
 perform public.save_agent_listing_owner(p_listing_id,p_values#>>'{private_owner,name}',p_values#>>'{private_owner,phone}',p_values#>>'{private_owner,notes}');
 perform public.manage_update_listing_basic(p_listing_id,p_values-'private_owner');
 update public.listings set
 price_period=case when p_values ? 'price_period' then (p_values->>'price_period')::public.price_period else price_period end,
 deposit_required_amount=case when p_values ? 'deposit_required_amount' then (p_values->>'deposit_required_amount')::numeric else deposit_required_amount end,
 listing_rules=case when p_values ? 'listing_rules' then p_values->>'listing_rules' else listing_rules end
 where id=p_listing_id;
end $$;
revoke all on function public.manage_save_listing_with_owner(uuid,jsonb) from public,anon;
grant execute on function public.manage_save_listing_with_owner(uuid,jsonb) to authenticated;

create or replace function public.create_agent_listing_draft(
 p_category_id uuid,p_location_id uuid,p_title text,p_description text,p_price_amount numeric,
 p_price_period public.price_period,p_attributes jsonb default '{}'::jsonb,
 p_owner_name text default null,p_owner_phone text default null,p_owner_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare a uuid:=public.current_agent_id(); listing_id uuid;
begin
 if a is null or not public.is_agent_active() then raise exception 'Active agent access required' using errcode='42501'; end if;
 if not public.agent_has_service_category(a,p_category_id) then raise exception 'Choose an assigned category'; end if;
 insert into public.listings(agent_id,category_id,location_id,title,description,price_amount,price_period,listing_attributes,status)
 values(a,p_category_id,p_location_id,trim(p_title),trim(p_description),p_price_amount,p_price_period,p_attributes,'draft')
 returning id into listing_id;
 if nullif(trim(p_owner_name),'') is not null or nullif(trim(p_owner_phone),'') is not null or nullif(trim(p_owner_notes),'') is not null then
   perform public.save_agent_listing_owner(listing_id,p_owner_name,p_owner_phone,p_owner_notes);
 end if;
 return listing_id;
end $$;
revoke all on function public.create_agent_listing_draft(uuid,uuid,text,text,numeric,public.price_period,jsonb,text,text,text) from public,anon;
grant execute on function public.create_agent_listing_draft(uuid,uuid,text,text,numeric,public.price_period,jsonb,text,text,text) to authenticated;

create or replace function public.get_assignable_verified_agents()
returns table(id uuid,display_name text,business_name text,public_location_label text)
language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null or not (public.current_owner_id() is not null or public.is_information_admin()
   or public.has_admin_permission('agents.manage')) then
   raise exception 'Owner or staff assignment access required' using errcode='42501';
 end if;
 return query select a.id,a.display_name,a.business_name,a.public_location_label from public.agents a
 where a.verification_status='approved' and a.account_status='active'
 order by coalesce(a.business_name,a.display_name),a.id;
end $$;
revoke all on function public.get_assignable_verified_agents() from public,anon;
grant execute on function public.get_assignable_verified_agents() to authenticated;

create table public.owner_agent_recommendations(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.owner_profiles(id),
 suggested_name text not null check(length(trim(suggested_name)) between 2 and 180),
 suggested_phone text not null check(length(trim(suggested_phone)) between 8 and 40),
 notes text,status text not null default 'submitted' check(status in ('submitted','contacting','accepted','rejected')),
 registered_agent_id uuid references public.agents(id),review_notes text,reviewed_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.owner_agent_recommendations enable row level security;
revoke all on public.owner_agent_recommendations from public,anon,authenticated;
grant select on public.owner_agent_recommendations to authenticated;
grant all on public.owner_agent_recommendations to service_role;
create policy recommendations_read on public.owner_agent_recommendations for select to authenticated
 using(owner_id=public.current_owner_id() or public.has_admin_permission('agents.manage'));
create unique index owner_agent_recommendation_pending_idx on public.owner_agent_recommendations(owner_id,suggested_phone) where status in ('submitted','contacting');
create or replace function public.recommend_owner_agent(p_name text,p_phone text,p_notes text default null)
returns public.owner_agent_recommendations language plpgsql security definer set search_path=public as $$
declare oid uuid:=public.current_owner_id(); r public.owner_agent_recommendations;
begin
 if oid is null then raise exception 'Verified owner access required' using errcode='42501'; end if;
 select * into r from public.owner_agent_recommendations where owner_id=oid and suggested_phone=trim(p_phone) and status in ('submitted','contacting');
 if found then return r; end if;
 insert into public.owner_agent_recommendations(owner_id,suggested_name,suggested_phone,notes)
 values(oid,trim(p_name),trim(p_phone),nullif(trim(p_notes),''))
 on conflict(owner_id,suggested_phone) where status in ('submitted','contacting')
 do update set updated_at=public.owner_agent_recommendations.updated_at returning * into r;
 return r;
end $$;
create or replace function public.review_owner_agent_recommendation(p_id uuid,p_status text,p_agent_id uuid default null,p_notes text default null)
returns public.owner_agent_recommendations language plpgsql security definer set search_path=public as $$
declare r public.owner_agent_recommendations;
begin
 if not public.has_admin_permission('agents.manage') then raise exception 'Agent management permission required' using errcode='42501'; end if;
 if p_status not in ('contacting','accepted','rejected') then raise exception 'Unsupported review status'; end if;
 if p_status='accepted' and not exists(select 1 from public.agents where id=p_agent_id and verification_status='approved' and account_status='active') then
   raise exception 'Link an active verified agent before accepting';
 end if;
 update public.owner_agent_recommendations set status=p_status,registered_agent_id=p_agent_id,review_notes=nullif(trim(p_notes),''),reviewed_by=auth.uid(),updated_at=now()
 where id=p_id returning * into r;
 if r.id is null then raise exception 'Recommendation not found'; end if;
 insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
 values(auth.uid(),'owner_agent_recommendation_reviewed','owner_agent_recommendations',r.id,jsonb_build_object('status',p_status,'agent_id',p_agent_id));
 return r;
end $$;
revoke all on function public.recommend_owner_agent(text,text,text),public.review_owner_agent_recommendation(uuid,text,uuid,text) from public,anon;
grant execute on function public.recommend_owner_agent(text,text,text),public.review_owner_agent_recommendation(uuid,text,uuid,text) to authenticated;
