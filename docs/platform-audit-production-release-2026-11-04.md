# KODIMALI production audit-repair release - 2026-11-04

**Final status: Deployment blocked before changes.**

The authorized release was stopped at the mandatory backup/recovery preflight gate. The Supabase backup API exposed no available backup or recovery point, with `backups: null`, `physical_backup_data: {}`, and `pitr_enabled: false`. `walg_enabled: true` alone does not verify recoverability. No restore test was performed, and no independently verified external backup was supplied.

No database migration, Edge deployment, Cloudflare upload, secret provisioning, Auth configuration change, payment, payout/refund, production notification send, or store publication was performed. The reviewed application source is unchanged. The audited production defects have **not** been activated as repairs merely because local tests pass.

This stop follows the deployment request's Phase 3: "If adequate backup or recovery readiness cannot be established, stop before database deployment." The dependent Edge and website release was also held, rather than exposing clients to missing backend contracts.

## A. Release identity and exact scope

- Branch: `feature/kodimali-events`.
- Candidate application commit: `1c394fdc230e404e966627172ff0ed5128243804`.
- Audited base: `2385eeedcbadbdd8b12d4401ec837562bafcbfc9`.
- Supabase project: `tlhoajedyaeaaqtrjqqh`; configured region `eu-north-1`.
- Production application release commit activated by this task: **none**.
- Cloudflare worker: `kodimali-web`, configured for `kodimali.com` and `www.kodimali.com`.
- Existing Cloudflare deployment: `eadf8d2d-6d6a-4b7a-adcc-deea46af7ebf`, created `2026-11-02T07:55:09.330654Z`.
- Existing Cloudflare worker version: `a6b9d0a8-bb2f-4174-8662-34d218b35be8`, receiving 100% traffic. No new website version uploaded.
- Edge versions were captured before and after the checks and matched exactly; the table below records them.

All six requested primary documents were read. The reviewed migration/regression source hashes match the implementation evidence. Only the nine expected new migration files differ from the audited base; no historical applied migration was edited. There were no tracked source changes after the reviewed repair commit. Existing untracked `design-previews/` and `homepage-mobile-check.png` were preserved and excluded.

The earlier repair report says ?28 functions.? The actual local `*/index.ts` inventory and production function list both contain **26 deployable functions**, all accounted for here. This report uses the observed count rather than repeating the incorrect earlier count.

This report and its evidence are documentation-only follow-up changes, not additional application changes.

## B. Database and recovery gate

`supabase db push --linked --dry-run` succeeded and listed exactly these pending migrations, with no seeds or roles to apply:

| Reviewed migration | Production status |
|---|---|
| `20261104080000_permission_boundaries.sql` | Pending; not applied |
| `20261104081000_payment_integrity_and_chat_grants.sql` | Pending; not applied |
| `20261104082000_private_worker_and_device_lifecycle.sql` | Pending; not applied |
| `20261104083000_payment_control_enforcement.sql` | Pending; not applied |
| `20261104084000_event_provider_area_ownership.sql` | Pending; not applied |
| `20261104085000_owner_booking_read_boundary.sql` | Pending; not applied |
| `20261104090000_booking_rpc_active_agent.sql` | Pending; not applied |
| `20261104091000_event_operations_task_and_dispute_boundaries.sql` | Pending; not applied |
| `20261104092000_free_chat_preserves_paid_and_revoked_access.sql` | Pending; not applied |

Production currently records 148 migration-history entries; none of the nine repair versions is present. Metadata confirms:

- 135 public tables have RLS enabled; zero public tables lack it. This does not prove that their existing policies correctly restrict every role.
- The new entitlement/evidence ledgers, atomic payment-event RPC and session-bound registration RPC are absent, as expected before migration.
- The existing chat grant RPC remains executable by `anon` and `authenticated`. Its production entitlement replay defect is therefore **not closed by this attempt**. It was not invoked.
- No entitlement-altering operation was executed. Preservation of historical paid access and revocations remains a deployment acceptance check; concurrent legitimate customer activity was not frozen or overwritten.
- The authorized worker/Vault configuration is absent. No scheduled cron commands referencing dispatch/notify/delay were found. The database dispatch trigger is the reviewed caller to update through the pending worker migration. External callers still require operator confirmation.

Backup readiness was queried through the authenticated Supabase CLI and returned:

```json
{"backups":null,"physical_backup_data":{},"pitr_enabled":false,"walg_enabled":true,"region":"eu-north-1"}
```

This is a lack of verified recovery evidence, not a claim that no internal provider copy can possibly exist. No latest usable recovery timestamp could be recorded. The metadata-only local schema snapshot is not a customer-data backup and does not satisfy this gate.

Recovery procedure: establish an accessible, verified production recovery point and operator restore procedure before release. Do not change the subscription, backup settings or PITR configuration silently. After a committed repair migration, prefer a reviewed forward corrective migration. Do not recover by reinstating insecure RLS, removing evidence checks, or deleting grant/evidence records. Before a migration transaction commits, its failure can roll back that transaction; after commit, inspect migration history and actual definitions before retrying. No rollback was necessary in this attempt.

The candidate needs a coordinated database/Edge release interval: old payment handlers can fail closed against new evidence guards until compatible handlers deploy. Schedule a controlled low-traffic release interval after recovery readiness is verified; retain webhook retries and notification queues. Do not disable payment products or the marketplace without an approved incident action. Lock duration on the live backfill was not measured because migrations were not applied.

## C. Administrative controls

A fresh read-only snapshot was taken with `scripts/repair-release-preflight.py`, then compared again after the checks. **All captured marketplace settings/prices and rollout flag configurations matched.** No historical setting value was forced onto production.

| Control | Observed before / after |
|---|---|
| Booking collection | Enabled / enabled |
| Booking deposit and balance rollout | Enabled / enabled |
| Events collection and deposit/balance rollout | Enabled / enabled |
| Chat and contact collection | Enabled / enabled |
| Listing boosts | Enabled / enabled |
| Publication collection | Disabled / disabled |
| Subscription collection | Disabled / disabled |
| Automatic refunds | Disabled / disabled |
| Automatic provider payouts | Disabled / disabled |
| External-deal accounting | Disabled / disabled |
| Chat unlock fee | TZS 1,000 / TZS 1,000 |

The comparison covers all fields captured by the script, not only this summary. Private local snapshots remain ignored at `tmp/release-controls-before.json` and `tmp/release-controls-after.json`. Their normalized comparison hash is in the evidence artifact. They are an aborted-attempt baseline; take fresh snapshots when deployment resumes. Existing refund/reconciliation obligations were neither executed nor changed, and live processing of those workflows remains pending.

## D. Application verification

Fresh checks on the candidate commit:

| Check | Current attempt result |
|---|---|
| Customer Flutter analysis | No issues |
| Customer full tests | 26 passed |
| Manage Flutter analysis | No issues |
| Manage full tests | 48 passed |
| Shared Flutter tests | 8 passed |
| Web TypeScript | Passed |
| ESLint | Passed |
| Next.js production build | Passed |
| Web unit tests | 29 passed |
| Local browser integration | Six checks passed |
| Edge regressions | 18 passed |
| Edge type checks | All 26 deployable entrypoints checked |
| Migration naming check | Passed |
| Reviewed migration/test hashes | Matched implementation evidence |

The browser checks use a local production build and intercepted Auth/PostgREST fixtures. They verify denied analyst access, provider service creation, assigned fulfillment tasks, coordinator quotation/dispute actions and finance denial at mobile/desktop widths. They do not certify production accounts, RLS or provider connectivity.

The previous full-schema SQL/entitlement/concurrency/device regressions remain recorded in the implementation report and match the reviewed source hashes. They were not rerun against production. No real customer booking or payment was used as a test fixture.

Read-only public HTTP baseline checks returned 200 with the expected page titles for homepage, listings, Events, Panga Tukio, Toa Taarifa, login, recovery URL and Manage; health also returned 200. These were **before-deployment availability checks**, not authenticated workflow acceptance. Login, password reset completion, customer bookings, paid-chat/contact state, Super Admin and restricted staff workflows were not certified through real sessions. No reset email or account mutation was triggered.

Both live association URLs still return **404**, because the new handlers were not deployed. The candidate handlers' intentional 503 fallback for missing release identities is locally implemented, not currently active on the website. Authentic certificate/team values were not available in the local signing environment. The recovery URL's HTTP 200 does not prove the Supabase redirect allowlist or email/PKCE recovery flow; those remain to verify.

Android signing environment variables and Apple/association identity variables were absent locally. The protected manual mobile workflow and its production-signing guard were reviewed; no signed AAB/APK/iOS archive was generated, no CI signing credentials were retrieved, and no store action was invoked. The availability of protected GitHub signing secrets was not established. Installed-release/device testing remains pending.

## E. Security and provider readiness

Additional blockers/prerequisites discovered without reading or publishing secret values:

1. `KODIMALI_WORKER_SECRET` is absent from Edge secret metadata, and `kodimali_worker_secret` is absent from Vault. Matching credentials must be provisioned securely after release gates pass and before worker activation. No secret was generated or installed during this blocked attempt.
2. SonicPesa API/webhook credential names are present, but presence does not verify their value, environment or provider acceptance. No provider round trip was performed.
3. ClickPesa collection API/client credentials are listed, but the candidate expects `CLICKPESA_COLLECTION_CHECKSUM_KEY` while production lists `CLICKPESA_COLLECTION_CHECKSUM_SECRET`. The required `_KEY` name is absent. Confirm the intended provider checksum value through protected operator configuration and align the required name without unnecessary rotation before deployment. Do not bypass checksum verification. Secret values were not compared or copied.
4. Dedicated real ES256 customer/agent/owner/staff test sessions were not supplied or created. Production authenticated acceptance remains pending. No privileged worker POST, entitlement grant replay, fabricated signed payment callback or notification send was attempted against the unrepaired live handlers.

Current queue metadata showed 24 sent and seven skipped notification rows, no pending/failed rows, and no reconciliation cases. This is a point-in-time aggregate, not proof of delivery to devices or complete provider reconciliation. Protected operational logs and post-deployment error trends were not certified while deployment was blocked.

| Finding | Source / local evidence | Production deployment and live acceptance |
|---|---|---|
| F01 | Domain RLS changes; prior full-schema role tests; fresh navigation/permission tests | Pending; current RLS flags checked, corrected production role boundary not installed |
| F02 | Unique grant ledger, replay/concurrency SQL evidence; fresh Edge regressions | Pending; old public execute permissions still present; no real receipt replay |
| F03 | Worker credential rejection tests pass | Pending; old worker remains; matching secrets absent; no live worker operation |
| F04 | Atomic transitions and terminal-state regression evidence | Pending; no synthetic provider callback applied to production |
| F05 | Evidence/checksum negative tests pass | Pending; provider round trip and checksum configuration alignment required |
| F06 | Privileged helper/permission tests pass | Pending; no real booking or notification mutation |
| F07 | Fresh shared lifecycle tests; prior SQL capability/session tests | Pending backend/mobile rollout; physical logout/account-switch delivery untested |
| F08 | Fresh Customer/Manage analysis and full tests pass | No new app release installed/distributed |
| F09 | Fresh chat error/retry/history/revocation widgets pass | Installed-app and live entitlement recovery pending |
| F10 | Fresh stalled-login timeout widget passes | Installed-app slow/offline Auth acceptance pending |
| F11 | Fresh guest/account isolation/tombstone tests pass | Installed shared-device/account-switch acceptance pending |
| F12 | Fresh Manage destination and payload tests pass | Killed/warm/local notification device acceptance pending |
| F13 | All actual 26 handlers accounted for and type-checked; authentication regressions pass | Existing deployed gateway settings recorded; new model not deployed; real ES256 acceptance pending |
| F14 | Association validation tests and route build pass | Live URLs remain 404; actual certificates/team and device tests pending |
| F15 | Production-signing configuration/workflow reviewed | Signed artifacts and installed release certification blocked/not performed |
| F16 | Fresh six browser checks and Events build pass; prior SQL task/dispute evidence | New operational pages/backend contracts not deployed; production role journeys pending |
| F17 | Fresh chat reading-position widget passes | Installed-device behavior pending |
| F18 | Fresh safe-error and bilingual/widget regression suites pass | Compatible website/app rollout and live recoverable-error acceptance pending |

Observed existing Edge deployments, unchanged before/after this attempt:

| Function | Version | Gateway verify_jwt | This attempt |
|---|---:|---|---|
| admin-delete-listing | 17 | true | Unchanged; not deployed |
| approve-listing | 16 | true | Unchanged; not deployed |
| check-agent-commercial-payment | 13 | true | Unchanged; not deployed |
| check-agent-listing-payment | 17 | false | Unchanged; not deployed |
| check-availability | 19 | false | Unchanged; not deployed |
| check-listing-chat-payment | 14 | true | Unchanged; not deployed |
| check-listing-contact-payment | 22 | false | Unchanged; not deployed |
| check-platform-payment | 5 | false | Unchanged; not deployed |
| clickpesa-payment-webhook | 28 | false | Unchanged; not deployed |
| clickpesa-return-page | 14 | false | Unchanged; not deployed |
| create-agent-account | 19 | true | Unchanged; not deployed |
| create-agent-commercial-payment | 15 | true | Unchanged; not deployed |
| create-agent-listing-payment | 21 | false | Unchanged; not deployed |
| create-booking-payment | 3 | true | Unchanged; not deployed |
| create-booking-request | 27 | false | Unchanged; not deployed |
| create-guest-booking-request | 24 | false | Unchanged; not deployed |
| create-listing-chat-payment | 21 | true | Unchanged; not deployed |
| create-listing-contact-payment | 31 | false | Unchanged; not deployed |
| create-platform-payment | 5 | false | Unchanged; not deployed |
| delete-empty-listing | 15 | true | Unchanged; not deployed |
| dispatch-push-notifications | 12 | false | Unchanged; not deployed |
| mark-agent-delayed | 14 | true | Unchanged; not deployed |
| notify-agent | 14 | true | Unchanged; not deployed |
| sonicpesa-payment-webhook | 3 | false | Unchanged; not deployed |
| update-booking-status | 14 | true | Unchanged; not deployed |
| verify-agent | 17 | true | Unchanged; not deployed |

The candidate config deliberately lets user handlers perform Auth.getUser validation, while dedicated worker credentials and provider authenticity protect non-user handlers. Changing gateway metadata before compatible handlers are deployed would be unsafe; no gateway settings were changed independently.

## F. Exact steps to unblock and resume

1. Establish a usable, accessible production backup/recovery point and document its timestamp, coverage, retention, restore access and validation. A verified independently managed encrypted backup may be assessed if available; the schema-only fixture does not qualify. Any plan/backup/PITR change needs explicit operator authorization. Recheck the mandatory gate rather than assuming WAL-G or a setting alone is enough.
2. Reconfirm candidate commit/source hashes, current deployed versions and exactly nine pending migrations. Take a **new** administrative-control snapshot immediately before the resumed release.
3. Securely provision matching worker credentials in Vault/Edge and verify intended database/external callers. Preserve queued work; never substitute a public key or bypass authorization.
4. Resolve the ClickPesa checksum-name mismatch through protected configuration and confirm provider environment/authenticity requirements. Keep provider round-trip certification pending unless actual controlled evidence is available. Do not create real payments.
5. Only after mandatory gates pass, apply the nine reviewed migrations, inspect their recorded versions/definitions and entitlements, then deploy compatible handlers. Never rerun blindly after an error. Do not deploy clients that require absent RPCs.
6. Verify real ES256 role scopes and safe synthetic operations with dedicated identities. Never replay real paid receipts, mass-replay webhooks or send real-customer notification tests.
7. Deploy the reviewed website to the recorded production target after backend checks pass. Verify actual application behavior at phone/desktop widths. Keep authentic-association fallback behavior; verify the approved recovery redirect/allowlist and email flow without silently replacing existing Auth configuration.
8. Compare fresh before/after controls, record new Edge/Cloudflare versions, and monitor webhook/reconciliation/outbox/auth/RLS/booking/Events failures.
9. Obtain authentic production signing and Apple identities, generate signed artifacts through protected configuration, and perform installed-release/provider/device acceptance. Do not publish to stores without approval.

The implementation report contains the reviewed rollout commands and forward recovery limitations. This document records why those mutating commands were not executed in this attempt.

## G. Final status and evidence

**Deployment blocked before changes.** Backup/recovery readiness is the primary hard stop. Worker credential provisioning and the ClickPesa checksum-name mismatch are additional prerequisites. Provider, real-session, physical-device and signing acceptance remain open; KODIMALI is not claimed fully certified.

[Machine-readable release evidence](platform-audit-production-release-evidence-2026-11-04.json) records source identity, exact pending migrations, backup response, current versions, control comparison and fresh test outcomes. Raw local artifacts are in ignored `tmp/production-release-20261104/`. No secrets, capability values, customer rows or raw provider payloads are included in the committed report/evidence.
