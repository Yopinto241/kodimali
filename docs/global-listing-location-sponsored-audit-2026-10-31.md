# Global listing location and KODIMALI sponsored-ad audit

Read-only review of the live website, current Supabase configuration/functions and Customer mobile source. No application changes, deployment, account edits or APK generation. Browser analytics writes were intercepted. Native findings are source-review findings; no native app build was generated or claimed as tested.

Live checks covered 320, 390, 768 and 1440 px. Screenshots: `design-previews/location-ads-audit/`. Reproduction logs: `tmp/location-ads-browser-audit.log`, `tmp/location-ads-layout-details.log`. Read-only database inspection: `tmp/listing-location-ads-audit.txt`, `tmp/promotion-current-gaps.txt`.

## Location problems

| ID | Priority | Finding and consequence | Recommended change |
| --- | --- | --- | --- |
| L1 | High | At 768 and 1440 px the location popup is clipped by `.search-filter-chips`, whose computed overflow is auto in both axes. The popup's measured point hits another element, and the screenshot shows no usable menu. Mobile's overflow override avoids this specific clipping. | Render the popup outside the scrolling chip container, or use a proper popover/dialog with independent positioning. |
| L2 | High | Rapidly selecting region A then B can show A's districts under B. Reproduced live with delayed fixture GET responses. Neither web district loading nor native parent/child loading has a request identity guard/cancellation. | Cancel stale requests and verify the selected parent before accepting a response. |
| L3 | Medium | “Choose location” is white (`rgb(255,255,255)`) on an almost white background (`rgb(247,250,249)`) due to inherited header styling. The location trigger is only 36 px high. | Scope popup typography and use at least 44 px touch targets. |
| L4 | Medium | Web listing location selection stops at region/district, despite the feed supporting ward/area. The native picker supports ward/area but offers no All locations/reset-region option; its Apply requires a region. | Offer a consistent optional region → district → ward → area hierarchy plus an explicit clear-all action. |
| L5 | Medium | The location dropdown navigates from the current URL rather than the current search form, so unapplied text/price changes are lost. Web writes selected IDs to preferences but listing initialization reads URL props only; ordinary links/hero search omit those IDs. | Define explicit page-versus-saved location behavior and serialize current selected filters consistently. |
| L6 | Medium | Native location sheet is a non-scrollable Column with four dropdowns. Its region/district selectors and Apply remain usable during child loading; request order is not protected. Small/landscape/large-font screens need scroll and loading-state handling. | Make the sheet scrollable with safe height bounds, disable conflicting interactions while loading and keep a visible Cancel/Clear/Apply row. |
| L7 | Medium | In native search, choosing a local search location changes `_searchRegionId` etc., but `_loadResults` still sends `widget.latitude/longitude`. Home's manual-location flow clears GPS correctly; the search-specific flow does not. | Clear or replace GPS when manually changing the search location, and show what location actually controls matching/ranking. |

Key sources: `apps/web/src/components/listing-location-filter.tsx:54`, `apps/web/src/components/listing-search-form.tsx:5`, `apps/web/src/app/listings/page.tsx:93`, `apps/web/src/app/globals.css:847`; `apps/customer_mobile/lib/app.dart:1830`, `:1941`, `:5458`.

## Sponsored-ad problems

| ID | Priority | Finding and consequence | Recommended change |
| --- | --- | --- | --- |
| A1 | Critical | Blocking sessionStorage reproduces the live “This page couldn’t load / Reload / Back” error. PromotionStrip reads sessionStorage directly in an effect and click handler without a safe fallback. | Make analytics best-effort, with safe in-memory fallback; ad measurement must never break listings. |
| A2 | High | A desktop ad card measures about 1,275 px tall, including 1,084 px square media. On mobile the card is about 529 px tall. Ads appear before listing/empty-state content, so zero-results searches can be dominated by advertising. | Use compact responsive creative bounds, a wider desktop format and a restrained mobile card; prioritize results/empty-state actions. |
| A3 | High | Both currently active promotions have no target URL. One also has no CTA label. Consequently neither live card has an action link. Current title/description copy also looks like test content, rather than a finished campaign. | Require a valid destination for actionable campaigns, provide a clear CTA and review creative content before activation. |
| A4 | Medium | Two full-width ads are placed in a horizontal snap strip with hidden scrollbar, no next/previous buttons, dots or swipe hint. The second ad is easy to miss, especially with a desktop mouse or keyboard. | Add accessible carousel controls/position indication, or use an intentional responsive grid/rotation. |
| A5 | High | Web `fetchPromotions` always sends null location IDs and caches without location, even when listings are filtered. Native search promotions use original `widget` location IDs rather than `_search...` selections, and location changes do not force ad refresh. The backend supports geographic targeting. Both current ads are global, so this is a wiring gap for targeted campaigns, not evidence that current ads have the wrong region. | Pass the same effective location to listings and campaigns, include it in cache keys and refresh both together. |
| A6 | Medium | Web attempts impressions for every mounted card rather than measuring visible exposure. Native PromotionBlock displays ads and launches destinations but has no platform promotion impression/click recording calls. | Implement consistent visibility-based impressions and click tracking, with errors isolated from navigation and content. |
| A7 | High | Website promotions are fetched inside the same Promise.all as listing data. Non-compatibility errors from promotion fetching propagate and can fail the whole listing/home page. | Isolate optional ad fetch/signing failures and render listings with a local ad fallback. |
| A8 | Medium | The same creative is cropped to square on web and 16:9 on native. This can crop poster text, logos or subjects inconsistently. Web also shows raw media-type tokens such as “video” rather than helpful campaign information. | Define supported creative formats and safe zones; preserve poster content and localize meaningful UI labels. |

Key sources: `apps/web/src/components/promotion-strip.tsx:27`, `:46`, `:83`; `apps/web/src/lib/supabase-public.ts:384`; `apps/web/src/app/listings/page.tsx:93`; `apps/customer_mobile/lib/app.dart:1844`, `:1957`, `:5920`, `:6343`.

## Verified current state and suggested order

Supabase currently has two active global promotions, one video and one image; zero geographically targeted promotions. Both active campaigns lack target URLs. The backend has a geographically aware promotion RPC and a promotion-event RPC, so the main targeting and measurement gaps are in client integration and presentation.

Fix A1 and L1 first (page failure and blocked desktop interaction), then L2 and A5 (wrong/stale location state), then A2/A3/A4 (ad size, destination and discoverability), followed by mobile parity, resilient ad fetching and measurement. Re-test desktop/mobile English/Swahili, parent changes under slow/failed networks, blocked storage, back/refresh, zero-results searches and both ad creative types.
