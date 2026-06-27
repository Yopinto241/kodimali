# KODIMALI Mobile UI System

This Flutter implementation now uses one shared design system for both mobile apps.

## Core rules

- Deep navy is the secure primary action color.
- Green is reserved for positive marketplace actions like `Tuma Ombi` and high-confidence next steps.
- White and soft gray surfaces keep screens calm and readable.
- Amber is for pending attention.
- Red is for danger or destructive moments only.

## Shared Flutter source

- Theme, colors, spacing, radii, button styles, and status tones live in `packages/flutter_design_system/lib/flutter_design_system.dart`.
- Both apps now load `KodimaliTheme.light()` and `KodimaliTheme.dark()` with `ThemeMode.system`.

## Reusable mobile patterns

- `KodimaliStatusBadge` keeps badge meaning consistent across customer and manage flows.
- `KodimaliButtonStyles.success` is the positive marketplace button style.
- `ManageHeroCard`, `ManagePanel`, `ManageMetricCard`, and `ManageWorkspaceScaffold` now follow the same visual language as the customer app.
- Customer listing cards, request flow, category headers, and location prompts now use the same palette, spacing rhythm, and action hierarchy.

## When adding new Flutter screens

1. Start with `KodimaliSpacing.screenPadding`.
2. Put context first, then the main action, then core content, then supporting details.
3. Reuse `Card`, `KodimaliStatusBadge`, and the shared button styles before inventing new visual patterns.
4. Keep videos tap-to-play and avoid public display of exact private location details.
