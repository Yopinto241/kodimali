# Dynamic free/paid listing publication — 2026-11-01

The live admin setting already had agent_listing_payments_enabled=false. Existing plan fees were basic=500, business=0, free=1000 and pro=0. These settings and values were left unchanged.

## Confirmed gaps and repair
- The payment function treated a zero-fee plan as free, but SQL release and the publication trigger still required a paid receipt whenever the global payment switch was enabled. Added a single internal effective-fee function that respects global free mode, active unexpired plan fee and the existing standard fallback. SQL release, payment gate, publication-mode RPC and admin approval's fee decision now agree.
- The web could keep checking an old pending transaction after the admin switched uploads to free. The web re-reads publication requirements on every submission/check. Free mode skips the old transaction and calls the free release path. The payment-check function also checks the current effective fee before contacting any provider, benefiting installed mobile apps as well.
- The UI shows free publication or the current fee and the approval requirement. Publication status is confirmed from the saved listing; an unresolved publication is not automatically labelled an approval delay when no approval is required.
- Payment functions fail closed if the effective fee cannot be read. Free mode does not mark a provider transaction paid, cancel it or issue refunds. An already initiated mobile money request can still exist at the provider; switching to free does not implicitly cancel or refund that earlier request.

## Validation and deployment
- scripts/test-dynamic-listing-fees.sql passed: global free switch, zero-fee plan, changed paid fee, expired plan fallback, unpaid publication blocked, paid receipt, free mode preserving approval/media/removal constraints, admin approval fee calculation, reenabled fees, private helper execution denied.
- scripts/test-dynamic-listing-payment.ts: four passing Deno tests, real request handlers with all service/provider fetches mocked. Both create/check skip the provider for a zero fee; missing fee fails closed. Deno type checks passed.
- TypeScript, targeted ESLint and 22 existing web library tests passed. OpenNext production build completed.
- scripts/test-add-asset-web.py passed five mocked browser scenarios: global free, paid, approval pending, pending payment switching to free, and zero-fee plan; includes image removal and retry. No real charges or test listings created.
- Only migration 20261101170000_dynamic_listing_publication_fees applied, atomically with migration history. It updates function definitions and permissions, without changing settings, plans, accounts or listings. The admin publication function's current authorization/audit implementation is preserved; only its fee decision changes.
- Deployed create-agent-listing-payment and check-agent-listing-payment individually. Web deployment/provider logs: tmp/dynamic-fee-web-deploy.log and tmp/dynamic-fee-web-deployments.log. Live mocked acceptance: tmp/dynamic-fee-live-browser.log. Read-only live mode verification: tmp/dynamic-fee-live.log.

No APK generated or native source changed. Existing mobile apps receive the server-side fixes through their existing RPC/payment functions. Global free-mode reconciliation remains the existing behavior; zero-fee plan changes are honored on the next submission/payment check. No new bulk publication operation introduced.


Verified live: all five isolated browser scenarios passed; Cloudflare version cbce6390-7cc2-42c4-9eaf-ab1641e6f22b receives 100% of traffic.
