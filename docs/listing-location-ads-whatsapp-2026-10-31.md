# Listing location, sponsored ads and paid WhatsApp

Implemented in the website and Customer mobile source. No APK is generated.

## Behavior

- Location selection supports optional region, district, ward and area. Unselected levels do not restrict results. All locations clears the location filter, including GPS coordinates.
- The web picker uses a native dialog above clipped filter containers. Native uses a bounded scrolling sheet, including landscape and enlarged text. Both discard stale location responses, clear dependent selections, and provide loading, retry and cancellation.
- Applying location preserves other web filter drafts. Home and category manual selection reuse the same picker. GPS preserves the category. Saved locations require an explicit action to reapply.
- Native search clears previous GPS coordinates after manual selection and refreshes promotion targeting with the selected hierarchy.
- Website promotion requests include the selected location in the RPC and cache key. Optional ad failures do not crash listing pages. Analytics tolerate unavailable browser storage and network failures.
- Sponsored cards use bounded media with contained images/video, compact copy and an explicit control for additional ads. Missing or unsafe destinations fall back to Browse listings. Uploaded creative copy is preserved.
- Impressions require at least 50% visibility for one second. Concealed ads do not count on mount. Native also pauses exposure checks when the app is inactive.
- Eligible listing cards show a WhatsApp action. Public feeds expose only `has_whatsapp`, never the agent phone. Web opens `/listing/:id/contact?intent=whatsapp`; Customer mobile uses the existing unlock sheet. A server-confirmed unlock opens WhatsApp. Saved unlocks are revalidated; pending or expired access cannot use a cached number.
- Existing payment endpoints, fees and 24-hour access rules are unchanged. The existing administrator-controlled free-contact mode is respected.
- New UI copy follows the English/Swahili switch. Apartment, book and booking remain unchanged.

## Database

Only `20261031120000_listing_whatsapp_availability.sql` is applied for this release. It adds a number-normalization function and extends the existing batch capability RPC with a public availability boolean, retaining its existing booking capability JSON. Public eligibility is checked and requests remain deduplicated and limited to 100 IDs.

No campaign content, listing content, contact charges or unrelated pending migrations are changed.

## Verification

Tests are in `scripts/test-listing-whatsapp.sql`, `scripts/test-listing-public-fixtures.py`, `scripts/test-listing-location-ads.py`, the web library tests, and `apps/customer_mobile/test/location_ads_whatsapp_test.dart`.

Browser fixtures run against an isolated public API server and separate preview cache. All payment/status responses and analytics are mocked. No test listing is inserted into Supabase and no real payment is initiated.

Final results:

- Web: 17 library tests passed, changed client components/helpers passed ESLint, and the full Next/OpenNext production build completed.
- Browser acceptance: passed at 320, 390, 768 and 1440 pixels, including hierarchy races, retry, preservation of category/search/price/sort drafts, optional ad storage, viewable impressions, hidden additional ads, button contrast, and pending/expired/completed WhatsApp access.
- Customer mobile: all 13 tests passed; the five feature tests also passed after the final test cleanup. `flutter analyze --no-pub` reported no issues. Manual location clears GPS and updates ad targeting; canceled and expired contact access do not launch a cached number.
- SQL fixture tests passed. Live read-only verification confirmed the migration, normalization and empty batch behavior. The unrelated `20261030140000` legacy migration remains unapplied.
- Live checks passed at 390 and 1440 pixels with no page errors, including denied session storage. Sponsored cards measured 344.3px on mobile and 238px on desktop. The existing sitemap returned HTTP 200 and valid `urlset` XML with Events and Toa Taarifa.

Cloudflare version `51628d0f-d171-4e73-8805-2b7f22df867b` serves 100% of traffic on kodimali.com and www.kodimali.com, deployed at 2026-10-31 20:15 UTC.

The live database contained **zero listings** during verification. Eligible new approved listings will display WhatsApp availability; the card/payment integration was tested with isolated fixtures because there were no real cards to exercise. Customer mobile source changes require the user's next app build; no APK was generated.
