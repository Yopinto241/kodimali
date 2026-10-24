# KODIMALI Events implementation checklist

Branch: `feature/kodimali-events`

## Preserved foundations

- [x] Existing dirty worktree retained without reset or checkout.
- [x] Existing customer, agent, owner and admin authentication reused.
- [x] Existing locations, notifications, referrals, disputes and accounting concepts reviewed.
- [x] Existing financial collection remains disabled by default.

## Marketplace and data

- [x] Add Sherehe na Matukio top-level discovery category.
- [x] Separate occasion types from equipment and professional services.
- [x] Model quantity equipment, bundles and underlying shared stock.
- [x] Model professional profiles, offerings, portfolios and service areas.
- [x] Model one event plan with multiple provider components.
- [x] Add revisioned, expiring, itemized quotations.
- [x] Add server-transactional equipment and provider availability checks.
- [x] Add audit, disputes, emergency escalation and payment obligations.
- [ ] Connect verified event leads to Information Admin review UI.

## Experiences

- [x] Primary website and Customer Mobile navigation for Ceremonies & Events.
- [x] Events sub-navigation: equipment, professionals, advisor, builder, control center and bookings.
- [x] Website Events landing and equipment/provider discovery.
- [x] Website searchable individual equipment/service catalog with location, dates, price, sort and pagination.
- [x] Website equipment/service detail routes and individual booking requests.
- [x] Website individual booking history alongside complete event plans.
- [x] Website package item builder, quote acceptance and event history.
- [x] Customer Mobile Events discovery and initial event planner.
- [x] Customer Mobile individual detail, booking request and history screens.
- [x] Customer Mobile package items, quote/agreement acceptance and status history.
- [x] Manage Mobile equipment/service registration and provider schedule dashboard.
- [x] Manage Mobile individual approval and quotation actions using shared allocation locks.
- [x] Event Coordinator verification, itemized quotation, agreement and emergency dashboard.
- [x] Rules-based Event Advisor on web and Customer Mobile with approved templates and explainable recommendations.
- [x] Canonical venue/vehicle links from event plans to existing rental assets and booking requests.
- [x] Event fulfilment task, incident and coordinator-assignment schema.
- [x] Hall-agent category registration and separate hall-owner/authorized-manager registration on web and Manage Mobile.
- [ ] Interactive substitution proposal/approval screen (schema and audit model are present).
- [x] Notifications for provider requests, confirmations, quotes, agreements and cancellations.

## Verification and release

- [ ] SQL tests: quantity, bundles, schedule conflicts, quote expiry and RLS.
- [ ] Existing house/car/hall booking regression tests.
- [x] Next.js production build (2026-10-24).
- [x] Targeted Flutter analysis for all changed Events files (2026-10-24).
- [ ] Full Flutter test suites.
- [x] Apply Events migrations to the explicitly approved linked Supabase project (2026-10-24).
- [ ] Keep real event payment collection disabled until legal/provider approval.

## Environment verification (2026-10-24)

- Linked Supabase ref: `tlhoajedyaeaaqtrjqqh`, project name `kodimali`.
- The CLI metadata does not identify this project as staging. No remote migration was applied.
- Local Supabase could not start because Docker/Podman is not installed or not on PATH.
- SQL tests `011_kodimali_events.sql` and `012_kodimali_events_individual.sql` are ready, but are not reported as executed.
- SQL test `013_kodimali_events_business_module.sql` covers advisor, canonical rental links, operations and owner-registration trigger structure.
- Migrations `160000`, `170000` and `180000` were applied successfully to linked project `tlhoajedyaeaaqtrjqqh` after explicit user approval. A follow-up dry run reports the remote database is up to date.
- The existing `verify-agent` Edge Function is ACTIVE remotely and remains the approval boundary for agents; Events does not need a second duplicate verification function.
- Remote schema lint found pre-existing errors in chat lookup, growth expiry, trust summary and tenant token routines. These must be repaired and retested before a production release.

## Production release gate

1. Create or positively identify a disposable staging project.
2. Apply migrations through `20261024170000_event_public_catalog_individual_bookings.sql` in order.
3. Run all SQL tests, then the 200-chair concurrency scenario with separate role accounts.
4. Seed only approved test offerings; verify drafts, paused, rejected and suspended rows remain private.
5. Run full web/mobile regression, accessibility and responsive checks.
6. Verify notification delivery, quotation expiry, agreement acceptance, cancellation release and emergency escalation.
7. Confirm online collection remains disabled; do not add payment credentials for Events.
8. Back up production, schedule the release, apply migrations, then monitor database errors and allocation conflicts.
