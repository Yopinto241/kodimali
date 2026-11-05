# Notification audit — 5 November 2026

Audited mobile source at `9f1a446` and the live Supabase configuration. This was a read-only audit: no production configuration was changed and no test notification was sent to customers.

## Verdict

The delivery infrastructure exists and has successful historical Firebase submissions. It is designed to notify registered, signed-in users while the app is backgrounded or ordinarily closed. Notification coverage and user controls are **not complete**, and physical-device delivery has not been verified in this session.

The event originates in **Supabase**:

`Booking/chat/payment/change → notifications row → delivery outbox → Supabase Edge dispatcher → Firebase Cloud Messaging → Android / Apple APNs → phone`

Firebase transports notifications. Supabase decides which business events create them, identifies recipients, applies preferences and schedules retries. Firebase Console campaigns are a separate capability and are not the business-event trigger used here.

## Verified configuration

- Both Android app registrations and both Dart Firebase configurations match Firebase project `kodimali`; Android app IDs/package names match their respective Customer and Manage registrations.
- iOS Firebase project and bundle identifiers also match the supplied Firebase configuration files.
- Firebase service-account and project secrets were present during deployment verification. Presence and matching app files do not independently prove that every credential remains valid or that APNs is configured.
- Live outbox: **24 sent**, **7 skipped**, no pending/processing/failed records at inspection. `sent` is recorded after Firebase accepts a message; it does not mean the phone displayed or the user read it.
- Enabled registrations: **2 Customer Android** and **2 Manage Android**. One other Manage Android registration is disabled. No iOS installation was registered at inspection.
- The private `kodimali-push-retry` scheduler runs every minute as `postgres`; the five most recent inspected runs succeeded. The dispatcher also handles immediate notifications, bounded retries, stale processing and acknowledged-device receipts.
- The Android Firebase Messaging dependency contributes Internet, wake-lock, network-state and Android notification permissions through manifest merging. Their absence in the app's own manifest is not, by itself, a missing-permission defect.

## Background and closed-app behavior

The app does not have to stay open for server-generated pushes. The dispatcher sends an FCM notification payload, allowing the OS to display an alert independently of the Flutter foreground UI. Both apps have foreground, background and initial-tap handling.

The app must have been opened and registered, the user must remain eligible for the registered account session, OS notification permission must be enabled, and the device must be able to reach its push service. Logout/revoked sessions intentionally stop personalized pushes. A never-opened installation has no registered recipient token.

Firebase documents that Android force-stop from device settings requires reopening the app. On iOS, swiping away the app restricts background-message handling until it is reopened. These restrictions differ from ordinary minimization; background execution is also distinct from an OS-displayed notification alert. See [Firebase message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

## Coverage and gaps

| Area | Finding | Consequence / required work |
| --- | --- | --- |
| Booking, chat, payment and event updates | Live triggers and notification-writing functions exist for these workflows. Agent account changes also insert notifications through the verification Edge handler. | Existing event coverage is substantial, but does not prove every transition in every feature emits an alert. Maintain an explicit event/recipient/category/destination matrix. |
| User-selected categories | Customer → My discovery tools → notification bell exposes Messages, Viewing requests, Payments and receipts, Follow-up reminders, Promotions and price alerts. Manage has no equivalent in-app preferences screen. | Make settings discoverable in both apps and document account-wide versus per-app behavior. |
| Category classification | Worker uses substring tests, not an explicit event mapping. `message_received` booking messages fall into requests; `chat_payment_*` falls into chat before payments; refund and settlement events may fall into requests. | Switches do not consistently control the events their labels suggest. Replace classification with explicit categories and test every event. |
| Price alerts | A real price-drop trigger checks active subscriptions, threshold and promotional preference. Its legacy payload contains `listing_id` without `route`/`eventType`; the dispatcher forwards `listingId`, not `listing_id`. | The worker can apply the requests preference as an additional gate, and taps fall back to account instead of the listing. Normalize payload/category/destination. |
| Saved searches / new matching listings | Saved searches and `alerts_enabled` are stored, but no deployed database function references `saved_searches`, and no matching worker or scheduler was found. | “Notify me when a matching property appears” is not implemented end to end. Add matching, deduplication and subscriber delivery. |
| Timed viewing/follow-up/SLA reminders | Appointment changes notify participants. Live scheduled jobs cover booking-hold expiry, product expiry and push retries; no scheduled viewing/SLA reminder producer was found. | Delivery retries cannot create a reminder that was never generated. Add explicit due-reminder producers; the callable `mark-agent-delayed` endpoint alone is not a scheduler. |
| Quiet hours | Preference columns exist, but the dispatcher does not read or enforce them. | Quiet-hour storage does not currently suppress or defer pushes. Define timezone and event exceptions before enabling this setting. |
| OS permission and delivery health | Both apps request permission but do not expose the returned permission status as a notification-health screen. Backend receipts represent FCM acceptance. | An enabled database token can coexist with OS-blocked notifications. Add permission/channel diagnostics, a settings link and controlled device checks. |
| Customer/Manage targeting | Dispatcher selects all enabled tokens for the recipient user without filtering `app_surface`. | A person using both apps can receive an event in both, including an app without the most suitable destination. Add an explicit audience/surface policy. |
| Signed-out notification taps | Customer rejects taps when there is no signed-in user. Manage retains a pending tap until sign-in. | Customer should preserve a recipient-bound destination through authentication, then recheck ownership before navigation. |
| In-app notification inbox | Manage's inbox opens booking-related notifications; it does not universally route chat, listing and event records. Its booking lookup also differs from the push payload parser. | Use one canonical payload/destination parser for push taps and inbox items. |
| iOS readiness | Firebase files match, push entitlements and `remote-notification` mode exist, but the checked-in Xcode projects have no development team or `APS_ENVIRONMENT` definition. `fetch` background mode is absent. APNs upload/signing was not verified, and there are no iOS registrations to validate. | Finish/verify Apple provisioning, resolved entitlements, required capabilities and Firebase APNs credentials on a Mac and physical iPhone. External build settings may supply values; the repository alone does not establish readiness. See [Firebase iOS setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started). |
| Guest requests | Mobile device registration requires an authenticated user. Guest booking requests are allowed separately. | A guest request does not automatically create a personal push subscription. Decide whether to require sign-in for tracking, implement a protected guest subscription, or provide another authorized channel. |

## Recommended repair order

1. Normalize event categories, identifiers and destinations; correct price-alert gating and routing, and unify inbox/push navigation.
2. Implement saved-search matching and scheduled reminder producers, with deduplication and explicit recipient rules.
3. Complete settings in both apps: permission health, category controls, app audience and quiet hours.
4. Verify iOS provisioning/APNs and run an end-to-end test on each app's own Android installation; add iPhone tests before claiming iOS readiness.

Physical-device verification should cover foreground, background, ordinarily closed, screen locked, offline then reconnected, permission denied, logout/account switch, each preference category and tapping into the correct screen. Use dedicated test accounts/devices rather than sending test alerts to customers. Keep FCM acceptance, phone receipt, displayed notification and user-read state distinct.

Sanitized live/configuration evidence: [notification-audit-2026-11-05.json](notification-audit-2026-11-05.json). No device tokens, customer identifiers, service-account keys or credentials are included.
