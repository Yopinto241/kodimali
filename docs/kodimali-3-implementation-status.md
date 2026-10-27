# KODIMALI 3.0 implementation status

Status date: 2026-10-27

This document describes the code currently implemented in the repository. It is not a production-activation record. The KODIMALI 3.0 migrations have not been applied to the live Supabase project and no deployment was performed.

## Architecture overview

KODIMALI keeps its existing Next.js website, Customer Flutter app, Manage Flutter app and shared Supabase project. New behavior is additive:

- Existing `booking_requests`, listings, canonical assets, chat and Events records remain in place.
- `booking_configurations` controls `not_bookable`, `request_booking` and `instant_booking` without silently enabling old inventory.
- `booking_terms_snapshots` stores the immutable accepted price, 25/75 split, cancellation snapshot, provider obligations and agreement version.
- `payment_intents` is the typed payment authority. Provider orders reference an intent; only a verified server callback can finalize collection.
- Immutable journals and postings separate collected cash, provider liabilities, refund liabilities, platform revenue, commissions and rewards.
- Fulfillment, incidents, cancellations, refunds and settlements have independent states.
- All new automated financial features default to disabled feature flags.

## Roles and permissions

| Role | Allowed | Not allowed |
| --- | --- | --- |
| Visitor | Browse/search/check general availability | Pay, book, view private records |
| Customer | Accept terms, pay deposit/balance, view own booking/payment state, report incidents | Confirm provider payment, modify ledger or settlement |
| Verified owner/provider | Configure authorized assets, see assigned bookings, confirm real fulfillment | Gain ownership from listing authorship, edit financial history, release own settlement |
| Authorized agent | Operate only delegated/assigned bookings and assets | Inherit owner authority automatically |
| Contributor | Submit and track permitted referrals | Approve bookings or receive rental payments |
| Finance/support/admin | Permission-scoped reconciliation, refund, dispute and settlement oversight | Arbitrarily edit posted journals |

## Booking state machine

The new transition validator retains existing states but records every accepted transition in `booking_state_events`. The intended customer path is:

`draft/request -> terms offered -> terms accepted -> inventory hold -> deposit awaiting payment -> deposit verified -> confirmed -> active/fulfillment -> completed`

Cancellation, expiry, rejection, incident and dispute paths remain explicit. A hold is not a confirmed booking. Existing listings are seeded as `request_booking`; they are not silently converted to Instant Booking.

## Payment state machine

`created -> awaiting_payment -> processing -> verified_paid`

Failure branches are `failed`, `expired` and `reconciliation_required`. Post-payment branches are `refund_pending`, `partially_refunded` and `refunded`. Frontend success never confirms money. The SonicPesa webhook validates event identity, amount and currency, is retry-safe and sends mismatches to reconciliation.

The accepted total is split deterministically:

- Deposit: 25%.
- Balance: total minus deposit.
- Deposit plus balance always equals the accepted total in integer TZS units.

Events deposits and balances use the same typed payment-intent, webhook and ledger path. An accepted Events quotation and agreement are snapshotted into intent metadata and use the same deterministic 25/75 split; existing Events APIs and historical obligations remain readable.

Web and Customer App event-plan views derive paid deposit and balance from verified typed intents, show both outstanding amounts and expose balance payment after deposit confirmation. Individual equipment and professional bookings continue through their generated event plan, quotation and agreement, so they share this payment path rather than creating another payment database.

KODIMALI 3 collection endpoints now call a shared payment-provider adapter rather than importing a specific provider throughout checkout logic. Each platform order persists the adapter that created it, status checks dispatch through that provider, and the SonicPesa webhook only claims SonicPesa-owned platform orders. SonicPesa is the only currently implemented KODIMALI 3 adapter; selecting an unapproved provider fails explicitly rather than guessing or silently falling back.

## Financial ledger

The financial core contains accounts, immutable journals and balanced postings. Separate liabilities and reporting are retained for provider payables, customer refunds, agent commissions and referral rewards. Paid chat and contact unlock are distinct products. External deal values are reported separately and are never presented as KODIMALI-collected money.

The Manage App financial control summary separates booking collections, outstanding balances, provider payables, refund liabilities, booking/chat/contact revenue, commissions, referral rewards, verified external-deal value and reconciliation cases.

The Financial Control Center also has an audited, permission-scoped payment-intent activity feed. Administrators can filter by date, product, status, booking, controlling provider, category and payment provider, then copy the filtered rows as CSV. This feed is read-only and cannot mutate posted journals or balances.

Refund and settlement operations are now separated into controlled stages. An authorized refund administrator may prepare only an approved refund and only while the automated-refunds flag is enabled; only the service role may record the payment provider result. Provider payables are grouped into draft batches, a different authorized administrator must approve the batch, and only a flag-gated service callback may record payout success. Failed payout batches place unsettled payables on hold and require an audited administrator review before those payables become eligible again.

The Manage App now lists refund obligations, selectable eligible provider payables, settlement batches and reconciliation cases. Payment administrators can start an investigation or close a discrepancy with a mandatory note. Closing or writing off a reconciliation case records the decision and audit trail only; it never edits posted ledger balances.

Approved cancellation allocation posts an idempotent balanced journal only when the full paid amount is already represented by verified KODIMALI 3 payment intents. Legacy or incomplete ledger coverage creates a reconciliation case instead of inventing cash or liabilities. Verified refund and settlement results clear the corresponding liability against payment-provider clearing through separate balanced journals.

External deals are submitted through an authorization-checked RPC. A declaration must relate to exactly one listing or referral, and the caller must be its assigned agent, verified controlling owner, contributor or an authorized administrator. Providers can review their declarations in the Manage App; payment administrators can verify, reject, dispute or advance their review status. Declared value remains outside KODIMALI collection and revenue totals.

## Cancellation policy matrix

| Time before agreed start | Customer | Provider | KODIMALI |
| --- | ---: | ---: | ---: |
| At least 14 days | 100% | 0% | 0% |
| At least 6, below 14 days | 90% | 0% | 10% |
| At least 4, below 6 days | 40% | 50% | 10% |
| At least 24 hours, below 4 days | 20% | 70% | 10% |
| Below 24 hours / no-show | Inactive until approved | Inactive until approved | Inactive until approved |

Calculations operate on the eligible amount already paid, not an unpaid future balance. Cancellation workflow tracks booking, refund, provider compensation, commission, reward, inventory and settlement outcomes independently.

The pgTAP matrix now covers exactly 14, just below 14, exactly 6, just below 6, exactly 4, just below 4, exactly 24 hours, the required under-24-hour rejection, partial-payment balancing, zero-paid allocation and deterministic rounding.

## Customer journey

Web and Customer App booking details show accepted total, deposit, balance, due date and separate payment actions. Payment initiation uses a stable idempotency key and a 30-minute inventory hold. Legacy booking checkout remains available as a compatibility path until the new flags and migrations are activated.

Eligible Instant Booking listings now expose an authoritative server quote after the customer selects the period. The quote contains the exact unit calculation, fees, total, 25% deposit, 75% balance, linked cancellation-policy version and owner-agreement version. Checkout locks the listing again and rejects a changed quote fingerprint before atomically creating the inventory hold and accepted immutable terms. Web and Customer App use this path; Request Booking remains separate.

My Bookings remains account-linked. The provider workspace now displays the same accepted terms and payment progress, plus fulfillment tasks, incidents and settlement state.

Customer booking details on Web and Customer App also expose cancellation tracking, refund state, problem reporting, fulfillment confirmation and customer acceptance/rejection of proposed substitutes. The short inventory-payment hold is intentionally handled in the backend and is not presented as an extra customer step; the visible flow remains choose, book, pay deposit and receive confirmation.

The invisible inventory-payment hold is configurable per rental listing from 5 to 60 minutes and defaults to 30. Events may use the same bounded setting through their approved rollout-flag configuration. The duration is stored in payment-intent metadata for audit, but remains an internal concurrency control rather than a customer-facing workflow step.

## Provider journey

The assigned verified provider sees the booking, customer follow-up, payment state, fulfillment milestones, protection cases and expected settlement status. A provider can confirm a fulfillment milestone through an authorization-checked RPC. That confirmation is audited and does not release payment; customer/admin verification and dispute controls remain separate.

Verified owners can configure each listing connected to a verified asset as Booking Off, Request Booking or Instant Booking in the Manage Owner Workspace. Instant Booking requires an active published listing, verified canonical asset and owner claim, accepted owner agreement, active policy, deterministic pricing and reliable availability. The owner can also set the bounded checkout protection duration. Listing authorship by itself grants none of these controls.

Verified owners can explicitly delegate booking, availability, fulfillment and customer-communication scopes for a specific asset to an active verified agent. Delegations are revocable and audited. Offering financial terms and confirming provider fulfillment now require controlling-owner authority, an explicit active delegation or administrator authority; merely creating the listing is insufficient.

Verified deposit or reservation transactions idempotently create category-specific milestones for homes/apartments, vehicles, offices and halls, and notify the customer and assigned provider. Admins with cancellation permission can review the exact customer/provider/platform allocation before approval or rejection; approval creates liabilities and releases inventory but does not automatically transfer money.

Push delivery uses the existing unique notification outbox. The dispatcher now recovers interrupted jobs, uses bounded exponential retry, records attempt and terminal timestamps, and reopens recent no-device failures when the user registers a device. This improves delivery reliability without enabling a new scheduler or financial automation.

## Admin financial workflow

Administrators with the relevant permission can view the read-only financial control summary. Existing payment toggles remain. Paid-chat price is now configurable and audited rather than hard-coded. If the approved amount is below the payment-provider minimum, checkout refuses clearly instead of silently increasing the charge.

KODIMALI 3.0 rollout flags are separate from the legacy marketplace availability switches. Only a Super Admin can activate them, activation requires an approval note, and every change is audited. Booking and Events deposit/balance payments, automated refunds and provider payouts remain disabled by default.

The legacy category-based reservation trigger is now gated by the authoritative listing booking configuration. A disabled global Instant Booking or deposit-payment flag safely falls back to Request Booking and does not create an inventory hold. Web listing details obtain the effective server-derived mode and show Booking Off, Request Booking or Book Now accordingly instead of assuming that every reservable category is instant.

## Chat and negotiation

Existing private listing chat and contact-unlock delivery are preserved. Their legacy payment rows are mirrored into typed `payment_intents`. A partial unique index prevents concurrent duplicate open paid-chat orders. Existing booking communication remains separate and free for essential fulfillment/support. Structured negotiated offers—not ordinary chat messages—can create official accepted terms after inventory revalidation.

## Security findings and controls

- New financial tables use RLS and permission checks.
- Provider payment visibility is limited to assigned bookings.
- Providers cannot mutate payment intents, journals, postings or settlement records.
- Privileged RPCs use fixed `search_path`, authorization and audit entries.
- Webhook amount/currency mismatch creates reconciliation rather than confirmation.
- Payment and webhook idempotency prevents repeated financial effects.
- Real credentials remain server-side and are not added to repository files.

## Files and migrations

Core migration sequence:

1. `20261026160000_kodimali_3_booking_authority_and_terms.sql`
2. `20261026170000_kodimali_3_financial_core.sql`
3. `20261026180000_kodimali_3_webhook_reliability.sql`
4. `20261026190000_kodimali_3_negotiation_fulfillment_protection.sql`
5. `20261026200000_kodimali_3_cancellation_workflow.sql`
6. `20261026210000_kodimali_3_booking_payment_intents.sql`
7. `20261026220000_kodimali_3_provider_booking_workspace.sql`
8. `20261026230000_kodimali_3_admin_financial_overview.sql`
9. `20261026240000_kodimali_3_legacy_access_payment_bridge.sql`
10. `20261026250000_kodimali_3_configurable_chat_price.sql`
11. `20261026260000_kodimali_3_customer_fulfillment_confirmation.sql`
12. `20261026270000_kodimali_3_fulfillment_seeding_notifications.sql`
13. `20261026280000_kodimali_3_event_payment_intents.sql`
14. `20261026290000_kodimali_3_rollout_flag_control.sql`
15. `20261026300000_kodimali_3_external_deal_authorization.sql`
16. `20261026310000_kodimali_3_notification_delivery_reliability.sql`
17. `20261026320000_kodimali_3_financial_activity_reporting.sql`
18. `20261026330000_kodimali_3_refund_settlement_operations.sql`
19. `20261026340000_kodimali_3_payment_provider_adapter.sql`
20. `20261026350000_kodimali_3_reconciliation_review.sql`
21. `20261026360000_kodimali_3_configurable_inventory_hold.sql`
22. `20261026370000_kodimali_3_owner_booking_configuration.sql`
23. `20261026380000_kodimali_3_booking_mode_enforcement.sql`
24. `20261026390000_kodimali_3_public_booking_capability_batch.sql`
25. `20261026400000_kodimali_3_atomic_instant_booking_checkout.sql`
26. `20261026410000_kodimali_3_owner_agent_delegation.sql`
27. `20261026420000_kodimali_3_cancellation_and_incident_completion.sql`
28. `20261026430000_kodimali_3_booking_policy_linkage.sql`

Corresponding pgTAP files are `014` through `041`. Application changes affect customer booking repositories/screens, Manage owner/booking/admin screens, web booking/chat components, the shared payment-provider adapter, platform/booking/payment/push Edge Functions and the SonicPesa webhook.

## Validation performed

- Next.js production build: passed.
- Customer Flutter targeted analysis: passed.
- Manage Flutter targeted analysis: passed.
- Deno checks for changed payment and notification Edge Functions: passed.
- Supabase migration filename/order checker: passed for 96 post-repair migrations.
- `git diff --check`: passed (line-ending conversion notices are warnings only).
- pgTAP database execution: not run because this workstation has no usable local Supabase CLI/database credentials. Test files exist but must not be reported as executed.

## Inactive decisions and operational blockers

The following must remain inactive until business/legal/provider approval: live deposit and balance collection, automated refunds, automated provider payout, below-24-hour/no-show allocation, category-specific balance deadlines, long-term cancellation overrides, dispute-window duration, settlement timing, safeguarding/delayed-settlement arrangements, compensation beyond refund, taxes and processing fees.

The new migrations must be applied in order to a disposable/local or confirmed staging database, pgTAP tests must pass, secrets and provider webhook configuration must be verified, and a controlled smoke test must complete before any production flag is enabled.

## Rollback and recovery

- Disable KODIMALI 3.0 feature flags first; existing legacy booking/chat paths remain available.
- Do not delete historical snapshots, intents, journals or events during rollback.
- Reverse financial effects with reversing journals, never updates/deletes of posted entries.
- Failed or mismatched callbacks stay in reconciliation for manual investigation.
- Database rollback should be forward-fix migrations because additive records may already reference the new tables.
