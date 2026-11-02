# Sponsored ads as listing cards

Sponsored campaigns now use listing-style cards on the website and Customer mobile source. Every eligible campaign assigned to the selected category is included, with no expansion button or one-ad category limit. Empty or short listing feeds retain all campaigns.

## Category assignments

In the website Manage → Promotions, select **Sponsored categories** and save. Manage mobile's promotion editor offers the same multi-category selection in its next app build. An empty selection means all categories. Existing campaigns keep that default until edited.

Category assignments work with existing placement, audience, active dates and location eligibility. Paused, expired, private or geographically ineligible campaigns are not made public. Multiple campaigns can target one category, and one campaign can target multiple categories.

Only migration `20261031210000_sponsored_category_cards.sql` is applied. It adds `target_category_ids`, validates IDs, and introduces a paginated public read RPC that reuses the existing promotion-eligibility function. Clients read every API page instead of stopping at one, two or six campaigns. Existing RPCs remain available to older apps.

## Presentation and playback

- Sponsored cards share listing media proportions, card colors and rounded corners. They retain a visible sponsored label and their destination button, without inventing a listing price or booking action.
- Global and category feeds insert an ad after every two listings, then include remaining campaigns. Empty feeds still show the assigned campaigns. The home page has a listing-style sponsored grid before listing rails. Events also receives its assigned campaigns.
- Ad videos play muted and loop when at least half the video is visible, then pause off-screen, in hidden browser tabs or while the app is inactive. Browser autoplay restrictions retain ordinary playback controls. Autoplay does not seek past the start to create a poster.
- Native video uses streaming playback and initializes on visibility. Website video sources load near the viewport. Existing viewable-impression tracking is retained, with no duplicate impression from native video visibility checks.
- Images and destination buttons open the campaign link. Unsafe/missing destinations retain the Browse listings fallback. Existing contact unlocking and fees are unchanged.
- Newly added management copy and sponsored labels support English and Swahili. No APK is generated.

## Verification

- SQL tests cover all matching ads, overlapping category assignments, invalid-category rejection, audience/activation eligibility, anonymous access and inventories exceeding 100 campaigns.
- Production-build browser fixtures verify 109 campaigns across API pages, category isolation, empty feeds, listing/ad order, mobile/desktop layout, visible autoplay, pausing off-screen and multiple-category assignment from the management UI.
- Video browser fixtures use [MDN's CC0 flower sample](https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.webm) stored locally. All campaign records, management writes and analytics are mocked; no test campaign or payment is created in Supabase.
- All 16 Customer mobile tests passed, including video lifecycle and campaign replacement tests. Customer and Manage mobile analyses reported no issues. Web library tests passed (17), ESLint passed for changed public components/helpers, and the full Next/OpenNext build completed.

Cloudflare version `b986dc1b-45ab-42ed-8687-e5c2418b1b06` serves 100% of traffic on kodimali.com and www.kodimali.com. The deployment completed on 1 November 2026 at 00:17 EAT (31 October 21:17 UTC). An initial authentication failure was resolved by retrying with the refreshed session and the same tested artifact.

Live verification compared rendered cards with the public RPC's eligible inventory on `/listings`, `/category/house` and `/events` at 390px and 1440px. Each page showed both eligible campaigns, without an expansion gate. Muted autoplay worked on every page and no page errors occurred, including with browser session storage blocked. Results are in `tmp/sponsored-live-results.json`.

The existing promotion cache remains in use. New category assignments are saved immediately in Supabase; cached public responses can take up to five minutes to refresh. No live campaign content or category assignment was changed by the implementation or tests. Customer and Manage mobile changes require the next app build; no APK was generated.
