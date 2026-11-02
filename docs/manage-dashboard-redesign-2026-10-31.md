# KODIMALI Manage redesign — implementation and review

Implemented on `feature/kodimali-events`, preserving the existing uncommitted work. Production has not been deployed or changed. No APK was generated.

## 1. Problems confirmed

- Web navigation changed local tabs instead of URLs; the large navigation grid pushed content down on phones.
- Native admin-menu permission filtering compared translated labels, allowing restricted entries to appear in Swahili. It now checks stable module IDs.
- Global public-site card styles overrode management text, fields and buttons.
- Native metadata chips forced white text on light cards. Inactive status labels could receive the active badge tone.
- Flutter instantiated every workspace destination at startup, including modules the user had not opened.
- Customer search operated on a limited downloaded result set. Moderation and location screens could load entire lists.
- Location management mixed parents and children. Region creation could omit the required country parent.
- The existing self-reference foreign key uses `ON DELETE CASCADE`; several other modules use `SET NULL`. A direct delete could remove children or clear references.
- Some native refresh callbacks returned a Future from `setState`, causing an error after a successful save.

## 2–3. Architecture, navigation and pages

The web retains the existing authenticated portal and operations, with a shared compact header, mobile drawer and desktop sidebar. Normal document navigation remains in place to preserve the previous fix for stale release/RSC navigation failures. The active module now has its own URL and appears directly below its heading. Manage links disable unused RSC prefetching because navigation uses document requests.

| URL | Purpose |
| --- | --- |
| `/manage` | Authorized dashboard; staff without dashboard access go to an allowed module |
| `/manage/users` | Customer directory |
| `/manage/users/[id]` | Authorized customer details |
| `/manage/listings` | Listing management and moderation |
| `/manage/listings/[id]` | Listing details and existing edit/moderation actions |
| `/manage/locations?parent=[id]` | Persistent parent/child location explorer |
| `/manage/information`, `/manage/business`, `/manage/admin-access` | Existing specialist workspaces |
| `/manage/requests`, `/manage/categories`, `/manage/agents`, `/manage/owners` | Existing operational modules |
| `/manage/reports`, `/manage/promotions`, `/manage/notifications`, `/manage/profile`, `/manage/add-listing` | Existing authorized modules |

`workspace=agent` preserves agent context for accounts with several roles. Existing `/admin`, `/agent` and management registration entry points remain available. Unsupported modules and malformed detail identifiers show the not-found screen. Filters and page numbers use URL parameters, retaining their context through refresh, details and Back. Management routes retain the existing private indexing rules.

Flutter checks module permissions using stable IDs, independently of the selected language. Dashboard opens first when authorized; otherwise the first permitted destination opens. Flutter keeps the existing role-filtered destination lists, instantiates only visited modules, preserves their state and handles Back to the previous module. Locations and record details use native pushed screens. No parallel role/account system was introduced.

## 4. Users management

- Twenty records per page, with search and confirmation filtering performed before database pagination.
- Real name, email, phone, language, registration/update dates and email-confirmation state; no invented account status.
- Responsive web rows/cards, native cards, dedicated details and retained search context on return.
- The same existing customer-directory scope: customer accounts excluding admin and agent accounts.
- The new RPC requires both administrative identity and `users.view`, and returns only the directory projection.
- Missing backend deployment produces a clear update-required message. It does not fall back to downloading profiles.

## 5. Listings management

Web listings use server-side title/category/status/publication-review filters and twenty-record pages. Native agent and moderation lists also page their results; moderation adds search, category and status filters. The business centre's existing listing behavior is preserved separately.

Cards show real price, location, category and state, with image previews where available. Details preserve existing owner fields and listing editing. Media URLs are signed using the authenticated client's existing storage permissions. Native admin details use the existing administrative moderation RPC; agent publication/payment actions remain in the agent context. Existing permanent deletion and inquiry safeguards remain available through listing moderation.

## 6. Location hierarchy

Read-only Supabase inspection confirmed one country named Tanzania, 31 regions, 152 districts, 4,343 wards and eight areas at inspection time. The existing enum also supports streets under areas. No location tables or hierarchy levels were invented.

The entry screen resolves the actual Tanzania record and immediately displays its regions. Opening a region loads only its districts, then wards and areas. Web breadcrumbs use persistent URLs; native breadcrumbs and Back return through the existing screen stack. Child lists use bounded queries, search and pagination.

Creation fixes the parent and derives the child type from the opened level. Names are normalized, existing uniqueness and hierarchy constraints remain authoritative, and duplicate errors are explained. Rename preserves the location ID and parent, retaining related records.

The prepared guarded deletion RPC locks the hierarchy and referencing tables, checks **all existing foreign-key references**, including records hidden by caller RLS, and rejects deletion when any child or reference exists. It never cascades or silently clears references.

## 7. Loading

The existing KODIMALI PNG is reused on the web and packaged once in the shared Flutter design system. CSS clipping and a native `AnimationController` fill the logo progressively. Both honor reduced motion and stop as soon as their loading component disappears. There is no minimum splash duration, artificial delay or new animation dependency.

Web loading covers initial authentication, App Router `loading.tsx` and significant data loads. Simple actions retain their normal busy/disabled state. Native directory/location/moderation loading and the app splash use the shared brand loader.

## 8. Appearance and language

Manage-specific navy, muted teal, neutral surfaces and gold focus/selection accents now avoid inherited public-site card styling. Labels, inputs, headings and buttons have explicit readable colors. Primary targets are at least 44 px on the web; records adapt to narrow screens. Status text remains visible alongside its color.

Native cards use the shared mobile theme. Metadata text adapts to light cards and dark headers; inactive and unverified badges no longer receive an active tone merely because their text contains “active” or “verified.”

New copy and status labels use the English/Swahili catalogs. The language control remains accessible inside Manage and its login. User-written names, descriptions, addresses and field values remain data. Apartment, book and booking retain the requested wording.

## 9–10. Supabase and security

Prepared, **not applied**: [20261030150000_manage_directory_and_safe_locations.sql](../supabase/migrations/20261030150000_manage_directory_and_safe_locations.sql).

It introduces only two functions: `search_manage_customers` and `manage_delete_unused_location`. The first is needed because the deployed directory RPC paginates internally before callers can apply a global search. The second is needed to prevent existing cascade/SET NULL behavior from destroying location relationships.

The functions check the existing identity and permissions, use a fixed search path, revoke public execution and grant authenticated execution. Browser and Flutter code use the existing public client and RLS. No service-role credential is introduced. Location add/rename continue to use existing RLS and triggers. No booking, payment, ledger, cancellation, refund or payment-service logic was modified.

## 11–13. Validation and changed files

| Check | Result |
| --- | --- |
| Web ESLint, entire app | Passed |
| Next production build, including TypeScript | Passed |
| OpenNext Cloudflare Worker build | Passed; local artifact only, not deployed |
| Web translation, roles, search and SEO unit tests | 14 passed |
| Manage Flutter suite | 36 passed |
| Customer Flutter regression suite | 8 passed |
| Shared Flutter design-system tests | 2 passed |
| Manage and design-system Flutter analysis | No issues |
| Isolated PostgreSQL management tests | Passed; transaction rolled back |
| Browser management suite | Routes, paging, search beyond the first page, details, refresh, Back, contextual creation, permissions and sampled text contrast tested at 320/375/390/430/768/1440 px; error recovery and private invalid-route handling passed |
| Browser language regression | Public screens and customer/admin/agent/owner fixture workspaces passed |
| Navigation regression | Repeated navigation with rejected RSC responses, Back and blocked storage passed |

Database tests exercise search, confirmation filters, pagination, staff exclusion, denied permissions, direct unauthorized location writes, the existing hierarchy validator, duplicate rejection, rename relationships, cascade prevention, hidden references and successful deletion of an unused leaf. Browser and native checks use fixture identities/data; they do not mutate production accounts.

Native tests also verify that an unassigned admin sees no restricted menu entries in either English or Swahili. Native tests cover narrow-screen customer search/details, hierarchy navigation and preserved parent context, contextual add/rename, lazy destination loading, module Back, duplicate/permission errors, missing backend functions, metadata contrast and reduced-motion loader disposal. Sampled web headings/actions and native metadata meet a 4.5:1 contrast threshold; this is not a claim of a complete accessibility certification.

Primary implementation files:

- Web routes: `apps/web/src/app/manage/page.tsx`, `[section]/page.tsx`, `[section]/[id]/page.tsx`, `loading.tsx`.
- Web shell/modules: `manage-workspace-shell.tsx`, `manage-portal.tsx`, `manage-users.tsx`, `manage-locations.tsx`, `manage-listing-filters.tsx`, `public-site-chrome.tsx` under `apps/web/src/components`.
- Web integration: `apps/web/src/lib/manage-routes.ts`, `apps/web/src/app/layout.tsx`, `globals.css`, `navigation-progress.tsx`, translation catalogs.
- Flutter: `manage_workspace_scaffold.dart`, `admin_shell_screen.dart`, `admin_workspace_access.dart`, `locations_tab.dart`, `users_tab.dart`, `listing_approval_tab.dart`, `agent_listings_tab.dart`, `listing_detail_screen.dart`, `manage_repository.dart`, `manage_ui.dart`, `kodimali_status_chip.dart`, `splash_screen.dart`.
- Native refresh fixes: `admin_dashboard_tab.dart`, `categories_tab.dart`.
- Shared Flutter: `packages/flutter_design_system/lib/kodimali_loading.dart`, its export, asset and pubspec declaration; Flutter core translation catalogs/generated copy.
- Tests: `scripts/test-manage-ui.py`, `scripts/test-manage-directory-locations.sql`, its existing-validator fixture, `apps/manage_mobile/test/core/manage_locations_ui_test.dart`; language-browser regression updated for routed navigation.

Screenshots show fixture records, not production customer data:

| Screen | Mobile | Desktop |
| --- | --- | --- |
| Dashboard | [390 px](../design-previews/manage-redesign/dashboard-390.png) | [1440 px](../design-previews/manage-redesign/dashboard-1440.png) |
| Users | [390 px](../design-previews/manage-redesign/users-390.png) | [1440 px](../design-previews/manage-redesign/users-1440.png) |
| Listings | [390 px](../design-previews/manage-redesign/listings-390.png) | [1440 px](../design-previews/manage-redesign/listings-1440.png) |
| Regions | [390 px](../design-previews/manage-redesign/locations-390.png) | [1440 px](../design-previews/manage-redesign/locations-1440.png) |
| Ward → areas | [390 px](../design-previews/manage-redesign/locations-hierarchy-390.png) | — |

## 14–15. Limitations and deployment readiness

The implementation is prepared for review and authorized rollout. The web release was deployed on 2026-10-31 after user authorization (see release record below). Customer search and guarded location deletion require the prepared management RPC migration before distributing the new Manage build. Live authenticated create/edit/delete smoke tests remain a rollout check; development validation used isolated fixtures and read-only production schema inspection.

The existing older-app booking compatibility migration `20261030140000_legacy_booking_audit_compatibility.sql` is still a separate pending change. Review pending migrations individually; do not blindly apply the entire local migration queue.

After explicit authorization, the rollout order is: apply the reviewed management migration, verify permissions against staff accounts, deploy the tested web source using the existing Cloudflare process, then generate/distribute the new Manage app. Before rollout authorization, no APK, Worker deployment or Supabase migration had been produced/applied. The authorized web/backend release is recorded below; payment services remain unchanged.


## Authorized release: 2026-10-31

Applied only 20261030150000_manage_directory_and_safe_locations.sql in a transaction with migration history. The older-app compatibility migration 20261030140000 remains pending. Read-only live checks confirmed both function definitions, fixed search paths, unauthorized request denial, and authenticated authorized-staff customer search using an impossible record ID; no customer records were returned or changed. Existing platform default grants include anon execution, but both RPC bodies enforce admin and module permissions before accessing records.

Deployed the previously tested OpenNext artifact to both custom domains. Cloudflare confirms 100% traffic on Worker version d118364e-a203-4082-8ba6-df9e580b870c. Deployment output reported success; the Windows wrapper returned status 1 after a Node warning, so the active deployment was independently confirmed with Wrangler deployment history.

Mobile source is ready for the user-generated new app. No APK or app bundle was generated. Live authenticated create/edit/delete against real records was intentionally not performed; mutation coverage uses intercepted fixtures and isolated PostgreSQL tests.

Live post-deployment browser acceptance passed at 320, 375, 390, 430, 768 and 1440 pixels: routing, search, pagination, details, hierarchy, contextual add using intercepted fixtures, restricted deep-link access, error recovery and invalid-route noindex. Public smoke checks passed for homepage, Events, Plan Event, four management routes and sitemap. Management X-Robots-Tag remains noindex; sitemap excludes management/account routes. Logs: tmp/manage-browser-live.log, tmp/manage-live-public.log, tmp/manage-release-verify.txt, tmp/manage-staff-release-verify.txt.
