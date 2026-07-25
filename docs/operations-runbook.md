# KODIMALI operations runbook

## Health checks

- Monitor `GET /api/health` from outside the hosting provider every five minutes.
- Alert when it returns a non-200 response twice consecutively.
- Verify Supabase Auth, REST, Storage, and Edge Function dashboards after an alert.

## Payment operations

- Treat ClickPesa webhooks as hints and reconcile pending transactions against the provider status.
- Never reveal contact details based only on a client response.
- Review payments that stay pending beyond 15 minutes or have a webhook/provider status mismatch.
- Keep unique order references and make payout/collection retries idempotent.

## Booking and chat operations

- `booking_requests.agent_id` is assigned from the listing and must never be reassigned by a customer or agent.
- Chat participants are derived from the authenticated customer and assigned agent on that request.
- Admin intervention must write an audit event.
- Review requests that have no agent response within the configured service window.

## Database deployments

- Never edit an already-applied migration.
- New migrations use a unique UTC `YYYYMMDDHHMMSS_description.sql` name.
- Run `node scripts/check-supabase-migrations.mjs` before deployment.
- Use `supabase db push --dry-run` against staging before production.
- Back up the database and capture `supabase migration list --linked` before repairing history.
- The repository contains legacy short-version migrations. Do not replay or repair those history rows casually; use the post-20260720 timestamped chain for all new work.

## Release checks

1. Run Flutter analysis for both apps.
2. Run web lint and production build.
3. Verify guest booking remains available without authentication.
4. Verify a signed-in customer sees only their requests and conversations.
5. Verify an agent sees only requests assigned to that agent.
6. Verify admin payment/report queues and audit records.
7. Test payment-required and free-contact modes.

## Mobile release credentials

- Android verified listing links require `/.well-known/assetlinks.json` on the production web domain with package `co.kodimali.customer_mobile` and the real release signing SHA-256 fingerprint.
- iOS universal links require `/.well-known/apple-app-site-association` with the real Apple Team ID and bundle `co.kodimali.customerMobile`.
- Background push requires the production Firebase/APNs projects, signing credentials, platform configuration files, notification permission flow, and a server-side delivery worker. Supabase Realtime and durable notification rows already provide in-app updates, but they do not replace OS push while the app is closed.
- Never commit production signing keys, APNs private keys, or service-account credentials.
