Customer and management mobile UI changes are ready in source; no APK or app bundle was built.

The unreadable Events/login headers came from a dark `AppBar` background combined with a retained explicit dark `titleTextStyle`. `KodimaliTheme.mobileLight()` now sets matching title, toolbar and icon colours. Both apps use this shared theme and `mobileDark()`. Management therefore adopts the customer's card surfaces, typography, spacing and navigation palette instead of maintaining separate bright navigation overrides.

The customer homepage category shortcut now has a visible Makundi/Categories label and a minimum 48-pixel touch target. It opens a scrollable, searchable category sheet with an explicit all-categories action and close button. Searches match English or Swahili captions, and navigation runs after the sheet closes. Category IDs and destinations are unchanged.

Homepage location, appearance and language controls have larger targets. Search expands to use the available row width, with its light inherited field fill disabled so white input remains visible. Branding fits narrow headers, category headings wrap, and category-card height responds to text scaling. Events uses the short translated Matukio/Events header and stacks location controls to avoid enlarged-text overflow.

Validation covers the real Events and login screens in English and Swahili, light and dark modes, at 320/390 px and text scaling of 100%/150%. Tests inspect rendered title contrast (at least 4.5:1), layout exceptions, the real home header/search, category searches and preserved category IDs/navigation callbacks. Full customer and management suites and shared theme tests are run, alongside Dart analysis.

The older-app cancellation-status compatibility migration from the preceding investigation remains prepared but unapplied while UI work takes priority. This UI update does not deploy database changes or remove any role-specific management functions.

Final verification: customer app 8/8 tests, management app 19/19 tests, shared design system 2/2 tests. Dart analysis of both apps and the shared design system reports no issues. No website or Supabase deployment was performed for this UI change.
