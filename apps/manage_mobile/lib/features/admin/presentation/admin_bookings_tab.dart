import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';
import '../../shared/presentation/booking_workspace_screen.dart';

class AdminBookingsTab extends StatefulWidget {
  const AdminBookingsTab({super.key});

  @override
  State<AdminBookingsTab> createState() => _AdminBookingsTabState();
}

class _AdminBookingsTabState extends State<AdminBookingsTab> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;
  String _filter = "attention";
  final Set<String> _updatingIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return AppScope.of(context).repository.fetchAdminBookings();
  }

  Future<void> _refresh() async {
    final Future<List<Map<String, dynamic>>> next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _updateStatus(
    Map<String, dynamic> booking,
    BookingStatus status,
  ) async {
    final String id = booking["id"] as String;
    if (_updatingIds.contains(id)) {
      return;
    }
    setState(() => _updatingIds.add(id));
    try {
      await AppScope.of(
        context,
      ).repository.updateBookingStatus(bookingId: id, status: status);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _updatingIds.remove(id));
      }
    }
  }

  Future<void> _openWorkspace(Map<String, dynamic> booking) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BookingWorkspaceScreen(
          booking: booking,
          isAdmin: true,
          onChanged: _refresh,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> bookings) {
    return bookings
        .where((Map<String, dynamic> booking) {
          final String status = booking["booking_status"] as String? ?? "new";
          return switch (_filter) {
            "attention" => <String>{"new", "agent_delayed"}.contains(status),
            "viewings" => status == "viewing_scheduled",
            "completed" => status == "completed",
            _ => true,
          };
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text(userFacingError(snapshot.error!)));
            }
            final List<Map<String, dynamic>> allBookings =
                snapshot.data ?? <Map<String, dynamic>>[];
            if (allBookings.isEmpty) {
              return const KodimaliEmptyState(
                title: "Hakuna maombi",
                message: "Maombi yote ya wateja yataonekana hapa.",
              );
            }
            final List<Map<String, dynamic>> bookings = _filtered(allBookings);
            final int attentionCount = allBookings.where((booking) {
              final String status =
                  booking["booking_status"] as String? ?? "new";
              return status == "new" || status == "agent_delayed";
            }).length;
            return ManagePageScrollView(
              onRefresh: _refresh,
              children: <Widget>[
                ManageHeroCard(
                  title: "Booking oversight",
                  subtitle:
                      "See exactly which agent received every request, investigate delayed responses, and audit the request-to-rental workflow.",
                  bottom: ManageMetaWrap(
                    items: <String>[
                      "$attentionCount need attention",
                      "${allBookings.length} total requests",
                      "Ownership comes from the listing assignment",
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: "attention",
                        label: Text("Needs attention"),
                        icon: Icon(Icons.priority_high_rounded),
                      ),
                      ButtonSegment<String>(
                        value: "viewings",
                        label: Text("Viewings"),
                        icon: Icon(Icons.event_outlined),
                      ),
                      ButtonSegment<String>(
                        value: "completed",
                        label: Text("Completed"),
                        icon: Icon(Icons.task_alt_outlined),
                      ),
                      ButtonSegment<String>(
                        value: "all",
                        label: Text("All"),
                        icon: Icon(Icons.list_alt_outlined),
                      ),
                    ],
                    selected: <String>{_filter},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<String> value) {
                      setState(() => _filter = value.first);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (bookings.isEmpty)
                  const ManagePanel(
                    child: Text("No requests match this queue."),
                  )
                else
                  ...bookings.map(_buildBookingCard),
              ],
            );
          },
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final Map<String, dynamic>? listing =
        booking["listings"] as Map<String, dynamic>?;
    final Map<String, dynamic>? agent =
        booking["assigned_agent"] as Map<String, dynamic>?;
    final String status = booking["booking_status"] as String? ?? "new";
    final String agentName =
        agent?["display_name"] as String? ??
        agent?["business_name"] as String? ??
        "Agent record unavailable";
    final bool busy = _updatingIds.contains(booking["id"]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ManagePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        listing?["title"] as String? ?? "Listing",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Customer: ${booking["customer_name"] ?? "-"}",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                KodimaliStatusChip(label: status, highlight: status == "new"),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.assignment_ind_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text("Assigned agent"),
                        Text(
                          agentName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  if ((agent?["account_status"] as String?)?.isNotEmpty == true)
                    KodimaliStatusChip(
                      label: agent!["account_status"] as String,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                Text("Reference ${booking["request_reference"] ?? "-"}"),
                Text(
                  "Sent ${DateFormatters.formatDateTime(booking["created_at"] as String?)}",
                ),
                Text(
                  booking["customer_id"] == null
                      ? "Guest request"
                      : "Customer login linked",
                ),
                if (booking["first_agent_response_at"] != null)
                  Text(
                    "Responded ${DateFormatters.formatDateTime(booking["first_agent_response_at"] as String?)}",
                  ),
              ],
            ),
            if ((booking["request_message"] as String?)?.isNotEmpty ==
                true) ...<Widget>[
              const SizedBox(height: 12),
              Text(booking["request_message"] as String),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => _openWorkspace(booking),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text("Open audit & workflow"),
                ),
                PopupMenuButton<BookingStatus>(
                  enabled: !busy,
                  onSelected: (BookingStatus value) =>
                      _updateStatus(booking, value),
                  itemBuilder: (BuildContext context) => BookingStatus.values
                      .map(
                        (BookingStatus item) => PopupMenuItem<BookingStatus>(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(growable: false),
                  child: const Chip(
                    avatar: Icon(Icons.account_tree_outlined, size: 18),
                    label: Text("Admin stage override"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
