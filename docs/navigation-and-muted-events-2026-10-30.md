# Navigation reliability and muted Events styling — 30 October 2026

Deployed to https://kodimali.com. Cloudflare version: `4c0276de-1d65-4a6b-9e0b-8ac11f144653`.

The user reported that navigation opened Next.js's “This page couldn't load” screen while manually reloading displayed the destination. Fresh direct page loads and repeated navigation worked in a clean browser during investigation; the exact state of the affected browser could not be reproduced. Blocking browser storage did reproduce the identical global error screen through the unguarded language preference effect.

## Changes

- Shared navigation now requests the destination as a complete document, including category selectors, search/location navigation, chat redirects and account links. This follows the working direct-load path and avoids relying on client-transition payloads and previously loaded page modules. The logo indicator remains, with no minimum delay or automatic reload/retry loop.
- Back uses browser history. The pending indicator resets on `pageshow`, including restored history entries.
- Main shared navigation/footer links disable unused client prefetching.
- Each production build receives a unique Next deployment identifier for version consistency and cache busting.
- Language preferences tolerate unavailable storage. Optional comparison, recent-listing and location preferences cannot crash browsing when storage is blocked or stored comparison JSON is malformed. Payment/session persistence behavior was not replaced with silent fallbacks.
- Events and Plan Event now use muted stone backgrounds, sage card/input surfaces, dark moss actions and a compact charcoal introduction. White panels, vivid green highlights and button glows were toned down. Readable headings, selected states and contrast are retained.

## Checks

- Production build and TypeScript validation passed.
- Existing six role/listing-filter tests passed.
- Events planning regression suite passed at 320px, 390px and 1440px, including saved selections, availability checks, login recovery and mocked signed-in submission.
- Navigation browser checks passed at 390px and 1440px: repeated Events/Plan/back navigation, Listings/Account links, deliberately failed client-transition responses, complete-document requests, no global error loop and no horizontal overflow.
- Browser checks with blocked storage passed for Events, language switching, Listings and Compare. The global error screen reproduced before the fix no longer appears in this scenario.
- Mobile and desktop muted-style screenshots were inspected. Local screenshots are in ignored `tmp/navigation-checks/`.
- The same navigation and blocked-storage suite passed against the deployed site at both widths. A tab kept open across deployment navigated to the new release without a manual reload. Live HTML includes the new deployment identifier and versioned asset URLs.

No APK was created. This follow-up changes the website only.
