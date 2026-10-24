# KODIMALI Events architecture

## Navigation and surfaces

- Website: highlighted main navigation and the Events category card open `/events`; module navigation exposes equipment, professionals, Event Advisor, builder and customer control-center links.
- Customer Mobile: Events is a primary bottom-navigation destination, not only a nested category.
- Customer Mobile: the server-provided `events` category opens the Events marketplace rather than ordinary property listings.
- Manage Mobile Agent: `Events` provides professional registration, offerings, requests and schedules.
- Manage Mobile Owner/Manager: the celebration action in Owner Workspace opens equipment inventory and requests.
- Manage Mobile Admin: `Events Coordinator` is visible only with `events.manage` permission.

## Roles

| Actor | Existing identity | Events responsibility |
| --- | --- | --- |
| Customer | Customer profile | Builds a plan, selects quantities/providers, accepts the quote and final agreement. |
| Equipment owner/manager | Verified owner profile | Registers stock, maintains quantities and confirms allocations. |
| Professional | Existing agent login plus verified event service profile | Publishes offerings and confirms time-based work. |
| Event Coordinator | Admin sub-role with Events permissions | Verifies providers, monitors confirmations, sends itemized quotes and agreements, and handles emergencies. |
| Information Admin | Existing Information Admin | Verifies private event leads before publication. |

Hall identities remain intentionally separate. An agent is associated through `agent_service_categories` with the meeting-hall or ceremony-hall category. A hall owner uses `owner_type = venue_owner`; a person managing a venue for its owner uses `owner_type = authorized_manager`. Both owner paths require admin verification before an owner profile and role are granted.

## Advisor and shared rental assets

`event_templates` contains approved rules, not generated claims. `run_event_advisor` persists recommendations and reasons without inventing prices, ratings or availability. A venue or vehicle selected for an event is linked through `event_plan_rental_assets` to the existing `rental_assets`, `listings` and optional `booking_requests` identities. Its ordinary `asset_reservations` record remains the availability authority, so the Events module never duplicates the physical asset.

An owner can be an `owner` or `authorized_manager`; both use the verified owner workflow. A professional is not stored as a physical asset. Their `event_service_profile` is attached to the authenticated profile already used in the Manage App.

## Booking flow

Individual equipment/service requests create a private one-item event plan and plan item. This is intentional: a request for 50 chairs and a request for one MC use the same allocation, quotation, agreement, cancellation and audit machinery as a complete multi-provider ceremony, without forcing the customer through the package builder.

1. The customer creates one `event_plan` with occasion, UTC period, location, attendance and budget.
2. Selected equipment and services become `event_plan_items`.
3. Each owner/provider receives a notification and confirms independently.
4. Equipment confirmation uses a database transaction, advisory lock and overlapping-allocation sum. Bundles allocate underlying stock.
5. Professional confirmation checks unavailable periods, existing bookings and travel buffers inside the database transaction.
6. A plan is `partially_confirmed` until every required item is confirmed, then becomes `fully_confirmed`.
7. The coordinator sends a revisioned itemized quote. The database rejects acceptance when a required provider is unconfirmed or the quote has expired.
8. The coordinator sends final terms. Customer acceptance promotes held allocations to confirmed bookings.
9. Provider cancellation releases allocations, records the cancellation, alerts the customer and opens an emergency escalation.

## Financial boundary

`event_payment_obligations` separates deposits, balances, transport, setup, cleaning, service fees and refunds by provider/item. Every record has `collection_enabled = false`; this is accounting and planning data, not escrow or authorization to collect funds.
