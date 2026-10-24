# Premium UI audit

## Existing product surfaces

The repository contains a Next.js marketplace, Flutter customer app, Flutter Manage App and one Supabase backend. Authentication, real listing queries, booking requests, referral submissions, Information Admin permissions, customer activity and payment records already exist and must remain authoritative.

## Visual findings

- The website used a dense three-level header, repeated category controls and explanatory copy where direct actions were clearer.
- The homepage lacked a strong media-led first impression and repeated the same marketplace instructions in multiple cards.
- Listing cards used square media, verbose helper text and weak hierarchy.
- Customer account and referral routes were functional but visually isolated from the marketplace.
- Flutter already had a reusable theme, spacing, status and button system, but its legacy lime/navy palette did not match the premium direction.
- Information Administration had a working queue but no filtering, assignment surface or detailed timeline yet.
- Several empty states were verbose. Critical transactional screens must stay restrained rather than cinematic.

## Reusable foundations

- Web: `PageShell`, `SectionHeading`, `PublicListingCard`, `ListingMediaGallery`, `DirectMediaImage`, status pills and Supabase query helpers.
- Flutter: `KodimaliTheme`, `KodimaliColors`, `KodimaliSpacing`, `KodimaliRadii`, status badges, shared scaffold and repositories.
- Backend: existing RLS and RPCs remain unchanged by this visual phase.

## Motion direction

- Native CSS entrance and hover transitions on web, isolated behind `RevealOnScroll`.
- No WebGL and no animation package in the initial bundle.
- Reduced-motion disables ambient zoom, smooth scrolling and reveal transforms.
- Flutter uses built-in animation primitives and shared `KodimaliMotion` durations.

## Performance risks

- Hero media can dominate LCP; it uses `next/image`, responsive sizing and one project-local source.
- Too many observers or staggered cards can affect low-end devices; reveals are limited and observers disconnect after entry.
- Listing video and image grids must remain lazy outside above-the-fold content.
- Blur and continuous parallax are intentionally limited.

## Prioritized checklist

- [x] Dedicated redesign branch.
- [x] Premium palette and shared motion tokens.
- [x] Compact responsive navigation with session-aware account actions.
- [x] Cinematic, searchable homepage hero with original imagery.
- [x] Animated category showcase backed by real listing media.
- [x] Premium listing-card hierarchy and real data preservation.
- [x] Accurate referral journey and CTA.
- [x] Reduced-motion support.
- [ ] Multi-step referral form with upload UI.
- [ ] Full listing-page sticky booking panel and richer gallery controls.
- [ ] Manage App assignment sheet and follow-up timeline.
- [ ] Flutter home/property cards and route-transition pass.
- [ ] Device-based performance and accessibility lab testing.
