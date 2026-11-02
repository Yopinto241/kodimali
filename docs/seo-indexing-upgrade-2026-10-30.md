**KODIMALI technical SEO and indexing release — 30 October 2026**

**Superseded release plan:** the user subsequently requested preserving the existing flat sitemap. See [the sitemap and language release](sitemap-and-language-release-2026-10-30.md) for the final implementation and deployment status. The sitemap index proposal and unapplied-migration statements below describe the earlier draft, not the final release.

Implementation and the Cloudflare production bundle are prepared locally. **Nothing from this SEO release has been deployed. The sitemap database migration has not been applied to production.** The attached brief explicitly requires authorization before deployment. Booking, payment and owner-settlement logic were preserved. No APK was created.

1. **Confirmed production problems**

   Read-only HTTP/source audit: `python scripts/audit-seo.py`. Evidence: `tmp/seo-audit-before.json`.

   - Homepage, marketplace and category pages lacked canonical URLs and mostly shared generic metadata. The root description described software rather than the rental marketplace.
   - Events titles repeated KODIMALI. Social sharing metadata lacked a consistent image. The initial document language was English although the default UI was Swahili.
   - HTTP, HTTPS, www and non-www variants served duplicate pages with HTTP 200 in the audit.
   - Account and management routes appeared in the old sitemap. Events and Toa Taarifa were omitted. Every sitemap generation fabricated a fresh modification date.
   - The sitemap requested 1,000 listings from a public search RPC that caps results at 50, silently truncating larger inventories. Database failures silently produced an incomplete successful sitemap.
   - Missing listing/category pages returned 200. Even after adding `notFound()`, the global loading boundary committed a streamed 200 before the missing page could resolve.
   - Events details and catalog rows were fetched only after JavaScript ran. General marketplace listings already had meaningful server-rendered HTML.
   - Listing JSON-LD hardcoded the old `.co.tz` domain and claimed `InStock` without date-specific availability evidence.
   - All eleven hero slides were mounted immediately. Photos for the first listing in every homepage category were also eagerly preloaded below the hero.

   Synthetic Googlebot/Bingbot requests returned public HTML, robots and sitemap without an observed challenge. These tests use crawler user-agent strings, **not verified Google/Microsoft IP addresses**. They cannot prove legitimate crawlers are exempt from Cloudflare rules.

2. **Files changed for this release**

   Existing unrelated workspace changes were preserved. This list describes the SEO work, not every outstanding change in the repository.

   - `apps/web/next.config.ts`: canonical redirects, private-route response headers, blocking metadata.
   - `apps/web/tsconfig.json`: allow type-stripped TypeScript imports in the small Node test suite.
   - `apps/web/src/lib/seo.ts`, `sitemap.ts`, `sitemap-public.ts`, `events-public.ts`: shared metadata/schema helpers, XML generation, public inventory access and server Events queries.
   - `apps/web/src/lib/supabase-public.ts`: export the existing anonymous fetch/media helpers for reuse. No service-role client was introduced.
   - `apps/web/src/app/layout.tsx`, `page.tsx`, `listings/page.tsx`, `category/[slug]/page.tsx`, `listing/[id]/page.tsx`, `agent/[id]/page.tsx`: metadata, language, schemas and real missing-page behavior.
   - `apps/web/src/app/events/page.tsx`, `events/equipment/[id]/page.tsx`, `events/service/[id]/page.tsx`, `events/plan/page.tsx`: metadata and public server rendering.
   - `apps/web/src/app/{advertise,download,delete-account,privacy,safety,terms,toa-taarifa}/page.tsx`: distinct public metadata and canonicals.
   - `apps/web/src/app/{account,admin,manage,owner,login,register,compare,map}/layout.tsx`, `events/plan/layout.tsx`, and `agent/page.tsx`: noindex controls. The exact agent dashboard is excluded; `/agent/[id]` remains a public profile route.
   - `apps/web/src/app/robots.ts`, `sitemap.xml/route.ts`, `sitemaps/[kind]/[file]/route.ts`: crawl discovery and paginated sitemap index. Replaced the old `app/sitemap.ts`.
   - `apps/web/src/app/not-found.tsx`: useful noindex 404 page. Removed the root `loading.tsx` boundary that caused soft 404 responses; the existing document-navigation logo still handles navigation progress.
   - `apps/web/src/app/opengraph-image.tsx`: generated 1200×630 sharing card using the existing official icon, with no remote logo fetch.
   - `apps/web/src/components/{structured-data,public-event-page}.tsx`, `simple-events-listings.tsx`, `event-individual-detail.tsx`, `language-provider.tsx`: safe JSON-LD, initial public server data and language hydration. Booking handlers were retained.
   - `apps/web/src/components/premium/{cinematic-hero,category-listing-rails}.tsx`: load slides when activated and lazy-load lower listing photos.
   - `apps/web/src/components/first-visit-welcome.tsx`: correct close-button stacking so foreground text cannot intercept the button.
   - `supabase/migrations/20261030120000_public_seo_sitemap.sql`: pending read-only public sitemap function.
   - `apps/web/src/lib/seo.test.mjs`, `scripts/{audit-seo,measure-seo-mobile,test-seo-web,check-seo-browser}.py`, `scripts/test-seo-db.sql`: repeatable verification tools. This report records their results.

3. **Metadata implemented**

   Metadata uses the supported Next.js App Router API and a fixed `https://kodimali.com` base.

   Homepage title: **KODIMALI | Nyumba, Magari na Huduma za Kukodisha Tanzania**.

   Homepage description: **Tafuta nyumba, apartments, magari, ofisi, kumbi, vifaa na wataalamu wa sherehe Tanzania. Gundua mali na huduma, linganisha chaguo na uweke booking kupitia KODIMALI.**

   Categories have descriptive titles such as “Nyumba za kupanga Tanzania” and “Magari ya kukodisha Tanzania”. Public listing/provider details use actual names, descriptions and public images, with a relevant fallback when the description is empty. Informational pages have individual descriptions. Open Graph and Twitter metadata use the same title, description, canonical identity and image. Existing favicons/app icons remain.

   The initial HTML uses the actual language cookie, defaulting to `sw`; LanguageProvider starts from the same value. No fake language-specific URLs or hreflang alternates were invented. Existing English-only informational copy remains unchanged.

4. **Sitemap URL and included pages**

   Entry point after deployment: **https://kodimali.com/sitemap.xml**. This becomes a sitemap index referencing:

   - `/sitemaps/static/0.xml`: homepage, marketplace, Events, Toa Taarifa, safety, privacy, terms, account-deletion instructions, advertising, download information and active category landing pages. `/category/events` is excluded because it redirects to Events.
   - `/sitemaps/listings/0.xml`, `/1.xml`, etc.: public active/available listings with approved publication states, active agents and categories, and no market-removal timestamp.
   - `/sitemaps/equipment/0.xml`, etc.: active, verified, published event equipment.
   - `/sitemaps/services/0.xml`, etc.: active published offerings belonging to active verified providers.

   Children contain at most 1,000 inventory URLs. IDs are sorted deterministically, and counts determine how many children are required. This avoids the old search RPC’s 50-row cap. Static entries omit modification dates when there is no reliable source. Inventory entries use actual `updated_at`; service entries also account for a later public provider-profile update. Dates are not replaced with the current time. This follows [Google’s sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap).

   Database outages return 503 with `Retry-After: 300`, rather than silently declaring inventory absent. Sitemap/public-data caching is bounded to five minutes. Private accounts, chats, management dashboards, checkout/booking actions, callbacks, private referrals and arbitrary filtered searches are excluded.

   **Release dependency:** production currently lacks `get_public_seo_sitemap`. The pending migration exposes only public IDs, modification dates and counts; anonymous direct access to private listing tables is not broadened. Apply this migration before deploying the new web worker. A preview connected to the unmigrated production database correctly returns 503 for the new inventory sitemap. Fixture-backed integration tests and an isolated PostgreSQL test validate the prepared implementation; the real production sitemap must be rechecked after authorization and release.

5. **robots.txt and private indexing controls**

   `User-agent: *`, `Allow: /`, `Disallow: /api/`, and `Sitemap: https://kodimali.com/sitemap.xml`.

   Private/low-value HTML gets `noindex, follow` metadata and `X-Robots-Tag`. Private HTML is not blanket-blocked in robots, allowing crawlers to discover its noindex directive. Authentication and Supabase authorization remain responsible for privacy; robots/noindex are not access controls. [Google explains why crawlers must be allowed to see noindex](https://developers.google.com/search/docs/crawling-indexing/block-indexing).

   Read-only anonymous production probes returned zero rows from `profiles`, `owners`, `agents`, `listing_contact_payments` and `event_plans`. A nonexistent `guest_requests` table probe returned 404 and is not counted as an authorization test. This is a targeted sanity check, not a complete penetration test.

6. **Structured data and official identity**

   Organization and WebSite identify KODIMALI, the official `.com` domain, the existing icon and the phone already displayed in the footer. Detail pages add BreadcrumbList and Service with public descriptions, images, general locations and genuine price specifications where known. Rentals/equipment/services are not falsely marked as scheduled Event entities. No unconditional stock availability, fabricated reviews, ratings, certifications, exact addresses or prices were added. Quote-only services omit a fixed-price offer. JSON-LD escapes `<` before embedding untrusted text.

   `sameAs` is deliberately omitted: social ownership was not verified, and the existing Facebook link is a search URL. The draft sharing image is available locally at `tmp/kodimali-seo-share.png`.

   Local checks validate JSON parsing, expected types/fields and omitted unsupported claims. Google’s Rich Results Test and the Schema.org online validator were **not run against the unpublished release**. Run [Rich Results Test](https://search.google.com/test/rich-results) and [Schema.org Validator](https://validator.schema.org/) against the public URLs after release. Service markup does not by itself guarantee a Google rich result or Knowledge Panel.

7. **Public crawlability and internal links**

   Home, categories and marketplace retain server-rendered headings, public listing names, prices, general locations and ordinary detail anchors. Listing details retain public descriptions and server-rendered media. A screen-reader heading was added to marketplace results without changing its layout.

   Events now supplies initial catalog rows and categories on the server. Equipment/service detail pages load the existing public field whitelist on the server and pass it into the existing UI. Tests with JavaScript disabled can read both descriptions, names and the catalog’s equipment link. A no-JavaScript link also reaches the professionals catalog. Search/filter refreshes and booking forms continue to work in the client.

   Exact protected addresses, owner records and paid contact details are not newly selected for SEO. The existing public listing RPC still applies the contact-unlock rule. No service-role secret is used. UUID URLs and existing booking/share references are preserved. No unsupported city landing pages were manufactured for Arusha or other locations.

8. **Canonical and redirect strategy**

   Public canonicals point to HTTPS non-www `.com`. `www.kodimali.com` redirects permanently to the corresponding canonical path, retaining query parameters. HTTP requests for the canonical host redirect when forwarded protocol is HTTP. `/category/events` permanently redirects to `/events`.

   Arbitrary content-changing filters/searches are `noindex, follow` and canonicalize to the clean catalog/category page. Tracking parameters do not create new indexable identities. Real page-number pagination self-canonicalizes, with a page-specific title. Missing/invalid listings, categories and Events details return real HTTP 404, a useful message and noindex, without a homepage canonical.

   Blocking metadata plus removal of the early loading boundary prevents committing a success status before route validation. The navigation-progress logo remains functional; repeated navigation/back tests passed. Localhost is not redirected to production.

   Actual Cloudflare HTTPS and forwarded-header behavior still needs post-release verification. The application redirect is not a claim that the zone’s edge HTTPS settings have been verified.

9. **Mobile performance and accessibility findings**

   Read-only Chromium lab: 390×844, 4× CPU throttle, 150 ms latency, approximately 1.6 Mbps down, cache disabled and reduced motion. These are single observations, **not CrUX percentiles, field INP, or a Lighthouse score**. The local server also uses Next’s image optimizer, whereas production image responses were substantially larger. Production-versus-local figures are not a controlled estimate of the exact deployed improvement.

   | Page / visit | Existing production LCP | Prepared local LCP | CLS |
   | --- | ---: | ---: | ---: |
   | Homepage / first visit | 15.76 s | 3.94 s | 0 |
   | Homepage / returning | 22.21 s | 1.99 s | 0 |
   | Events / returning | 3.04 s | 1.90 s | 0 |

   Homepage hero images initially mounted: **11 → 1**. Other slides load on activation, retaining the fade/animation behavior and pause control. Reduced-motion tests keep the slide still; keyboard focus can select another slide. Lower homepage listing rails no longer preload a first photo for every category. Image dimensions and responsive sizes remain. Existing fonts use system fallbacks rather than adding font downloads. No broad script deferral, auth-cache change or booking/payment change was introduced.

   Final local first-visit TTFB was about 1.93 s while public data caches were cold; returning TTFB was about 47 ms. Sampled homepage pause interaction duration was about 120 ms locally, versus 296 ms in the production observation; this is only a sampled Event Timing measurement, not field INP. The cold first visit still exceeds the good LCP threshold. Field Core Web Vitals remain unverified; use Search Console/CrUX after release. [Google’s Core Web Vitals documentation](https://developers.google.com/search/docs/appearance/core-web-vitals) explains these metrics.

   Axe-core 4.10.3 mobile WCAG A/AA checks: Events and Plan Event had zero automated violations in the tested state. Existing contrast findings remain on the homepage (8 nodes), marketplace (9) and one listing detail (1), primarily the hero kicker and listing action buttons. These were recorded without changing the site’s established colors/design. No tested page overflowed; no visible loaded image was broken. The welcome close button’s stacking issue was fixed and click-tested. Automated scans do not establish full accessibility conformance.

10. **Executed checks and results**

    - Full website ESLint: zero errors/warnings. The final small listing-rail optimization also passed a focused lint check.
    - TypeScript `--noEmit`: passed; production build type check passed.
    - Ten Node tests: metadata/canonical rules, sitemap partitioning/escaping/dates, truthful schemas, listing-filter behavior and staff access rules passed.
    - Full Next.js/OpenNext Cloudflare production build: passed. OpenNext emits its existing Windows compatibility warning. Built worker: `apps/web/.open-next/worker.js`.
    - Disposable local PostgreSQL 18: the actual new migration passed with 1,005 public listings plus hidden/inactive/removed/pending/suspended-agent/disabled-category fixtures. Verified pagination, event publication/provider checks, actual dates, invalid kind rejection, limited anonymous output and denial of direct private-table access. The transaction rolled back and the temporary PostgreSQL process was stopped. No production records or schema were changed.
    - Production-build HTTP integration: 14 public pages, 14 private/action routes, filters, pagination, canonical redirects, query preservation, real 404/noindex responses, robots, generated PNG, sitemap index/children and retryable outage behavior passed. The index covered 1,001 fixture listings and both Events detail types. Fixtures never entered Supabase; their persistent test cache was isolated/restored.
    - JavaScript-disabled browser: Events catalog and both detail types remained readable with real links.
    - Navigation regression: mobile 390 px and desktop 1440 px, repeated Events/planner/back and account/listings links, simulated failing RSC requests and denied storage passed.
    - Events planning regression: 320/390/1440 px, validation, independent filters, selection persistence, location edits, reload recovery, availability changes and login recovery passed. Mocked signed-in submission checked quantity/idempotency/draft cleanup without a live booking or payment.
    - Hero regression: one initial slide, reduced motion, keyboard selection, actual image load, normal autoplay, pause and lazy lower listing photos passed. Welcome dismiss button passed.
    - Production and prepared-preview HTML audits completed. Published listing HTML includes names, descriptions, canonical metadata and public JSON-LD. No `.co.tz` references remain in the website source.
    - `git diff --check`: passed. Worker cache checked for fixture names/local proxy URLs: none found.

    Evidence is in `tmp/seo-{audit-before,audit-preview,mobile-before,mobile-preview,accessibility,web-test-results}.json`, `tmp/web-eslint-seo-final.json` and the existing navigation/Events browser screenshots. Temporary files are ignored by Git.

11. **Domain-owner actions and authorized release procedure**

    - Explicitly authorize this web release and the read-only sitemap migration. Apply only `20261030120000_public_seo_sitemap.sql` through the established migration workflow, then deploy the prepared Cloudflare worker. No booking/payment schema change is required.
    - Recheck HTTPS/non-www redirects on all three alternate origins, including paths/query parameters; verify no redirect loop. Inspect `/robots.txt`, `/sitemap.xml`, every indexed child sitemap, a published listing, category, public Events detail if one exists, missing URL and private-route headers on the deployed worker.
    - In Search Console, add/verify the Domain property for `kodimali.com` using the DNS record supplied by Google, or use an existing verified property. Domain verification requires the owner’s access; no token was invented or published. See [ownership verification](https://support.google.com/webmasters/answer/9008080).
    - Submit `https://kodimali.com/sitemap.xml` once the new endpoint is healthy. Inspect the homepage, an important category and a real published listing. Run a live test, compare Google-selected canonical and request indexing for those representative URLs. See [URL Inspection](https://support.google.com/webmasters/answer/9012289).
    - Review Page Indexing, Crawl Stats, sitemap processing, Security Issues, Manual Actions and Core Web Vitals. Existing indexing state and manual/security actions were not accessible in this session.
    - In Cloudflare, inspect HTTPS enforcement and encryption configuration, WAF rules, rate limiting and verified search-crawler traffic. Zone lookup was allowed, but reads of `settings/always_use_https`, `settings/ssl`, `rulesets` and `bot_management` each returned **403** with the available OAuth scope. No security rule was changed. Exempt legitimate verified search crawlers from inappropriate challenges using [Cloudflare’s verified-bot guidance](https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-verified-bots/), rather than trusting a spoofable user-agent alone. Avoid blanket public-page challenges or caching authenticated responses.
    - Check image transformation support in the production Cloudflare setup: audited production image responses were much larger than the locally optimized equivalents. Do not infer production mobile performance from localhost alone.
    - Run the online structured-data validators after deployment; confirm official social-profile ownership before adding `sameAs`. Google Business Profile is a separate owner-controlled process if the business is eligible; no address or certification was invented here.

12. **Remaining indexing blockers and limits**

    The new release is not live, and its sitemap function is intentionally unapplied. Existing production metadata, duplicate origins and old sitemap behavior therefore remain until an authorized release. Verified Cloudflare crawler access, Search Console ownership/indexing state, Google-selected canonicals, online rich-results validation and field Core Web Vitals still require owner access or post-release observation. Low-contrast text findings are a documented accessibility follow-up, not proof of an indexing prohibition.

    The implementation makes intended public pages technically eligible once deployed and verified; it cannot force Google to crawl, index, display a Knowledge Panel or rank pages first. No immediate indexing or first-page promise is made.
