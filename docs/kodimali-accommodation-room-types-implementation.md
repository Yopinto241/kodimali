# Accommodation room types and independent lodge operations

Implementation date: 7 November 2026. Deployment status: **local implementation and verification; no production accommodation migration applied**.

## Existing implementation

The repository has one Next.js marketplace and Manage portal, Customer and Manage Flutter applications, shared Flutter components and a Supabase backend. The accommodation workspace was being implemented in this same repository when the room-type update arrived. Its migration is unreleased. The update extends that migration and those screens rather than creating another application or a second inventory.

Read-only production inspection found no `lodge_*` accommodation tables or existing `lodges-guesthouses` category. Existing marketplace payment/contact functions were inspected without changing payment settings. This compatibility check must be repeated immediately before a live release.

The additive migration is `supabase/migrations/20261107120000_independent_lodge_workspace.sql` (SHA-256 of LF-normalized SQL `2f3bcfcaff7eeb736f12fd6e8fd2a22a1ba89306c0b6d33a86865f7853630483`). It adds the accommodation inventory, membership/invitation/application, guest/reservation/enquiry, lodge-reported payment, audit and idempotency tables; scoped RPCs; private `lodge-media` storage; and the dedicated marketplace category. It adds no lodge payment-provider function and rewrites no existing rental/payment function.

## Inventory and authorization

`lodges → lodge_room_types → lodge_rooms` separates the commercial offer from the real room. Room types own description, one nullable `main_image`, nightly price, currency, facilities, bed configuration, capacity and activation state. Physical rooms have a lodge-unique trimmed, case-insensitive code, assigned type, readiness condition, maintenance notes and calendar.

Physical-room descriptive columns are a server-maintained compatibility projection of the type; the trigger replaces client values and propagates type edits. They are not independent prices. All foreign relationships are lodge-scoped. Room types with upcoming accepted reservations cannot be deactivated or have capacity reduced below accepted occupancy. Rooms with upcoming accepted reservations cannot be deactivated or reassigned to another type.

Separate membership and permissions support owner, manager, receptionist and housekeeping. Owning a lodge does not grant general marketplace administrator authority. Staff invitations are account invitations with expiry and explicit acceptance. All client table writes are revoked; permission-checked RPCs, RLS reads and audit records enforce the tenant boundary. Removed membership takes effect on the next request. Super Admin reviews publication.

## Availability and allocation

`lodge_room_bookable` is the shared server predicate. It requires active inventory and type, valid stay dates, no conflicting accepted reservation or dated maintenance block, operational readiness for an immediate arrival and the lodge's same-day turnover policy. Date ranges use `[arrival, departure)`. Current maintenance/out-of-service conditions remain unavailable until staff explicitly release them; dated maintenance blocks cover planned maintenance.

Public responses expose aggregate counts only. Current physical occupancy, cleaning, maintenance, immediately bookable inventory and selected-date availability are different values. They never include room codes, guest identity or staff notes. Public date counts respect the lodge's availability-publication setting.

`lodge_enquiries` stores a customer's selected type, dates and quoted terms, without reserving a physical room. `confirm_enquiry` locks the lodge, rechecks availability, selects an eligible physical room and creates the confirmed reservation in one transaction. The GiST exclusion constraint is the final protection against conflicting allocations across every channel. Repeated confirmation returns the same allocation. Walk-in, phone, WhatsApp and marketplace requests share `lodge_reservations`; there is no parallel availability ledger.

Accepted terms snapshot type identity, description, facilities, capacity, price, currency, total, dates and applicable check-in/out policies. A price edit cannot change an existing quote or accepted reservation. Staff may reassign an upcoming accepted reservation to another compatible room of the same type; changes to accepted commercial terms are rejected. A customer-accepted revised-offer workflow is not yet provided; staff cannot use that absence to change an accepted offer.

## Payments and notifications

Lodge payments are explicitly **lodge-reported, not KODIMALI-verified**. The append-only local payment table supports positive receipts, reversals and atomic corrections. An operation UUID protects retries from duplicate reservations or payment records. Reports group by currency. No lodge operation creates a marketplace payment intent, invokes a payment provider, collects a rental deposit or changes ordinary rental cancellation rules.

Requests, confirmations and cancellations enter the existing notifications/outbox pipeline with private destination routes and no guest details in push bodies. Account-scoped request status is also available inside lodge details. Actual background delivery still depends on the existing production worker, device permissions and token registration; isolated tests do not prove delivery to a physical device.

Public phone/email responses obey the global contact-payment gate: free contact may expose the approved lodge contact; paid mode redacts it. **Paid lodge contact unlocking is not yet wired to an accommodation-specific entitlement/checkout**. Do not expose contact details or substitute rental checkout to work around this gap.

## Website and Flutter

Public `/lodges` and `/lodges/[id]` use the existing marketplace category convention. Manage has dedicated lodge pages for room types, rooms, calendars, reservations, guests, lodge payments, staff, reports and settings. Customer Flutter opens the same public experience from the accommodation category and domain links. Manage Flutter uses dedicated routes rather than granting ordinary agent/admin access to lodge owners.

Room-type cards use configured descriptions, capacity, facilities, real prices and one representative photograph. Existing signed private storage, upload validation, compression and image components are reused. Missing photographs use a placeholder; no generated inventory images are used. Ordinary listing cards retain their compact dimensions and detail photographs remain large.

`packages/flutter_core/lodge-forms.json` is the shared form/permission definition; `scripts/sync-lodge-forms.py` generates the Dart definition. English/Swahili copy uses the existing shared catalog.

## Verification

All database checks use the isolated loopback database `kodimali_lodges_20261107`, cloned from an existing protected restoration. SQL fixtures roll back. Persistent browser/concurrency fixtures contain synthetic data only. No real guest bookings, customer transactions or provider requests are created.

Verified so far:

- Migration application and SQL/RLS suite, including cross-lodge isolation, public privacy, room types/prices, unique room codes, dated blocks, check-in/out and cleaning, staff permissions, immutable receipts/reversals and no marketplace payment intents.
- Customer requests do not block inventory; confirmation allocates once, preserves a quote after a price edit, exposes confirmation only to its customer and writes the existing notification pipeline.
- Two concurrent staff reservations for one physical room yield one success and one conflict. Retried payment produces one record; atomic correction preserves the correct net amount.
- Shared Flutter core suite: 14 passing tests, including retry preservation, date forms, public browsing, configured room-type prices/placeholders and controlled error messages.
- Manage Flutter: 52 passing tests, including room and room-type routes at phone/tablet widths and housekeeping permission boundaries. Customer Flutter: 37 passing tests.
- Website production build, TypeScript and targeted ESLint checks pass. Browser flows at 390px and 1440px cover type/room creation, date calendars, walk-in/telephone reservations, check-in/out, lodge-reported payment, customer room-type request and staff confirmation, private customer status, no horizontal overflow and cross-lodge denial. No payment-provider call was made by these accommodation flows.
- Existing dynamic listing-payment suite: eight passing tests. Existing payment-access browser suite: eight passing cases, including free contact/chat and verified paid WhatsApp continuation.
- All 576 pre-existing public database function definitions and execution grants match the protected baseline exactly.

The 20 existing database regression suites numbered 027–045 were run against both a separate baseline clone and the accommodation database, using pgTAP plus a test-only compatibility helper for the suites' `function_is_definer` assertions. Fourteen suites pass; six have **identical baseline failures**, with no accommodation regression. Those six cover historical default flags (027/036), historical provider nullability (032), payment-channel settings (042), an Events fixture missing `full_name` (042 Events), and a supervisor fixture failing the Super Admin guard (043). Production flags and unrelated security controls were not changed to satisfy these old fixtures.

Customer and Manage analysis found no errors. Shared-core analysis retains one pre-existing informational brace lint in `push_device_lifecycle.dart`; that unrelated file is unchanged. Test drivers: `supabase/tests/046_independent_lodges.sql`, `scripts/test-lodges-postgres.py`, `scripts/test-lodges-browser.py`, shared Flutter lodge-flow tests and Manage navigation tests. Test database DSNs must be supplied through `KODIMALI_LODGE_TEST_DSN`; both database drivers reject non-loopback/non-isolated databases.

## Production deployment procedure

1. Finish the unresolved implementation and verification items below; review the final SQL and diff.
2. Recheck current production schema, existing category slugs, function compatibility and migration history using read-only access.
3. Inspect available recovery capabilities. Existing protected logical backups and a successful isolated restoration are available from earlier work; create a fresh, consistent authorized production recovery set immediately before release. Include required schemas/data, roles and configuration, securely outside this repository. Validate archive integrity and restore into an isolated database where feasible. Do not publish backup paths containing credentials or customer data.
4. If backup creation or restoration verification fails, continue preparation and safe tests but do not apply data-risking production changes. Neither paid PITR nor a staging subscription is required.
5. Apply the reviewed additive accommodation migration first. Verify RPC grants, RLS, private storage and unchanged marketplace payment controls. Deploy compatible website and mobile source only after backend verification. No new accommodation payment-provider Edge Function is required; reuse the reviewed notification pipeline.
6. Verify anonymous discovery/privacy, authorized staff access, free/paid contact boundaries and notification routing with authorized synthetic checks. Do not create real guest stays or financial transactions during release verification.
7. If the frontend must be rolled back, restore the previous frontend deployment and leave the additive tables intact. Do not drop accommodation/customer records as a rollback mechanism.

No APK/AAB has been built, installed or published for this task. No accommodation change has been deployed to Cloudflare or production Supabase.

## Remaining release requirements

- Complete paid accommodation contact entitlement integration while preserving existing contact rules.
- The six identical pre-existing database-suite failures above need separate fixture/policy maintenance; they were not silently waived or repaired by changing production controls.
- Physical-device notification delivery verification remains a production/device check, not a claimed outcome of local tests.
- A revised commercial offer requires a future explicit customer-acceptance flow; accepted offers remain immutable in this version.
