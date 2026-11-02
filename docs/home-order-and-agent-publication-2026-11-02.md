# Home ordering and agent publication

The home feed previously sorted by a seeded random value ahead of publication date. Migration `20261102190000_home_feed_newest_first.sql` orders by publication date (creation date fallback), descending, before pagination. The existing RPC signature, public visibility conditions and location behavior are preserved. The migration was applied individually and recorded in production history; unrelated pending migrations were not applied.

The project's live Auth discovery endpoint advertises ES256 signing keys. Both listing publication/payment functions were still deployed with the legacy JWT gateway enabled. Per Supabase's [401 troubleshooting guidance](https://supabase.com/kb/troubleshooting/edge-function-401-error-response), these two functions now let requests reach their existing `Auth.getUser(token)` validation and agent/listing/payment ownership checks. Configuration is persisted in `supabase/config.toml`. Deployed create function version 20 and check function version 16; provider metadata confirms `verify_jwt=false` for both. Missing/invalid sessions still receive the handlers' 401 responses.

Validation before release:

- Local PostgreSQL fixture tests actual home RPC chronology before pagination, publication/creation date fallback, seed independence and private/inactive-agent exclusions.
- Eight Edge Function tests verify invalid-session rejection before database access, another agent's resource denial, free publication without provider access, and failure when fee settings are unavailable.
- An authenticated draft creation/staging smoke test against the live schema passed within an explicitly rolled-back transaction.

Post-release checks:

- Live database confirms the migration and newest-first function definition; both current public listings return in date order.
- Live preflight and unauthenticated/invalid-session tests passed for both functions.
- Five browser scenarios against the live website with isolated authenticated API/storage fixtures passed: free, paid, awaiting approval, switch to free, zero-fee plan. These exercise hierarchy, typed area, image compression, retry without duplicate draft, and submission. They do not constitute a real-user paid transaction.

Logs are in `tmp/home-feed-sql-tests.log`, `tmp/home-feed-release.log`, `tmp/home-feed-live-verify.log`, `tmp/publication-auth-tests.log`, `tmp/publication-smoke.log`, `tmp/publication-live-auth.log`, and `tmp/publication-live-browser.log`. No website rebuild or APK was required for these backend changes.
