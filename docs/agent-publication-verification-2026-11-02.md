# Agent upload and publication verification

The deeper verification reproduced an additional blocker: Manage allows an uploaded video to be the listing cover, with uploaded images in the gallery, but `listing_has_publishable_media` required the cover itself to be an image. A real database transaction with authenticated agent permissions successfully created/staged the listing and attached its media, then failed to publish it with the old helper.

Migration `20261102200000_publish_video_cover_with_image.sql` allows an image or video cover while still requiring at least one uploaded image. Media insertion continues to require a verified storage object. Agent ownership, account verification, approval, payment, capacity and removal checks are preserved. This backend change also applies to existing Manage app installations without generating an APK.

Before release, the candidate helper passed local SQL tests for image cover, video cover with gallery image, no media, missing cover and video-only rejection. It also passed the formerly failing publication scenario against the actual linked schema within a rolled-back transaction. Eight publication authentication tests and the dynamic fee regression suite passed.

The migration was applied individually and recorded in live migration history. Post-deployment, `scripts/test-publication-live-transaction.sql` passed both complete image-cover and video-cover cases under actual authenticated/service roles and RLS. It verifies own draft visibility, media attachment, staging, plan capacity, release and appearance in the public home feed. Simulated storage metadata and all database test rows are rolled back; no binary file upload or real payment occurs in this database test.

The separate Playwright acceptance test exercises actual browser JPEG compression, upload calls, partial upload failure/retry without duplicate drafts, submission, and reopening/reloading My listings. Its authenticated APIs and storage are isolated fixtures against the live website.

All five browser scenarios passed after reopening/reloading: free, paid, approval required, switching to free and a zero-fee plan. Pending-approval cases were submitted again from the reopened detail page without creating a second draft. The test uses HTTP/1.1 for intercepted browser traffic; initial HTTP/2 automation runs intermittently stalled on script downloads. A separate unmocked live Manage sign-in check loaded normally. Read-only production verification confirms the migration, both real listings remain active, and no probe listings or simulated storage metadata remain.

Evidence: `tmp/publication-video-before.log`, `tmp/publication-video-patched.log`, `tmp/publication-cover-sql-tests.log`, `tmp/video-cover-release.log`, `tmp/publication-complete-live.log`, `tmp/publication-second-auth-tests.log`, `tmp/publication-second-fee-tests.log`, `tmp/publication-cover-live-verify.log`, `tmp/publication-reopen-live-browser.log`.
