# Mobile Clear filters layout

The shared listing/category filter footer now uses a two-column grid below 720px. Results occupy their own row; sort and Apply remain together; Clear filters occupies a full-width row with a minimum 44px tap target. Desktop layout and filter-reset behavior are preserved.

Validated global listings and the House category at 320, 390, 430 and 1440px in English and Swahili: no horizontal overflow, phone Clear button fills its row, text fits, and clicking clears price/sort while retaining the correct route. Inspected the 320px Swahili screenshot. ESLint and the production OpenNext build passed.

Validation logs: `tmp/mobile-clear-browser.log`, `tmp/mobile-clear-build.log`. No APK generated.
