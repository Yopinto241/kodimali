# Business Rules

## Operating model

- KODIMALI has three product surfaces: Customer App, Manage App, and Website.
- The Manage App is shared by agents and admins.
- Customers browse publicly with no account, login, registration, or profile.
- Role check after login determines which Manage App dashboard opens.

## Roles

### Public visitor

- Searches eligible public listings.
- Sends guest requests using only full name and phone number.
- Can skip location access and still browse normally.
- Does not see owner phone numbers, exact addresses, or exact private map pins.

### Agent

- Registers and submits verification documents.
- Starts as `inactive` until admin confirms offline activation.
- Stores owner details privately.
- Posts listings directly when the account is active.
- Manages pricing, availability, visibility, and customer request responses.
- Receives requests only for listings they posted.

### Admin

- Activates, deactivates, or suspends agents.
- Moderates listing visibility and can remove or reactivate any listing.
- Manages categories, locations, complaints, and fraud actions.
- Monitors all customer requests without becoming the default request handler.

## Asset posting flow

Active agents post in this order:

```text
1. Choose asset category
2. Add basic information
3. Select location
4. Add price and availability
5. Upload media
6. Add owner record
7. Publish listing to the marketplace
```

## Listing rules

- A listing belongs to one agent account.
- A listing may link to one owner record.
- An active agent can create and edit only their own listings.
- Protected backend logic keeps `approval_status = approved` for compatibility.
- Media must stay within cost-control limits.
- The first image becomes the cover image.
- Video should always have a thumbnail.

Public listing eligibility:

```text
listing.status = active
AND listing.availability_status = available
AND listing.removed_from_market_at IS NULL
AND agent.account_status = active
AND category.is_active = true
```

## Location rules

- Locations come from controlled Supabase data.
- Agents should not type arbitrary place names in production flows.
- Region and District are required.
- Ward, Area, and Street are optional.
- Customers see approximate location first.
- Exact address or map pin is disclosed only when the workflow allows it.

## Request rules

- Guest request creation copies `listings.agent_id` into `booking_requests.agent_id`.
- Only that agent should receive the operational notification.
- Admin monitors and intervenes when needed but is not the default handler.
- A request does not reserve or close a listing automatically.
- Multiple visitors can request the same listing.
- The same phone number cannot send another request to the same listing within 10 minutes.
- Request time is stored automatically by Supabase using server time.

## Security rules

- Owner details are private.
- Verification documents are private.
- Customers can report fake listings.
- Agent cannot edit another agent's records.
- Every meaningful moderation or request status change should be auditable.
- Listings should expire automatically after a chosen period.
