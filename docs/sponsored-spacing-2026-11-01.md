# Sponsored spacing and overflow

The requested feed pattern is **three ordinary listings, then one sponsored card**. A sponsored slot is inserted only when another listing follows, so the feed opens with listings and ends with a clearly separated sponsored section instead of a block of trailing ads. Every unique eligible campaign is included once in the combined inline/overflow inventory; duplicate campaign IDs do not create extra cards. The existing campaign eligibility and ordering are preserved.

With 12 listings and 20 campaigns, three campaigns occupy slots after listings 3, 6 and 9. The other 17 appear in a single sideways-scrolling sponsored row below the listings. Scrolling/swiping accesses every card. No campaign is discarded or hidden behind an expansion button. Short and empty feeds use the sponsored row directly. This is a per-feed layout rule, not a cross-session impression limit.

Web Home shows listing rails before its sponsored row. Web Events and Customer mobile Events use the same three-listing spacing, followed by the overflow row. Customer mobile browse/search/home feeds use the same spacing. Available third-party ad slots use the same spacing opportunities only when a KODIMALI sponsored card is not occupying that slot, preventing stacked ad placements. Web third-party slots require configured client and slot IDs.

Cards retain their existing appearance, category/location eligibility, tracking, links and visible muted video autoplay. Off-screen videos remain paused. The sponsored row has a visible translated swipe hint; web keyboard users can focus and scroll the row. English and Swahili support is included. No database migration or live campaign changes are required. No APK is generated.

Validation covers more than 100 campaigns, duplicate IDs, short/empty listing feeds, inventory preservation, horizontal access, three-to-one spacing, category isolation and video playback lifecycle.

Released web version `d325fef2-0103-47b9-9f66-992f6f3deaf9` at 100% traffic on November 1, 2026 (06:13 UTC). Nineteen web library tests, ESLint, the full production build and all 17 Customer mobile tests passed; Customer mobile analysis reported no issues. Browser fixtures verified all 109 campaigns, horizontal scrolling and Events placement at 390/1440px. Live checks passed for `/listings`, `/category/house` and `/events` at both sizes, including eligible inventory counts, scrolling layout, muted autoplay, blocked session storage and no page errors. Logs are in `tmp/sponsored-spacing-*.log`.

The new nested horizontal/vertical layout required listening to both enclosing scroll positions for native video visibility. Visibility now also intersects ancestor viewport bounds; the video lifecycle regression test confirms vertical page scrolling pauses videos in the sponsored row.
