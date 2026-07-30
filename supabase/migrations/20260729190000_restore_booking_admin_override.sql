-- Several booking guard/audit triggers intentionally protect this flag. Restore
-- it for databases that were created through an older compacted schema path.
alter table public.booking_requests
  add column if not exists admin_override boolean not null default false;

comment on column public.booking_requests.admin_override is
  'True only when an authorized administrator overrides normal booking workflow safeguards.';
