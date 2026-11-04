import 'package:flutter/material.dart';
import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/app_scope.dart';
import '../../agent/presentation/listing_detail_screen.dart';
import '../../agent/presentation/agent_business_center_screen.dart';
import '../../admin/presentation/admin_growth_operations_screen.dart';
import '../../admin/presentation/admin_workspace_access.dart';
import '../../events/presentation/event_coordinator_screen.dart';
import '../../events/presentation/events_provider_workspace_screen.dart';
import 'booking_workspace_screen.dart';
import 'notifications_screen.dart';

class NotificationDestinationScreen extends StatefulWidget {
  const NotificationDestinationScreen({
    super.key,
    required this.kind,
    required this.id,
  });
  final String kind, id;
  @override
  State<NotificationDestinationScreen> createState() => _DestinationState();
}

class _DestinationState extends State<NotificationDestinationScreen> {
  late Future<Widget> _destination = _resolve().timeout(
    const Duration(seconds: 20),
  );
  Future<Widget> _resolve() async {
    final db = Supabase.instance.client;
    if (db.auth.currentUser == null) return const NotificationsScreen();
    final permissions = await AppScope.of(
      context,
    ).repository.fetchMyAdminPermissions();
    bool allows(String permission) =>
        permissions.contains('*') || permissions.contains(permission);
    final isAdmin = allows('bookings.manage');
    if (widget.kind == 'booking' && widget.id != 'overview') {
      final row = await db
          .from('booking_requests')
          .select()
          .eq('id', widget.id)
          .maybeSingle();
      if (row != null) {
        return BookingWorkspaceScreen(booking: row, isAdmin: isAdmin);
      }
    }
    if (widget.kind == 'listing' && widget.id != 'overview') {
      final row = await db
          .from('listings')
          .select('id,agent_id,agents!inner(profile_id)')
          .eq('id', widget.id)
          .maybeSingle();
      final relation = row?['agents'];
      if (row != null &&
          (allows('listings.manage') ||
              relation is Map &&
                  relation['profile_id'] == db.auth.currentUser!.id)) {
        return ListingDetailScreen(
          listingId: widget.id,
          adminMode: allows('listings.manage'),
        );
      }
    }
    if (widget.kind == 'payments') {
      if (allows('payments.manage')) {
        return AdminGrowthOperationsScreen(
          access: AdminWorkspaceAccess(permissions),
        );
      }
      final agent = await db
          .from('agents')
          .select('id')
          .eq('profile_id', db.auth.currentUser!.id)
          .maybeSingle();
      if (agent != null) return const AgentBusinessCenterScreen();
    }
    if (widget.kind == 'events') {
      if (allows('events.manage')) return const EventCoordinatorScreen();
      return const EventsProviderWorkspaceScreen();
    }
    return const NotificationsScreen();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: _destination,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const LocalizedUiText('Notifications')),
          body: RecoverableError(
            error: snapshot.error,
            onRetry: () => setState(() {
              _destination = _resolve().timeout(const Duration(seconds: 20));
            }),
          ),
        );
      }
      return snapshot.data ??
          const Scaffold(body: Center(child: CircularProgressIndicator()));
    },
  );
}
