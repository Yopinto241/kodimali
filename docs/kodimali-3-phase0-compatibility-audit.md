# KODIMALI 3.0 Phase 0 compatibility audit

Date: 2026-10-26

Scope: local repository only. No Supabase migration was applied, no Edge Function was deployed, and no live payment feature was activated.

## Executive assessment

KODIMALI already has substantial booking and marketplace foundations. The safe path is an additive compatibility layer around the existing `booking_requests`, canonical `rental_assets`, `asset_reservations`, Events inventory, chat entitlements, and SonicPesa order records. Rebuilding these domains would risk historical records and should not be done.

The current implementation is not yet compliant with the KODIMALI 3.0 financial contract. In particular, ordinary booking checkout collects a configurable flat reservation fee rather than a 25% deposit on an immutable agreed total; Events defaults to a 30% deposit; a complete double-entry financial core does not exist; cancellation allocations are not implemented; and several payment/retry boundaries require hardening before live use.

## Existing implementation by domain

| Domain | Existing authoritative implementation | Compatibility assessment |
| --- | --- | --- |
| Customer identity | Supabase Auth, `profiles`, web login/register, Customer App repository | Reusable. Protected actions already require authentication. |
| Roles | `user_roles`, `agents`, `owner_profiles`, admin role/permission tables | Reusable, but financial permissions need finer separation and consistent use. |
| Owner authority | `owner_applications`, `owner_asset_claims`, owner agreement acceptance | Strong foundation. Asset authority is distinct from listing creation. |
| Canonical inventory | `rental_assets`; listings reference `asset_id` | Correct foundation for shared inventory. Events still use dedicated allocation tables and need a unified availability bridge. |
| Listing verification | agent/owner verification, listing publication rules, asset verification history | Reusable. Instant-booking eligibility must be explicit and must not be inferred only from publication. |
| Booking | `booking_requests`, category dates, owner approval state, status history | Reusable compatibility aggregate. It lacks immutable pricing/agreement snapshots and a complete state-transition gate. |
| Availability | `asset_reservations` with held/confirmed periods; availability RPC | Good base for rentals. Quantity inventory and professional buffers remain separate in Events. |
| Holds | automatic 30-minute hold and scheduled expiry | Matches the requested initial duration. Late-payment recovery is incomplete. |
| Customer dashboard | web account/request views and Customer App booking repository | Existing My Bookings visibility is usable but does not yet expose the full deposit/balance/refund/fulfillment model. |
| Provider dashboard | Manage App agent/admin booking tabs; web owner/manage portals | Existing booking visibility is reusable. Calendar, obligations, settlement, and disputes are incomplete. |
| Booking chat | booking conversations/messages plus separate listing paid chat | Reusable. Essential confirmed-booking communication must remain free. Attachment, retention, abuse/blocking controls need review. |
| Paid listing chat | `listing_chat_payments`, `listing_chat_access`, conversations/messages | Existing entitlement model is reusable for `paid_chat_unlock`. Product naming and refund/reversal linkage need normalization. |
| Contact unlock | separate contact payment flow and entitlement behavior | Preserve as a distinct product. Provider disclosure authorization and leak review remain required. |
| Payments | `platform_payment_orders`, SonicPesa adapter, signed webhook, legacy product payment tables | Useful adapter foundation, but not yet a unified financial core. |
| Events | equipment, professionals, allocations, service bookings, plans, quotes, agreements, individual bookings | Rich existing module. Discovery can remain unchanged. Payments and inventory need compatibility with the unified booking/ledger model. |
| Referrals | submissions, follow-ups, agreements, rewards, payouts | Reusable and already separates contributors from booking authority. Reward accounting needs ledger obligations and reversals. |
| Notifications | database notifications, triggers, Firebase dispatch | Reusable. Delivery deduplication/retry evidence needs strengthening. |
| Refunds | generic `payment_refunds`, booking refund status, Events cancellation records | Fragmented. No authoritative allocation engine or complete refund state machine. |
| Settlement | owner statement entries and agent wallet/accounting records | Not a complete provider-payable/settlement system. Existing comments correctly state that these are not escrow. |
| Audit | general `audit_logs`, Events audit log, status history | Partial. Not every privileged financial/status action is immutably audited. |

## Current booking flow

1. An authenticated customer submits a category-specific period through `create-booking-request`.
2. The Edge Function validates the public listing and calls `create_authenticated_booking_request`.
3. Verified reservable inventory can create a 30-minute hold and mark the request ready for payment.
4. `create-platform-payment` calls `prepare_booking_for_payment` and creates a SonicPesa order.
5. A signed SonicPesa webhook calls `finalize_platform_payment`.
6. The payment transaction is recorded, the reservation is confirmed, and the booking becomes confirmed.

This skeleton is compatible with KODIMALI 3.0, but the amount currently comes from `reservation_fee_tzs`, not from an agreed booking total and 25% deposit calculation.

## Current payment flow and critical findings

1. `platform_payment_orders` currently supports only `booking_reservation`, `event_deposit`, and `event_balance`.
2. Contact unlock, paid chat, listing publication, and subscriptions use separate product tables and share the SonicPesa webhook through fallback table scanning.
3. Booking payment preparation returns a flat reservation fee.
4. Events use `event_deposit_percent = 30`, which conflicts with the required default 25%.
5. Migration `20261025213000_unified_sonicpesa_checkout.sql` sets booking, Events, contact, chat, and subscription payment flags to true. This conflicts with the requested controlled rollout and must be superseded by a safe migration that defaults unapproved financial automation to disabled without silently changing an operator's existing explicit choice.
6. Webhook HMAC verification and provider-event deduplication exist.
7. The webhook does not currently validate payload amount, currency, customer reference, and payment purpose against the stored order before finalization.
8. The webhook event is inserted before finalization. If finalization fails, a provider retry can hit the unique event ID and return `duplicate: true` without reprocessing the failed event. A retry-safe processing state and reconciliation path are required.
9. Payment success after an expired hold is not explicitly routed to safe reallocation or refund/reconciliation.
10. `update-booking-status` accepts a caller-supplied next status and writes with service-role privileges after only an agent/admin ownership check. It needs an allow-listed transition function and granular authority checks.

## KODIMALI 3.0 gaps

### Booking and agreement

- Explicit booking modes: `not_bookable`, `request_booking`, `instant_booking`.
- Explicit owner/provider instant-booking authority per asset/offering.
- Immutable booking price, fee, cancellation-policy, agreement, and timezone snapshots.
- Deterministic category pricing and precise 25%/75% split.
- Structured pickup, delivery, driver, quantity, location, duration, and fulfillment inputs.
- A validated booking state machine shared by Edge Functions, web, and mobile clients.

### Financial core

- Typed payment intents/products covering all requested products.
- Integer TZS amounts as the canonical representation.
- Double-entry accounts, journals, postings, and reversing entries.
- Refund obligations, provider payables, settlement batches, commission and referral liabilities.
- Reconciliation queue and recoverable webhook processing.
- Separation of collections, liabilities, and earned KODIMALI revenue.

### Cancellation and customer protection

- Versioned policy bands and exact boundary calculations.
- Independent booking cancellation, refund, fee, compensation, commission, inventory, and settlement states.
- Provider-failure incidents, evidence, replacement proposals, partial remedies, and settlement suspension.
- Fulfillment milestones and a configurable dispute/release window.

### Communication

- Typed `paid_chat_unlock` product under the unified payment-intent architecture.
- Free support/dispute/refund/confirmed-booking communication rules enforced server-side.
- Structured negotiated offers and amendments.
- Attachment authorization, retention, spam/blocking, and support-access audit.

### Applications

- Short unified checkout and full price breakdown on web and Customer App.
- Complete booking detail, balances, receipts, cancellation, disputes, and fulfillment UI.
- Provider calendar, fulfillment queue, payables, disputes, and statements in Manage App.
- Permission-restricted financial control center with exports and immutable operations.

## Compatibility decisions

1. Keep `booking_requests` as the public compatibility aggregate and attach new immutable booking-order records to it.
2. Keep `platform_payment_orders` readable for historical transactions; introduce typed payment intents and ledger references additively.
3. Keep legacy contact/chat/commercial tables and bridge them to typed financial products rather than deleting or rewriting history.
4. Keep `asset_reservations` for time-based rental inventory and add quantity/professional allocation adapters for Events.
5. Keep existing status values readable; introduce validated transition functions and mappings instead of destructive enum replacement.
6. Never backfill existing listings as instant-bookable without explicit verified authority and a complete policy.
7. Preserve all existing booking, agreement, message, reward, payment, and audit identifiers.

## Recommended implementation order after this audit

1. Add feature flags and safe inactive defaults for new KODIMALI 3.0 financial automation.
2. Add booking configuration, authority, immutable quote/agreement snapshot, and state-transition tables/functions.
3. Add integer-safe 25% deposit and 75% balance calculations with boundary tests.
4. Harden holds, webhook inbox processing, payment validation, and late-payment reconciliation.
5. Add the double-entry ledger and bridge existing payment products.
6. Add cancellation/refund calculations and liabilities.
7. Extend customer/provider dashboards and mobile repositories.
8. Add fulfillment, incidents, disputes, settlement readiness, and external-deal tracking.
9. Complete admin financial reporting and automated tests.

## Operational blockers that remain intentionally inactive

- Paid-chat price approval.
- Under-24-hour/no-show cancellation allocation.
- Category balance deadlines.
- Long-term tenancy cancellation rules.
- Dispute-window duration.
- Provider payout timing and lawful payout mechanism.
- Tax and payment-processing treatment.
- Automated refunds and settlements.

