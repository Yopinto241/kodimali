# Database Design

## Core principle

One Supabase PostgreSQL schema powers customer browsing, agent operations, and admin moderation.

## Main tables

```text
profiles
user_roles
agents
agent_documents
owners
locations
asset_categories
listings
listing_media
listing_private_locations
property_details
vehicle_details
venue_details
availability_blocks
booking_requests
booking_status_history
device_tokens
notifications
reports
reviews
audit_logs
```

## Key relationships

```text
auth.users 1 -> 1 profiles
profiles 1 -> many user_roles
profiles 1 -> 0..1 agents
agents 1 -> many owners
agents 1 -> many listings
locations 1 -> many child locations
locations 1 -> many listings
asset_categories 1 -> many listings
owners 1 -> many listings
listings 1 -> many listing_media
listings 1 -> many booking_requests
booking_requests 1 -> many booking_status_history rows
```

## Listing model

`listings` stores universal commercial and visibility fields:

- legacy `category` enum for compatibility
- `category_id` pointing to `asset_categories`
- `listing_attributes` JSON for dynamic fields
- title and description
- structured location reference
- public location label
- private address or optional pin
- price and price period
- deposit
- listing rules
- account-aware visibility state
- availability state
- expiry and publication timestamps

Dynamic category definitions live in `asset_categories`:

- `name`
- `slug`
- `icon_key`
- `display_order`
- `is_active`
- `home_feed_weight`
- `field_schema`

Legacy category-specific detail tables still exist for backward compatibility:

- `property_details`
- `vehicle_details`
- `venue_details`

## Media model

`listing_media` replaces image-only handling and supports:

- `image`
- `video`

Important fields:

- `thumbnail_path`
- `display_order`
- `is_cover`

## Location model

Locations use a self-referencing hierarchy:

```text
Country
 -> Region
 -> District
 -> Ward
 -> Area
 -> Street
```

This keeps search, filtering, and admin cleanup consistent.

## Request model

`booking_requests.agent_id` is copied from the listing when the request is created.

That gives:

- correct routing
- clean agent history
- auditable ownership
- simpler notification targeting

Guest requests now allow:

- `customer_id` to remain `NULL`
- name and phone only
- automatic `created_at`
- multiple requests against the same listing

## Public feed model

`get_public_home_feed` is the main feed RPC for public surfaces.

Its job is to:

- enforce the central public eligibility rule
- prioritize selected region and district
- use approximate GPS only for ranking
- aim for an approximate 50/50 split between house listings and other active categories
