# Role workspace repairs — 29 October 2026

Addresses the dashboard and database gaps identified in the role review.

## Changes

- The Manage workspace switcher and login router use the same destination rule. Active Events agents reach Events; blocked agents reach account status; owners and administrators retain their own workspaces.
- The workspace badge displays the selected role.
- Admin permissions come from a server RPC using active role definitions. Permission-loading failures show Retry instead of an indefinite spinner.
- Growth Ops fetches and renders only authorized sections. Analysts retain read-only financial reports; finance actions, moderation, marketing, wallets and role assignment remain separate. Only Super Admin receives role-assignment controls.
- Admin Dashboard hides payment settings from non-Super Admins and payment operations from staff without payment-management permission.
- The website honors `/admin` and `/agent` separately for accounts holding both roles. Its menus and Business Operations queries use assigned permissions. Available workspaces have explicit links; permission failures offer retry.
- Owner listing reads use the live publication fields and the canonical asset category when selecting booking policies. Owner loading errors can be retried.
- Owner booking configuration uses `publication_review_status` and the canonical asset category, replacing missing historical listing fields.
- Tenant token generation, invitation acceptance and quote fingerprints explicitly resolve crypto functions in `extensions`.
- Customer fulfillment confirmation loads the full milestone row correctly and preserves customer ownership checks and retry behavior.
- Support chat lookup qualifies the conversation ID, preserving its support permission check and audit entry.
- Restores the missing reports table used by agent trust and website moderation; mobile reports now read actual records. Reporters can submit/read their own reports; moderators can review status. Anonymous users have no table privileges.
- Global marketplace settings writes have a database trigger requiring Super Admin or trusted service/maintenance access. This protects direct requests as well as dashboard controls.

## Database verification

`supabase/tests/043_role_workspace_repairs.sql` is explicitly transactional and ends with rollback. It tests all active admin assignments, global-settings boundaries, owner authority, tenant-token generation/acceptance/replay, full Instant Booking configuration and deterministic quote fingerprints, customer fulfillment authorization/idempotency, agent trust, support authorization and actual report RLS under `authenticated`.

Tests run against the linked schema before migration application and again after application. Fixture rows, temporary role assignments, a temporary listing asset link and test rollout-flag changes are rolled back. No invitations are sent and no payments or transfers are initiated.

## Application verification

- Manage: 15 Flutter tests, including Events routing and staff permission boundaries.
- Web: three permission-matrix tests covering all ten admin subroles, Agent and unassigned Admin.
- Targeted Flutter analysis; TypeScript and production Cloudflare build.

This verifies the identified repairs. It is not an exhaustive security audit of every historical table, RPC or screen, and does not replace signed-in device acceptance testing.

## Release

Database migrations:

- `20261029150000_role_workspace_repairs.sql`
- `20261029151000_super_admin_marketplace_settings.sql`

Website: https://kodimali.com. Cloudflare version `bf20940f-6a6d-433b-9443-b42609d67e6d`.

The final Manage APK and verification results are recorded below once packaging completes. Customer-side database repairs apply without a new Customer APK.


Final deployed database verification: both migrations applied; the transactional workflow suite passed after deployment; `supabase db lint --linked --level error` returned an empty results list. Targeted Flutter analysis passed with no issues after the final dashboard restriction. Public HTTP smoke checks returned 200 for `/admin`, `/agent`, `/manage`, `/owner`, `/account` and `/events`. These public checks verify page delivery, not signed-in role interactions.


Final Manage release APK: `builds/role-repairs-2026-10-29/kodimali-manage.apk` (66859314 bytes), SHA-256 `0d22b63a3a85f50bb386f3bf64146d7753f2f20673ef0d1c138c83deb4e05f0e`. The final source build passed. Android signature verification passed, its certificate matches the previous Manage installer, the package remains `co.kodimali.manage_mobile`, and the AOT binary includes the new permission RPC. `manifest.json` records the installer and deployment metadata. This is a local installer; no store release was performed.
