# API Rules

## General approach

- Use Supabase Auth for identity.
- Use RLS-protected direct queries for safe reads.
- Use Edge Functions for privileged or state-changing workflows.
- Keep backend logic authoritative for request routing, public eligibility, activation, and moderation.

## Key Edge Functions

### `create-guest-booking-request`

- Public guest action
- Reads listing visibility and owning agent
- Copies `listings.agent_id` into `booking_requests.agent_id`
- Creates the request row using only `listing_id`, `customer_name`, and `customer_phone_number`
- Blocks duplicate requests from the same phone number to the same listing within 10 minutes
- Creates the initial agent notification

### `create-booking-request`

- Compatibility wrapper for older clients
- Maps camelCase fields to the guest-request function payload

### `check-availability`

- Confirms that a listing is still publicly active and available
- Does not reserve inventory and does not block parallel guest requests

### `update-booking-status`

- Used by the owning agent or admin
- Stores status history
- Marks first agent response timestamp

### `mark-agent-delayed`

- Operational SLA helper
- Marks eligible requests as `agent_delayed`
- Notifies admins for intervention

### `approve-listing`

- Admin-only moderation action
- Updates listing visibility state and audit trail while keeping compatibility fields safe

### `verify-agent`

- Admin-only activation action
- Updates `account_status`, activation timestamps, and audit trail

## Client rules

- Do not expose service-role credentials in apps or web.
- Treat push notifications as hints only.
- Re-read authoritative request state from the backend after operational actions.
- Public clients should use approximate location labels unless business rules allow more disclosure.
