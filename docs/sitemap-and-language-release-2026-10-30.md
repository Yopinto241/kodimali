**KODIMALI sitemap maintenance and bilingual website release — 30 October 2026**

This release follows the revised instruction to preserve the existing successful sitemap. It supersedes the sitemap-index proposal in the earlier SEO report. The existing `/sitemap.xml` URL, Next.js MetadataRoute implementation and flat `<urlset>` XML format are retained. No Search Console property, submission URL, DNS or Cloudflare security setting was changed.

The production sitemap reviewed before deployment included `/account` and `/manage`, omitted Events and Toa Taarifa, and assigned the current generation time to every URL. The earlier proposed index and child-sitemap handlers were removed from the prepared code.

The maintained sitemap now:

- Excludes private accounts, management/admin/owner workspaces, chat and booking/payment action pages.
- Includes `/events`, `/toa-taarifa`, active public category pages and useful informational pages. Public account-deletion instructions remain; they are not a private account dashboard.
- Includes only approved, public, active and available listings, with active agents/categories and no market-removal timestamp.
- Includes verified, active, published equipment and services when available. Services require a verified active provider.
- Uses actual database modification dates for inventory. Public service dates also account for later provider-profile changes. Static/category URLs omit `lastmod` when no reliable modification date is available.
- Reads inventory in bounded pages instead of relying on the search RPC’s 50-row limit. Keeps the flat sitemap’s standard 50,000-URL ceiling and fails rather than silently truncating beyond it.
- Caches the public data for five minutes, without replacing dates with the request time or silently returning incomplete inventory during a database error.

The tested migration `20261030120000_public_seo_sitemap.sql` was applied. It adds a read-only public projection containing IDs, modification dates and counts. It does not change inventory rows, private-table access policies, booking rules, payments or settlement logic. Anonymous production checks returned five approved public listings and no currently published Events inventory.

The website translation update uses a shared application-copy catalog, exact text lookup, explicit templates and small React components that respond to the existing language context. It covers public pages, account and referral screens, Events, management/owner workspaces, actions, helper text, placeholders, accessible labels, statuses and known system messages. Existing saved preferences are synchronized with the language cookie.

The words **apartment**, **book** and **booking** remain unchanged in both languages. “Save” translates to “Hifadhi”. Proper names, brands, customer-written listing descriptions/messages, addresses, phone numbers, emails and references remain original. Input values, category IDs, database enums, request parameters and payment amounts are not translated. Dynamic configured field labels, required-field markers and measurement-option captions translate while their stored option values remain unchanged.

Both Flutter apps now use a shared 2,493-phrase application-copy catalog (`packages/flutter_core/lib/localized_ui.dart`) alongside their existing saved language settings. This covers public browsing, booking, Events planning/recovery, Toa Taarifa, account, agent publishing, owner and staff workspaces. Static text, form captions, validation, status notices and interpolated application messages translate without rewriting inserted names, descriptions, references, numbers or option values. Source catalogs can be synchronized with `python scripts/sync-mobile-ui-copy.py`. No APK or app bundle was created; mobile source changes require a future app release to reach installed apps.

Primary implementation files:

- `apps/web/src/app/sitemap.ts`, `src/lib/sitemap.ts`, `src/lib/sitemap-public.ts` and the read-only Supabase migration.
- `apps/web/src/lib/ui-copy.json`, `ui-aliases.json`, `ui-templates.json`, `ui-translation.ts` and `src/components/ui-text.tsx`.
- Existing page/component display slots and `language-provider.tsx`; customer-owned data and form/API values remain separate from UI captions.
- `apps/web/src/lib/{seo,ui-translation}.test.mjs`, `scripts/test-seo-db.sql`, `scripts/test-seo-web.py` and `scripts/test-web-language.py`.

Validation before web deployment:

- Both mobile apps and shared Flutter core: Dart analysis; 16 management tests, one customer language test and four shared tests, including protected vocabulary and unchanged input/selection/interpolation values.

- Full website ESLint with zero warnings allowed, TypeScript and the Next.js/OpenNext Cloudflare production build.
- Fourteen unit tests covering flat-sitemap pagination/dates/exclusions, metadata, schemas, role access, independent filters, translation coverage, preserved terms, required-field markers, references and confirmation tokens.
- Disposable PostgreSQL test of the actual migration with 1,005 public rows plus pending/inactive/removed/suspended-agent/disabled-category fixtures; private fields and direct anonymous table reads stay excluded. The fixture transaction rolled back and the local database process was stopped.
- HTTP integration against the production build: flat XML parsing, 1,001 listing fixtures, public Events/service entries, private exclusions, real dates, metadata, robots, canonical redirects and real 404s. Test fixtures did not enter production Supabase; the persistent fixture cache was isolated and restored.
- Browser language switching in both directions at 390/1440 px, refresh persistence, unchanged typed text and apartment label, plus mocked customer/admin/agent/owner sessions. Agent form checks cover translated configured labels without changing numeric fields or option values.
- Navigation regression at 390/1440 px, repeated back/forward navigation, failed RSC simulation and blocked browser storage.
- Events planning regression at 320/390/1440 px, form validation, selection persistence, independent filters, location changes, login recovery and a mocked signed-in submission. No real booking or payment was submitted.

The owner reports Search Console Success for the existing sitemap. The checks here verify the XML endpoint and content; they do not claim authenticated access to the Search Console dashboard or guarantee how quickly Google recrawls changes. Keep the existing sitemap submission.

Website deployed to Cloudflare Worker `kodimali-web`, version `9846095f-ca7d-4bb4-a965-17096ed83343`, on both configured domains. Live verification returned HTTP 200 for the unchanged flat `/sitemap.xml`: 25 URLs, five approved public listings, Events and Toa Taarifa present, no private dashboards, and all five inventory dates exactly matching the anonymous read-only Supabase projection. Static-page dates are omitted. `robots.txt` retains `https://kodimali.com/sitemap.xml`.

Live browser checks passed at 390 px and 1440 px: language switching in both directions, refresh persistence, preserved input text and apartment label, no overflow, and customer/admin/agent/owner workspaces using intercepted fixture authentication. Configured agent fields translate without changing numeric inputs or stored option values. Repeated document navigation/back, failed-RSC simulation and blocked browser storage also passed without the page-load error loop.

Final mobile verification: Dart analysis reports no issues; shared Flutter core 4/4 tests, management app 16/16 tests, customer app 1/1 test. The final catalog contains 2,493 phrases. Mobile packages were not built or distributed.
