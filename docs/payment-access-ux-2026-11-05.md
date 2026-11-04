# Payment-aware contact and chat UX - 2026-11-05

**Website and three payment functions deployed. Customer/Manage source updated and pushed. Mobile distribution, social publishing authorization/integration and provider acceptance remain outstanding.**

Source commit: `e3a9f5e46ceb22ed5cc899371c041cb429b791bf`, branch `feature/kodimali-events`. This follows the production audit-repair rollout; it does not replace that release's external/device acceptance requirements.

## User-visible behavior

- Free contact access shows the agent's number immediately, with matching WhatsApp links on the number/icon and WhatsApp action. A separate Call action remains available. No payment form, payment phone collection or pay/unlock copy appears in free mode.
- WhatsApp on a listing checks current access. Free access continues to the agent's `wa.me` destination. Paid access retains WhatsApp intent through payment and continues there automatically after server confirmation.
- Free chat and an existing current-agent entitlement open the conversation directly after sign-in. No payment form is shown. Anonymous chat requires sign-in because conversation membership is account-bound; contact access can remain anonymous.
- Paid access presents the server's current amount before an explicit payment action. Checkout submits that amount for comparison; a changed fee rejects before creating an order. The existing-access check precedes payment phone validation, and backend read errors fail closed.
- The former Next steps / Pay and unlock number / Private chat block is replaced by contact details and clear Chat here / Request a booking actions. Unavailable booking modes are hidden. Listing-card booking links now open the booking page instead of a removed anchor.
- Unknown settings show retry instead of inventing a free entitlement or TZS 1,000 price. Pending contact payments cannot be casually reset into another payment. Verified contact expiry remains respected.
- Contact phone numbers from cached listing summaries are not embedded in the server-rendered card props. Website access refreshes periodically and on focus/account changes; app contact access is rechecked when opened and resumed. Backend checks remain authoritative if administrative settings change during checkout.

The customer app removes the preliminary pay-to-chat dialog, uses current access/price, automatically enters available chat, refreshes after sign-in, and uses a real WhatsApp icon and destination for the contact number. Manage administration now calls the feature Chat. No new APK/AAB or store release was produced by this change; installed applications need a new signed build to receive these updates.

## Deployment and verification

No database migration was required or applied, and no administrative settings were written. Fresh snapshots before deployment, after Edge deployment and after website deployment matched exactly. The administrator's current **chat and contact payment switches are both off**; they remain off. This intentionally differs from the historical audit-release snapshot because administrator settings are authoritative.

A live read-only quote returned free contact access without customer details, payment ID or access capability creation. An unmocked production browser verified that the actual number and WhatsApp action share the same destination, free contact has no payment form, and anonymous free chat asks only for sign-in. No payment, provider callback, customer message, payout or refund was submitted.

| Edge Function | Deployed version | State |
|---|---:|---|
| `create-listing-contact-payment` | 34 | ACTIVE |
| `check-listing-contact-payment` | 25 | ACTIVE |
| `create-listing-chat-payment` | 24 | ACTIVE |

All three retain handler authentication/gateway settings from the reviewed audit release. Worker credentials, provider credentials and webhook authenticity enforcement were not changed.

Cloudflare worker: `kodimali-web`, production domains `kodimali.com` and `www.kodimali.com`. Deployment `0e8ce1ab-9367-413b-a552-2a8708760916`, version `6301db89-cd50-4018-8e0e-467c9f666da0`, 100% traffic, created `2026-11-04T21:20:24.05388Z` (5 November in Nairobi).

Passed checks:

- Customer analysis: no issues; 30 full-suite tests and four focused final access-gate tests.
- Manage changed-file analysis: no issues. This app change is copy only.
- 22 Edge regression tests; three changed entrypoints type-checked.
- 29 web unit tests; lint, TypeScript, Next and OpenNext production builds.
- Eight browser scenarios locally and against deployed frontend assets: English/Swahili mobile and English desktop free contact, free chat, existing paid chat entitlement, paid WhatsApp continuation, current paid-chat pricing and unavailable-settings recovery.
- Mobile/desktop overflow checks and visual review of the contact screen.

Browser payment scenarios intercept Auth/PostgREST/checkout responses and create no actual charges. They verify the deployed frontend's behavior, not provider settlement. The separate unmocked check verifies actual current free-mode behavior. Real provider/device acceptance is not claimed.

## Social publishing: not active

Requested destinations are Instagram `@kodimali1`, Facebook Page **Kodimali Tanzania**, and TikTok `@kodimali1`. The caption must use the agent's listing description. Only approved, publicly available listings should publish; draft/rejected posts must stay private, and edits/retries must not create duplicates.

The repository has no active automatic social publisher, and none was falsely enabled by this release. Metricool was found and offered as a possible approved publisher connection. The available installation controls only initiate a user connection flow; they cannot complete installation or sign into the owner's accounts. Account authorization was not confirmed, and no publishing tokens or verified Page/account IDs are available to the backend.

After account authorization, the remaining implementation is to verify the exact destinations and publishing scopes, connect a durable approved-listing event queue to the approved publisher API, implement platform-appropriate media/caption validation, retries/deduplication and status reconciliation, then verify a controlled post. Installing a chat connector alone does not create a continuous backend automation. Do not mark a post published until the provider confirms it.

TikTok requires an authorized publishing app and applicable creator/privacy/consent handling; arbitrary background direct-post behavior should not be invented. See [TikTok's official posting guide](https://developers.tiktok.com/docs/en/content-posting-api-get-started) and [content-sharing guidelines](https://developers.tiktok.com/docs/en/content-sharing-guidelines). An approved social-management integration is the appropriate path to assess for these brand accounts.

## SonicPesa: user deferred provider testing

ClickPesa checksum configuration and SonicPesa credentials are separate integrations. The existing ClickPesa `_CHECKSUM_SECRET` compatibility alias remains intact. SonicPesa payment requests use `X-API-KEY`, as shown in its [official payment examples](https://docs.sonicpesa.com/pages/code-examples.html).

SonicPesa's webhook/signing documentation returned HTTP 403 to web requests and the browser during this task, so its exact signing contract was not independently verified. No checksum/secret value was guessed, renamed, exposed or rotated, and authenticity checks were not disabled. The user explicitly deferred SonicPesa testing. Existing provider acceptance remains open until their controlled test and accessible official webhook verification contract are available.

[Sanitized deployment evidence](payment-access-ux-evidence-2026-11-05.json) contains exact versions and verification outcomes. Raw logs and screenshots are ignored under `tmp/`; unrelated `design-previews/` and `homepage-mobile-check.png` were preserved.
