-- Safe public interfaces required by the production website.

create table if not exists public.platform_promotion_events (
  id bigint generated always as identity primary key,
  promotion_id uuid not null references public.platform_promotions(id) on delete cascade,
  event_type text not null check (event_type in ('impression','click')),
  surface text not null default 'website',
  session_key text not null,
  created_at timestamptz not null default timezone('utc',now())
);
create index if not exists idx_platform_promotion_events_campaign
  on public.platform_promotion_events(promotion_id,event_type,created_at desc);
create unique index if not exists idx_platform_promotion_events_unique_impression
  on public.platform_promotion_events(promotion_id,event_type,session_key)
  where event_type='impression';
alter table public.platform_promotion_events enable row level security;
create policy platform_promotion_events_admin_read on public.platform_promotion_events
  for select to authenticated using(public.is_admin());

create or replace function public.record_platform_promotion_event(
  p_promotion_id uuid,p_event_type text,p_surface text,p_session_key text
) returns boolean language plpgsql security definer set search_path=public as $$
begin
 if p_event_type not in ('impression','click') or length(trim(p_session_key))<8 then return false; end if;
 if not exists(select 1 from public.platform_promotions where id=p_promotion_id and is_active and coalesce(start_at,now())<=now() and coalesce(end_at,now()+interval '100 years')>=now()) then return false; end if;
 insert into public.platform_promotion_events(promotion_id,event_type,surface,session_key)
 values(p_promotion_id,p_event_type,left(coalesce(nullif(trim(p_surface),''),'website'),40),left(trim(p_session_key),120))
 on conflict do nothing;
 return true;
end $$;
grant execute on function public.record_platform_promotion_event(uuid,text,text,text) to anon,authenticated,service_role;

create or replace function public.get_public_agent_profile(p_agent_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
 select case when a.id is null then null else jsonb_build_object(
  'id',a.id,'display_name',a.display_name,'business_name',a.business_name,
  'location_label',l.name,'profile_photo_path',a.profile_photo_path,
  'created_at',a.created_at,'trust',public.agent_trust_summary(a.id),
  'active_listing_count',(select count(*) from public.listings x where x.agent_id=a.id and public.is_listing_public(x.id))
 ) end
 from (select * from public.agents where id=p_agent_id and account_status='active' and verification_status='approved') a
 left join public.locations l on l.id=a.location_id
$$;
grant execute on function public.get_public_agent_profile(uuid) to anon,authenticated,service_role;

create or replace function public.get_platform_promotion_performance(p_days integer default 30)
returns table(promotion_id uuid,title text,impressions bigint,clicks bigint,click_through_rate numeric)
language sql stable security definer set search_path=public as $$
 select p.id as promotion_id,p.title::text as title,
 (count(e.id) filter(where e.event_type='impression'))::bigint as impressions,
 (count(e.id) filter(where e.event_type='click'))::bigint as clicks,
 (case when count(e.id) filter(where e.event_type='impression')=0 then 0::numeric else round((100.0::numeric*count(e.id) filter(where e.event_type='click'))/(count(e.id) filter(where e.event_type='impression'))::numeric,2) end)::numeric as click_through_rate
 from public.platform_promotions p left join public.platform_promotion_events e on e.promotion_id=p.id and e.created_at>now()-make_interval(days=>greatest(1,p_days))
 where public.is_admin() group by p.id,p.title order by (count(e.id) filter(where e.event_type='impression')) desc
$$;
grant execute on function public.get_platform_promotion_performance(integer) to authenticated,service_role;
