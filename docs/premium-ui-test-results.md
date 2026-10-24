# Premium UI test results

## Automated checks

Results for this implementation:

- Web ESLint: passed.
- Next.js TypeScript and production build: passed; 27 routes generated.
- Shared Flutter design-system tests: 2 passed.
- Customer Flutter analysis: passed with no issues.
- Manage Flutter analysis: passed with no issues.
- The previously reported Dart SDK mismatch was not reproduced in the current environment. The configured SDK accepted the packages and analysis completed.
- Customer app has no `test` directory, so no customer widget suite was available to run.

## Manual checks

- Keyboard navigation and visible focus.
- Mobile menu and account state.
- Reduced-motion mode.
- Hero/search at 360px, 412px, 768px and desktop widths.
- Real listing media, empty results and missing-image fallback.
- Referral submission success only after Supabase response.

## Measurement status

Lighthouse percentile targets, INP, CLS, LCP, memory growth and low-end Android frame timings require deployed or profiled builds. They are not claimed as achieved from a local production build alone.

Screenshot automation was not available in the current tool environment. The generated hero source was visually inspected before integration.
