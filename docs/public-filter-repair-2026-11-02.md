# Public location and price filtering repair — 2026-11-02

Repaired the confirmed web filter defects without changing database data, app roles, payment settings or native app code.

- Location lookups combine cancellation on close/selection changes with a 10-second deadline. A failed/stalled lookup offers Retry and allows searching with the selected parent location after loading ends.
- Empty child dropdowns are disabled with specific guidance to search using the selected region/district/ward. An optional area is not required to search.
- A shared filter-form validator handles negative/invalid prices and reversed min/max ranges. Errors reopen the price panel and focus the relevant field. Error feedback is rendered inside the panel rather than underneath it.
- Category/sort auto-submit restores the applied control value if invalid prices prevent navigation, keeping displayed controls consistent with the URL/results.
- Manual location submission uses the same price validation, preventing a second route around validation.
- Category pages share the validator while preserving their route and existing Apply behavior. Added an Apply price filter button inside their price panel because the panel can cover the external Apply button on narrow screens.
- New copy is translated in English/Swahili. The earlier scoped location contrast correction remains included in this build.

Validation: 24 web library tests, targeted ESLint and production build/type checking. Browser acceptance script scripts/test-filter-repair-web.py covers stalled response recovery, Retry, optional empty areas, negative price inside a closed panel, category control consistency, reversed ranges, corrected combined filters, category-page submission and English/Swahili at phone/desktop widths. All injected failures exist only inside the browser fixture; location/result reads do not mutate production data.

Logs: tmp/filter-repair-browser-final.log, tmp/filter-repair-deploy.log, tmp/filter-repair-live-browser.log and tmp/filter-repair-deployments.log. Deployment status is confirmed separately from the build result.


Deployment verified: Cloudflare version 938d02a7-1bb0-439f-a732-a4ba07298212 receives 100% of traffic. All seven focused live browser checks passed, including English/Swahili and phone/desktop views.
