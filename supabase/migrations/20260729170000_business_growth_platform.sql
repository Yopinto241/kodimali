-- KODIMALI business-growth foundation. All objects are additive and retain
-- compatibility with existing listing, chat, booking and payment workflows.

create table if not exists public.business_events (
  id bigint generated always as identity primary key,
  event_type text not null,
  user_id uuid references public.profiles(id) on delete set null,
  agent_id uuid references public.agents(id) on delete set null,
  listing_id uuid references public.listings(id) on delete set null,
  category_id uuid references public.asset_categories(id) on delete set null,
  location_id uuid references public.locations(id) on delete set null,
  amount_tzs numeric(14,2),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc',now())
);
create index if not exists idx_business_events_type_created on public.business_events(event_type,created_at desc);
create index if not exists idx_business_events_agent_created on public.business_events(agent_id,created_at desc);
alter table public.business_events enable row level security;
create policy business_events_admin_select on public.business_events for select to authenticated using(public.is_admin());

create table if not exists public.agent_subscription_plans (
  id text primary key,
  name text not null,
  monthly_price_tzs integer not null check(monthly_price_tzs>=0),
  listing_limit integer,
  publication_fee_tzs integer not null default 1000 check(publication_fee_tzs>=0),
  priority_weight integer not null default 0,
  staff_limit integer not null default 1,
  analytics_enabled boolean not null default false,
  verification_badge boolean not null default false,
  is_active boolean not null default true,
  features jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc',now()),
  updated_at timestamptz not null default timezone('utc',now())
);
insert into public.agent_subscription_plans(id,name,monthly_price_tzs,listing_limit,publication_fee_tzs,priority_weight,staff_limit,analytics_enabled,verification_badge,features) values
 ('free','Free',0,3,1000,0,1,false,false,'["3 active listings"]'),
 ('basic','Basic',15000,15,500,10,1,true,false,'["15 listings","Reduced publication fee","Basic analytics"]'),
 ('pro','Pro',35000,null,0,30,2,true,true,'["Unlimited listings","Priority placement","Trust badge","Analytics"]'),
 ('business','Business',75000,null,0,60,10,true,true,'["Team access","Advanced reporting","Highest priority"]')
on conflict(id) do update set name=excluded.name,monthly_price_tzs=excluded.monthly_price_tzs,listing_limit=excluded.listing_limit,publication_fee_tzs=excluded.publication_fee_tzs,priority_weight=excluded.priority_weight,staff_limit=excluded.staff_limit,analytics_enabled=excluded.analytics_enabled,verification_badge=excluded.verification_badge,features=excluded.features;
alter table public.agent_subscription_plans enable row level security;
create policy subscription_plans_read on public.agent_subscription_plans for select using(is_active or public.is_admin());
create policy subscription_plans_admin_write on public.agent_subscription_plans for all to authenticated using(public.is_admin()) with check(public.is_admin());

create table if not exists public.agent_subscriptions (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agents(id) on delete cascade,
  plan_id text not null references public.agent_subscription_plans(id),
  status text not null default 'active' check(status in ('pending','active','past_due','cancelled','expired')),
  starts_at timestamptz not null default timezone('utc',now()),
  expires_at timestamptz,
  auto_renew boolean not null default false,
  created_at timestamptz not null default timezone('utc',now()),
  updated_at timestamptz not null default timezone('utc',now())
);
create unique index if not exists idx_agent_one_active_subscription on public.agent_subscriptions(agent_id) where status='active';
alter table public.agent_subscriptions enable row level security;
create policy agent_subscriptions_read on public.agent_subscriptions for select to authenticated using(public.is_admin() or agent_id=public.current_agent_id());
create policy agent_subscriptions_admin on public.agent_subscriptions for all to authenticated using(public.is_admin()) with check(public.is_admin());

create table if not exists public.listing_boosts (
  id uuid primary key default gen_random_uuid(), listing_id uuid not null references public.listings(id) on delete cascade,
  agent_id uuid not null references public.agents(id) on delete cascade,
  placement text not null check(placement in ('search_top','featured','homepage','regional','category')),
  duration_days integer not null check(duration_days in (3,7,30)),
  amount_tzs integer not null check(amount_tzs>=0), status text not null default 'pending' check(status in ('pending','active','expired','cancelled','failed')),
  target_category_id uuid references public.asset_categories(id), target_location_id uuid references public.locations(id),
  starts_at timestamptz, ends_at timestamptz, created_at timestamptz not null default timezone('utc',now()), updated_at timestamptz not null default timezone('utc',now())
);
alter table public.listing_boosts enable row level security;
create policy listing_boosts_owner_read on public.listing_boosts for select to authenticated using(public.is_admin() or agent_id=public.current_agent_id());
create policy listing_boosts_owner_insert on public.listing_boosts for insert to authenticated with check(agent_id=public.current_agent_id());
create policy listing_boosts_admin_update on public.listing_boosts for update to authenticated using(public.is_admin()) with check(public.is_admin());

create table if not exists public.saved_searches (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 name text not null, filters jsonb not null default '{}'::jsonb, alerts_enabled boolean not null default true,
 last_notified_at timestamptz, created_at timestamptz not null default timezone('utc',now()), updated_at timestamptz not null default timezone('utc',now())
);
alter table public.saved_searches enable row level security;
create policy saved_searches_self on public.saved_searches for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create table if not exists public.price_alerts (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 listing_id uuid not null references public.listings(id) on delete cascade, target_price numeric(14,2),
 last_seen_price numeric(14,2), is_active boolean not null default true,
 created_at timestamptz not null default timezone('utc',now()), updated_at timestamptz not null default timezone('utc',now()), unique(user_id,listing_id)
);
alter table public.price_alerts enable row level security;
create policy price_alerts_self on public.price_alerts for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create table if not exists public.listing_comparisons (
 user_id uuid not null references public.profiles(id) on delete cascade,
 listing_id uuid not null references public.listings(id) on delete cascade,
 created_at timestamptz not null default timezone('utc',now()), primary key(user_id,listing_id)
);
alter table public.listing_comparisons enable row level security;
create policy comparisons_self on public.listing_comparisons for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create table if not exists public.agent_lead_notes (
 id uuid primary key default gen_random_uuid(), booking_request_id uuid not null references public.booking_requests(id) on delete cascade,
 agent_id uuid not null references public.agents(id) on delete cascade, stage text not null default 'new' check(stage in ('new','contacted','viewing_scheduled','negotiating','completed','lost')),
 note text, follow_up_at timestamptz, transaction_value_tzs numeric(14,2),
 created_at timestamptz not null default timezone('utc',now()), updated_at timestamptz not null default timezone('utc',now()), unique(booking_request_id)
);
alter table public.agent_lead_notes enable row level security;
create policy lead_notes_owner on public.agent_lead_notes for all to authenticated using(public.is_admin() or agent_id=public.current_agent_id()) with check(public.is_admin() or agent_id=public.current_agent_id());

create table if not exists public.agent_wallets (
 agent_id uuid primary key references public.agents(id) on delete cascade,
 available_balance_tzs numeric(14,2) not null default 0, promotional_credits_tzs numeric(14,2) not null default 0,
 lifetime_revenue_tzs numeric(14,2) not null default 0, updated_at timestamptz not null default timezone('utc',now())
);
alter table public.agent_wallets enable row level security;
create policy wallets_owner_read on public.agent_wallets for select to authenticated using(public.is_admin() or agent_id=public.current_agent_id());
create policy wallets_admin_write on public.agent_wallets for all to authenticated using(public.is_admin()) with check(public.is_admin());

create table if not exists public.payment_receipts (
 id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id), agent_id uuid references public.agents(id),
 payment_kind text not null, source_payment_id uuid not null, receipt_number text not null unique,
 amount_tzs numeric(14,2) not null, status text not null, issued_at timestamptz not null default timezone('utc',now()), metadata jsonb not null default '{}'::jsonb
);
alter table public.payment_receipts enable row level security;
create policy receipts_owner_read on public.payment_receipts for select to authenticated using(public.is_admin() or user_id=auth.uid() or agent_id=public.current_agent_id());

create table if not exists public.notification_preferences (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 chat_enabled boolean not null default true, requests_enabled boolean not null default true,
 payments_enabled boolean not null default true, reminders_enabled boolean not null default true,
 promotions_enabled boolean not null default true, quiet_hours_start time, quiet_hours_end time,
 updated_at timestamptz not null default timezone('utc',now())
);
alter table public.notification_preferences enable row level security;
create policy notification_preferences_self on public.notification_preferences for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create table if not exists public.platform_risk_flags (
 id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null,
 risk_type text not null, severity text not null default 'medium' check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','reviewing','resolved','dismissed')),
 reason text not null, evidence jsonb not null default '{}'::jsonb, assigned_to uuid references public.profiles(id),
 created_at timestamptz not null default timezone('utc',now()), resolved_at timestamptz
);
alter table public.platform_risk_flags enable row level security;
create policy risk_flags_admin on public.platform_risk_flags for all to authenticated using(public.is_admin()) with check(public.is_admin());

create table if not exists public.payment_refunds (
 id uuid primary key default gen_random_uuid(), payment_kind text not null, source_payment_id uuid not null,
 requested_by uuid references public.profiles(id), amount_tzs numeric(14,2) not null,
 reason text not null, status text not null default 'requested' check(status in ('requested','approved','rejected','processing','refunded','failed')),
 reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, created_at timestamptz not null default timezone('utc',now())
);
alter table public.payment_refunds enable row level security;
create policy refunds_requester_read on public.payment_refunds for select to authenticated using(public.is_admin() or requested_by=auth.uid());
create policy refunds_requester_insert on public.payment_refunds for insert to authenticated with check(requested_by=auth.uid());
create policy refunds_admin_update on public.payment_refunds for update to authenticated using(public.is_admin()) with check(public.is_admin());

create or replace function public.track_business_event(p_event_type text,p_listing_id uuid default null,p_amount_tzs numeric default null,p_metadata jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_id bigint; v_agent uuid; v_category uuid; v_location uuid;
begin
 if p_listing_id is not null then select agent_id,category_id,location_id into v_agent,v_category,v_location from public.listings where id=p_listing_id; end if;
 insert into public.business_events(event_type,user_id,agent_id,listing_id,category_id,location_id,amount_tzs,metadata)
 values(left(trim(p_event_type),80),auth.uid(),v_agent,p_listing_id,v_category,v_location,p_amount_tzs,coalesce(p_metadata,'{}')) returning id into v_id;
 return v_id;
end $$;
grant execute on function public.track_business_event(text,uuid,numeric,jsonb) to anon,authenticated,service_role;

create or replace function public.get_admin_business_analytics(p_days integer default 30)
returns jsonb language sql stable security definer set search_path=public as $$
 select case when public.is_admin() then jsonb_build_object(
  'active_customers',(select count(distinct p.id) from public.profiles p where exists(select 1 from public.booking_requests b where b.customer_id=p.id and b.created_at>now()-make_interval(days=>p_days))),
  'active_agents',(select count(*) from public.agents where account_status='active'),
  'live_listings',(select count(*) from public.listings where status='active'),
  'listing_views',(select count(*) from public.business_events where event_type='listing_view' and created_at>now()-make_interval(days=>p_days)),
  'contact_unlocks',(select count(*) from public.listing_contact_payments where payment_status='paid' and created_at>now()-make_interval(days=>p_days)),
  'chat_conversions',(select count(*) from public.listing_chat_access where created_at>now()-make_interval(days=>p_days)),
  'payments_paid',(select count(*) from public.listing_contact_payments where payment_status='paid' and created_at>now()-make_interval(days=>p_days))+(select count(*) from public.listing_chat_payments where payment_status='paid' and created_at>now()-make_interval(days=>p_days))+(select count(*) from public.agent_listing_payments where payment_status='paid' and created_at>now()-make_interval(days=>p_days)),
  'payments_failed',(select count(*) from public.listing_contact_payments where payment_status='failed' and created_at>now()-make_interval(days=>p_days))+(select count(*) from public.listing_chat_payments where payment_status='failed' and created_at>now()-make_interval(days=>p_days))+(select count(*) from public.agent_listing_payments where payment_status='failed' and created_at>now()-make_interval(days=>p_days)),
  'revenue_tzs',coalesce((select sum(requested_amount) from public.listing_contact_payments where payment_status='paid' and created_at>now()-make_interval(days=>p_days)),0)+coalesce((select sum(requested_amount) from public.listing_chat_payments where payment_status='paid' and created_at>now()-make_interval(days=>p_days)),0)+coalesce((select sum(requested_amount) from public.agent_listing_payments where payment_status='paid' and created_at>now()-make_interval(days=>p_days)),0),
  'notification_pending',(select count(*) from public.notification_delivery_outbox where status in ('pending','failed')),
  'open_risk_flags',(select count(*) from public.platform_risk_flags where status in ('open','reviewing')),
  'average_response_minutes',(select round(avg(extract(epoch from(first_agent_response_at-created_at))/60)::numeric,1) from public.booking_requests where first_agent_response_at is not null and created_at>now()-make_interval(days=>p_days))
 ) else '{}'::jsonb end
$$;
grant execute on function public.get_admin_business_analytics(integer) to authenticated;

create or replace function public.get_my_agent_business_dashboard()
returns jsonb language sql stable security definer set search_path=public as $$
 with a as(select public.current_agent_id() id), plan as(
  select s.plan_id,p.name,p.listing_limit,p.publication_fee_tzs,p.analytics_enabled,p.priority_weight,s.expires_at
  from public.agent_subscriptions s join public.agent_subscription_plans p on p.id=s.plan_id,a where s.agent_id=a.id and s.status='active' and (s.expires_at is null or s.expires_at>now()) limit 1
 ), perf as(
  select count(*) filter(where b.booking_status='completed') completed,
   count(*) filter(where b.booking_status in ('cancelled','rejected','no_response')) lost,
   round(avg(extract(epoch from(b.first_agent_response_at-b.created_at))/60)::numeric,1) response_minutes
  from public.booking_requests b,a where b.agent_id=a.id
 ), ratings as(select round(avg(r.rating)::numeric,2) rating,count(*) reviews from public.reviews r join public.booking_requests b on b.id=r.booking_request_id,a where b.agent_id=a.id)
 select jsonb_build_object('plan',coalesce((select to_jsonb(plan) from plan),jsonb_build_object('plan_id','free','name','Free','listing_limit',3,'publication_fee_tzs',1000,'analytics_enabled',false,'priority_weight',0)),
 'active_listings',(select count(*) from public.listings l,a where l.agent_id=a.id and l.status='active'),
 'leads',(select count(*) from public.booking_requests b,a where b.agent_id=a.id),
 'performance',(select to_jsonb(perf) from perf),'ratings',(select to_jsonb(ratings) from ratings),
 'wallet',coalesce((select to_jsonb(w) from public.agent_wallets w,a where w.agent_id=a.id),jsonb_build_object('available_balance_tzs',0,'promotional_credits_tzs',0,'lifetime_revenue_tzs',0)),
 'follow_ups',(select count(*) from public.agent_lead_notes n,a where n.agent_id=a.id and n.follow_up_at between now() and now()+interval '7 days'))
$$;
grant execute on function public.get_my_agent_business_dashboard() to authenticated;

create or replace function public.get_recommended_listing_ids(p_limit integer default 20)
returns table(listing_id uuid,score numeric) language sql stable security definer set search_path=public as $$
 select l.id,
  (case when exists(select 1 from public.listing_boosts b where b.listing_id=l.id and b.status='active' and b.ends_at>now()) then 100 else 0 end
   + coalesce((select p.priority_weight from public.agent_subscriptions s join public.agent_subscription_plans p on p.id=s.plan_id where s.agent_id=l.agent_id and s.status='active' limit 1),0)
   + coalesce((select count(*)*2 from public.business_events e where e.listing_id=l.id and e.event_type='listing_view' and e.created_at>now()-interval '7 days'),0))::numeric score
 from public.listings l where public.is_listing_public(l.id) order by score desc,l.published_at desc limit greatest(1,least(p_limit,100))
$$;
grant execute on function public.get_recommended_listing_ids(integer) to anon,authenticated;
