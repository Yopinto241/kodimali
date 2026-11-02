# Supervisor own assets and complete web publication — 2026-11-01

## Confirmed defects
- A Supervisor's restrictive agents policy allowed assigned subordinate records but excluded their own agent record. Although their live account had an active approved agent record, the agent role and an assigned category, the web/mobile profile lookup could not read it. Payment-owner policies using an agents subquery were affected too.
- The previous web upload form stopped after saving media to a draft; it did not initiate the existing agent listing payment/release workflow.
- Selected-image removal existed as a small text link; it is now an explicit large Remove image button with a cross.

## Changes
- Migration 20261101160000_supervisor_own_agent_workspace splits the restrictive ALL policy into command-specific policies. SELECT allows one's own profile in addition to the assigned team. INSERT/UPDATE/DELETE preserve the original team boundary. A narrowly scoped Supervisor self-read policy supplies SELECT access without granting profile writes or approval privileges.
- Add Asset routes infer the agent workspace when the account has an agent role. The administrative navigation provides Add my asset for dual-role users.
- Upload asset saves the record and images, then presents Submit listing. This uses the same create-agent-listing-payment / check-agent-listing-payment functions as Manage mobile. Draft status becomes inactive after upload; only the existing backend release function can publish based on current fees, active account, valid media and approval requirements.
- The publication panel shows published, approval pending, or mobile payment confirmation/check states. An existing pending payment is checked rather than initiating another payment request. Resumable submission is also available on eligible own-listing detail pages.
- Selected images can be removed and selected again before upload. The upload phase locks image edits to keep saved metadata consistent.
- New interface copy is translated in the web English/Swahili catalog.

## Validation
- Existing supervisor SQL regression suite passed, including promotion, territory/team exclusivity, revocation and legacy staff. Added checks confirm own agent read, another team's agent remains invisible, and own-record UPDATE/DELETE remain denied.
- Applied only the named migration and its migration history atomically. No accounts/assignments changed. Live read-only authenticated check confirms the existing Supervisor now sees exactly their own agent record and assigned category and remains active.
- TypeScript and targeted ESLint pass; 22 web library tests pass.
- Isolated Playwright acceptance cases passed at mobile/desktop widths for Supervisor dual-role Add Asset routing, image removal/reselection, hierarchy/manual area, JPEG upload, partial upload retry using the same draft, free publication, paid publication and approval pending. All listing/location/payment/storage mutations mocked; no real charges, listings or media created.
- OpenNext build completed. Deployment and provider logs: tmp/publication-deploy.log, tmp/publication-deployments.log. Live isolated acceptance log: tmp/publication-live-browser.log.

## Operational limits
No APK generated. The database self-read fix also benefits installed Manage apps after profile refresh/workspace selection; native UI source was not changed. Network failure while creating a draft can still require checking My listings before making another draft. Existing plan/payment/approval rules were not bypassed or changed.
