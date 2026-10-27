-- KODIMALI 3.0: Events deposits and balances use the same typed payment core.

insert into public.kodimali_feature_flags(key) values
  ('event_deposit_payments'),
  ('event_balance_payments')
on conflict(key) do nothing;

do $$
declare v_constraint text;
begin
  for v_constraint in
    select conname from pg_constraint
    where conrelid='public.payment_intents'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) ilike '%product%'
  loop
    execute format('alter table public.payment_intents drop constraint %I',v_constraint);
  end loop;
  alter table public.payment_intents add constraint payment_intents_product_check
  check(product in (
    'booking_deposit','booking_balance','event_deposit','event_balance',
    'contact_unlock','paid_chat_unlock','booking_service_fee',
    'provider_settlement','agent_commission','referral_reward',
    'customer_refund','external_deal_record'
  ));
end $$;

create or replace function public.prepare_event_payment_intent(
  p_plan_id uuid,
  p_product text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.event_plans;
  v_quote public.event_quote_revisions;
  v_agreement public.event_agreements;
  v_deposit bigint;
  v_balance bigint;
  v_paid_deposit bigint;
  v_paid_balance bigint;
  v_amount bigint;
  v_intent public.payment_intents;
begin
  if p_product not in ('event_deposit','event_balance') then
    raise exception 'Unsupported event payment product';
  end if;
  if not public.kodimali_feature_enabled(
    case when p_product='event_deposit' then 'event_deposit_payments' else 'event_balance_payments' end
  ) then
    raise exception 'This event payment product is not enabled';
  end if;
  if nullif(trim(p_idempotency_key),'') is null then
    raise exception 'Idempotency key is required';
  end if;

  select * into v_plan from public.event_plans
  where id=p_plan_id and customer_id=auth.uid() for update;
  if v_plan.id is null then raise exception 'Event plan was not found'; end if;
  select * into v_quote from public.event_quote_revisions
  where id=v_plan.accepted_quote_revision_id and status='accepted';
  if v_quote.id is null then raise exception 'Accept a valid quotation before payment'; end if;
  select * into v_agreement from public.event_agreements
  where plan_id=v_plan.id and status='accepted'
  order by version desc limit 1;
  if v_agreement.id is null then raise exception 'Accept the event agreement before payment'; end if;

  select deposit_minor,balance_minor into v_deposit,v_balance
  from public.calculate_booking_split(round(v_quote.total_tzs)::bigint,25);
  select coalesce(sum(amount_minor),0) into v_paid_deposit
  from public.payment_intents
  where resource_type='event_plan' and resource_id=v_plan.id
    and product='event_deposit' and status='verified_paid';
  select coalesce(sum(amount_minor),0) into v_paid_balance
  from public.payment_intents
  where resource_type='event_plan' and resource_id=v_plan.id
    and product='event_balance' and status='verified_paid';

  v_amount:=case when p_product='event_deposit'
    then greatest(0,v_deposit-v_paid_deposit)
    else greatest(0,v_balance-v_paid_balance)
  end;
  if p_product='event_balance' and v_paid_deposit<v_deposit then
    raise exception 'The event deposit must be verified first';
  end if;
  if v_amount<=0 then raise exception 'No payable amount remains for this event payment'; end if;

  insert into public.payment_intents(
    customer_id,product,resource_type,resource_id,amount_minor,currency,status,
    idempotency_key,metadata,expires_at
  ) values(
    auth.uid(),p_product,'event_plan',v_plan.id,v_amount,'TZS','awaiting_payment',
    trim(p_idempotency_key),
    jsonb_build_object(
      'event_reference',v_plan.reference,
      'quote_revision_id',v_quote.id,
      'quote_revision',v_quote.revision,
      'agreement_id',v_agreement.id,
      'agreement_version',v_agreement.version,
      'agreed_total_minor',round(v_quote.total_tzs)::bigint,
      'deposit_percent',25
    ),
    now()+interval '30 minutes'
  )
  on conflict(idempotency_key) do update set updated_at=now()
  returning * into v_intent;

  if v_intent.customer_id<>auth.uid() or v_intent.resource_id<>v_plan.id
     or v_intent.product<>p_product or v_intent.amount_minor<>v_amount then
    raise exception 'Idempotency key belongs to a different payment request';
  end if;
  update public.event_plans set status='payment_pending',updated_at=now()
  where id=v_plan.id and status in ('agreement_pending','payment_pending');
  return jsonb_build_object(
    'payment_intent_id',v_intent.id,
    'amount_minor',v_intent.amount_minor,
    'currency',v_intent.currency,
    'product',v_intent.product,
    'expires_at',v_intent.expires_at,
    'agreed_total_minor',round(v_quote.total_tzs)::bigint,
    'deposit_minor',v_deposit,
    'balance_minor',v_balance
  );
end;
$$;

revoke all on function public.prepare_event_payment_intent(uuid,text,text)
from public, anon, authenticated;
grant execute on function public.prepare_event_payment_intent(uuid,text,text)
to authenticated, service_role;

comment on function public.prepare_event_payment_intent(uuid,text,text) is
'Creates an idempotent 25/75 Events payment intent from an accepted quote and agreement.';
