import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';
import '../../shared/presentation/booking_workspace_screen.dart';

String _formatRequestedService(dynamic value) {
  final String text = value?.toString() ?? "";
  if (text.isEmpty) {
    return "";
  }
  return text
      .replaceAll("_available", "")
      .replaceAll("_", " ")
      .split(" ")
      .where((String part) => part.isNotEmpty)
      .map((String part) => "${part[0].toUpperCase()}${part.substring(1)}")
      .join(" ");
}

String _bookingPhone(dynamic value) {
  final String phone = value?.toString().trim() ?? "";
  return phone.contains("@") ? "" : phone;
}

class AgentBookingsTab extends StatefulWidget {
  const AgentBookingsTab({super.key});

  @override
  State<AgentBookingsTab> createState() => _AgentBookingsTabState();
}

class _AgentBookingsTabState extends State<AgentBookingsTab> {
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
    return AppScope.of(context).repository.fetchAgentBookings();
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
      booking["booking_status"] = status.storageValue;
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

  Future<void> _runExternal(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
      }
    }
  }

  Future<void> _openWorkspace(Map<String, dynamic> booking) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            BookingWorkspaceScreen(booking: booking, onChanged: _refresh),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  List<Map<String, dynamic>> _filteredBookings(
    List<Map<String, dynamic>> bookings,
  ) {
    const Set<String> terminal = <String>{
      "completed",
      "cancelled",
      "rejected",
      "no_response",
    };
    final List<Map<String, dynamic>> filtered = bookings
        .where((booking) {
          final String status = booking["booking_status"] as String? ?? "new";
          return switch (_filter) {
            "attention" => <String>{"new", "agent_delayed"}.contains(status),
            "active" => !terminal.contains(status),
            "viewings" => status == "viewing_scheduled",
            "completed" => status == "completed",
            _ => true,
          };
        })
        .toList(growable: false);
    filtered.sort((Map<String, dynamic> left, Map<String, dynamic> right) {
      final String leftStatus = left["booking_status"] as String? ?? "";
      final String rightStatus = right["booking_status"] as String? ?? "";
      final int leftPriority = leftStatus == "new" ? 0 : 1;
      final int rightPriority = rightStatus == "new" ? 0 : 1;
      if (leftPriority != rightPriority) {
        return leftPriority.compareTo(rightPriority);
      }
      return (right["created_at"]?.toString() ?? "").compareTo(
        left["created_at"]?.toString() ?? "",
      );
    });
    return filtered;
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
                message: "Maombi mapya ya listings zako yataonekana hapa.",
              );
            }
            final List<Map<String, dynamic>> bookings = _filteredBookings(
              allBookings,
            );
            final int attentionCount = allBookings.where((booking) {
              final String status =
                  booking["booking_status"] as String? ?? "new";
              return status == "new" || status == "agent_delayed";
            }).length;

            return ManagePageScrollView(
              onRefresh: _refresh,
              children: <Widget>[
                ManageHeroCard(
                  title: "Customer request queue",
                  subtitle:
                      "Every request below is assigned to your agent account. Accept, contact, schedule a viewing, chat with signed-in customers, and record completion here.",
                  bottom: ManageMetaWrap(
                    items: <String>[
                      "$attentionCount need attention",
                      "${allBookings.length} total requests",
                      "New requests are shown first",
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
                        value: "active",
                        label: Text("In progress"),
                        icon: Icon(Icons.pending_actions_outlined),
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
    final String status = booking["booking_status"] as String? ?? "new";
    final String phone = _bookingPhone(booking["customer_phone_number"]);
    final List<dynamic> requestedServices =
        booking["requested_service_codes"] as List<dynamic>? ?? <dynamic>[];
    final bool hasLinkedCustomer = booking["customer_id"] != null;
    final bool busy = _updatingIds.contains(booking["id"]);
    final bool terminal = <String>{
      "completed",
      "cancelled",
      "rejected",
      "no_response",
    }.contains(status);
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
                        "${booking["customer_name"] ?? "Customer"} • ${booking["request_reference"] ?? "No reference"}",
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                const Chip(
                  avatar: Icon(Icons.assignment_ind_outlined, size: 18),
                  label: Text("Assigned to you"),
                ),
                Chip(
                  avatar: Icon(
                    hasLinkedCustomer
                        ? Icons.chat_outlined
                        : Icons.phone_outlined,
                    size: 18,
                  ),
                  label: Text(
                    hasLinkedCustomer ? "In-app chat ready" : "Guest contact",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              booking["request_message"] as String? ??
                  "Customer did not add a message.",
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                Text(
                  "Sent ${DateFormatters.formatDateTime(booking["created_at"] as String?)}",
                ),
                if (phone.isNotEmpty) Text("Phone $phone"),
                if (requestedServices.isNotEmpty)
                  Text(
                    "Services ${requestedServices.map(_formatRequestedService).join(", ")}",
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: busy || terminal
                      ? null
                      : () => _updateStatus(
                          booking,
                          BookingStatus.checkingAvailability,
                        ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text("Accept"),
                ),
                OutlinedButton.icon(
                  onPressed: phone.isEmpty
                      ? null
                      : () => _runExternal(() => Launchers.callPhone(phone)),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text("Call"),
                ),
                OutlinedButton.icon(
                  onPressed: phone.isEmpty
                      ? null
                      : () => _runExternal(() => Launchers.openWhatsApp(phone)),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text("WhatsApp"),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _openWorkspace(booking),
                  icon: Icon(
                    hasLinkedCustomer
                        ? Icons.forum_outlined
                        : Icons.pending_actions_outlined,
                  ),
                  label: Text(
                    hasLinkedCustomer
                        ? "Open chat & workflow"
                        : "Open workflow",
                  ),
                ),
                TextButton.icon(
                  onPressed: busy || terminal
                      ? null
                      : () => _updateStatus(booking, BookingStatus.rejected),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text("Reject"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
