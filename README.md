# KODIMALI Platform

KODIMALI is a shared rental marketplace platform with:

- `apps/customer_mobile`: Flutter app for customers
- `apps/manage_mobile`: Flutter Manage App for agents and admins
- `apps/web`: Next.js public marketplace and customer web account
- `packages/*`: shared Dart packages for models, constants, theme, and app utilities
- `supabase/*`: shared backend schema, seed data, and Edge Function stubs
- `docs/*`: business, database, API, and deployment guidance

## Platform goal

Build one platform, not disconnected systems.

```text
Customer App
Manage App (Agent + Admin)
Website
        |
One Supabase Backend
```

This repository now follows the final operating design:

- One Manage App checks role after login and opens agent or admin dashboard
- Booking requests are owned by the posting agent from the moment they are created
- Locations come from Supabase hierarchy, not free-text entry
- Listing media supports images and video with controlled limits
- Kiswahili-first product direction stays intact

## Repository structure

```text
apps/
  customer_mobile/
  manage_mobile/
  web/
packages/
  flutter_core/
  flutter_design_system/
  shared_models/
  shared_constants/
supabase/
  migrations/
  functions/
docs/
.github/workflows/
```

## Local setup

### Web

```bash
cd apps/web
npm install
npm run dev
```

### Flutter apps

```bash
cd apps/customer_mobile
flutter pub get
flutter run
```

```bash
cd apps/manage_mobile
flutter pub get
flutter run
```

### Supabase

1. Create a Supabase project.
2. Apply `supabase/migrations/20260624_initial_schema.sql`.
3. Load `supabase/seed.sql` for demo content if needed.
4. Configure environment secrets for Edge Functions:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `FCM_SERVER_KEY` or your preferred notification credential

## MVP scope

The first launch stays intentionally focused:

- Geography: Arusha first
- Categories: houses, cars, motorcycles, offices, meeting halls, ceremony halls
- Media limits: up to 8 images, up to 1 video, 30 seconds, 25 MB max
- No payments yet
- No SMS yet
- No in-app messaging yet
- No maps for public exact addresses yet

## Core operating rules

- Agents add private owner records and post listings for approval.
- Admins approve agents, listings, locations, and moderation actions from the Manage App.
- Booking requests always copy `listings.agent_id` into `booking_requests.agent_id`.
- Customers initially see only approximate location such as `Njiro, Arusha`.
- Exact addresses and map pins stay protected until the workflow allows disclosure.

## Suggested next steps

1. Connect the apps and website to one Supabase project.
2. Build real login and role-routing inside the Manage App.
3. Implement listing posting with category-specific forms and location pickers.
4. Add scheduled handling for `agent_delayed` and `no_response` workflows.
5. Wire Firebase Cloud Messaging for live operational alerts.

