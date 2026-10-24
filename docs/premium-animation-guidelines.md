# Premium animation guidelines

| Interaction | Duration |
|---|---:|
| Press/focus feedback | 120–180ms |
| Hover/selection | 180–250ms |
| Card reveal | 250–450ms |
| Page transition | 250–500ms |
| Hero reveal | 600–1000ms |

Entrances use ease-out. Continuous motion is decorative only, pauses through browser lifecycle behavior, and never blocks input. The web implementation uses CSS and IntersectionObserver; no animation dependency or WebGL runtime was introduced.

`prefers-reduced-motion: reduce` disables ambient hero zoom, reveal transforms, smooth scrolling and long transitions. Flutter animations should check platform accessibility settings, avoid controllers when implicit animation is sufficient, dispose every controller and keep financial values static.

Never animate a successful payment, booking, referral or payout state before the server operation succeeds.
