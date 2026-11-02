# Owner, information and staff workflows — 29 October 2026

Website deployed to https://kodimali.com. Cloudflare version: `fb629d89-626b-4beb-be9c-e1d3a24d0e14`.

## Delivered

- Agents can create listings without owner details, or add/edit/remove a private owner contact. Name and phone are required only when supplying a contact. Contact entry does not verify ownership or grant account authority.
- Verified owners can select verified agents, grant asset delegation, revoke access, and recommend their own agents. Agent Manager reviews recommendations; accepting a recommendation does not automatically grant asset access.
- Toa Taarifa supports structured submissions, consent for owner contact sharing, submission history, agreement acceptance, reward status and payout references.
- Information Admin reviews private leads, assigns agents, links published listings, records follow-ups and proposes explicit fixed-TZS or percentage reward terms. Contributors must accept the current terms version.
- Completed bookings with verified service fees generate eligible rewards. Deposits, balances and unverified fees do not qualify. Modern and legacy fee records are not counted twice.
- Finance reviews rewards and records an already completed external payout with its reference. The form does not transfer funds. Dispute/refund checks and idempotent payout recording protect this workflow. No default commission rate was invented.
- Role permissions are enforced by database functions and policies as well as workspace navigation.

## Live staff accounts

All accounts were created, email-confirmed and tested using password sign-in. Each has the admin base role and only its requested admin subrole. Credentials are intentionally excluded from this report.

| Email | Subrole |
| --- | --- |
| financekodimali@kodimali.com | finance_admin |
| operationadmin@kodimali.com | operations_admin |
| informationkodimali@kodimali.com | information_admin |
| agentmanager@kodimali.com | agent_manager |
| eventcordinator@kodimali.com | event_coordinator |
| listingmoderator@kodimali.com | listing_moderator |
| marketing@kodimali.com | marketing_admin |
| customersupport@kodimali.com | support_admin |
| businessanalyst@kodimali.com | analyst |

The event coordinator email retains the exact supplied spelling.

## Database and verification

Applied migrations:

- `20261029160000_optional_owners_and_agent_recommendations.sql`
- `20261029161000_information_referral_workflow.sql`

Passed:

- Database lint: zero errors.
- Rolled-back database suites 043 and 044, covering role boundaries, private contacts, agent recommendations/delegation, contributor consent, reward basis, disputes and repeat payout protection.
- Manage Flutter tests: 15 passed; targeted analysis of changed Manage and Customer sources: no issues.
- Web TypeScript check, six access/filter tests, production build and Cloudflare deployment.
- Authenticated live queries for Information Admin nested submissions, Finance rewards, Agent Manager recommendations and verified agent directory.
- HTTP 200 without server exception markers for `/admin`, `/agent`, `/owner`, `/toa-taarifa` and `/account?section=information`.

Mobile changes are source-only. **No APK was created for this task**, as requested. Browser/device end-to-end interaction and real-money payouts were not exercised. The contributor reward queue is separate from the existing typed financial-obligation overview; the deployed form records external payouts rather than initiating transfers.
