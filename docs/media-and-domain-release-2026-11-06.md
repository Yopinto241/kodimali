# Listing media and official domain - 2026-11-06

## Delivered

- Customer listing shares use `https://kodimali.com`. Legacy `.co.tz` inbound links remain accepted for compatibility. Manage URL examples and shared package homepages use the official domain.
- Supabase Auth's production `site_url` is now `https://kodimali.com`; official-domain redirects were added while preserving every existing redirect. A fresh remote configuration snapshot was stored outside the repository before the update; the post-update configuration diff was empty. No database migration or Edge Function update was necessary.
- Customer and Manage listing cards use larger portrait media frames. Customer detail media is taller; Manage detail replaces 56-pixel media records with a swipeable full gallery, playable video and fullscreen photo zoom.
- Website cards use portrait media on mobile and landscape media on desktop, with complete photos/videos contained within the frame. Titles and locations sit below media; cards grow with their content. Detail galleries use the same larger responsive framing and retain fullscreen photo viewing.
- Customer video uses network streaming instead of downloading the entire MP4 before creating a player. Shared mobile players initialize only when visible, pause off-screen/in the background, reject hidden routes, and dispose replaced sources. Visibility uses the available viewport area so large portrait frames remain playable on smaller screens. Muted card previews hide playback controls; detail players retain interactive controls.
- Shared mobile images use persistent caching and bounded image decoding. Optional prefetching checks existing cache entries and is limited to two feed images or one detail image; videos are excluded.
- The website's existing Cloudflare deployment has no `IMAGES` binding, so its image proxy returned unchanged original bytes at every requested width. Supabase images now load directly, avoiding that redundant proxy hop. Existing upload compression remains in place; this change does not promise resized WebP/AVIF delivery or alter original customer uploads.
- Website video sources activate once near the viewport, avoiding repeat `.load()` calls on scrolling back. Removed forced seeking/canvas poster extraction. Listing previews play muted only while visible; detail controls remain available.
- Added Swahili labels for media controls and preserved the required English product term "booking" in the mobile contact header.

## Verification

- Customer app full suite: 36 passed. The subsequent combined media/discovery suite: seven passed (network streaming, visibility/background pause, source replacement/disposal, oversized frames, hidden media).
- Manage app full suite: 49 passed. Both app analyzers passed. Shared media file analysis passed.
- Shared Flutter package suite: nine passed. Package-wide analysis has one pre-existing informational brace warning in `push_device_lifecycle.dart:52`; the new media code has no findings.
- Website TypeScript, component ESLint and production build passed. Cloudflare production version: `f7176798-1e3a-4c86-8442-9383fb2c6c11`, serving `kodimali.com` and `www.kodimali.com`.
- Live checks at 390px and 1440px confirmed HTTP 200 homepage/detail pages, contained media, titles below media, working fullscreen photos, and no browser page errors. Final release checks also confirmed muted cover-video playback and pausing when scrolled off-screen at both widths.
- Mobile homepage media increased from 224px to approximately 391px high. Detail media measured 346 x 432.5px on mobile and 1108 x 831px on desktop.
- Two image samples were byte-identical through the former proxy and directly from storage (320,300 and 149,013 bytes). One sequential check measured proxy times of 2.04/1.64 seconds and direct times of 0.98/0.46 seconds. These are sample observations, not speed guarantees.
- A live 12,752,706-byte MP4 served a 4,096-byte range with HTTP 206. Browser playback was verified; one check began playback in about 1.9 seconds after waiting for metadata. Network/device conditions affect results.

## Release boundaries

No APK/AAB was built, installed or published. Both mobile apps require the next signed release for installed users to receive these source changes. No customer payment, notification or account changes were made. No paid image-processing service was enabled. Physical-device playback and slow-network behavior still need release-device checks; automated platform fakes and Chromium playback do not establish behavior on every device.

Public screenshots, non-sensitive timing results and build logs are in the ignored local `tmp/media-domain-20261106` directory. Production Auth recovery configuration is stored securely under the user's `Kodimali-Recovery/20261106-media-domain` directory outside the repository.


## Follow-up: compact listing cards

At the user's request, normal listing cards were restored to their earlier dimensions: square Customer media, 160px Manage previews, and 390px website cards with 224px media. Website card titles returned to their prior overlay position to fit the original card height. The large detail galleries, streaming, caching and official-domain changes remain in place.

Both mobile analyzers passed. The website production build and TypeScript checks passed. Cloudflare production version: `404f1e25-b336-4df0-8d3c-1709fb4f4df7`. No mobile binaries were built.

Live Chromium checks at 390px and 1440px confirmed 390px cards with 224px media, while detail galleries remained 432.5px and 831px high respectively. Homepage/detail requests returned HTTP 200 with no browser page errors.
