import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';
import 'package:manage_mobile/core/router/workspace_location.dart';
import 'package:manage_mobile/features/admin/presentation/admin_workspace_access.dart';

void main() {
  test(
    'Supervisor manages agents without finance or staff role assignment',
    () {
      const access = AdminWorkspaceAccess({
        'agents.manage',
        'supervisor.scoped',
      });
      expect(access.allowsDestination('agents'), isTrue);
      expect(access.allowsDestination('agent-recommendations'), isFalse);
      for (final destination in [
        'users',
        'listings',
        'requests',
        'growth',
        'locations',
      ]) {
        expect(access.allowsDestination(destination), isFalse);
      }
      expect(access.roles, isFalse);
      expect(access.payments, isFalse);
    },
  );
  test(
    'Events and blocked agents always reach their specialized workspace',
    () {
      expect(
        workspaceLocation(
          AppRole.agent,
          agentBlocked: false,
          eventsAgent: true,
        ),
        '/events-provider',
      );
      expect(
        workspaceLocation(AppRole.agent, agentBlocked: true, eventsAgent: true),
        '/agent-account-status',
      );
      expect(
        workspaceLocation(
          AppRole.agent,
          agentBlocked: false,
          eventsAgent: false,
        ),
        '/agent',
      );
      expect(
        workspaceLocation(AppRole.owner, agentBlocked: true, eventsAgent: true),
        '/owner',
      );
      expect(
        workspaceLocation(
          AppRole.customer,
          agentBlocked: false,
          eventsAgent: false,
        ),
        '/access-denied',
      );
    },
  );

  test(
    'Analyst can read finance without finance or role-management actions',
    () {
      const access = AdminWorkspaceAccess({
        'dashboard.view',
        'analytics.view',
        'payments.view',
      });
      expect(access.growth, isTrue);
      expect(access.financialReports, isTrue);
      expect(
        access.payments ||
            access.refunds ||
            access.wallets ||
            access.roles ||
            access.boosts ||
            access.risks,
        isFalse,
      );
    },
  );

  test('Marketing and moderation cannot load finance or role directories', () {
    for (final permissions in [
      {'promotions.manage', 'boosts.manage', 'analytics.view'},
      {'listings.manage', 'reports.manage', 'risk.manage'},
    ]) {
      final access = AdminWorkspaceAccess(permissions);
      expect(access.growth, isTrue);
      expect(
        access.financialReports || access.wallets || access.roles,
        isFalse,
      );
    }
  });

  test('Coordinator cannot open unrelated growth operations', () {
    const access = AdminWorkspaceAccess({
      'events.manage',
      'events.quotes',
      'events.escalations',
      'bookings.manage',
    });
    expect(access.growth, isFalse);
    expect(access.allows('events.manage'), isTrue);
  });

  test('Finance and Super Admin retain their authorized operations', () {
    const finance = AdminWorkspaceAccess({
      'payments.manage',
      'refunds.manage',
      'wallets.manage',
      'subscriptions.manage',
    });
    expect(
      finance.financialReports &&
          finance.payments &&
          finance.refunds &&
          finance.wallets,
      isTrue,
    );
    expect(finance.roles || finance.risks || finance.boosts, isFalse);
    const superAdmin = AdminWorkspaceAccess({'*'});
    expect(
      superAdmin.roles &&
          superAdmin.payments &&
          superAdmin.risks &&
          superAdmin.boosts,
      isTrue,
    );
  });
}
