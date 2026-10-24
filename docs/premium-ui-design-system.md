# KODIMALI premium design system

## Foundation

| Token | Value | Use |
|---|---:|---|
| Navy | `#102438` | Primary text, navigation, dark panels |
| Teal | `#147D8C` | Primary action and selected state |
| Gold | `#D6A75B` | Selective premium accent |
| Canvas | `#F7F8FA` | Page background |
| White | `#FFFFFF` | Primary surfaces |

Success, warning, error and information colors remain semantic and must not be replaced by decorative gold. Body text uses Manrope and headings use Plus Jakarta Sans on web; Flutter uses the platform-compatible shared theme.

Spacing follows an 8-point base: 8, 12, 16, 24, 32, 40 and 48. Controls have a minimum 44px touch target. Cards use 18–24px radii; feature panels may use 32px. Shadows remain low-opacity navy rather than black.

## Components

- Primary action: teal fill; premium/referral feature action may use gold.
- Secondary action: pale surface with a visible border.
- Cards: white surface, restrained border, lift of at most 5px on pointer hover.
- Forms: persistent labels, visible focus rings, inline errors and no delayed validation.
- Status: text plus color; never color alone.
- Empty states: one short factual sentence and an action only when useful.
- Navigation: compact desktop bar, 44px mobile menu trigger and session-aware account controls.

## Themes and responsiveness

Web defaults to light premium canvas. Existing Flutter light and dark themes inherit the same navy/teal family. Layouts target narrow mobile, standard phone, tablet and desktop without hiding business-critical fields.
