-- KODIMALI 3.0: controlled refund and provider-settlement operations.
-- This migration adds preparation and provider-result recording only. It does
-- not schedule calls, enable flags, or contact a payment provider.

alter table public.settlement_batch_items
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists provider text,
  add column if not exists provider_payload jsonb not null default '{}'::jsonb;

alter table public.refund_obligations
  add column if not exists provider text,
  add column if not exists provider_transaction_id text,
  add column if not exists provider_payload jsonb not null default '{}'::jsonb;

create unique index if not exists refund_obligation_provider_transaction_idx
on public.refund_obligations(provider,provider_transaction_id)
where provider is not null and provider_transaction_id is not null;

alter table public.settlement_batch_items
  drop constraint if exists settlement_batch_items_payable_id_key;
create unique index if not exists settlement_active_payable_idx
on public.settlement_batch_items(payable_id)
where status<>'failed';

create unique index if not exists settlement_item_provider_transaction_idx
on public.settlement_batch_items(provider_transaction_id)
where provider_transaction_id is not null;

create or replace function public.post_cancellation_allocation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_collected bigint;
  v_journal uuid;
  v_collection_account uuid;
  v_refund_account uuid;
  v_provider_account uuid;
  v_revenue_account uuid;
begin
  if new.booking_status<>'cancelled' or old.booking_status='cancelled' or new.paid_minor=0 then
    return new;
  end if;

  select coalesce(sum(i.amount_minor),0) into v_collected
  from public.payment_intents i
  where i.resource_type='booking_request'
    and i.resource_id=new.booking_request_id
    and i.product in ('booking_deposit','booking_balance','booking_service_fee')
    and i.status='verified_paid';

  if v_collected<new.paid_minor then
    if not exists(
      select 1 from public.financial_reconciliation_cases x
      where x.provider='internal_ledger'
        and x.provider_order_id=new.id::text
        and x.reason='Cancellation allocation is not fully represented in the KODIMALI 3 ledger'
        and x.status in ('open','investigating')
    ) then
      insert into public.financial_reconciliation_cases(
        provider,provider_order_id,expected_amount_minor,reported_amount_minor,
        reason,status
      ) values(
        'internal_ledger',new.id::text,new.paid_minor,v_collected,
        'Cancellation allocation is not fully represented in the KODIMALI 3 ledger','open'
      );
    end if;
    return new;
  end if;

  select id into v_journal from public.financial_journals
  where idempotency_key='cancellation-allocation:'||new.id::text;
  if v_journal is not null then return new; end if;

  select id into v_collection_account from public.financial_accounts
  where code='BOOKING_COLLECTIONS_LIABILITY';
  select id into v_refund_account from public.financial_accounts
  where code='CUSTOMER_REFUND_LIABILITY';
  select id into v_provider_account from public.financial_accounts
  where code='PROVIDER_PAYABLE';
  select id into v_revenue_account from public.financial_accounts
  where code='KODIMALI_BOOKING_FEE_REVENUE';
  if v_collection_account is null or v_refund_account is null
     or v_provider_account is null or v_revenue_account is null then
    raise exception 'Required cancellation ledger accounts are missing';
  end if;

  insert into public.financial_journals(
    journal_type,reference_type,reference_id,idempotency_key,description,posted_by,metadata
  ) values(
    'cancellation_allocation','booking_cancellation_case',new.id,
    'cancellation-allocation:'||new.id::text,
    'Approved cancellation allocation',auth.uid(),
    jsonb_build_object('booking_request_id',new.booking_request_id,'paid_minor',new.paid_minor)
  ) returning id into v_journal;

  insert into public.financial_postings(journal_id,account_id,debit_minor,memo)
  values(v_journal,v_collection_account,new.paid_minor,'Release booking collection liability');
  if new.customer_refund_minor>0 then
    insert into public.financial_postings(journal_id,account_id,credit_minor,memo)
    values(v_journal,v_refund_account,new.customer_refund_minor,'Recognize customer refund liability');
  end if;
  if new.provider_compensation_minor>0 then
    insert into public.financial_postings(journal_id,account_id,credit_minor,memo)
    values(v_journal,v_provider_account,new.provider_compensation_minor,'Recognize provider compensation payable');
  end if;
  if new.platform_fee_minor>0 then
    insert into public.financial_postings(journal_id,account_id,credit_minor,memo)
    values(v_journal,v_revenue_account,new.platform_fee_minor,'Recognize approved cancellation fee');
  end if;
  return new;
end;
$$;

drop trigger if exists post_cancellation_allocation on public.booking_cancellation_cases;
create trigger post_cancellation_allocation
after update of booking_status on public.booking_cancellation_cases
for each row execute function public.post_cancellation_allocation();

create or replace function public.link_obligation_to_cancellation_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_journal uuid;
begin
  select j.id into v_journal
  from public.booking_cancellation_cases c
  join public.financial_journals j
    on j.idempotency_key='cancellation-allocation:'||c.id::text
  where c.booking_request_id=new.booking_request_id
    and c.booking_status='cancelled'
  order by c.reviewed_at desc nulls last
  limit 1;
  if v_journal is not null and new.journal_id is null then
    if tg_table_name='refund_obligations' then
      update public.refund_obligations set journal_id=v_journal where id=new.id;
    elsif tg_table_name='provider_payables' then
      update public.provider_payables set journal_id=v_journal where id=new.id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists link_refund_cancellation_journal on public.refund_obligations;
create trigger link_refund_cancellation_journal
after insert on public.refund_obligations
for each row execute function public.link_obligation_to_cancellation_journal();
drop trigger if exists link_payable_cancellation_journal on public.provider_payables;
create trigger link_payable_cancellation_journal
after insert on public.provider_payables
for each row execute function public.link_obligation_to_cancellation_journal();

create or replace function public.prepare_refund_execution(
  p_refund_id uuid,
  p_note text
)
returns public.refund_obligations
language plpgsql
security definer
set search_path = public
as $$
declare v_refund public.refund_obligations;
begin
  if not public.has_admin_permission('refunds.manage') then
    raise exception 'Refund management permission required';
  end if;
  if not public.kodimali_feature_enabled('automated_refunds') then
    raise exception 'Automated refunds are not enabled';
  end if;
  if length(trim(coalesce(p_note,'')))<10 then
    raise exception 'A clear execution note is required';
  end if;
  select * into v_refund from public.refund_obligations where id=p_refund_id for update;
  if v_refund.id is null then raise exception 'Refund obligation not found'; end if;
  if v_refund.status<>'approved' then raise exception 'Only an approved refund can be prepared'; end if;
  update public.refund_obligations set status='processing',updated_at=now()
  where id=v_refund.id returning * into v_refund;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'refund_execution_prepared','refund_obligations',v_refund.id,
    jsonb_build_object('amount_minor',v_refund.amount_minor,'note',trim(p_note)));
  return v_refund;
end;
$$;

create or replace function public.record_refund_provider_result(
  p_refund_id uuid,
  p_succeeded boolean,
  p_provider text,
  p_provider_transaction_id text,
  p_provider_payload jsonb default '{}'::jsonb
)
returns public.refund_obligations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refund public.refund_obligations;
  v_journal uuid;
  v_refund_account uuid;
  v_cash_account uuid;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
  if not public.kodimali_feature_enabled('automated_refunds') then
    raise exception 'Automated refunds are not enabled';
  end if;
  if nullif(trim(p_provider),'') is null then raise exception 'Payment provider is required'; end if;
  select * into v_refund from public.refund_obligations where id=p_refund_id for update;
  if v_refund.id is null then raise exception 'Refund obligation not found'; end if;
  if v_refund.status='refunded' then return v_refund; end if;
  if v_refund.status<>'processing' then raise exception 'Refund is not awaiting a provider result'; end if;

  if not p_succeeded then
    update public.refund_obligations
    set status='reconciliation_required',provider=lower(trim(p_provider)),
        provider_transaction_id=nullif(trim(p_provider_transaction_id),''),
        provider_payload=coalesce(p_provider_payload,'{}'::jsonb),updated_at=now()
    where id=v_refund.id returning * into v_refund;
    insert into public.financial_reconciliation_cases(
      provider,provider_transaction_id,payment_intent_id,expected_amount_minor,
      reported_amount_minor,reason,status
    ) values(
      lower(trim(p_provider)),nullif(trim(p_provider_transaction_id),''),v_refund.payment_intent_id,
      v_refund.amount_minor,0,'Refund provider execution failed','open'
    );
    insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
    values(auth.uid(),'refund_provider_failed','refund_obligations',v_refund.id,
      jsonb_build_object('provider_transaction_id',p_provider_transaction_id));
    return v_refund;
  end if;
  if nullif(trim(p_provider_transaction_id),'') is null then
    raise exception 'Provider transaction ID is required for a successful refund';
  end if;

  select id into v_refund_account from public.financial_accounts
  where code='CUSTOMER_REFUND_LIABILITY';
  select id into v_cash_account from public.financial_accounts
  where code='CASH_PROVIDER_CLEARING';
  insert into public.financial_journals(
    journal_type,reference_type,reference_id,idempotency_key,description,metadata
  ) values(
    'customer_refund','refund_obligation',v_refund.id,'refund-paid:'||v_refund.id::text,
    'Verified customer refund',jsonb_build_object(
      'provider_transaction_id',trim(p_provider_transaction_id),
      'provider',lower(trim(p_provider)),
      'provider_payload',coalesce(p_provider_payload,'{}'::jsonb)
    )
  ) on conflict(idempotency_key) do nothing returning id into v_journal;
  if v_journal is not null then
    insert into public.financial_postings(journal_id,account_id,debit_minor,memo)
    values(v_journal,v_refund_account,v_refund.amount_minor,'Clear customer refund liability');
    insert into public.financial_postings(journal_id,account_id,credit_minor,memo)
    values(v_journal,v_cash_account,v_refund.amount_minor,'Refund paid through provider');
  end if;
  update public.refund_obligations
  set status='refunded',provider=lower(trim(p_provider)),
      provider_transaction_id=trim(p_provider_transaction_id),
      provider_payload=coalesce(p_provider_payload,'{}'::jsonb),updated_at=now()
  where id=v_refund.id returning * into v_refund;
  update public.booking_requests set refund_status='refunded',updated_at=now()
  where id=v_refund.booking_request_id;
  update public.booking_cancellation_cases set refund_status='refunded',updated_at=now()
  where booking_request_id=v_refund.booking_request_id and booking_status='cancelled';
  insert into public.notifications(user_id,booking_request_id,type,title,body,payload)
  values(v_refund.customer_id,v_refund.booking_request_id,'announcement',
    'Refund completed','Your approved booking refund has been completed.',
    jsonb_build_object('eventType','booking_refund_completed','bookingId',v_refund.booking_request_id,'refundId',v_refund.id));
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'refund_provider_verified','refund_obligations',v_refund.id,
    jsonb_build_object('provider_transaction_id',trim(p_provider_transaction_id),'amount_minor',v_refund.amount_minor));
  return v_refund;
end;
$$;

create or replace function public.create_provider_settlement_batch(
  p_payable_ids uuid[],
  p_note text
)
returns public.settlement_batches
language plpgsql
security definer
set search_path = public
as $$
declare v_batch public.settlement_batches; v_expected integer; v_inserted integer;
begin
  if not public.has_admin_permission('payments.manage') then
    raise exception 'Payment management permission required';
  end if;
  v_expected:=coalesce(array_length(p_payable_ids,1),0);
  if v_expected=0 then raise exception 'Choose at least one provider payable'; end if;
  if length(trim(coalesce(p_note,'')))<10 then raise exception 'A clear batch note is required'; end if;

  insert into public.settlement_batches(reference,status,created_by)
  values('SET-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'draft',auth.uid())
  returning * into v_batch;
  insert into public.settlement_batch_items(batch_id,payable_id,amount_minor)
  select v_batch.id,p.id,p.amount_minor
  from public.provider_payables p
  where p.id=any(p_payable_ids)
    and p.status='eligible'
    and not exists(
      select 1 from public.booking_incidents i
      where i.booking_request_id=p.booking_request_id
        and i.settlement_suspended=true
        and i.status not in ('resolved','rejected')
    )
  on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted<>v_expected then
    raise exception 'One or more payables are missing, ineligible, disputed, suspended or already batched';
  end if;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'settlement_batch_created','settlement_batches',v_batch.id,
    jsonb_build_object('payable_count',v_inserted,'note',trim(p_note)));
  return v_batch;
end;
$$;

create or replace function public.approve_provider_settlement_batch(
  p_batch_id uuid,
  p_note text
)
returns public.settlement_batches
language plpgsql
security definer
set search_path = public
as $$
declare v_batch public.settlement_batches;
begin
  if not public.has_admin_permission('payments.manage') then
    raise exception 'Payment management permission required';
  end if;
  if length(trim(coalesce(p_note,'')))<10 then raise exception 'A clear approval note is required'; end if;
  select * into v_batch from public.settlement_batches where id=p_batch_id for update;
  if v_batch.id is null then raise exception 'Settlement batch not found'; end if;
  if v_batch.status<>'draft' then raise exception 'Only a draft batch can be approved'; end if;
  if v_batch.created_by=auth.uid() then raise exception 'A different authorized administrator must approve this batch'; end if;
  if exists(
    select 1 from public.settlement_batch_items i
    join public.provider_payables p on p.id=i.payable_id
    where i.batch_id=v_batch.id and p.status<>'eligible'
  ) then raise exception 'The batch contains a payable that is no longer eligible'; end if;
  update public.settlement_batches
  set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now()
  where id=v_batch.id returning * into v_batch;
  update public.provider_payables p set status='scheduled',updated_at=now()
  from public.settlement_batch_items i
  where i.batch_id=v_batch.id and i.payable_id=p.id;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'settlement_batch_approved','settlement_batches',v_batch.id,
    jsonb_build_object('note',trim(p_note)));
  return v_batch;
end;
$$;

create or replace function public.record_settlement_provider_result(
  p_batch_item_id uuid,
  p_succeeded boolean,
  p_provider text,
  p_provider_transaction_id text,
  p_provider_payload jsonb default '{}'::jsonb
)
returns public.settlement_batch_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.settlement_batch_items;
  v_batch public.settlement_batches;
  v_payable public.provider_payables;
  v_journal uuid;
  v_payable_account uuid;
  v_cash_account uuid;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
  if not public.kodimali_feature_enabled('automated_provider_payouts') then
    raise exception 'Automated provider payouts are not enabled';
  end if;
  if nullif(trim(p_provider),'') is null then raise exception 'Payment provider is required'; end if;
  select * into v_item from public.settlement_batch_items where id=p_batch_item_id for update;
  if v_item.id is null then raise exception 'Settlement item not found'; end if;
  select * into v_batch from public.settlement_batches where id=v_item.batch_id for update;
  select * into v_payable from public.provider_payables where id=v_item.payable_id for update;
  if v_item.status='settled' then return v_item; end if;
  if v_batch.status not in ('approved','processing') or v_payable.status<>'scheduled' then
    raise exception 'Settlement item is not ready for provider execution';
  end if;
  update public.settlement_batches set status='processing',updated_at=now() where id=v_batch.id;

  if not p_succeeded then
    update public.settlement_batch_items
    set status='failed',provider=lower(trim(p_provider)),
        provider_payload=coalesce(p_provider_payload,'{}'::jsonb),updated_at=now()
    where batch_id=v_batch.id and status<>'settled';
    select * into v_item from public.settlement_batch_items where id=p_batch_item_id;
    update public.provider_payables p set status='on_hold',updated_at=now()
    from public.settlement_batch_items i
    where i.batch_id=v_batch.id and i.payable_id=p.id and i.status='failed';
    update public.settlement_batches set status='failed',updated_at=now() where id=v_batch.id;
    insert into public.financial_reconciliation_cases(
      provider,provider_transaction_id,expected_amount_minor,reported_amount_minor,reason,status
    ) values(
      lower(trim(p_provider)),nullif(trim(p_provider_transaction_id),''),v_item.amount_minor,0,
      'Provider settlement execution failed','open'
    );
    insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
    values(auth.uid(),'provider_settlement_failed','settlement_batch_items',v_item.id,
      jsonb_build_object('provider_transaction_id',p_provider_transaction_id,'amount_minor',v_item.amount_minor));
    return v_item;
  end if;
  if nullif(trim(p_provider_transaction_id),'') is null then
    raise exception 'Provider transaction ID is required for a successful settlement';
  end if;

  select id into v_payable_account from public.financial_accounts where code='PROVIDER_PAYABLE';
  select id into v_cash_account from public.financial_accounts where code='CASH_PROVIDER_CLEARING';
  insert into public.financial_journals(
    journal_type,reference_type,reference_id,idempotency_key,description,metadata
  ) values(
    'provider_settlement','settlement_batch_item',v_item.id,'settlement-paid:'||v_item.id::text,
    'Verified provider settlement',jsonb_build_object(
      'provider_transaction_id',trim(p_provider_transaction_id),
      'provider',lower(trim(p_provider)),
      'provider_payload',coalesce(p_provider_payload,'{}'::jsonb)
    )
  ) on conflict(idempotency_key) do nothing returning id into v_journal;
  if v_journal is not null then
    insert into public.financial_postings(journal_id,account_id,debit_minor,memo)
    values(v_journal,v_payable_account,v_item.amount_minor,'Clear provider payable');
    insert into public.financial_postings(journal_id,account_id,credit_minor,memo)
    values(v_journal,v_cash_account,v_item.amount_minor,'Provider payout through payment provider');
  end if;
  update public.settlement_batch_items
  set status='settled',provider=lower(trim(p_provider)),
      provider_transaction_id=trim(p_provider_transaction_id),
      provider_payload=coalesce(p_provider_payload,'{}'::jsonb),updated_at=now()
  where id=v_item.id returning * into v_item;
  update public.provider_payables set status='settled',updated_at=now() where id=v_payable.id;
  update public.booking_cancellation_cases
  set provider_compensation_status='settled',settlement_status='settled',updated_at=now()
  where booking_request_id=v_payable.booking_request_id and booking_status='cancelled';
  insert into public.notifications(user_id,booking_request_id,type,title,body,payload)
  values(v_payable.provider_profile_id,v_payable.booking_request_id,'announcement',
    'Settlement completed','Your eligible booking settlement has been completed.',
    jsonb_build_object('eventType','provider_settlement_completed','bookingId',v_payable.booking_request_id,'payableId',v_payable.id));
  if not exists(
    select 1 from public.settlement_batch_items
    where batch_id=v_batch.id and status not in ('settled','failed')
  ) then
    update public.settlement_batches
    set status=case when exists(select 1 from public.settlement_batch_items where batch_id=v_batch.id and status='failed') then 'failed' else 'completed' end,
        provider_reference=trim(p_provider_transaction_id),updated_at=now()
    where id=v_batch.id;
  end if;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'provider_settlement_verified','settlement_batch_items',v_item.id,
    jsonb_build_object('provider_transaction_id',trim(p_provider_transaction_id),'amount_minor',v_item.amount_minor));
  return v_item;
end;
$$;

create or replace function public.release_failed_settlement_payable(
  p_payable_id uuid,
  p_note text
)
returns public.provider_payables
language plpgsql
security definer
set search_path = public
as $$
declare v_payable public.provider_payables;
begin
  if not public.has_admin_permission('payments.manage') then
    raise exception 'Payment management permission required';
  end if;
  if length(trim(coalesce(p_note,'')))<10 then
    raise exception 'A clear recovery note is required';
  end if;
  select * into v_payable from public.provider_payables where id=p_payable_id for update;
  if v_payable.id is null then raise exception 'Provider payable not found'; end if;
  if v_payable.status<>'on_hold' or not exists(
    select 1 from public.settlement_batch_items i
    where i.payable_id=v_payable.id and i.status='failed'
  ) then raise exception 'Only a payable from a failed settlement can be released'; end if;
  if exists(
    select 1 from public.booking_incidents i
    where i.booking_request_id=v_payable.booking_request_id
      and i.settlement_suspended=true and i.status not in ('resolved','rejected')
  ) then raise exception 'Resolve the booking incident before releasing settlement'; end if;
  update public.provider_payables set status='eligible',updated_at=now()
  where id=v_payable.id returning * into v_payable;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'failed_settlement_payable_released','provider_payables',v_payable.id,
    jsonb_build_object('note',trim(p_note)));
  return v_payable;
end;
$$;

revoke all on function public.post_cancellation_allocation() from public,anon,authenticated;
revoke all on function public.link_obligation_to_cancellation_journal() from public,anon,authenticated;
revoke all on function public.prepare_refund_execution(uuid,text) from public,anon,authenticated;
grant execute on function public.prepare_refund_execution(uuid,text) to authenticated,service_role;
revoke all on function public.record_refund_provider_result(uuid,boolean,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.record_refund_provider_result(uuid,boolean,text,text,jsonb) to service_role;
revoke all on function public.create_provider_settlement_batch(uuid[],text) from public,anon,authenticated;
grant execute on function public.create_provider_settlement_batch(uuid[],text) to authenticated,service_role;
revoke all on function public.approve_provider_settlement_batch(uuid,text) from public,anon,authenticated;
grant execute on function public.approve_provider_settlement_batch(uuid,text) to authenticated,service_role;
revoke all on function public.record_settlement_provider_result(uuid,boolean,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.record_settlement_provider_result(uuid,boolean,text,text,jsonb) to service_role;
revoke all on function public.release_failed_settlement_payable(uuid,text) from public,anon,authenticated;
grant execute on function public.release_failed_settlement_payable(uuid,text) to authenticated,service_role;

comment on function public.prepare_refund_execution(uuid,text) is
'Moves an approved refund to processing only when automated refunds have been explicitly enabled.';
comment on function public.record_settlement_provider_result(uuid,boolean,text,text,jsonb) is
'Service-only, flag-gated settlement result recorder with idempotent ledger posting.';

