# Supervisor role

The initial platform-wide behavior below is superseded by [location-based Supervisor teams](supervisor-teams-2026-10-31.md).

Added `supervisor` / Supervisor / Msimamizi as a permission-scoped staff role. It uses the existing admin account routing and agent-management workspace on web and Manage mobile. Existing Agent Manager assignments are unchanged.

Permissions: `agents.manage`, `agent_roles.manage`, `agent_performance.view`. Supervisors can use the agent directory, add existing profiles or create new agents through the existing mobile tools, manage categories and agent access, and use the web directory's approval/deactivation actions. The web directory now includes an Add agent form that creates accounts through the protected Edge Function without changing the supervisor's session. Like Agent Manager, the role also sees operating locations. This is platform-wide agent supervision; it does not introduce per-supervisor teams, commission rules, or staff-role delegation.

Only Super Admin can assign the role through the existing staff access tools. No account is assigned automatically. Finance, customer-directory, booking management, listing moderation and staff-role assignment permissions are not included. Existing broader platform RLS policies were not redesigned in this change.

Both `create-agent-account` and `verify-agent` now require authenticated admin membership **and** `agents.manage`, rather than general admin membership alone. Browser CORS preflight is supported. Handlers were extracted for isolated authorization testing; entry points still register them directly with `Deno.serve`.

Role labels/descriptions and new status copy are translated in English/Swahili and synchronized to Flutter. Native UI uses the existing agent-management screen; distributing the localized role label requires the user's new app build. No APK or app bundle generated.

Validation:

- Isolated PostgreSQL migration test passes, including repeat application and exact restricted permissions.
- Deno tests pass for both real handlers: preflight, missing authentication, denied staff, non-admin denial and permitted supervisor reaching validation; all network calls intercepted, no records created.
- Eight web permission/translation tests pass; changed web components pass ESLint.
- Six Manage mobile workspace permission tests pass; affected native code passes analysis.
- Full production OpenNext build succeeds.
- Management browser suite passes at 320/375/390/430/768/1440 widths, including new supervisor account creation with intercepted fixtures and preserved staff session.

Release uses only migration `20261031100000_agent_supervisor_role.sql`; older-app compatibility migration remains pending. Both agent Edge Functions have been deployed. Production role definition verified read-only; assigned supervisor count is zero pending the user's account email. Live mutation of real customer/agent data is not part of smoke tests.

Cloudflare web version `eab40a70-87ef-41a1-9645-4820a2da7b11` is deployed at 100% traffic on both custom domains. The live browser Supervisor Add agent flow passed with intercepted fixtures, preserving the staff session. Both live Edge Functions passed browser OPTIONS preflight and unauthenticated mutation denial. An initial live network request timed out; retry passed both endpoints. Deployment wrappers reported Windows stderr-warning exit codes; actual successful deployments were confirmed through provider output and active Cloudflare deployment history.
