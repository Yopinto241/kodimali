# Customer mobile audit — 1 November 2026

Scope: current Flutter source and simulated widget/repository behavior. No production records, payments or app behavior were changed. No APK was generated. Existing dirty workspace changes were preserved.

Baseline: `flutter analyze` reported no issues and all 17 existing tests passed, run with one test worker. Logs: `tmp/customer-audit-analyze.log`, `tmp/customer-audit-tests.log`. Additional temporary probes are in `tmp/customer_audit_findings_test.dart`, with results in `tmp/customer-audit-findings-verified.log`. These probes examine existing defects rather than constitute a passing regression suite: the refresh probe actually raises the documented runtime exception; the other four reproduce the faulty behaviors successfully.

## 1. Faulty Future-returning refresh callbacks — high priority

`apps/customer_mobile/lib/features/chat/listing_chat_screens.dart:27` updates state with `setState(() => _future = repository.fetchListingChats())`. The callback returns a Future, which violates Flutter's synchronous state-update contract. The automatic five-second refresh reproduced `setState() callback argument returned a Future`. Manual refresh at line 58 has the same issue.

The same pattern exists in `features/events/events_marketplace_screen.dart:176`, `features/account/customer_account_screens.dart:488`, `:1500`, `:1690`, `features/account/customer_information_screen.dart:41`, and Events recovery controls. These additional sites were identified by inspection, not individually exercised. The assertion is a debug/test-mode failure; this finding does not establish that every release APK crashes. In release mode, replacing the Future on every poll also makes the chat list enter its loading state instead of preserving visible rows.

Recommendation: create/request the Future outside the state callback, assign it inside a block returning void, preserve loaded data during background refresh and avoid overlapping/background polling.

## 2. Failed chat access check displayed as expired access — high priority

`features/chat/listing_chat_screens.dart:385` ignores the error/loading state of the conversation details Future, substitutes an empty map, and calculates access as false. A simulated network error produced “Chat access expired” and a disabled composer instead of a recoverable loading/error state. This can mislead someone who still has valid paid access; it does not demonstrate incorrect server-side payment accounting.

Recommendation: distinguish loading, unavailable and genuinely expired access; offer Retry and retain the last confirmed access state while refreshing. Keep the server authorization check authoritative.

## 3. Customer Auth has no app-level request deadline — high priority

`features/account/customer_account_screens.dart:960` leaves `_submitting` true until the sign-in/sign-up Future resolves; `core/data/customer_account_repository.dart:139` and `:149` forward Auth calls without an application deadline. In a simulated stalled login, the button remained disabled after two virtual minutes with no recovery message. Platform/backend behavior may eventually time out; the customer UI itself does not provide a bounded recovery.

Recommendation: bound requests, end the busy state and explain uncertain outcomes without automatically resubmitting signup/payment requests.

## 4. Technical errors leak into customer screens — medium priority

The chat list at `features/chat/listing_chat_screens.dart:48` renders `snapshot.error.toString()`. A simulated Postgrest error displayed its table name and error code. Events also renders raw exceptions, for example `features/events/events_marketplace_screen.dart:1930`, `:2291`, `:2420`, and startup fallback shows `error.toString()` through `main.dart:33`/`:62`.

Recommendation: keep diagnostic details in internal logs and show consistent, translated, polite customer messages with a useful recovery action.

## 5. Incoming chat updates force scrolling to the newest message — medium priority

`features/chat/listing_chat_screens.dart:442` schedules scrolling to the newest message on every nonempty stream rebuild. The probe scrolled 800 pixels into older messages, delivered an incoming message, then observed the offset return to zero. This interrupts reading older conversation history.

Recommendation: scroll automatically only when the reader is already near the newest message, or after their own send; otherwise show a new-message indicator.

## Verification limits

Real Android/iOS lifecycle behavior, notification delivery, cold-start password reset/deep links and live mobile-money prompts were not exercised. No real customer account was used. This is a source/widget audit, not certification of the installed APK or every production flow.
