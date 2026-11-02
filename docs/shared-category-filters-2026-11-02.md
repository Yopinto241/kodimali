# Shared catalog filters and ward-wide GPS - 2026-11-02

## Implemented behavior
- Global listings and every dynamic asset category route use CatalogFilters, one shared UI and submission path. Category pages omit the category selector and old category-switch control; the category remains fixed by its route.
- Search, manual hierarchical location, minimum/maximum price, price period, sort auto-apply, result count, validation, Clear filters and Save search are available consistently. Saved searches now retain ward and area IDs as well.
- Clear filters returns to the current category's clean URL, resets unsaved input, closes price panels, clears validation feedback and removes stored browsing location preferences. Global Clear returns to /listings.
- WardGpsFilter is available beside manual selection. It requests device location, resolves a suggested ward using the existing resolver and asks the user to confirm that ward or switch to manual selection. GPS suggestions are approximate: the current resolver uses nearest mapped locations, not administrative boundary polygons. The confirmation prevents silently applying an uncertain ward.
- GPS confirmation retains independent search/price/sort/category choices, sets region/district/ward IDs and removes areaId, lat, lng and pagination. Neither precise coordinates nor a GPS area are used to filter listings or stored in browsing preferences. Manual selection can still explicitly narrow to an area.
- Home's existing GPS entry point uses the same widget. Older coordinate-based home/global/category URLs are normalized server-side to ward-level location before requesting listings; coordinates are never forwarded to the listing search. Existing explicit manual area URLs without GPS coordinates remain supported.
- GPS denial, lookup failure and unresolved wards leave manual location available. Device and resolver waits are bounded.
- Existing category publication, listing visibility, ads, payment/approval rules and sitemap configuration are preserved. No production database data or policy changed, no native code changed and no APK generated. The separate /events marketplace and its existing /category/events redirect remain separate from the ten ordinary asset category routes.

## Validation
- 26 web library tests passed, including ward-only URL generation, removal of old precise-area/coordinate/page filters and rejection of resolutions without a ward.
- scripts/test-ward-wide-catalog.sql loads the existing production search migration into an isolated rolled-back database fixture. Tests prove one ward returns listings from two different areas, excludes another ward and another category, supports explicit manual-area narrowing and combines with price filtering.
- scripts/test-shared-catalog-web.py passed at 390 English and 1440 Swahili widths across all ten asset category routes: shared UI, no category selector, GPS/manual/price/sort/clear/save controls, manual area, GPS ward-only URL, preservation of other filters, Clear including unsaved values/preferences, unresolved GPS and permission-denied manual fallback. Browser geolocation and resolver writes/reads used isolated mocked responses; no real accounts/listings/payments were created.
- Existing focused filter regression script updated for the shared category selectors and passed timeout/retry, empty areas, hidden-invalid-price recovery, reversed-range validation and category-route preservation at phone/desktop widths in English/Swahili.
- Targeted ESLint and OpenNext production build/type checking passed.

Logs: tmp/catalog-unify-build-final.log, tmp/catalog-unify-browser.log, tmp/catalog-unify-regression.log, tmp/catalog-unify-deploy.log, tmp/catalog-unify-deployments.log, tmp/catalog-unify-live-browser.log. Screenshots: design-previews/shared-catalog/.

Final readiness protection: filter controls remain disabled until client interaction handlers are ready. A delayed-script browser test verifies the first click works. Final build/type checks and focused ESLint passed.

Final Cloudflare deployment: 6e46efdf-869b-4b0e-94ca-4c308f6d439d, 100% traffic. Live shared-catalog tests passed across all ten asset category routes, English phone and Swahili desktop views, including ward-only GPS/manual/clear flows and delayed-script readiness. Final logs: tmp/catalog-hydration-live-browser.log, tmp/catalog-hydration-live-regression.log and tmp/catalog-hydration-deployments.log.
