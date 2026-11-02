# Events and Plan Event UI improvements — 30 October 2026

Deployed to https://kodimali.com/events and https://kodimali.com/events/plan. Cloudflare version: `66fb9785-456f-4fb4-837f-2f544e6a4c07`.

## Website

- Compact introductory sections bring browsing controls and listings higher on the page.
- Scoped light backgrounds, dark headings and labels, green actions/selection states, and consistent borders replace the competing dark filter surfaces. Other product workspaces retain their styling.
- Mobile equipment/professional navigation wraps cleanly; the planner uses a selection column and separate summary on desktop, with a compact fixed summary on mobile. The global shortcut bar is suppressed on the planner to prevent overlapping controls.
- Search, sorting, category, location, price and date filters work independently. Text filters are debounced. Advanced controls are collapsible, applied filters are removable, and browsing starts with all locations rather than silently applying saved account locations.
- Professionals have translated service categories. Prices identify equipment pricing units; quote-based services use clear wording. Listing images have lightweight placeholders and failure handling.
- Planning follows event details, equipment/services, then review/send. Names wrap; quantity inputs have visible labels and activate with equipment selection. Catalog search, categories and pagination keep lists manageable.
- Choices are independent from catalog pages and filters. Location/date changes preserve selections. Drafts and submission keys survive reload/login in browser-local storage; users are told if storage is unavailable.
- Review checks the complete selection against public inventory, provider calendars and location coverage. Invalid quantities or unavailable choices block sending. This preview does not reserve inventory; providers still confirm before booking.
- The summary shows the event period, location, selected quantities and indicative unit prices. A combined total is deliberately left to the quotation because units, duration, delivery and deposits can differ.
- Successful submission shows a reference, next steps and a link to event plans. Required-field errors and catalog failures have distinct feedback. Operational configuration on detail pages is presented as readable information rather than raw JSON.

## Customer mobile source

- Smaller green introduction, actionable event-type cards, listing thumbnails, clear price units, translated service types and location visibility.
- Search, pricing, sorting, category and date filters; unrelated empty sections no longer imply inventory is missing.
- Event planning has explicit start/end date and time pickers instead of fixed start times/durations. The individual-booking dialog also allows both endpoints.
- Device-local detail and selection drafts, a resume action for existing draft plans, dated/location-specific catalog loading, catalog search/categories, readable equipment quantity controls, a final review and availability check, and confirmation linking to plan history.
- Selection names are saved with drafts so later catalog pagination does not turn the review into a list of IDs.

Mobile work is source-only. **No APK was built**, as requested. Native device interaction has not been exercised.

## Database

Migration `20261030100000_public_event_selection_check.sql` adds the read-only `check_public_event_selection` RPC for public catalog selections. It exposes only availability and quantities for published, verified equipment/professionals, handles setup/return buffers and active holds, and checks service-area coverage. It creates no plans, reservations or payments.

## Verification

- Browser regression suite `scripts/test-event-ui.py`: passed at 320px, 390px and 1440px, covering required-field validation, location edits, selection/quantity persistence, reload/login recovery, availability rejection/recheck, independent filters, readable heading colors and horizontal overflow.
- Signed-in success path tested with intercepted API fixtures, including exact submitted quantity, idempotency key, confirmation reference and draft cleanup. No live quotation request was submitted by this test.
- Screenshots inspected for mobile and desktop; regression screenshots are in ignored `tmp/event-ui-checks/`.
- Database suite `045_event_selection_preview.sql`: passed in a rolled-back transaction, including missing/unpublished equipment, overstock/zero quantities, malformed periods/selections and anonymous access. No test fixtures were retained.
- Live anonymous availability RPC smoke check: passed. Database lint: zero errors.
- Post-deployment live browser checks: both pages returned HTTP 200 at 390px and 1440px, hydrated correctly, showed no horizontal overflow or JavaScript page errors, and the planner displayed required-field feedback.
- Production website build and TypeScript validation: passed. Existing six role/filter tests: passed. Targeted customer Dart analysis: no issues. Whitespace check: passed.

No real bookings, payments or transfers were created during UI verification.
