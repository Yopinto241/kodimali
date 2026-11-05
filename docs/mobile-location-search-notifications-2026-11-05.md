# Mobile listing organization, search and notification improvements

Implemented on 5 November 2026 for Customer and Manage. Backend migrations and `dispatch-push-notifications` are deployed to the existing Supabase project. Mobile source is ready for the next signed build; no APK/AAB, installation or store publication was performed in this task.

## Listing details and contact

Customer details now follow a consistent order: media, title/location, price, description, property features/services, agent contact, Chat and booking, then comparison/price-alert tools. Property attributes share a single readable section. The chat action is labelled **Chat**.

Free or valid unlocked contact access displays the actual agent number with a Call icon and a WhatsApp action. Tapping the number opens WhatsApp; selecting text allows copying it. When payment is required, both **Call / View number** and **WhatsApp** use the existing server-authorized access flow before opening the requested destination. Loading and failed access checks show progress/retry rather than inventing a payment state. Owner contacts remain private to authorized Manage users.

Manage's editor places public information and pricing first, with separate expandable sections for category fields, private owner contacts and media. Owner contacts have Call and WhatsApp actions.

## Finding and managing listings

In **Manage → My listings** or the admin listing workspace:

1. Open a region, district, ward or smaller location.
2. Use **View listings here** at any level. The button remains above the bounded folder list; breadcrumbs return to a parent.
3. Choose **All statuses**, **Active**, or **Parked / not on market**. Parked includes inactive, suspended, expired, removed and unavailable records according to their stored status/availability.

Location filtering happens in the database before the existing listing pagination. No records are moved or deactivated by browsing. The read-only directory view uses PostgreSQL `security_invoker`, preserving listing RLS. Agents retain their explicit own-agent filter; admins can open **Agent management → View agent listings** to narrow the workspace to one agent, then browse that agent's locations. Management text search also covers public location labels.

## Agent and administrator locations

Agent management has the same location browser, backed by a location-scoped version of the existing agent search. Its status filters and pagination continue to apply within the selected territory. Stale search responses cannot replace a newer location selection.

Super Admin's **Administrative roles** area now supports **View staff here** and a location icon for assigning an existing administrator's work location. An explicit work location takes precedence over their supervisor territory or agent location for directory organization. Accounts without a location are labelled as unassigned. Assigning a work location does not grant roles, transfer agents or change supervisor territories; only Super Admin may assign it.

## Customer search

- Location suggestions appear while typing; selecting one searches listings at that location and clears conflicting GPS scope.
- **Search all Tanzania** provides an explicit nationwide search option.
- Searches fetch 40 results per page with **Load more results**, rather than stopping after the first 20. The backend supports up to 100 per page; there is no fixed total-result cap in this screen.
- Swahili/English keyword groups cover houses, rooms, plots/land, farms, vehicles, apartments, offices, shops, warehouses, venues and rental terms. Every significant query token must match, including location words. Whole-word matching avoids mistakes such as matching “room” solely because a description contains “bathroom”.
- Existing category, price, period and geographic filters remain in force. Explicit sort choices remain available; search relevance precedes randomized discovery ordering. Optional location-suggestion failures do not hide listing results.

## Notifications

Both apps retain cold-start taps until navigation listeners attach, recover initialization failures, retry device registration after transient failures and on resume, and periodically refresh registration while foregrounded. Customer booking/payment notifications with a booking identifier now open the corresponding request. Foreground presentation uses local notifications to avoid duplicate iOS alerts.

The dispatcher saves successful per-device receipts so retries can skip acknowledged installations. Partial delivery remains retryable; malformed payload errors do not disable valid tokens. Only explicit FCM `UNREGISTERED` responses disable installations. Provider requests have bounded timeouts.

Live inspection also found that delayed retries had no scheduler and registration-triggered wakeups lacked the dedicated worker credential. A private database wakeup function now obtains the existing credential from Vault. The existing pg_cron extension runs **kodimali-push-retry** every minute as the stable `postgres` role. It wakes the dispatcher only for due or stalled work. Registration revives recent missing-device skips without resetting exhausted failures or user-preference skips on every heartbeat. The scheduler has completed successful live runs.

Physical-device foreground/background/terminated delivery still needs a device check with the updated apps and OS notification permission enabled. No test push was sent to customers. Firebase credentials are configured; scheduler success is not proof of delivery to a physical phone.

## Verification and recovery

- Customer: **33 tests passed**; Manage: **49 tests passed**; both analyzers report **No issues found**.
- Shared push lifecycle/inbox: **5 tests passed**. Edge delivery classification/retry: **2 tests passed**; dispatcher type check passed.
- A fresh consistent database backup captured schemas/data, roles and recovery configuration outside Git. It restored into an isolated local database with all **175 scoped table counts matching**. Managed cron/net/Vault runtimes were stubbed only in that isolated verification environment.
- The directory migration preserved the contents of the original tables in the restore. Tests covered bilingual matching, wrong-location exclusions, anonymous denial, agent RLS parity, read-only listing access, and Super Admin-only staff assignment.
- Live checks verified PostgREST relationships through the view, filtering before pagination, anonymous denial, location suggestions, bilingual searches, worker authorization and successful cron execution. Comparison of 174 original production tables found changes only in normal Auth user/session/refresh-token tables since the snapshot; business records matched the migration trial.
- Backup location on this laptop: `~/Kodimali-Recovery/20261105T091211Z`. Files have restricted Windows permissions. The encrypted `production-recovery.dpapi` archive passed a nine-component integrity check. Its entropy file and Windows user profile are required to decrypt this additional copy. Private files and credentials were not committed.
- A database recovery must be coordinated with the dispatcher version: disable the new cron job and restore the previous dispatcher source from commit `7e8b5e9` when reverting to the pre-migration database. Preserve newly created production records before any restore; the backup is a recovery point, not permission to overwrite later activity.

Payment switches were preserved as found. No payment, customer booking, role assignment or staff-location assignment was submitted to production as a test. No paid backup plan, staging service or new social integration was required.

Sanitized evidence: [mobile-location-search-notifications-2026-11-05.json](mobile-location-search-notifications-2026-11-05.json).
