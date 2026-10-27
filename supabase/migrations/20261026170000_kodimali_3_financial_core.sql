-- KODIMALI 3.0 phase 2: typed payment intents, balanced immutable ledger,
-- liabilities, reconciliation and approved cancellation bands.

create table if not exists public.payment_intents (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.profiles(id) on delete restrict,
  product text not null check(product in ('booking_deposit','booking_balance','contact_unlock','paid_chat_unlock','booking_service_fee','provider_settlement','agent_commission','referral_reward','customer_refund','external_deal_record')),
  resource_type text not null,
  resource_id uuid,
  amount_minor bigint not null check(amount_minor>=0),
  currency text not null default 'TZS' check(currency='TZS'),
  status text not null default 'created' check(status in ('created','awaiting_payment','processing','verified_paid','failed','expired','refund_pending','refunded','partially_refunded','reconciliation_required')),
  idempotency_key text not null unique,
  provider text,
  provider_order_id text,
  provider_transaction_id text,
  agreement_snapshot_id uuid references public.booking_terms_snapshots(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  expires_at timestamptz,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider,provider_transaction_id)
);
alter table public.platform_payment_orders add column if not exists payment_intent_id uuid references public.payment_intents(id) on delete restrict;
create unique index if not exists platform_payment_orders_intent_idx on public.platform_payment_orders(payment_intent_id) where payment_intent_id is not null;

create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_class text not null check(account_class in ('asset','liability','equity','revenue','expense','clearing')),
  owner_kind text not null default 'platform' check(owner_kind in ('platform','customer','provider','agent','referral_contributor','payment_provider')),
  owner_id uuid,
  currency text not null default 'TZS' check(currency='TZS'),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.financial_accounts(code,name,account_class) values
 ('CASH_PROVIDER_CLEARING','Payment provider clearing','asset'),
 ('BOOKING_COLLECTIONS_LIABILITY','Booking collections pending allocation','liability'),
 ('PROVIDER_PAYABLE','Amounts payable to providers','liability'),
 ('CUSTOMER_REFUND_LIABILITY','Approved and pending customer refunds','liability'),
 ('AGENT_COMMISSION_LIABILITY','Agent commissions payable','liability'),
 ('REFERRAL_REWARD_LIABILITY','Referral rewards payable','liability'),
 ('KODIMALI_BOOKING_FEE_REVENUE','Earned booking fee revenue','revenue'),
 ('KODIMALI_CHAT_REVENUE','Earned paid-chat revenue','revenue'),
 ('KODIMALI_CONTACT_REVENUE','Earned contact-unlock revenue','revenue'),
 ('PAYMENT_PROCESSING_EXPENSE','Payment processing costs','expense'),
 ('UNRESOLVED_RECONCILIATION','Unresolved provider differences','clearing'),
 ('EXTERNAL_DEALS_MEMO','Externally completed deals; not KODIMALI cash','clearing')
on conflict(code) do nothing;

create table if not exists public.financial_journals (
  id uuid primary key default gen_random_uuid(),
  journal_type text not null,
  reference_type text not null,
  reference_id uuid,
  idempotency_key text not null unique,
  description text not null,
  status text not null default 'posted' check(status in ('posted','reversed')),
  reverses_journal_id uuid unique references public.financial_journals(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  posted_by uuid references public.profiles(id) on delete restrict,
  posted_at timestamptz not null default now()
);

create table if not exists public.financial_postings (
  id bigint generated always as identity primary key,
  journal_id uuid not null references public.financial_journals(id) on delete restrict,
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  debit_minor bigint not null default 0 check(debit_minor>=0),
  credit_minor bigint not null default 0 check(credit_minor>=0),
  currency text not null default 'TZS' check(currency='TZS'),
  memo text,
  created_at timestamptz not null default now(),
  check((debit_minor>0 and credit_minor=0) or (credit_minor>0 and debit_minor=0))
);
create index if not exists financial_postings_journal_idx on public.financial_postings(journal_id);
create index if not exists financial_postings_account_idx on public.financial_postings(account_id,created_at);

create or replace function public.assert_balanced_financial_journal()
returns trigger language plpgsql set search_path=public as $$
declare jid uuid;d bigint;c bigint;n integer;
begin
 jid:=coalesce(new.journal_id,old.journal_id);
 select coalesce(sum(debit_minor),0),coalesce(sum(credit_minor),0),count(*) into d,c,n from public.financial_postings where journal_id=jid;
 if n<2 or d<>c then raise exception 'Financial journal % is not balanced: debit %, credit %',jid,d,c; end if;
 return null;
end $$;
create constraint trigger financial_journal_must_balance
after insert or update or delete on public.financial_postings deferrable initially deferred
for each row execute function public.assert_balanced_financial_journal();

create or replace function public.prevent_posted_financial_mutation()
returns trigger language plpgsql set search_path=public as $$
begin raise exception 'Posted financial history is append-only; create a reversing journal'; end $$;
create trigger financial_journals_append_only before update or delete on public.financial_journals
for each row execute function public.prevent_posted_financial_mutation();
create trigger financial_postings_append_only before update or delete on public.financial_postings
for each row execute function public.prevent_posted_financial_mutation();

create table if not exists public.refund_obligations (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid references public.booking_requests(id) on delete restrict,
 payment_intent_id uuid references public.payment_intents(id) on delete restrict,customer_id uuid not null references public.profiles(id) on delete restrict,
 amount_minor bigint not null check(amount_minor>0),currency text not null default 'TZS' check(currency='TZS'),
 reason text not null,status text not null default 'pending_review' check(status in ('pending_review','approved','processing','refunded','partially_refunded','declined','reconciliation_required')),
 journal_id uuid references public.financial_journals(id) on delete restrict,approved_by uuid references public.profiles(id),approved_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.provider_payables (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid references public.booking_requests(id) on delete restrict,
 provider_profile_id uuid not null references public.profiles(id) on delete restrict,amount_minor bigint not null check(amount_minor>=0),currency text not null default 'TZS' check(currency='TZS'),
 status text not null default 'pending_fulfillment' check(status in ('pending_fulfillment','eligible','on_hold','scheduled','settled','reversed','disputed')),
 journal_id uuid references public.financial_journals(id) on delete restrict,eligible_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.commission_obligations (
 id uuid primary key default gen_random_uuid(),booking_request_id uuid references public.booking_requests(id) on delete restrict,
 beneficiary_profile_id uuid not null references public.profiles(id) on delete restrict,kind text not null check(kind in ('agent_commission','referral_reward')),
 amount_minor bigint not null check(amount_minor>=0),status text not null default 'pending' check(status in ('pending','eligible','payable','paid','reversed','disputed')),
 journal_id uuid references public.financial_journals(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.settlement_batches (
 id uuid primary key default gen_random_uuid(),reference text not null unique,status text not null default 'draft' check(status in ('draft','approved','processing','completed','failed','cancelled')),
 approved_by uuid references public.profiles(id),approved_at timestamptz,provider_reference text,created_by uuid references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.settlement_batch_items (
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.settlement_batches(id) on delete restrict,payable_id uuid not null unique references public.provider_payables(id) on delete restrict,
 amount_minor bigint not null check(amount_minor>0),status text not null default 'pending' check(status in ('pending','processing','settled','failed')),provider_transaction_id text,created_at timestamptz not null default now()
);
create table if not exists public.financial_reconciliation_cases (
 id uuid primary key default gen_random_uuid(),provider text not null,provider_transaction_id text,provider_order_id text,payment_intent_id uuid references public.payment_intents(id) on delete restrict,
 expected_amount_minor bigint,reported_amount_minor bigint,currency text not null default 'TZS',reason text not null,status text not null default 'open' check(status in ('open','investigating','resolved','written_off')),
 resolution text,resolved_by uuid references public.profiles(id),resolved_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.external_deal_declarations (
 id uuid primary key default gen_random_uuid(),listing_id uuid references public.listings(id) on delete restrict,referral_submission_id uuid references public.rental_information_submissions(id) on delete restrict,
 declared_by uuid not null references public.profiles(id) on delete restrict,other_party_id uuid references public.profiles(id) on delete set null,claimed_value_minor bigint not null check(claimed_value_minor>=0),currency text not null default 'TZS' check(currency='TZS'),
 transaction_date date not null,evidence_paths jsonb not null default '[]'::jsonb,status text not null default 'reported' check(status in ('reported','evidence_submitted','verified','commission_assessed','settled','rejected','disputed')),
 verified_by uuid references public.profiles(id),verified_at timestamptz,notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);

alter table public.payment_intents enable row level security;alter table public.financial_accounts enable row level security;
alter table public.financial_journals enable row level security;alter table public.financial_postings enable row level security;
alter table public.refund_obligations enable row level security;alter table public.provider_payables enable row level security;
alter table public.commission_obligations enable row level security;alter table public.settlement_batches enable row level security;
alter table public.settlement_batch_items enable row level security;alter table public.financial_reconciliation_cases enable row level security;
alter table public.external_deal_declarations enable row level security;

create policy payment_intents_customer_finance_read on public.payment_intents for select to authenticated using(customer_id=auth.uid() or public.has_admin_permission('payments.view') or public.has_admin_permission('payments.manage'));
create policy financial_accounts_finance_read on public.financial_accounts for select to authenticated using(public.has_admin_permission('payments.view') or public.has_admin_permission('payments.manage'));
create policy financial_journals_finance_read on public.financial_journals for select to authenticated using(public.has_admin_permission('payments.view') or public.has_admin_permission('payments.manage'));
create policy financial_postings_finance_read on public.financial_postings for select to authenticated using(public.has_admin_permission('payments.view') or public.has_admin_permission('payments.manage'));
create policy refund_customer_finance_read on public.refund_obligations for select to authenticated using(customer_id=auth.uid() or public.has_admin_permission('refunds.manage'));
create policy payable_provider_finance_read on public.provider_payables for select to authenticated using(provider_profile_id=auth.uid() or public.has_admin_permission('payments.manage'));
create policy commission_beneficiary_finance_read on public.commission_obligations for select to authenticated using(beneficiary_profile_id=auth.uid() or public.has_admin_permission('payments.manage'));
create policy settlement_finance_read on public.settlement_batches for select to authenticated using(public.has_admin_permission('payments.manage'));
create policy settlement_items_finance_read on public.settlement_batch_items for select to authenticated using(public.has_admin_permission('payments.manage'));
create policy reconciliation_finance_read on public.financial_reconciliation_cases for select to authenticated using(public.has_admin_permission('payments.manage'));
create policy external_deal_participant_read on public.external_deal_declarations for select to authenticated using(declared_by=auth.uid() or other_party_id=auth.uid() or public.has_admin_permission('payments.manage'));
create policy external_deal_self_insert on public.external_deal_declarations for insert to authenticated with check(declared_by=auth.uid() and status='reported');

create table if not exists public.cancellation_policy_versions (
 id uuid primary key default gen_random_uuid(),code text not null,version integer not null,title text not null,applies_to text not null default 'short_term',timezone text not null default 'Africa/Dar_es_Salaam',
 is_active boolean not null default false,effective_from timestamptz not null,effective_until timestamptz,created_by uuid references public.profiles(id),created_at timestamptz not null default now(),unique(code,version)
);
create table if not exists public.cancellation_policy_bands (
 id uuid primary key default gen_random_uuid(),policy_version_id uuid not null references public.cancellation_policy_versions(id) on delete restrict,
 minimum_minutes_before_start integer not null check(minimum_minutes_before_start>=0),customer_percent integer not null check(customer_percent between 0 and 100),provider_percent integer not null check(provider_percent between 0 and 100),platform_percent integer not null check(platform_percent between 0 and 100),
 created_at timestamptz not null default now(),unique(policy_version_id,minimum_minutes_before_start),check(customer_percent+provider_percent+platform_percent=100)
);
alter table public.cancellation_policy_versions enable row level security;alter table public.cancellation_policy_bands enable row level security;
create policy cancellation_versions_read on public.cancellation_policy_versions for select using(is_active or public.is_admin());
create policy cancellation_bands_read on public.cancellation_policy_bands for select using(exists(select 1 from public.cancellation_policy_versions v where v.id=policy_version_id and(v.is_active or public.is_admin())));

with policy as (
 insert into public.cancellation_policy_versions(code,version,title,is_active,effective_from)
 values('KDM-STANDARD-SHORT',1,'KODIMALI standard short-term cancellation bands',true,now())
 on conflict(code,version) do update set title=excluded.title returning id
)
insert into public.cancellation_policy_bands(policy_version_id,minimum_minutes_before_start,customer_percent,provider_percent,platform_percent)
select id,x.minutes,x.customer,x.provider,x.platform from policy cross join (values
 (20160,100,0,0),(8640,90,0,10),(5760,40,50,10),(1440,20,70,10)
) as x(minutes,customer,provider,platform) on conflict(policy_version_id,minimum_minutes_before_start) do nothing;

create or replace function public.calculate_cancellation_allocation(p_policy_version_id uuid,p_paid_minor bigint,p_service_start timestamptz,p_cancelled_at timestamptz default now())
returns table(customer_minor bigint,provider_minor bigint,platform_minor bigint,minimum_minutes_before_start integer)
language plpgsql stable set search_path=public as $$
declare mins numeric;band public.cancellation_policy_bands;remaining bigint;
begin
 if p_paid_minor<0 then raise exception 'Paid amount cannot be negative'; end if;
 mins:=extract(epoch from(p_service_start-p_cancelled_at))/60;
 if mins<1440 then raise exception 'An approved under-24-hour or no-show policy is required'; end if;
 select * into band from public.cancellation_policy_bands b where b.policy_version_id=p_policy_version_id and b.minimum_minutes_before_start<=mins order by b.minimum_minutes_before_start desc limit 1;
 if band.id is null then raise exception 'No cancellation band applies'; end if;
 customer_minor:=floor((p_paid_minor::numeric*band.customer_percent+50)/100)::bigint;
 provider_minor:=floor((p_paid_minor::numeric*band.provider_percent+50)/100)::bigint;
 remaining:=p_paid_minor-customer_minor-provider_minor;
 platform_minor:=remaining;
 minimum_minutes_before_start:=band.minimum_minutes_before_start;
 return next;
end $$;
grant execute on function public.calculate_cancellation_allocation(uuid,bigint,timestamptz,timestamptz) to authenticated,service_role;

comment on table public.financial_journals is 'Immutable double-entry journal headers. Corrections require a reversing journal.';
comment on table public.external_deal_declarations is 'External business declarations only; claimed value is never classified as KODIMALI-collected cash.';
