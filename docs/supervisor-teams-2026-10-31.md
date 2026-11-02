# Location-based Supervisor teams

This replaces the initial platform-wide Supervisor behavior. Multiple supervisors are supported. Each has one assigned location (region, district, ward or area), including its descendants. Multiple supervisors may cover the same location, but their teams remain separate.

Each agent has one `supervisor_id`; the existing unique agent profile constraint also prevents duplicate agent accounts for the same person. Only Super Admin can assign or transfer an existing agent. Supervisors cannot take another team's agents or change their own territory. Super Admin keeps global access. Existing agents start unassigned; no production teams or staff assignments are invented automatically.

Super Admin uses **Manage → Agents → Supervisors and territories** to configure a registered account and its territory. Each agent card has an **Assigned supervisor** control for assignment, transfer or removal. The same controls are available in the new Manage mobile source. New agents created by a supervisor receive that supervisor automatically through protected Auth app metadata and an agent insert trigger. They must have a valid operating area inside the assigned territory. Public signup metadata cannot claim a team.

An inactive, unconfigured or removed Supervisor role fails closed. Previously configured supervisors stay excluded from blanket admin policies even after the role is removed, preventing accidental promotion to unrestricted admin. Assigning Super Admin explicitly restores global access. Other extra roles do not widen a scoped supervisor's permissions. Existing non-supervisor staff retain their established access.

Database enforcement covers agent rows, profile details, verification documents/files and service-category assignments. Supervisor searches use the existing RLS-aware search function. General admin policies now exclude scoped supervisors. The verification Edge Function checks team ownership and retains the supervisor predicate on the actual update, protecting against transfers between authorization and update. Ownership, territory changes and transfers are audited. Territory updates and hierarchy changes cannot silently strand agents outside an active territory.

The web Supervisor form navigates only inside its assigned territory. Native creation shows the assigned territory; the existing area picker still lists public location options, with the server rejecting out-of-territory submissions. Scoped supervisors cannot open global location management, customer directories, global agent recommendations, finance or staff-role administration. Super Admin can assign any registered account through the territory form, without first promoting it to another staff role.

The supervisor configuration panel uses a controlled section. Native `details` was unsuitable because the site's outside-click menu handler collapsed it before clicks on the transfer button completed, moving the target under the pointer.

Validation:

- Transactional PostgreSQL fixtures use existing production agent-account/verification guards and actual RLS policies, without production records. Tests cover overlapping territories with separate teams, private data/documents/storage, search, category writes, out-of-area creation, automatic assignment, forged user metadata, unauthorized transfers/direct writes, immediate loss of old-team access, location-tree changes, inactive/revoked supervisors, anonymous RPC ACLs and continued Super Admin/Agent Manager access.
- Four Deno tests exercise both real Edge handlers with all HTTP requests intercepted, including creation metadata, geography rejection, cross-team verification denial and the ownership predicate on accepted updates.
- Eight web permission/translation tests pass. Changed web components pass ESLint. The full OpenNext production build passes.
- Twenty-six native permission/widget tests pass, including territory configuration and agent transfer at 390 px, fail-closed creation, and existing management navigation/directory/location regressions. Affected native code passes analysis.
- Browser management regressions passed at 320/375/390/430/768/1440 widths. Additional Supervisor/Super Admin fixture tests cover scoped area selection, preserved staff login, inactive territory denial, territory configuration and exclusive assignment.

No APK/app bundle is generated. Mobile source changes require the user's new app build. Booking, commission and payment rules are unchanged. Deployment records are appended after live verification.

## Production release

Applied only `20261031110000_supervisor_territories_and_exclusive_agents.sql` transactionally with migration history. The unrelated older-app compatibility migration remains pending. Deployed both agent Edge Functions and Cloudflare web version `9cc70572-5b19-4aa0-8f2c-2c471fdcce07`; provider deployment history confirms 100% traffic on both custom domains.

Read-only production checks confirm the owner column, zero invented territory/team assignments, authenticated-only configuration/transfer RPC ACLs, denied unauthorized configuration/transfer, and preserved access for an existing Super Admin. Live Edge checks pass preflight and unauthenticated denial. Live browser fixture checks pass scoped agent creation without replacing the staff session, inactive-territory denial, Super Admin territory configuration and exclusive assignment. Live public routes, private noindex headers and sitemap checks also pass. No real customer/agent mutations were used for testing.

Logs: `tmp/supervisor-teams-db-tests.log`, `tmp/supervisor-scoped-edge-tests.log`, `tmp/supervisor-teams-web-tests.log`, `tmp/supervisor-teams-mobile-tests.log`, `tmp/supervisor-teams-analyze.log`, `tmp/supervisor-teams-smoke-live.log`, `tmp/supervisor-teams-live-verify.txt`, `tmp/supervisor-teams-public-live.log`.
