Listing deletion failed because the listing FK uses `ON DELETE SET NULL` to retain booking requests, while `guard_guest_booking_request_update` treated that FK change as an illegal immutable-field edit. The booking-mode trigger could also reinterpret historical requests during detachment.

The migration permits only an actual deleted-parent detachment: the old listing ID must be present, the new ID must be null, the parent must no longer exist, and every other request field except the normal update timestamp must be unchanged. Ordinary unlinking, reassignment and customer/contact edits remain protected. The migration does not delete any listing itself.

“Open audit & workflow” failed because its loader calls `mark_conversation_read`. Administrators may inspect a conversation but cannot act as a customer or assigned agent. The RPC now returns zero for a legitimate administrator auditing a conversation they do not participate in; it changes no read receipts. Missing conversations, anonymous callers and unrelated users remain rejected. Real participants retain normal read-receipt behavior.

The management app source also skips that RPC in admin audit mode. Seven optional workflow readers now await their query results inside the existing error handlers, so asynchronous missing-schema errors can use the intended compatibility fallback. Permission failures still propagate.

Validation:

- Disposable PostgreSQL regression reproduces both original failures using the prior production function bodies, then applies the actual migration. Deletion preserves request fields, payment rows and request conversation/messages; direct unlinking and immutable-field edits remain blocked; audit read state stays unchanged; customer read receipts and active-agent status updates still work. The fixture transaction rolls back.
- Flutter regression covers asynchronous compatibility failures versus permission denials and opens the audit/agent screens with a deleted listing relationship.
- No APK is created. The database fix supports existing app versions; the client changes remain ready for the next app release.

Applied migration `20261030130000_listing_deletion_and_admin_audit.sql` to the linked production project after the database regression passed. Live verification ran in a read-only transaction and confirmed the deployed functions and migration record; its audit RPC assertion changes no read receipts. Management app analysis reports no issues and the complete 19-test suite passes. No production listing was deleted during verification.
