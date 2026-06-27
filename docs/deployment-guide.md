# Deployment Guide

## Shared architecture

- Customer app: Flutter
- Manage app: Flutter
- Website: Next.js
- Backend: Supabase
- Notifications: Firebase Cloud Messaging

## Environments

Create at least:

- `development`
- `staging`
- `production`

Each environment should have its own:

- Supabase project
- Firebase app configuration
- storage buckets
- secrets
- location seed data

## Website deployment

Deploy `apps/web` to a Node-compatible host such as:

- Vercel
- Docker on a VM
- Railway
- Render

Required environment variables:

```text
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
```

## Mobile deployment

- Publish `apps/customer_mobile` and `apps/manage_mobile` separately.
- Keep customer and management app bundle identifiers separate.
- If needed, use separate Firebase app registrations for cleaner notification routing.

## Supabase deployment

1. Do not rerun or modify already-applied `001`, `002`, or `003`.
2. Apply only the new local migration `004_marketplace_activation_categories_feed.sql`.
3. Enable or verify RLS policies before public rollout.
4. Seed or verify the live location hierarchy.
5. Deploy the updated Edge Functions.
6. Verify public browsing, guest requests, and agent activation flows.

## Launch checklist

- Guest request submission works end to end
- Agent activation and suspension work end to end
- Dynamic categories load in public and management surfaces
- Location hierarchy is loaded and usable
- Media limits are enforced
- Customer requests route only to the posting agent
- Inactive or suspended agent listings disappear from public surfaces
- Admin can suspend bad actors quickly
