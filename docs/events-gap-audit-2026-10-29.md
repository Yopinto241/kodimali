# Events gap audit — 29 October 2026

Repair implementation and verification: [Events repairs](events-repairs-2026-10-29.md).

Scope: repository review of website, customer app, Manage app and the latest applicable Supabase migrations. No application or database changes were made for this audit. No signed-in production account, payment, stock allocation or approval was exercised. These are source findings; deployed database policies and functions still need comparison against the repository.

The previously reported owner-workspace routing and verified-but-unpublished equipment controls remain outstanding. Additional findings follow.

## 1. Website individual booking reads the form after React clears its event reference — high

`apps/web/src/components/event-individual-detail.tsx:62–77` awaits `supabase.auth.getUser()` before constructing `FormData(event.currentTarget)`, and later calls `event.currentTarget.reset()` after another await. React clears `currentTarget` after dispatch; the installed React DOM implementation explicitly does this. A signed-in customer can therefore encounter a TypeError before the booking RPC, and the uncaught exception leaves the busy state set.

Repair: capture the form element and its values before the first await; use the captured element for reset. Add try/finally and a visible error. Validate start/end before converting dates. Verify one successful request, one rejected request and retry after failure.

## 2. Multi-item event providers have no confirmation action — high

`apps/manage_mobile/lib/features/events/presentation/events_provider_workspace_screen.dart:576` requires an individual-booking record with status `requested` before showing Confirm. A package plan item has no individual-booking record, so no button appears. `_confirmRequest` already contains a package branch, but the displayed action never reaches it.

Repair: offer confirmation for eligible package requests as well as individual requests, with server-enforced states. Test a plan containing both equipment and a professional.

## 3. Individual booking says confirmed before the payment flow confirms its plan — high

`supabase/migrations/20261024170000_event_public_catalog_individual_bookings.sql:82` installs a trigger that marks an individual booking `confirmed` when its agreement becomes accepted. The later `accept_event_agreement` definition in `20261025213000_unified_sonicpesa_checkout.sql:171` moves the parent plan to `payment_pending` and sets individual payment status to `pending`. It does not replace that trigger. These statuses can disagree even in one committed transaction.

Repair: use one authoritative state transition. Agreement acceptance must leave payment-dependent bookings awaiting payment; only verified payment should confirm them. Define the intended offline/disabled-payment behavior explicitly.

## 4. Expired stock and professional holds can be revived without a fresh availability check — high

The confirmation routines in `20261024160000_kodimali_events_foundation.sql` ignore holds whose expiry has passed when checking capacity. Providers create 24-hour holds, while the coordinator/provider quotation screens offer three-day quote validity. Quote acceptance checks provider-confirmed item statuses rather than whether the allocation is still valid. The Events payment branch in `20261026210000_kodimali_3_booking_payment_intents.sql:98–99` promotes held allocations to confirmed without checking expiry or reacquiring capacity.

An expired hold can stop blocking new requests, then a late payment can revive it after the same chairs or professional have been allocated elsewhere. The later configurable payment-intent expiry does not itself revalidate resource allocations.

Repair: coordinate quote, payment and inventory deadlines; recheck availability under resource locks before taking payment and before confirming late payment. Define refund/review handling when a late payment cannot secure inventory. Test overlapping requests with an expired hold.

## 5. Approval fields lack a separate server-side write boundary in the migration policies — high; verify deployed grants

`20261024160000_kodimali_events_foundation.sql:140,144,146` gives owners/providers ALL operations on their own equipment, professional profiles and offerings. The policies check ownership, but do not reserve verification/publication columns for coordinators. No later Events column guard was found. Under ordinary table write grants, a provider can set approval fields through the API rather than use the review screen.

Repair: compare live table grants and policies; restrict protected columns or enforce transitions in triggers/admin RPCs. Test that owners/providers cannot self-verify, self-publish, or change protected states after suspension. Do not rely on hidden UI controls.

## 6. Equipment-owner photo uploads conflict with existing storage permissions — medium

`events_provider_workspace_screen.dart:245` uploads event photos into `listing-media`. Its latest storage write policy in `20260720220000_listing_promotion_write_hardening.sql:70–98` admits admins or active agents writing their own paths. It does not admit an equipment owner who has no active agent role. Thus, fixing the owner route alone is insufficient for equipment photos. The item is inserted before upload, so upload failure can leave a partial submission.

Repair: add narrowly scoped verified-owner access for event media, check public reads for approved media, and make failed upload recovery visible. Verify using an owner-only account, not an account that is also an agent/admin.

## 7. Catalogue failures are shown as an empty marketplace — medium

`apps/web/src/components/simple-events-listings.tsx:50–57` ignores the RPC error and renders `data ?? []`. Customers cannot distinguish a failed query from no published equipment. There is also no stale-response guard when category/location/mode changes rapidly, so an older response can overwrite a newer selection.

Repair: separate loading, error and empty states; provide retry, and discard responses for superseded requests.

## 8. Listings beyond the first 30 are unreachable — medium

Both modes in `simple-events-listings.tsx` use limit 30 and offset 0, with no pagination or load-more control. Customer Mobile `customer_public_repository.dart:108` uses the same fixed first page. Published items after that page cannot be browsed through these screens. The active web screen also lacks the search/date/price/sort controls present in the older unused catalogue component.

Repair: add pagination/load more and clear applied-filter controls. Test with more than 30 published items. Keep availability explicitly tied to selected dates.

## 9. Package submission can leave partial or duplicate event plans — medium

`apps/web/src/components/event-plan-builder.tsx:83–148` creates the plan, adds each item, and requests the quote as separate RPC calls. An item failure leaves the prior plan/items saved. Submitting again creates a new plan. There is no rollback, reusable draft identity or submission idempotency key.

Repair: submit the plan/items atomically through one RPC, or retain and resume the same draft with idempotent item creation. Test failure on the second item and a retry.

## 10. Events cancellation and replacement recovery has no complete user interface — medium

The database defines `provider_cancel_event_item` and `event_substitution_proposals`. No calls to the Events cancellation function or Events substitution-table workflows were found in web/customer/Manage UI. The coordinator emergency screen offers assignment to `coordinating`, but not a complete propose-replacement/customer-acceptance/resolution flow. The ordinary rental-booking substitution UI uses different tables and does not complete this Events flow.

Repair: connect provider cancellation, customer notification, replacement proposal, customer acceptance/rejection and final escalation resolution. Preserve stock release and price disclosure.

## Verification gaps and repair order

Events tests `011` and `012` predominantly assert that tables/columns/functions exist. They do not prove correct role boundaries, concurrent allocation, expiry handling or completed user journeys. The implementation checklist also leaves behavioral SQL and full Flutter verification incomplete. No behavioral SQL tests were executed in this audit.

Recommended order:

1. Protect approval fields; fix the booking form, premature confirmation and expired-hold handling.
2. Connect equipment-owner routing/media and package-provider confirmation.
3. Complete publication, cancellation and replacement controls.
4. Add catalogue error handling/pagination and atomic package submission.
5. Test with separate customer, owner-only, professional, coordinator, Super Admin and unrelated accounts. Include overlapping quantity requests, expired holds, late payment, upload failure, denied self-approval and retry after partial failure.
