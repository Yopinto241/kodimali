# KODIMALI 2.0 implementation and release checklist

## Audit summary

The repository already had customer and guest booking requests, viewing appointments, agent assignment, agent/listing approval, admin sub-roles, audit logs, notifications, ClickPesa-oriented payment records and customer receipts. These remain intact. The missing boundary was a private contributor lead that could be verified into one canonical physical asset independently of agent advertisements.

Implemented in `20261023120000_kodimali_2_referrals_inventory_bookings.sql`:

- Private customer submissions, status/eligibility tracking and internal follow-ups.
- A dedicated `information_admin` administrative role with `information.manage`, `inventory.manage`, `referrals.manage` and `disputes.manage` permissions.
- Canonical rental assets, duplicate fingerprints, owner-advertising authorization and verification history. Listings may link to one asset, allowing multiple agent advertisements without splitting availability.
- Referral agreements, calculated reward records and unique manual payout records. No withdrawable wallet was added.
- Versioned booking policies, accepted-policy references, payment expiry, disputes and verified provider transactions.
- Atomic `[start,end)` inventory reservations protected by a PostgreSQL exclusion constraint. Browser callbacks cannot confirm a paid reservation.
- An idempotent provider webhook event store keyed by provider and provider event ID.
- Contributor and Information Admin screens in the existing Flutter apps.

## Security model

Contributors may read only their own submissions, agreements, rewards and payout result. Owner contacts, evidence and internal follow-ups are available only to Information Admin staff. Public listing queries do not join these tables. Staff mutations require database permissions; the UI is not the authorization boundary.

`confirm_asset_reservation` locks the booking, requires a canonical asset, checks a server-verified paid transaction for paid reservations, and inserts into the collision-protected reservation table. The unique payout constraint and row lock prevent duplicate payout. An open dispute blocks payout.

## Payment provider configuration (not enabled)

Before financial collection is enabled, legal/security owners must approve the provider contract and confirm authorization, signed webhooks, refunds, reconciliation, settlement and payout capabilities. Then configure secrets only in the Supabase Edge Function environment, never in Flutter or Next.js:

- provider API base URL and server credential;
- webhook signing secret and allowed algorithms;
- merchant/account identifier;
- an explicit production payment feature flag, default `false`;
- monitored webhook and reconciliation alert destinations.

The webhook handler must verify the raw-body signature, insert `payment_webhook_events`, return success for an already-recorded event, independently fetch/verify the transaction where supported, and only then set `booking_payment_transactions.status = 'paid'` and `verified_at`. A return page must remain informational.

## Booking policy draft for legal review

This is product scaffolding, not approved legal text. Publish a version per category that states: viewing appointments are free; each charge is labelled as reservation payment, security deposit, rental balance or service fee; the full price and amount due now are disclosed before authorization; refundable and non-refundable amounts and cancellation deadlines are explicit; KODIMALI or supplier inability to provide the verified item receives a full refund subject to law; disputes pause referral payouts; and acceptance time plus immutable policy version are recorded.

For houses, keep `booking_kind = 'viewing'` until the asset is verified, owner authority is evidenced, the agreement is approved and the production payment feature is separately enabled.

## Safe deployment

1. Back up the database and test restore; take a staging schema snapshot.
2. Apply migrations to a Supabase staging branch with `supabase db push`; do not edit or squash production history.
3. Run `node scripts/check-supabase-migrations.mjs`, SQL authorization tests, Flutter analysis/tests and the web lint/build.
4. Assign `information_admin` through the existing super-admin role function. Test with separate contributor, agent, Information Admin and unrelated-user accounts.
5. Deploy apps with payment collection still disabled. Verify submission privacy, assignments, duplicate review and asset publication end to end.
6. Backfill `listings.asset_id` only after assets are matched and verified; never auto-merge likely duplicates.
7. Enable reservation payments only after legal/provider approval and a signed-webhook production drill. Automated payouts remain out of scope.

## Remaining provider-dependent work

Implement the chosen provider's reservation-payment initiation, signed webhook and refund Edge Functions after capabilities and contract terms are verified. Photo upload UI/storage policies, richer category-specific contributor fields, automated duplicate scoring, notification templates, refund execution and scheduled unpaid-booking expiry also remain follow-up work. Manual referral payout recording is intentionally the MVP endpoint.
