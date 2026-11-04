# KODIMALI platform audit repair ? 2026-11-04

Implementation against audited commit `2385eee`, on `feature/kodimali-events`.

**Production has not been deployed by this repair pass.** No real payment, customer-data mutation, store publication, migration push, or Cloudflare deployment was performed. Production administrative controls were read and compared successfully. The source repairs and nine forward migrations are ready for review; operational dependencies and integration acceptance below remain mandatory.

?Fixed and verified? in this report means verified in source and isolated fixtures, not verified on the production gateway or an installed release. This is not certification of every row of the original 96-feature matrix.

| ID | Original severity | Root cause | Fix | Tests | Status |
|---|---|---|---|---|---|
| F01 | P1 | Permissive legacy `is_admin()` policies bypassed granular staff permissions. | Domain permissions replace installed legacy predicates; unknown domains and administrative controls stay Super Admin only. Existing participant and scoped-supervisor clauses remain. Verified owner booking access no longer depends on public listing visibility. | Full-schema SQL and actual local PostgREST JWT requests for customer, owner, assigned agent, analyst, marketing, support, finance, supervisor and Super Admin. | Fixed and verified |
| F02 | P1 | Public grant RPC replayed the same receipt and webhook/trigger paths both granted. | Service-only RPC, payment ledger with a unique receipt key, row/advisory locks, trigger as the paid grant authority, historical consumption backfill, revoked-access review. Free mode also preserves existing paid terms and revocations. | Same-receipt replay; distinct renewal adds exactly seven days; revoked renewal stays revoked; four concurrent verified callbacks create one grant. | Fixed and verified |
| F03 | P1 | Public push worker could perform service writes. | Dedicated constant-time worker credential before client construction. Database dispatch obtains matching credential from Vault. Missing secret keeps durable work pending. | Public, frontend-key and incorrect-secret requests rejected before database access. | Implemented, pending integration verification |
| F04 | P1 | Webhooks overwrote terminal paid states. | One locked SQL payment-event path; late processing cannot downgrade paid/refunded records; contradictory final events enter reconciliation. All payment pollers use the same path. | Local payment-state/replay assertions, intercepted webhook tests, existing Events refund/replay tests. | Fixed and verified |
| F05 | P1 | Missing amount/currency evidence was treated as successful payment. | Require provider, order, transaction, exact amount and currency; uniquely bind provider transactions to payments; require stored verified evidence before finalization. Sonic incomplete success queries provider when possible; ClickPesa requires checksum and authenticated provider query. | Wrong amount/missing currency grant nothing; complete evidence grants once; unsigned/invalid ClickPesa events rejected; no direct webhook finalization. | Fixed and verified |
| F06 | P1 | Operational helpers trusted broad roles or no caller identity. | Dedicated credential for notify/delay workers; notify validates booking assignment. Booking handler uses user JWT and granular permission/active assignment. Direct booking RPC enforces the same active-agent boundary. | Unauthorized staff/worker tests; direct inactive-agent RPC denial; role RLS tests. | Fixed and verified |
| F07 | P1 | Logout left device tokens attached to the previous user. | Durable installation-capability disable queue, hashed server capability, session-bound registrations, token deletion and local notification cleanup. Logout clears local Auth even if push cleanup fails. Worker suppresses revoked bound sessions and sends generic text with whitelisted routing data. Foreground/tap code checks recipient identity. | Shared offline logout and registration race tests; SQL capability/session/A?B tests; payload privacy tests. | Implemented, pending integration verification |
| F08 | P2 | Async expressions returned Futures from Flutter `setState` callbacks. | Converted affected callbacks across both apps into synchronous state updates; work remains outside callbacks. | Both analyzers clean; both full widget suites pass; original chat refresh reproduction now asserts no exception. | Fixed and verified |
| F09 | P2 | Access-fetch errors were presented as expired paid chat. | Explicit loading/error/expired/revoked handling, bounded access lookup, retry, retained details/history/draft and a stable message stream. Failed access checks prevent sending without claiming expiry. | Failed lookup recovery; stream failure preserves history/draft; safe error and retry assertions. | Fixed and verified |
| F10 | P2 | Customer login could remain busy indefinitely. | Bounded repository and UI authentication requests, recoverable timeout, mounted checks and released controls. | Stalled repository fixture releases login controls after deadline. | Fixed and verified |
| F11 | P2 | Device-global activity merged across accounts. | Per-user and guest namespaces, per-account pending saves/removals, actor-checked acknowledgements, explicit guest import. Ambiguous v1 data is retained but quarantined. Captured persistence keys prevent account-switch write races. | Guest/A/B/logout/restart, tombstones, wrong-account acknowledgement and v1 quarantine tests. | Fixed and verified |
| F12 | P2 | Manage initial notification emitted before subscription; only chat routed. | Subscribe before initialization; preserve cold-launch and local-notification payloads; queue until authentication/profile load; whitelist destinations for booking/listing/payment/Events/chat; use RLS and permissions when resolving resources. | Destination and malformed-route unit tests; recipient/payload tests. | Implemented, pending integration verification |
| F13 | P2 | Checked-in gateway configuration differed from public availability usage. | Explicit handler-auth model for all 28 functions; public availability remains public, user handlers call Auth.getUser, internal workers require dedicated credential and webhooks verify provider authenticity. | All 28 entrypoints type-check; local handler authorization tests pass. | Implemented, pending integration verification |
| F14 | P2 | Association routes absent and Customer HTTPS host outdated. | Environment-backed Android/Apple association handlers, correct kodimali.com Android/iOS declarations, account/recovery routes, explicit web recovery redirect for Manage. Missing identities return 503 without invented certificates. | Association identity validation unit tests; route included in production build. | External dependency blocked |
| F15 | P2 | Release used debug signing; no certified distribution artifacts. | Both Android releases require production signing environment; protected manual CI builds signed AABs and records public certificate; keystores ignored. iOS APNs environment is development for Debug and production for Release/Profile. Existing store placeholders remain truthful. | Build configuration inspected; application analysis/tests pass. No signed binary was produced or certified. | External dependency blocked |
| F16 | P2 | Web lacked provider/coordinator Events operations. | Dedicated responsive provider/coordinator routes and Back navigation; equipment/service management, requests, quotations, agreements, approvals, replacements/escalations, finance review, assigned fulfillment tasks and audited dispute review. Existing data/roles/RPCs reused; two narrow task/dispute RPCs added where no operation existed. | Browser tests for denied staff, provider service/task operations, coordinator quotation/dispute actions and finance denial; SQL assignment/coordinator boundaries; existing Events suite. | Fixed and verified |
| F17 | P3 | Incoming chat always scrolled to latest. | Scroll only on first load, near latest, own send, or explicit jump; otherwise retain reading position and show new-message control. | Incoming-message reading-position widget regression. | Fixed and verified |
| F18 | P3 | UI displayed raw technical exceptions. | Shared safe English/Kiswahili classification, controlled copy, recoverable messages across web and both Flutter apps; registration keeps known safe validation messages. | Private table/path/SQL error fixtures never appear in output; chat privacy widget; bilingual web/shared tests; existing login contrast tests. | Fixed and verified |

## Changes and data preservation

Nine new migrations, in order:

1. `20261104080000_permission_boundaries.sql`
2. `20261104081000_payment_integrity_and_chat_grants.sql`
3. `20261104082000_private_worker_and_device_lifecycle.sql`
4. `20261104083000_payment_control_enforcement.sql`
5. `20261104084000_event_provider_area_ownership.sql`
6. `20261104085000_owner_booking_read_boundary.sql`
7. `20261104090000_booking_rpc_active_agent.sql`
8. `20261104091000_event_operations_task_and_dispute_boundaries.sql`
9. `20261104092000_free_chat_preserves_paid_and_revoked_access.sql`

Applied migrations were not edited. The new migrations add evidence/grant records, device columns and narrow operations, and replace policy/function/trigger definitions. They do not drop application data, reset controls or change prices. Historical paid receipts are marked consumed; existing entitlement expiry/revocation is retained. Only missing, still-current historical access is recovered with its original paid date, never a fresh seven days from deployment.

Main source groups:

- Supabase: config, worker authentication, both provider webhooks, five polling handlers, legacy creation paths and booking checkout enforcement. `apply_verified_payment_event` is the authoritative atomic path.
- Customer: authentication deadlines, account-isolated activity, chat recovery/history/scroll, safe errors, recipient-aware notifications and kodimali.com recovery links.
- Manage: synchronous state callbacks, safe errors, device/logout lifecycle, cold/warm/local notification routing, permission-aware resource resolution and explicit browser recovery.
- Shared Flutter: `push_device_lifecycle.dart`, `push_payload.dart`, `user_messages.dart`, copy catalog and regressions.
- Web: `event-operations.tsx`, dedicated `/manage/events-provider/*` and `/manage/events-coordinator/*` pages, navigation permissions, safe errors and `.well-known` association handlers.
- CI: web/Flutter/shared/Edge regressions run in CI; the manual protected mobile workflow builds artifacts and does not publish to stores.

The complete implementation manifest is [platform-audit-repair-files-2026-11-04.txt](platform-audit-repair-files-2026-11-04.txt). Unrelated existing `design-previews/` and `homepage-mobile-check.png` were preserved.

## Executed evidence

| Check | Result |
|---|---|
| Next.js production build | Passed, including new Events and association routes |
| Web TypeScript / ESLint | Passed |
| Web unit tests | 29 passed |
| New browser integration checks | 6 passed; intercepted Auth/PostgREST fixtures, mobile and desktop widths |
| Customer Flutter analysis / full tests | No issues / 26 passed |
| Manage Flutter analysis / full tests | No issues / 48 passed |
| Shared Flutter tests | 8 passed |
| Edge entrypoint type checks | 28 checked |
| Edge regression tests | 18 passed, including 8 existing dynamic-publication and 4 existing supervisor tests |
| Existing standalone SQL suites | All 14 passed |
| Existing Events behavior suite | Passed, including equipment/service concurrency and refund/recovery checks |
| New full-schema repair SQL | 35 named assertions plus negative-operation checks passed |
| Device lifecycle SQL | 6 assertions passed |
| Real local PostgREST JWT/RLS | Nine role scopes, denied privileged RPCs and four-callback concurrency passed |
| Forward migrations | All nine applied transactionally to a fresh metadata-only local database |
| Migration naming checker | Passed |
| Production administrative control snapshot/comparison | Matched; read-only, no application mutations |

A compact result and source-hash record is [platform-audit-repair-evidence-2026-11-04.json](platform-audit-repair-evidence-2026-11-04.json). Raw local logs are in ignored `tmp/repair-tests/`. A metadata-only public/auth/storage schema was restored into a new localhost PostgreSQL database, then the real repair migrations were applied. Fake fixture identities and transactions never contacted a payment provider. Local `net.http_post` is stubbed and Vault contains no real secrets. PostgREST tests use fixture HMAC JWTs; they are not evidence of production ES256 gateway acceptance.

The original audit probes remain historical evidence. Corrected behavior is asserted by `test-production-repairs-edge.test.ts`, `test-production-repairs.sql`, the device/HTTP/browser regressions, and the Flutter repair tests. The original defect assertions are not counted as passing repair tests.

Reproduce the database checks using the ignored metadata snapshot and the isolated PostgreSQL server on 127.0.0.1:55439:

```powershell
python -X utf8 scripts/repair-schema-fixture.py
$env:PGHOST='127.0.0.1'; $env:PGPORT='55439'; $env:PGUSER='postgres'
$fixture=(Get-Content tmp/repair-tests/database.txt).Trim()
psql -X -v ON_ERROR_STOP=1 -d $fixture -f scripts/fixtures/production-repair-seed.sql -f scripts/test-production-repairs.sql
psql -X -v ON_ERROR_STOP=1 -d $fixture -f scripts/test-production-repairs-device.sql
python -X utf8 scripts/test-production-repairs-http.py
```

The restore requires `tmp/repair-baseline/schema.sql`, PostgreSQL 18 tools and the local PostgREST executable. The snapshot is intentionally not committed. The HTTP test commits synthetic callback effects into that disposable database; create a fresh fixture before repeating the SQL suite. Historical standalone SQL suites and Events tests use their own disposable databases.

## Administrative payment controls

Read-only production checks confirmed: booking, Events, chat, contact and boosts enabled; publication and subscriptions disabled; chat unlock fee **TZS 1,000**. Existing rollout flags, automatic payout/refund restrictions and prices were not changed.

Local regressions disable booking deposit/balance, event deposit/balance, chat, contact, publication, subscription and boost collection. New checkout respects server-side controls, booking/event preparation checks both product and master switches, existing verified receipts/access survive, and marketplace-control changes are audited. Free publication/contact/chat behavior remains an existing product mode; disabled collection is not treated as absent functionality. Existing refund/reconciliation code remains available independently of new-checkout switches. Repeated verified callbacks do not enable a switch or replay historical charges.

`scripts/repair-release-preflight.py` snapshots every marketplace control/price and rollout flag using a read-only transaction and can compare before/after deployment. A mismatch stops the procedure; do not restore old values over a legitimate administrator change.

## Deployment procedure ? prepared, not executed

1. Review the full diff and the nine migrations. Confirm the linked project is `tlhoajedyaeaaqtrjqqh`. Record the release commit, deployed Edge versions and Cloudflare deployment ID; confirm backup/PITR access. Take a fresh control snapshot immediately before deployment:

   ```powershell
   python -X utf8 scripts/repair-release-preflight.py --output tmp/release-controls-before.json
   supabase db push --linked --dry-run
   ```

   Set `SUPABASE_CLI` to the executable path when it is not on PATH. Dry-run must list only the nine reviewed migrations. Stop on unexpected migrations.

2. Before worker rollout, provision a cryptographically random credential of at least 32 characters in both Supabase Vault as `kodimali_worker_secret` and Edge secrets as `KODIMALI_WORKER_SECRET`. Use protected operator input/files, never source, shell history, console output or a public API key. If already provisioned, use its existing value consistently; rotation requires coordinating both sides. The Vault UI and secret functions are documented in the [official Vault guide](https://supabase.com/docs/guides/database/vault). Edge environment provisioning is documented in [Function secrets](https://supabase.com/docs/guides/functions/secrets).

   ```powershell
   supabase secrets set --project-ref tlhoajedyaeaaqtrjqqh --env-file <protected-temporary-worker-env-file>
   ```

   Remove the temporary file after setting it. Check any cron/external callers of dispatch/notify/delay and configure the dedicated header. A cron SQL caller should resolve the Vault value at execution time, not embed the credential in `cron.job.command`. Do not expose Vault to frontend roles.

3. Verify Sonic webhook and ClickPesa collection checksum/API credentials already exist and match provider configuration. Do not rotate payment credentials or generate a charge as part of this repair. Missing ClickPesa checksum now fails closed; polling can still reconcile using authenticated provider queries. Obtain provider sandbox evidence before certifying actual money flow.

4. Apply the reviewed additive migrations, then deploy updated handlers. During the short interval, old unverified finalization attempts can fail closed; keep existing queued/retry work intact and retry after handler deployment:

   ```powershell
   supabase db push --linked
   supabase functions deploy --project-ref tlhoajedyaeaaqtrjqqh
   ```

   The explicit configuration covers all 28 functions. Verify the deployed settings, not just local TOML. Public availability and guest inquiries remain public; user functions must reject invalid sessions and accept authorized real ES256 customer/agent/staff sessions; internal workers must reject public/incorrect credentials. Verify valid worker processing with a synthetic non-sensitive notification and a test device, without replaying real customer notifications.

5. Configure actual release identities before publishing association documents: `ANDROID_CUSTOMER_RELEASE_SHA256`, `ANDROID_MANAGE_RELEASE_SHA256` (comma-separated actual SHA-256 certificate fingerprints), and `APPLE_TEAM_ID` (actual Apple team). Android Play App Signing installations require the app-signing certificate, not merely the upload-key certificate. Apple uses existing `co.kodimali.customerMobile`; Manage password recovery intentionally falls back to the website. Add `https://kodimali.com/account?mode=recovery` to the Supabase Auth redirect allowlist before releasing updated reset flows. Verify both PKCE/token recovery variants and browser fallback.

6. Deploy the compatible website only after backend checks pass:

   ```powershell
   cd apps/web
   npm run deploy:cloudflare
   ```

   Check public discovery/availability, account and Manage navigation, authenticated chat, Events operations, and `.well-known` responses. Association endpoints intentionally return 503 until authentic release configuration exists; do not claim verified links while they do. Preserve customer Events discovery rules.

7. Compare controls, inspect reconciliation and notification queues, and validate role-isolation using dedicated operator test identities without real payments:

   ```powershell
   python -X utf8 scripts/repair-release-preflight.py --compare tmp/release-controls-before.json --output tmp/release-controls-after.json
   ```

   Preserve original paid records/access and inspect new reconciliation cases. Historical grant backfill is consumption tracking, not permission to replay payments. Check for stuck/failed webhook events and older pending notification work; use provider status verification to resolve them individually. Do not mass-replay or resurrect revoked access.

8. Configure protected `mobile-release` environment secrets for both CUSTOMER and MANAGE prefixes: `KEYSTORE_B64`, `KEY_ALIAS`, `STORE_PASSWORD`, `KEY_PASSWORD`. Dispatch the signed-artifact workflow on the reviewed commit. Use a build number higher than the last distributed version. It builds signed AABs on a Linux runner; it does not publish them. Use a Mac with actual Apple distribution profiles/APNs credentials for iOS archives. Update store URLs only after real listings exist, then perform installed-release device acceptance before distribution.

## Recovery and monitoring

Do not roll the database back by dropping columns/tables, deleting grant/evidence rows or restoring insecure policy definitions. Migration transactions can roll back before commit; after commit, use a reviewed forward corrective migration. An old payment Edge version is not fully compatible with the new evidence guard. Prefer fixing/redeploying the compatible handler rather than bypassing evidence validation. Cloudflare can revert to its recorded prior deployment if needed; keep the secure backend and preserve all administrative controls.

An absent/mismatched worker credential leaves outbox work pending; fix credential agreement and then drain through the authorized worker. Monitor new reconciliation cases, webhook failures/retries, outbox age/terminal failures, payment-state contradictions, denied staff operations and auth/recovery errors. Do not log raw payment payloads, push capabilities or secrets to public application logs.

External acceptance still outstanding:

- Real ES256 session smoke tests through the deployed Supabase gateway and post-deployment role/workflow tests.
- Provider sandbox round trips, concurrent webhook/polling under deployed infrastructure, and operational reconciliation review.
- Physical Android/iOS permission, offline logout, A?B account switch, background/foreground/killed-app push, local notification launch and revoked-session tests.
- Actual release signing credentials, store listings, Apple team/profiles, APNs configuration and production certificate associations.
- Installed-release listing/request/recovery links, cold/warm starts, cancellation/back navigation, FCM/APNs delivery and payment return flows.
- Broader authenticated acceptance of the original feature matrix, load/backup restore verification and operational monitoring. Passing these repair tests does not establish blanket coverage of every existing feature.
