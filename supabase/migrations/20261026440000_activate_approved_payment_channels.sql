-- Production rollout approved by the platform owner on 2026-10-27.
-- Enable customer/provider payment collection while keeping autonomous money
-- movement (automatic refunds and provider payouts) behind manual review.

do $$
declare
  v_approver uuid;
  v_note constant text := 'Platform owner approved production payment activation on 2026-10-27.';
begin
  select ara.user_id
  into v_approver
  from public.admin_role_assignments ara
  where ara.role_id = 'super_admin'
  order by ara.assigned_at nulls last, ara.user_id
  limit 1;

  if v_approver is null then
    raise exception 'Payment activation requires an existing Super Admin';
  end if;

  update public.marketplace_settings
  set contact_payments_enabled = true,
      agent_listing_payments_enabled = true,
      chat_payments_enabled = true,
      subscription_payments_enabled = true,
      listing_boost_payments_enabled = true,
      booking_payments_enabled = true,
      event_payments_enabled = true,
      updated_by = v_approver,
      updated_at = now()
  where id = true;

  update public.kodimali_feature_flags
  set enabled = true,
      approved_by = v_approver,
      approved_at = now(),
      updated_by = v_approver,
      updated_at = now(),
      configuration = configuration || jsonb_build_object(
        'approval_note', v_note,
        'activation_source', 'migration_20261026440000'
      )
  where key in (
    'instant_booking',
    'booking_deposit_payments',
    'booking_balance_payments',
    'paid_chat_unlock_v3',
    'contact_unlock_v3',
    'event_deposit_payments',
    'event_balance_payments'
  );

  insert into public.audit_logs(actor_id, action, target_table, target_id, metadata)
  values (
    v_approver,
    'production_payment_channels_activated',
    'marketplace_settings',
    null,
    jsonb_build_object(
      'approval_note', v_note,
      'automated_refunds', false,
      'automated_provider_payouts', false
    )
  );
end
$$;

