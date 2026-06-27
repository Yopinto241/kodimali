# KODIMALI Manual Test Checklist

Use this checklist after applying `004_marketplace_activation_categories_feed.sql` and deploying the updated Edge Functions.

- [ ] 1. Public visitor opens Customer App without login.
- [ ] 2. Visitor skips the location banner and still sees the home feed.
- [ ] 3. Visitor allows GPS and receives nearby listings first.
- [ ] 4. Visitor selects Region and District manually and receives matching listings first.
- [ ] 5. Home feed returns about 50% houses when enough houses exist.
- [ ] 6. Admin adds a new category in Manage App.
- [ ] 7. The new category appears automatically in website category navigation and the Manage App Add Asset screen.
- [ ] 8. Active agent posts a listing and it appears publicly immediately.
- [ ] 9. Agent edits and soft-removes only their own listing.
- [ ] 10. Admin edits or removes any listing.
- [ ] 11. Admin deactivates an agent account.
- [ ] 12. All active listings of that agent disappear from the public app and website immediately.
- [ ] 13. Public visitor cannot send a request to a deactivated agent's listing.
- [ ] 14. Admin reactivates the agent and eligible listings return publicly.
- [ ] 15. Guest visitor sends only name and phone number.
- [ ] 16. The correct agent receives the request.
- [ ] 17. Multiple visitors request the same listing and the listing remains active.
- [ ] 18. Inquiry count increases correctly in Agent Dashboard, Admin Dashboard, listing cards, and listing detail.
- [ ] 19. No service-role key, database password, owner data, exact private address, or private GPS pin is exposed in Flutter or the website.
