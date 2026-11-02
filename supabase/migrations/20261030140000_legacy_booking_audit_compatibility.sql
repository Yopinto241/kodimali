-- Older installed management apps select this legacy name while loading the
-- entire audit workspace. Mirror the canonical status without a second writable
-- source of truth, changing no financial workflow, grants, or RLS policies.
alter table public.booking_cancellation_cases
  add column commission_adjustment_status text
  generated always as (commission_reversal_status) stored;

comment on column public.booking_cancellation_cases.commission_adjustment_status is
  'Read-only compatibility alias for older management app audit queries; canonical value is commission_reversal_status.';

notify pgrst, 'reload schema';
