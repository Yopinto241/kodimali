# Add Asset web repair — 2026-11-01

The live web AddListingForm had no image input/compression/upload pipeline and loaded all location types into a single unpaginated select. Category textarea fields rendered as single-line inputs. The Manage native app already had hierarchical locations, manual area entry, image previews, cover choice and compression.

## Web repair
- Reuse the hierarchical location picker, requiring an area and allowing a new area name under a selected ward via the existing ensure_ward_area RPC.
- Add multiline additional details to the public description. Unknown keys are intentionally not injected into listing_attributes: the database rejects keys absent from the category schema.
- Support multiple JPG/PNG/WebP images, local previews, removal and cover selection. Resize to at most 1920 pixels on the longest edge, encode JPEG with progressively lower quality towards 420 KB; the target is best effort. Show source/prepared sizes.
- Match Manage image counts: 15 for apartment, 8 for other categories. Require at least one image.
- Preserve private optional owner details and draft/review workflow.
- Upload under the authenticated user's folder with existing storage policies. Store actual JPEG bytes with matching extension/MIME. Bound upload waiting to 60 seconds, draft creation to 30 seconds and metadata/location requests to 10–15 seconds.
- Retain the confirmed draft ID and upload paths while the form remains open, so an image/metadata retry does not create another draft. Check existing metadata before inserting it again. If draft creation itself loses its response, the message directs the agent to check My listings before starting another draft; full cross-session idempotency is not introduced in this patch.
- Save button recovers in finally and shows a polite message. Added English/Swahili UI translations.

## Validation
- TypeScript and targeted ESLint pass.
- Existing web library suite: 22 passing tests.
- scripts/test-add-asset-web.py: isolated authenticated fixtures at 390 and 1440 widths. Verifies hierarchical choice, typed area resolution, extra description, actual JPEG header, upload failure/retry, same draft/storage path, cover metadata and no horizontal overflow or page exceptions. All mutations/storage writes intercepted.
- Manage media validator suite: 7 passing tests. No native source changed; no installed-device verification and no APK generated.
- OpenNext production build completed. Deployment result is recorded in tmp/asset-deploy.log and provider verification in tmp/asset-deployments.log.
- Browser screenshots: design-previews/add-asset/form-390.png and form-1440.png.

## Scope and operational limits
No real accounts, listings, media or database permissions were changed by tests. No database migration was required. The new web form creates a draft; existing payment/publication review remains the next workflow. Native video compression already exists; this patch adds web images, not browser video transcoding. A browser that cannot decode HEIC should use JPG/PNG/WebP. Prepared images are retained in memory during the form session, so keep the tab open when retrying an image upload.

Deployment verified: Cloudflare version 225b9a5a-4838-4518-9def-7708e43c8e10 receives 100% of traffic. Live isolated acceptance flow passed at 390 and 1440 widths, including failed-upload retry. Production fixture writes were intercepted.
