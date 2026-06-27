# KODIMALI UI System

This web implementation now follows one shared product language:

- Brand colors: navy for trust and structure, green for marketplace actions, white and soft gray for breathing space, amber for pending states, red for danger only.
- Layout rule: every page leads with context, then the main action, then primary content, then supporting information.
- Spacing rule: components are built around the 8px rhythm using 16px mobile gutters, 24px tablet gutters, and a 1200px centered desktop shell.
- Card rule: white or soft-surface cards, 16px to 20px radii, thin borders, and restrained shadows instead of heavy glass effects.
- Button rule: `btn-primary` is the secure navy action, `btn-success` is the positive marketplace action, and `btn-outline` handles secondary actions.
- Form rule: labels stay visible above inputs, helper text sits below fields, and errors are written in text rather than shown with color alone.
- Badge rule: status meanings stay stable across the app through `StatusPill` tones for active, pending, danger, muted, and info.
- Media rule: listing imagery uses consistent cover ratios, videos do not autoplay, and placeholders are visible while media is missing.
- Dark mode rule: dark surfaces stay deep navy rather than pure black and preserve the same status color meanings.

Code touchpoints:

- Global tokens and shared utility classes live in `apps/web/src/app/globals.css`.
- Brand typography is defined in `apps/web/src/app/fonts.ts` and applied in `apps/web/src/app/layout.tsx`.
- Shared page structure is handled by `apps/web/src/components/page-shell.tsx` and `apps/web/src/components/page-hero.tsx`.
- Shared status, form, and card language flows through `apps/web/src/components/`.

If new pages are added later, the safest default is:

1. Start with `PageShell`.
2. Add context and the primary action through `PageHero`.
3. Reuse `surface-card`, `soft-panel`, `StatusPill`, and the shared button classes before inventing new page-level patterns.
