# Events repairs — 29 October 2026

This implements the ten findings in `events-gap-audit-2026-10-29.md`, the previously identified owner-workspace/publication gaps, and two access problems exposed by behavioral tests.

## Implemented behavior

| Finding | Repair |
| --- | --- |
| Website booking fails after an asynchronous auth check | Capture the form before awaiting, validate dates, report failures and always clear the busy state. |
| Package suppliers cannot confirm | Confirm works for package requests and individual bookings; server checks caller ownership, request state and availability. |
| Individual booking prematurely confirmed | Agreement acceptance keeps payment-dependent bookings pending; verified deposit confirms the plan and individual booking together. Disabled online collection explicitly uses an offline arrangement. |
| Expired inventory can be revived | Shared resource locks and fresh quantity/calendar checks apply to provider confirmation, quotes, acceptance, checkout and verified deposit. Quote holds cover quote validity. A late unavailable payment is recorded for finance review rather than confirming stock. |
| Providers can alter approval fields | Triggers protect verification/publication. Material provider edits return entries to review; publishing requires verification. |
| Owner-only accounts cannot upload event photos | Ownership-scoped event-media write policy and approved-media read policy; equipment screen includes photo retry. |
| Query failures appear empty / stale results win | Separate catalogue errors and retry; discard superseded responses. |
| Only first 30 listings accessible | Web pagination, customer-app load more, and component-selector load more. Web catalogue exposes optional search, price, date and sort controls. |
| Partial/duplicate package submission | One atomic, idempotent website submission RPC; atomic resumable mobile draft submission. Correct service offering identifiers are used. |
| Incomplete cancellation/replacement | Provider cancellation, customer cancellation, coordinator replacement proposals, customer consent, supplier re-confirmation and revised price/terms consent. Finance records external settlements and late-payment refund/credit decisions; coordinator can resolve incidents after the required financial review. |
| Equipment-owner routing | Verified owners can open Events equipment from their workspace. The route no longer requires an agent identity. |
| Verified but unpublished equipment | Coordinator publication, pause, reject and suspend controls; equivalent provider/offering review controls. |
| Recursive plan/item RLS | Shared security-definer read predicate prevents policy recursion and keeps unrelated users out. |
| Owner cannot read their allocations | Scoped allocation read policy for the equipment owner. |

## Payment and replacement boundaries

- No payment feature flags were enabled or disabled by these repairs.
- No real customer payments, refunds or supplier approvals were exercised during verification.
- A replacement proposal does not itself reserve an unconfirmed supplier or authorize a new charge. It invalidates the previous quotation/agreement and creates a fresh provider request after customer consent.
- Finance-only refund controls record refunds already completed outside the application. They do not initiate a transfer. Completed refund records create balanced journal entries; duplicate references/settlements are rejected.
- Verified funds retained for a customer-approved replacement count against the new deposit and remaining total. The new terms still require customer acceptance.
- Money received after cancellation or an inventory conflict is recorded for review. Refunded webhooks remain terminal when replayed.

## Verification

- `python scripts/test-events-workflows.py`: disposable local PostgreSQL database, actual Events migrations/functions, shared-auth/account prerequisite fixtures; authorization, RLS, media permissions, rollback/idempotency, quote holds, cancellation, replacement consent, offline/online confirmation, late-payment review/refund/credit and webhook replay checks. Separate simultaneous PostgreSQL sessions verify equipment and professional allocation locking.
- `flutter test` in Manage: all 10 existing tests pass.
- Targeted Flutter analysis of changed customer and Manage files: no issues.
- Next.js production build and TypeScript validation pass. Cloudflare packaging/release and APK build outcomes are recorded below when complete.
- Migration naming/uniqueness check and `git diff --check` pass.
- Both final migrations were validated against the actual linked schema in a rolled-back transaction before application.

Local behavior tests do not replace signed-in device testing or a real provider/payment drill. No production test users or event inventory were seeded.

## Release

Applied to linked Supabase project `tlhoajedyaeaaqtrjqqh`:

- `20261029140000_events_workflow_repairs.sql`
- `20261029141000_events_recovery_workflows.sql`
- `20261029143000_event_payment_terms_consistency.sql`: a verified deposit must match the currently accepted quotation, agreement and deposit amount. Superseded-term payments are recorded for finance review.
- `20261029142000_events_admin_role_setup_dependency.sql`: fixes the obsolete `listings.category` reference in the financial report loaded by Growth Ops, so the role-assignment screen can load. The report was executed successfully against the linked schema in a rolled-back validation transaction before application.

The existing normal-marketplace `viti` listing was not moved, duplicated or deleted. The public Events catalogue remains separate, as requested. Equipment must be submitted through the equipment-owner Events workspace and reviewed before publication.


Website published to https://kodimali.com (Cloudflare Worker version `6ac7d6c2-491e-4691-8357-433b5a8efb67`). Public HTTP smoke checks returned 200 without server-error markup for Events, the planner, filtered listings, account Events, and the viti contact/chat/booking routes. Default Python user-agent requests were denied; a normal browser user agent succeeded.

The first concurrent Android packaging attempt exhausted local Java native memory. Packaging was retried sequentially. Manage release APK built successfully (63.7 MB).

Whole-schema live lint found no errors in the repaired Events routines. Seven pre-existing errors remain outside these repairs: `get_admin_listing_chat_conversation`, `agent_trust_summary`, `invite_tenant`, `accept_tenant_invitation`, `confirm_customer_fulfillment_milestone`, `configure_owned_listing_booking`, and `get_public_listing_booking_quote`. The eighth reported error, `get_admin_financial_activity`, was repaired because it blocked Growth Ops role setup.

## Using the repaired flow

1. Equipment suppliers register in Manage as Owner/Manager ? Equipment owner and wait for owner verification. After signing in with the updated Manage app, open Event equipment from Owner Workspace, add the item and photo, and submit it for review.
2. Professionals use approved Events agent accounts, then register their service profile and offerings in Events Workspace.
3. Coordinators use an existing confirmed account. A Super Admin assigns Event Coordinator under Growth Ops ? Administrative roles; the staff member signs in again in Manage. Coordinator is not a public signup choice.
4. The coordinator verifies/publishes equipment or professional offerings. The item then appears in the separate public Events catalogue.
5. Finance permissions are required to record settlements or resolve late-payment reviews. These actions record completed external refunds or customer-approved credit; they do not send money.


Final Android artifacts:

- `builds/events-repairs-2026-10-29/kodimali-manage.apk` ? 66,793,778 bytes.
- `builds/events-repairs-2026-10-29/kodimali-customer.apk` ? 65,437,924 bytes.
- `builds/events-repairs-2026-10-29/manifest.json` contains SHA-256 hashes and the website deployment version. Both are successful universal release APK builds; they are local installation artifacts, not app-store uploads.

The final behavioral suite additionally verifies atomic mobile draft retries and delayed deposits for superseded quote/agreement terms. The final terms guard was validated against the linked database schema in a rolled-back transaction before application.


Follow-up: the seven database errors recorded above were subsequently addressed by the role-workspace repairs. See [role-workspace-repairs-2026-10-29.md](role-workspace-repairs-2026-10-29.md) for the repairs and subsequent verification.
