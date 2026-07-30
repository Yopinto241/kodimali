-- Some live environments predate the initial-schema definition of these
-- workflow fields. The manage app and status Edge Functions require them.
alter table public.booking_requests
  add column if not exists agent_response_due_at timestamptz,
  add column if not exists first_agent_response_at timestamptz;

create index if not exists idx_booking_requests_agent_response_due
  on public.booking_requests(agent_response_due_at);
