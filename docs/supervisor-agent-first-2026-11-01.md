# Supervisor appointment through agent registration

Candidates register through the ordinary agent registration flow. There is no public Supervisor signup option. Super Admin opens **Manage > Agents > Supervisors and territories**, enters the registered agent email, selects an active region/district/ward/area, and saves the appointment.

The Supervisor signs in again and opens **https://kodimali.com/manage/agents?workspace=admin**. Manage mobile automatically selects the admin workspace, restricted to Agents, Notifications and Profile. Supervisors can create agents in their territory and manage only their assigned team. Multiple supervisors may cover the same location; an agent belongs to only one supervisor.

Migration `20261101010000_supervisor_agent_first.sql` enforces agent registration on administrative role assignment itself, including the generic role editor. Only Super Admin can appoint a Supervisor. An agent already assigned to a supervisor must first be unassigned by Super Admin before promotion. Existing appointments and reactivation remain compatible. The existing territory function, team transfer safeguards and audit logging are preserved.

No real account is appointed by this release. Web and Manage mobile explain this flow in English and Swahili. Customer mobile continues using normal agent registration. No APK is generated.

Validation: expanded `scripts/test-supervisor-teams.sql` verifies all existing isolation/territory/revocation cases plus customer rejection, generic role editor rejection, subordinate release requirement, Super Admin authorization, successful agent promotion and reactivation. Manage mobile Supervisor UI tests also check the new agent-first instructions.

Released: Supabase migration applied and trigger verified enabled. Web version `0e12b8fb-0868-40da-a5b4-9c58b92f280c` deployed at 100% traffic on November 1, 2026. Full OpenNext production build and ESLint passed; Manage mobile analysis reported no issues and all three Supervisor UI tests passed. Browser management acceptance checks passed at 320, 375, 390, 430, 768 and 1440 pixels. Live checks with isolated fixture sessions passed for Super Admin and Supervisor at 390/1440 pixels without writing real account data. Evidence is in `tmp/supervisor-agent-first-*.log`. Production had zero configured supervisor territories at verification; appointment still requires Super Admin to choose an actual agent account.
