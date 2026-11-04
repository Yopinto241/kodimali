# KODIMALI platform audit — 3 November 2026

Audited commit: `2385eee`, branch `feature/kodimali-events`. Surfaces: Customer Flutter app, Manage Flutter app, Next.js website, and linked Supabase project `tlhoajedyaeaaqtrjqqh`.

## Assessment

The platform builds and its existing regression suites pass, but there are important authorization, paid-access, payment-state, notification privacy, and mobile recovery defects. Passing the current tests does **not** establish that every production workflow is safe. Prioritize F01–F07 before increasing payment traffic or adding staff accounts.

This audit changed no production records, settings, deployments, payments, or GitHub branches. Local test databases, browser fixtures, source downloads, and audit artifacts were created. Successful transactions were simulated locally; no customer account or real mobile-money transfer was used.

See [the feature coverage matrix](platform-feature-matrix-2026-11-03.csv) for individual features, evidence, defects, and outstanding acceptance checks. [The inventory](platform-audit-inventory-2026-11-03.json) enumerates web pages/API routes, Flutter screens, and Edge Functions. Features marked **reviewed** have source/contract review, not completed end-to-end certification.

## Evidence collected

| Check | Result and limits |
|---|---|
| Customer Flutter | Analysis: no issues. Existing tests: **17 passed**. No installed-device test. |
| Manage Flutter | Analysis: no issues. Existing tests: **46 passed**. No installed-device test. |
| Shared Dart packages | **10 tests passed** across four packages. |
| Website | Production webpack build, TypeScript, and ESLint passed. **26 library tests passed**. |
| Edge Functions | All **26 entry points** type-checked; **12 existing handler tests passed**. |
| SQL regressions | **14 scripts passed** in separate disposable databases. SEO fixture role creation was made repeatable in the runner because cluster roles already existed. |
| Event workflow integration | Passed **47 reported checks**, including competing equipment/service reservations, replacement credit, revised terms, cancellation accounting, and duplicate refunded finalization. This tests SQL behavior, not the HTTP webhook's ordering logic. |
| Management browser fixtures | Six widths, 320–1440 px: navigation, search, pagination, details, location hierarchy, denied links, scoped supervisor and Super Admin flows passed. Auth/API data were intercepted. |
| Event browser fixtures | 320/390/1440 px: validation, drafts, reload, quantity, availability, login recovery, submitted idempotency key and no overflow passed. |
| Registration browser fixtures | English/Swahili, phone/desktop: required hierarchy, typed-area reuse, stalled signup recovery, duplicate-account messages and submission payload passed. |
| Filter/browser recovery | Stalled lookup, retry, reversed prices, parent-only location, category navigation, GPS/manual/clear/save and delayed hydration passed. |
| Navigation/language | Production local server: repeated document navigation/back, broken RSC responses, blocked storage, English/Swahili switching and retained user values passed. |
| Add-listing/browser | All five publication modes passed in a diagnostic repeat: free, paid, approval, switch to free, zero-fee plan; JPEG preparation, failed-upload retry and one draft verified. The original test timed out awaiting its first preview; a repeat with a 2-second preparation pause passed. Treat this as test stability/latency evidence, not an independently confirmed product defect. |
| Production HTTP | **24 expected pages/endpoints returned 200**; health reported `ok`. Unknown route returned 404. Two association endpoints returned 404: F14. These are response checks, not authenticated workflow tests. |
| Production database metadata | **135 public tables, all with RLS**, **222 policies**, **529 function names**, **120 triggers**, **148 migration-history entries**. All local migration versions were present. RLS being enabled does not establish that its policies are sufficiently restrictive: F01. |
| RPC compatibility | **214 literal client RPC call sites**, **130 distinct names**: no missing functions or unexpected literal `p_*` argument names. Dynamic calls, parameter types, embedded relationship selections and every response shape are not fully verified by this scan. |
| Deployed source | Downloaded worker/webhook and several payment/availability functions match local source. Two legacy function downloads (`notify-agent`, `update-booking-status`) failed because the CLI expected multipart and received octet-stream; their deployed bodies were not independently compared. |
| Defect probes | Two SQL probes reproduced F01/F02. Three isolated Edge probes reproduced F03–F05. Four mobile probes asserted existing defects; the refresh probe actually failed with the documented Flutter assertion, reproducing F08. These probes assert faulty behavior and are not passing security regression tests. |

Evidence logs are under `tmp/platform-audit/`, plus `tmp/audit-{customer-tests,manage-tests,web-tests,web-lint,web-build,edge-tests,events-db}.log`. Private schema snapshots and downloaded server source stay in ignored `tmp/`; no customer rows or credentials are included in the report.

## Findings, ordered by priority

P1: address urgently because of unauthorized access, paid entitlement, payment correctness, or notification privacy. P2: material reliability, feature parity, or release issue. P3: usability/diagnostic quality. No production exploitation or financial loss was demonstrated.

### F01 — P1: legacy policies bypass restricted staff permissions

**Confirmed from deployed definitions and an isolated SQL reproduction.** `is_admin()` returns true for a user carrying the base `admin` role unless they are a scoped supervisor. Several older **permissive** policies still authorize `is_admin()` alongside newer policies that check individual permissions. Permissive policies combine with OR, so the newer policy does not close the older path.

The probe created an analyst with `analytics.view`, no `bookings.manage`, and no relationship to a fixture booking. The deployed `bookings_active_agent_or_admin_select` policy let the analyst read that booking's private phone field. This is a server authorization defect even though UI permission tests pass. Deployed policies for private locations, agents, profiles and marketplace settings also contain broad admin checks and need review; only the booking read was reproduced, not every write path.

Sources: `supabase/migrations/20261031110000_supervisor_territories_and_exclusive_agents.sql:24`; production policies captured in the ignored catalog; `scripts/audit-platform-policy-probes.py`. The legacy policy names were **not found in the checked-in migration chain**, so a repair must account for actual installed policies.

**Fix:** add a forward migration replacing/removing broad policies per domain, retain scoped-supervisor restrictions, and test analyst/marketing/finance/support/agent/owner/customer/anonymous identities through direct PostgREST queries. Do not rely on hidden navigation to enforce access.

### F02 — P1: the same chat payment can extend access repeatedly

**Confirmed in deployed SQL and an isolated reproduction.** `grant_listing_chat_access(uuid)` is SECURITY DEFINER, executable by `anon` and `authenticated`, with no caller authorization. Each call adds seven days and clears revocation, even when the same paid payment ID was already applied. Calling it twice with one fixture payment yielded at least 14 days.

There is also a normal-path double-grant risk: the `release_paid_listing_chat` trigger grants access on transition to paid, and `sonicpesa-payment-webhook` explicitly calls the grant again after updating payment status. Both definitions are present in production. A legitimate purchaser knows their own payment ID; no guessed victim ID is needed to replay their entitlement.

Sources: `supabase/migrations/20260729120000_paid_listing_chat.sql:99`, `:109`, `:116`; `supabase/functions/sonicpesa-payment-webhook/index.ts:189`; `scripts/audit-platform-policy-probes.py`.

**Fix:** revoke client execution, use service-only authorization, record exactly one entitlement grant per payment, and select one authoritative grant path. Preserve a separate intentional renewal transaction. Verify replay, concurrency and revoked-access behavior.

### F03 — P1: anyone can invoke the privileged push worker

**Confirmed in deployed source/config and isolated HTTP fixture.** `dispatch-push-notifications` has `verify_jwt=false`; its handler checks only the HTTP method, then uses the service role. An unauthenticated fixture POST performed two outbox updates and returned 200. With queued jobs it can initiate sends, retries and associated provider work. The fixture used an empty queue and never contacted Firebase; no live dispatch POST was sent.

Sources: `supabase/functions/dispatch-push-notifications/index.ts:77`, `:88`; `supabase/config.toml`; `scripts/audit-platform-edge-probes.test.ts`.

**Fix:** require a dedicated scheduler/worker secret or verified service identity before constructing the admin client or touching jobs. Test missing, invalid, user-level and worker credentials. Keep job claiming/retry behavior.

### F04 — P1: an out-of-order webhook can downgrade a terminal payment

**Confirmed in deployed source and isolated HTTP fixture.** The SonicPesa handler reads an existing platform order's status, but a non-paid callback unconditionally writes the incoming status. The probe supplied an already-paid order and a valid fixture-signed `INPROGRESS` event; the handler wrote `processing` and returned 200. Legacy payment branches also write incoming states directly.

Deduplication by provider event ID protects identical events, not distinct late events for the same order. There is no deployed `platform_payment_orders` trigger that closes this path. A later success may then attempt finalization again or conflict with an existing journal, creating inconsistent UI and reconciliation state. Actual duplicate money collection was not demonstrated.

Source: `supabase/functions/sonicpesa-payment-webhook/index.ts:152`, `:173`; `scripts/audit-platform-edge-probes.test.ts`.

**Fix:** enforce monotonic terminal transitions atomically, preserve paid/refunded outcomes, reconcile contradictory provider events, and test paid→processing, refunded→success, duplicate, concurrent and replayed events across both platform and legacy tables.

### F05 — P1: webhook finalization does not require amount evidence

**Confirmed in the deployed handler and fixture.** A validly signed `SUCCESS` platform callback without `amount` passes the mismatch condition and calls `finalize_platform_payment`. Missing currency defaults to TZS. The finalizer compares the internal order against the internal intent; it does not establish the amount actually reported by the provider. Legacy branches do not perform the platform branch's amount check.

This is a reconciliation weakness, **not evidence that an unsigned attacker can forge a payment**: the HMAC check is present and rejects invalid signatures. Whether SonicPesa guarantees all necessary fields on every real success callback still requires a provider contract and controlled integration test.

Sources: `supabase/functions/sonicpesa-payment-webhook/index.ts:81`; deployed `finalize_platform_payment_before_events_repair`; `scripts/audit-platform-edge-probes.test.ts`.

**Fix:** require verified provider order/transaction identity, exact amount and currency, or query the provider before finalizing. Missing or inconsistent evidence should enter reconciliation rather than unlock inventory/contact/chat.

### F06 — P1: notification injection and operational helpers lack caller authorization

**Source-confirmed; legacy deployed-body download unavailable.** `notify-agent` accepts caller-supplied agent ID, title and body, then inserts notifications using the service role. It does not check the caller or booking relationship. Its live gateway requires a JWT, which establishes identity but does not restrict the caller to operational staff. `mark-agent-delayed` similarly checks the booking/SLA but not caller authority. `update-booking-status` accepts any base-admin role rather than the granular permission set.

Sources: `supabase/functions/notify-agent/index.ts:9`, `:19`, `:39`; `mark-agent-delayed/index.ts`; `update-booking-status/index.ts`. Live metadata confirms all three exist with JWT verification enabled. No production notification or booking was changed.

**Fix:** make internal helpers worker-only or enforce the exact domain permission and ownership before service-role work. Test a valid customer session, restricted staff session, suspended agent and unrelated booking.

### F07 — P1: signing out leaves a push device attached to the previous account

**Source-confirmed in both apps and delivery worker.** Sign-out only calls Supabase Auth. Auth listeners attempt registration, but return when the user becomes null; neither unregisters/disables the old device association. The worker selects enabled device tokens by user ID without requiring an active session. A signed-out installation can therefore remain eligible for the old account's OS notification title/body until reassignment or token invalidation. Real-device delivery after logout was not exercised.

Sources: Customer `core/data/customer_account_repository.dart:169`, `core/notifications/push_notification_service.dart:90`; Manage `core/data/manage_repository.dart:418`, `core/notifications/push_notification_service.dart:70`; worker `index.ts:147`.

**Fix:** disable this installation's token while still authenticated, handle offline logout/retry, and register it only to the new account after switching. Test logout, account switch, token rotation and shared devices; avoid exposing sensitive notification text on lock screens.

### F08 — P2: Future-returning Flutter state callbacks fail refresh

**Reproduced runtime assertion.** The customer chat list calls `setState(() => _future = fetchListingChats())` every five seconds. The callback returns a Future, violating Flutter's state callback contract. The audit probe failed with `setState() callback argument returned a Future` at the real screen line 27. Similar assignments exist in requests, events, growth/information and tenancy refresh paths; these additional paths were inspected, not all independently exercised. The assertion establishes a debug/test failure, not that every release APK crashes.

Sources: `apps/customer_mobile/lib/features/chat/listing_chat_screens.dart:27`, `:58`; `features/account/customer_tenancy_screen.dart:36`; `scripts/audit_customer_findings.dart.fixture`.

**Fix:** assign inside a void-returning block, separate request work from state updates, retain loaded data while refreshing, prevent overlapping polling and stop timers when inactive.

### F09 — P2: unavailable chat details are shown as expired paid access

**Reproduced with a failed repository lookup.** The conversation FutureBuilder substitutes an empty map without handling loading/error. That makes the expiry null, displays “Chat access expired” and disables the composer. A transient failure is presented as an entitlement decision.

Source: `apps/customer_mobile/lib/features/chat/listing_chat_screens.dart:383` and the mobile audit fixture.

**Fix:** separate loading/unavailable/expired states; show Retry and retain the last confirmed entitlement during refresh. Keep the backend authoritative for sending messages.

### F10 — P2: stalled customer authentication has no app deadline

**Reproduced with a non-resolving login Future.** After two virtual minutes, sign-in remained disabled with no recovery message. Customer Auth repository methods forward sign-in/sign-up requests without an application timeout. Underlying network code may eventually time out; the UI does not provide a bounded outcome.

Sources: `apps/customer_mobile/lib/core/data/customer_account_repository.dart:139`, `:149`; `features/account/customer_account_screens.dart:960`.

**Fix:** bound waiting, restore controls and explain uncertain signup outcomes without automatically repeating account creation. Test slow/disconnected Auth and resume.

### F11 — P2: account switching merges the previous user's favourites

**Source-confirmed.** Saved snapshots use one device-global preference key. On account refresh, all local IDs absent from the new account's remote set are uploaded, then the union is persisted. Sign-out does not clear or scope this store. Account B can inherit account A's saved interests on the same installation. Guest-to-account merging is useful, but it must distinguish guest activity from another signed-in user's data.

Sources: `apps/customer_mobile/lib/core/cache/customer_activity_store.dart:16`; `features/account/customer_account_screens.dart:127`–`:133`.

**Fix:** namespace private activity by user ID, keep guest activity separate and offer an explicit one-time merge. Verify A→logout→B, guest→A, offline removal and remote synchronization.

### F12 — P2: cold-start Manage notification navigation is lost

**Source-confirmed ordering defect.** `PushNotificationService.initialize()` adds `getInitialMessage()` data to a broadcast stream. Manage subscribes to `notificationTaps` only **after** awaiting initialization, so the initial event has no listener. Real OS notification tapping remains untested. Manage's tap router also only handles `chat/`, while other payload route types need explicit handling or a documented landing-page fallback.

Sources: `apps/manage_mobile/lib/main.dart:39`–`:40`; `core/notifications/push_notification_service.dart:67`.

**Fix:** subscribe before initialization or retain/return the initial message; route booking, listing, payment and event notifications deliberately, with role checks.

### F13 — P2: checked-in availability gateway settings differ from production

**Confirmed configuration drift.** `supabase/config.toml:27` sets `check-availability` to `verify_jwt=true`; production metadata says false. The public website invokes it with a publishable API key, not a user session. Redeploying it from the current config can change/break anonymous availability checks.

Several user-facing functions still use gateway JWT verification while Auth publishes an ES256 key. Supabase's current official materials describe both legacy incompatibility and newer asymmetric support, so **this audit does not assert that all those calls currently fail**. A valid ES256 session smoke test is required; invalid-token 401 checks alone cannot prove compatibility.

**Fix:** explicitly configure every function's intended auth model and test public calls plus valid customer/agent/admin sessions on the deployed gateway. Never disable gateway checks on internal workers without adding handler authorization.

References: [Supabase 401 troubleshooting](https://supabase.com/kb/troubleshooting/edge-function-401-error-response), [current auth-header implementation documentation](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/functions/auth-headers.mdx).

### F14 — P2: verified mobile links are not deployed

**Confirmed by live HTTP.** Both `https://kodimali.com/.well-known/assetlinks.json` and `/.well-known/apple-app-site-association` returned 404. Customer Android declares a verified HTTPS listing intent. Browser fallback can still work, but automatic verified app opening is not established.

**Fix:** publish association documents using actual release certificates/Apple application identifiers, then test install, cold/warm start, listing links and password recovery on physical devices. Manage currently sends password recovery without an app redirect and has no recovery intent; its browser recovery journey needs an explicit acceptance test rather than assuming native recovery works.

### F15 — P2: release artifacts and distribution are not ready for certification

**Source-confirmed.** Both Android release build types use debug signing (`android/app/build.gradle.kts:44`). The preceding Manage APK attempts exhausted Windows native memory; this audit did not rebuild or certify an APK. `/download` has store-link placeholders. iOS signing/APNs/App Store readiness was not tested.

**Fix:** configure protected production signing, versioning and distribution; build on a machine/runner with sufficient memory, install the actual release builds, and test all platform integrations. Do not treat Flutter analysis as an installable-release check.

### F16 — P2: web lacks the Manage app's event operations workspace

**Source/inventory-confirmed parity gap.** Manage has `EventCoordinatorScreen` and `EventsProviderWorkspaceScreen`. The website offers public event discovery/planning and customer recovery, but `manageSections` has no events section and no corresponding provider/coordinator workspace. Web staff cannot complete the same event operations journey there. Whether this is a business requirement is a product decision; do not advertise full operational parity until resolved.

Sources: `apps/web/src/lib/manage-routes.ts:1`; `apps/manage_mobile/lib/features/events/presentation/`.

### F17 — P3: chat refresh pulls readers away from older messages

**Reproduced in a widget fixture.** A reader positioned 800 pixels into history was returned to offset zero by an incoming message. `_scrollToLatest()` is scheduled on every nonempty stream rebuild.

Source: `apps/customer_mobile/lib/features/chat/listing_chat_screens.dart:442`.

**Fix:** auto-scroll only near the latest message or after the user's own send; otherwise display a new-message indicator.

### F18 — P3: raw backend errors reach customer-facing UI

**Reproduced in chat and source-confirmed elsewhere.** A fixture Postgrest exception exposed its table name and error code. Events, startup, account and some web forms also display raw exception messages. These errors are not proven credential leaks, but can confuse users and reveal implementation details.

Sources: `apps/customer_mobile/lib/features/chat/listing_chat_screens.dart:48`; `apps/customer_mobile/lib/main.dart:33`; event/account screens; `apps/web/src/components/account-deletion-form.tsx`.

**Fix:** use translated customer messages with Retry/reference IDs and retain detailed diagnostics in protected logs.

## Production operating state observed

Read-only settings show contact and chat charging enabled, publication charging disabled, subscriptions disabled, boosts enabled, booking payments enabled and event payments enabled. Chat unlock is TZS 1,000.

Feature flags enable instant booking, booking deposit/balance, V3 paid chat/contact, and event deposit/balance. Automated refunds, automated provider payouts and external-deal accounting are disabled. These states were recorded, not changed. The earlier implementation document describes some payment rollout decisions as inactive; reconcile documentation and actual approvals with these live settings.

The push queue contained 24 `sent` and seven `skipped` rows, with no pending/failed rows in this snapshot. Existing terminal-looking rows have some unset `terminal_at` values, so queue telemetry/backfill should be reviewed, but this snapshot does not show a stuck delivery backlog or prove that every intended recipient got an OS notification.

Listing media, agent documents and promotions buckets are private; agent profile photos are public. All public tables have RLS. These are positive controls, subject to policy semantics and storage signed-URL/ownership tests.

## Coverage limits and required acceptance work

The audit covers all identified feature families in the matrix, with different evidence levels. It does **not** certify every role, device, data volume, external provider or action. In particular:

- No live authenticated customer/agent/admin/owner/supervisor session was used to mutate data. Direct cross-role access was reproduced locally from live definitions, not exercised against real customer rows.
- No real payment prompt, cancellation refund, bank payout or provider reconciliation was executed. Obtain controlled sandbox/provider evidence before accepting payment reliability.
- No Android/iOS installation, background/terminated push, GPS permissions, camera/gallery permissions, app lifecycle, system clock change, native recovery link, or assistive technology device test was completed.
- Existing `supabase/tests/*.sql` pgTAP files were inspected but **the complete pgTAP suite was not executed** against a full schema clone. The 14 focused scripts and event workflow runner are different tests.
- Owner applications/claims, tenant invitations/agreements/move-out, verified reviews, referral reward approvals/payout recording, wallet adjustments, finance settlement and account deletion completion have source/contract review but still need role-specific end-to-end acceptance.
- Accessibility fixtures cover width/text/readability/overflow in selected screens, not a complete keyboard/screen-reader/contrast assessment. No load test, penetration-test certification, dependency advisory sweep, backup restore drill or external monitoring verification was performed.
- Production responses can change after this snapshot. Health returning 200 is not proof of all workflows, message delivery, payment correctness or business-rule authorization.

## Recommended repair sequence and verification gates

1. **Authorization:** F01, F02, F03 and F06. Add forward migrations and handler checks, then direct API negative tests for every role. Verify no legitimate workflow loses access before deployment.
2. **Payment correctness:** F04/F05 and the double-grant path in F02. Replay signed fixture events in every order; verify one balanced ledger effect, one entitlement and no terminal-state regression. Complete a controlled provider round trip.
3. **Account privacy:** F07/F11. Physical-device sign-out and A→B account-switch tests must show no old notifications or private activity.
4. **Customer/Manage reliability:** F08–F10/F12/F17/F18. Regressions should assert desired behavior; the supplied audit probes intentionally describe defects and must be replaced/inverted when repaired.
5. **Deploy/release parity:** F13–F16. Align function auth configuration, deploy verified-link documents, sign release binaries, and decide event-operations web scope.
6. **Remaining acceptance:** execute every outstanding row of the feature matrix with dedicated test identities and provider sandbox data, then full database suite, device matrix, load/backup/monitoring checks.

No fixes or deployments were bundled into this audit. The next implementation should preserve audit evidence, use additive migrations, and verify each repair independently.
