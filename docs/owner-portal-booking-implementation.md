# Owner portal and booking implementation

## Delivered

- One-login `owner`, `agent`, and `admin` routing in Manage Mobile, including a workspace chooser for multi-role accounts.
- Owner application and administrator verification. Approval creates the verified owner profile and grants the existing `owner` role.
- Web owner portal at `/owner` and an Owner workspace inside `apps/manage_mobile`.
- Owner asset claims linked to canonical rental assets; only verified claims participate in owner booking authorization.
- Versioned owner booking agreement with immutable acceptance records.
- Asset-level booking policies supporting manual approval first and conditional automatic approval configuration.
- Transactional owner approval with response deadline and overlap protection through the existing exclusion-constrained reservation table.
- Tenant invitations requiring acceptance by an authenticated customer, rental agreements, move-out notices, owner statement entries and participant-scoped RLS.
- Admin owner-application review in the web management portal.

## Financial integration status

`owner_statement_entries` is an accounting ledger, not a wallet or escrow. Booking collection, automatic refunds and owner payouts are not activated by this migration. Existing contact/chat providers remain separate from booking settlement.

Before activation, confirm merchant acquiring capability, settlement/refund support, provider webhook signature rules, contracts, tax/accounting treatment and applicable Tanzanian regulatory requirements. Then add an audited server-only payment workflow and an explicit global activation switch.

## Deployment requirements

1. Review and apply `20261024120000_owner_portal_and_booking_policy.sql` to the intended Supabase environment.
2. Confirm private verification-document storage policies before enabling uploads; the current web application submits an application without document upload rather than exposing an insecure path.
3. Create and verify owner asset claims through authorized inventory administration.
4. Review the seeded agreement version and publish a replacement version if legal wording changes.
5. Rebuild and release Web, Customer Mobile and Manage Mobile. No production deployment was performed by this change.
