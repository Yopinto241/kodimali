# KODIMALI production audit-repair release - 2026-11-04

**Status: Partially deployed; remaining steps documented. The production database, all 26 Edge Functions and the Cloudflare website are deployed and the listed checks passed. Signed mobile distribution, provider certification and physical-device acceptance remain pending.**

This report supersedes the earlier backup-blocked report committed in `d56f880`. The user's updated instruction authorized an independent secure backup and explicitly removed any prerequisite for paid backups, PITR or staging. No paid infrastructure was purchased.

## A. Release identity

- Branch: `feature/kodimali-events`.
- Reviewed repair commit: `1c394fdc230e404e966627172ff0ed5128243804`; deployed application candidate: `2861f37bab17fbf377d5186bfbd8f4ef399ae6b5`.
- Candidate adds only compatibility for the existing protected ClickPesa `_CHECKSUM_SECRET` name and a regression test. Explicit `_CHECKSUM_KEY` takes precedence and checksum verification remains mandatory. Provider credentials were neither exposed nor rotated.
- Supabase: `tlhoajedyaeaaqtrjqqh`, `eu-north-1`.
- Cloudflare worker: `kodimali-web`; production domains: `kodimali.com`, `www.kodimali.com`.
- Cloudflare deployment: `595b6c12-41f1-43e8-aba7-a3dde79d6b39`, created `2026-11-04T18:25:31.172239Z`; worker version `4053b32d-9ceb-4405-9c4b-07c1053a7e42` at 100%.
- Previous worker version: `a6b9d0a8-bb2f-4174-8662-34d218b35be8`.

Existing untracked `design-previews/` and `homepage-mobile-check.png` were preserved and excluded. No historical migration was edited. The actual local and live function count is 26; the earlier repair report's 28 was incorrect.

## B. Recovery and database

The initial Supabase backup API returned `backups: null`, `physical_backup_data: {}`, `pitr_enabled: false`, `walg_enabled: true`. WAL-G metadata alone did not establish recovery. A full consistent logical backup was therefore created through the authorized database connection, using an exported repeatable-read snapshot. Its run began `2026-11-04T14:45:43Z`.

The custom PostgreSQL archive includes schema, data, constraints, indexes, policies, grants and original extension metadata/data. Role definitions and memberships were exported separately without role passwords. Auth user password hashes are part of the protected database data. Database configuration, remote Supabase configuration, table counts and restore proof accompany the archive. The newly provisioned worker credential is included only inside the encrypted recovery package.

Recovery files are outside the repository under the current Windows user's `Kodimali-Recovery` directory, with inherited access removed and access restricted to that user and SYSTEM. The recovery ZIP is encrypted with Windows DPAPI CurrentUser; recovery requires this Windows profile and the adjacent entropy file. All 11 encrypted members passed decryption and SHA-256 verification. The secure directory contains the operator recovery instructions. This is a verified local recovery method, not a portable offsite backup guarantee.

A password-protected isolated PostgreSQL 18 instance restored the actual backup. All **173 public/auth/storage/migration-history table counts** matched the consistent source snapshot. This Windows installation lacks managed `pg_cron`, `pg_net` and `supabase_vault` runtimes: only the isolated check substituted those runtimes, disabled outbound calls, and adjusted managed role grantor/bootstrap compatibility. The original definitions and encrypted extension data remain unchanged in the archive. The isolated server was stopped after verification.

All nine candidate migrations then applied successfully to that restored production data. Original table content hashes were unchanged, and every existing chat entitlement row was preserved. The comparison excluded the two newly added nullable device columns and allowed additive historical chat grants; none of the original data changed. Storage object binaries and existing Edge secret values are not exported by a database backup. These release migrations delete no storage objects. A different Supabase project would also require managed extension/Vault keys and protected provider configuration to be re-established.

| Reviewed migration | Production status |
|---|---|
| `20261104080000_permission_boundaries.sql` | Applied |
| `20261104081000_payment_integrity_and_chat_grants.sql` | Applied |
| `20261104082000_private_worker_and_device_lifecycle.sql` | Applied |
| `20261104083000_payment_control_enforcement.sql` | Applied |
| `20261104084000_event_provider_area_ownership.sql` | Applied |
| `20261104085000_owner_booking_read_boundary.sql` | Applied |
| `20261104090000_booking_rpc_active_agent.sql` | Applied |
| `20261104091000_event_operations_task_and_dispute_boundaries.sql` | Applied |
| `20261104092000_free_chat_preserves_paid_and_revoked_access.sql` | Applied |

Production migration history increased from 148 to **157** entries. The final CLI dry run reports **up to date**, with no pending migrations, seeds or roles. Both new evidence/entitlement ledgers and the atomic payment and session-bound device RPCs are installed. All **137** public tables have RLS enabled; zero public tables lack RLS. The chat entitlement grant RPC denies execute to both `anon` and `authenticated`.

A read-only production comparison across 172 original non-migration tables matched the migration trial for every marketplace table, including financial records, profiles, roles, settings and chat entitlements. Only `auth.users`, `auth.sessions` and `auth.refresh_tokens` differed during normal live Auth activity. No customer rows were emitted. This comparison preceded temporary verification accounts, which were subsequently removed.

Recovery after a failed transaction starts with inspecting actual migration history and definitions. Prefer a reviewed forward correction after commit. Never reinstate insecure RLS or delete evidence/grants as a rollback. A database restore requires a controlled recovery procedure to avoid overwriting subsequent customer activity; restore into an isolated compatible environment and verify first. The previous Cloudflare version is recorded for website rollback, but backend contracts must remain compatible.

## C. Administrative controls and queues

A fresh snapshot immediately before the resumed deployment matched both post-database and final post-deployment snapshots exactly. All settings and complete feature configurations were compared, excluding audit timestamps/actors. No switches, prices or rollout settings were reset.

Booking, Events, chat, contact and boost payment switches remain enabled. Publication charging and subscriptions remain disabled. Chat fee remains TZS 1,000. Instant booking, deposit/balance and paid chat/contact flags retain their administrator values; automated refunds, provider payouts and external deal accounting remain disabled.

Final notification aggregates remain 24 sent and seven skipped, with no pending/failed rows. Reconciliation remains empty. No dispatch replay, charge, payout, refund, fabricated signed callback or customer notification test occurred. These point-in-time checks do not certify long-duration error rates or provider delivery.

## D. Application verification

Fresh local checks passed: Customer Flutter analysis and 26 tests; Manage analysis and 48 tests; eight shared lifecycle tests; 29 web unit tests; web lint, TypeScript and production build; 19 Edge regressions; all 26 Edge entrypoint type checks. Historical exploit-reproduction probes assume the old vulnerable behavior and are not the post-repair acceptance suite.

The OpenNext production build and Cloudflare deployment succeeded. Eleven live routes return 200, including listings, Events, plan creation, reporting, login, recovery, Manage, provider/coordinator pages and `/api/health`. Six browser checks passed against deployed production frontend assets with intercepted Auth/PostgREST fixtures: mobile/desktop denied-analyst isolation, provider service creation, narrow fulfillment RPC, audited dispute review, and canonical itemized quote behavior. These form tests made no real marketplace writes.

Real ES256 sessions were created only for temporary non-customer test identities using admin creation with email confirmation and no email send. Live permission/RLS and grant-denial checks passed for customer, agent, owner, analyst, marketing, finance, support, Events coordinator and Super Admin roles. Only HEAD counts were read for booking scope; no customer booking payloads were fetched. Agent/owner accounts had no assigned marketplace assets, so their own-record positive journeys remain device/fixture acceptance. Supervisor appointment was correctly denied by its existing Super Admin/registered-agent guard; it was not bypassed to force a test. Local full-schema supervisor scope evidence remains applicable.

The live device lifecycle check registered a unique non-FCM token on a temporary identity, verified session binding, rejected the wrong capability, disabled it using the correct offline capability, re-registered, and verified ineligibility after Auth session revocation. The fake token and temporary identities/roles were removed. No notification dispatch was invoked.

The approved `https://kodimali.com/account?mode=recovery` URL was missing from the actual Supabase allowlist. A reviewed one-property config diff added it while preserving every existing redirect, the existing `https://kodimali.co.tz` site URL, SMTP, MFA and other Auth settings. A final diff found no remaining declared update. A generated recovery link retained the exact approved redirect without sending email. Inbox delivery and actual password change remain pending.

Android and Apple association routes now return intentional **503 with Cache-Control: no-store** while authentic release identities are unavailable, replacing the former 404. No certificate fingerprints or Apple identity were fabricated.

## E. Security and per-finding acceptance

A matching dedicated random credential was provisioned in Vault (`kodimali_worker_secret`) and Edge (`KODIMALI_WORKER_SECRET`). Vault used parameter binding with session statement and parameter logging disabled. No public API key substitutes for this credential. The reviewed database dispatch trigger reads Vault; no relevant cron callers were found. External callers must use the dedicated header; their existence/configuration is not certified here.

Sixteen live negative checks returned 401 for absent/invalid worker credentials, unsigned/invalid-signature webhooks and unauthenticated user handlers. Both input-validated workers accepted the real credential and returned 400 for empty input before any business action. The dispatcher was not manually invoked. All 26 function deployments are ACTIVE with gateway `verify_jwt=false`; user handlers validate sessions, workers validate their dedicated secret and webhooks validate provider authenticity.

| Finding | Production/source result | Remaining acceptance |
|---|---|---|
| F01 | Permission/RLS migration live; nine real-session role scopes checked | Assigned supervisor/agent/owner positive journeys |
| F02 | Durable grant ledger and public execute revocation live; historical entitlements preserved | No replay of real paid receipts; local concurrency evidence only |
| F03 | Dedicated worker secrets/handler live; live invalid and valid credential checks pass | Device delivery and external caller inventory |
| F04 | Atomic financial transition RPC and compatible handlers live | Actual provider sandbox terminal-state round trip |
| F05 | Evidence/checksum enforcement live; invalid callbacks denied; existing checksum secret alias supported | Controlled provider-valid signatures and evidence |
| F06 | Booking/worker permission boundaries live; role regression checks pass | Real assigned booking journey without customer disruption |
| F07 | Session-bound device backend live; real-session lifecycle check passes | Installed app offline logout/account switch and delivery |
| F08 | Flutter source and analysis/tests pass | Production-signed app distribution and installed lifecycle |
| F09 | Chat retry/history/revocation source tests pass; backend live | Installed app/live chat entitlement journey |
| F10 | Login timeout source/widget test passes; web Auth session verified | Installed app slow/offline login |
| F11 | Guest/account isolation and tombstone source tests pass | Physical shared-device account switching |
| F12 | Manage notification destination/payload source tests pass | Warm/killed/local notification taps on devices |
| F13 | All 26 compatible handlers live; real ES256 Auth/handler session accepted | Full assigned-role device journeys |
| F14 | Association routes live with safe uncached 503 | Authentic certificates/Apple team and device link verification |
| F15 | Production-signing configuration is in source | Protected signing credentials, signed APK/AAB and installed verification |
| F16 | Events backend and website live; six deployed-frontend browser checks pass | Full real provider/coordinator fulfillment and provider payment sandbox |
| F17 | Chat reading-position source/widget test passes | Installed-device acceptance |
| F18 | Safe-error/bilingual source suites pass; compatible website deployed | Installed-device/network-recovery acceptance |

Observed deployed function versions:

| Function | Before | Deployed | Gateway / state |
|---|---:|---:|---|
| admin-delete-listing | 17 | 19 | false / ACTIVE |
| approve-listing | 16 | 18 | false / ACTIVE |
| check-agent-commercial-payment | 13 | 15 | false / ACTIVE |
| check-agent-listing-payment | 17 | 19 | false / ACTIVE |
| check-availability | 19 | 21 | false / ACTIVE |
| check-listing-chat-payment | 14 | 16 | false / ACTIVE |
| check-listing-contact-payment | 22 | 24 | false / ACTIVE |
| check-platform-payment | 5 | 7 | false / ACTIVE |
| clickpesa-payment-webhook | 28 | 30 | false / ACTIVE |
| clickpesa-return-page | 14 | 16 | false / ACTIVE |
| create-agent-account | 19 | 21 | false / ACTIVE |
| create-agent-commercial-payment | 15 | 17 | false / ACTIVE |
| create-agent-listing-payment | 21 | 23 | false / ACTIVE |
| create-booking-payment | 3 | 5 | false / ACTIVE |
| create-booking-request | 27 | 29 | false / ACTIVE |
| create-guest-booking-request | 24 | 26 | false / ACTIVE |
| create-listing-chat-payment | 21 | 23 | false / ACTIVE |
| create-listing-contact-payment | 31 | 33 | false / ACTIVE |
| create-platform-payment | 5 | 7 | false / ACTIVE |
| delete-empty-listing | 15 | 17 | false / ACTIVE |
| dispatch-push-notifications | 12 | 14 | false / ACTIVE |
| mark-agent-delayed | 14 | 16 | false / ACTIVE |
| notify-agent | 14 | 16 | false / ACTIVE |
| sonicpesa-payment-webhook | 3 | 5 | false / ACTIVE |
| update-booking-status | 14 | 16 | false / ACTIVE |
| verify-agent | 17 | 19 | false / ACTIVE |

## F. Outstanding dependencies

Provider credentials are present by name but no actual provider sandbox round trip was authorized through a supplied sandbox environment; presence is not provider certification. No real payment or provider-secret rotation occurred. Production Android signing inputs and Apple team identity are unavailable locally, and protected GitHub signing secret availability was not certified. No APK/AAB signed artifact, installed-release verification or store publication occurred. Physical notification/deep-link/lifecycle/chat acceptance and delivered-email password recovery remain pending.

The verified recovery package is tied to the current Windows profile. Preserve that profile and the entropy file, keep recovery files private, and arrange a separately secured portable/offsite copy through an approved process if desired. No paid backup subscription or staging environment is required to finish the remaining acceptance.

## G. Final status and evidence

**Partially deployed; remaining steps documented.** All approved database, Edge and website deployments are complete. The final control comparison is exact, marketplace/entitlement preservation checks passed, queues show no new failures, and safe live verification passed. Mobile distribution and the listed provider/device/signing acceptance are outstanding; the platform is not claimed fully certified.

[Machine-readable release evidence](platform-audit-production-release-evidence-2026-11-04.json) records the exact candidate, migrations, versions, recovery proof, control comparison and tests. Raw local artifacts are ignored under `tmp/production-release-20261104/`; production data, keys, session tokens and recovery files are excluded from GitHub.
