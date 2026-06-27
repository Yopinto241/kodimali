import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class AgentBookingsTab extends StatefulWidget {
  const AgentBookingsTab({super.key});

  @override
  State<AgentBookingsTab> createState() => _AgentBookingsTabState();
}

class _AgentBookingsTabState extends State<AgentBookingsTab> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;

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
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _updateStatus(String bookingId, BookingStatus status) async {
    await AppScope.of(context).repository.updateBookingStatus(
      bookingId: bookingId,
      status: status,
    );
    await _refresh();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (
        BuildContext context,
        AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
      ) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final List<Map<String, dynamic>> bookings =
            snapshot.data ?? <Map<String, dynamic>>[];
        if (bookings.isEmpty) {
          return const KodimaliEmptyState(
            title: "Hakuna maombi",
            message: "Maombi mapya ya listings zako yataonekana hapa.",
          );
        }

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Customer requests",
              subtitle:
                  "Reply fast from one place, call or open WhatsApp directly, and keep each request moving to the next stage.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${bookings.length} request${bookings.length == 1 ? "" : "s"} loaded",
                  "Pull down to refresh live activity",
                  "Only active agents should manage these requests",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManageSectionTitle(
              title: "Recent activity",
              subtitle:
                  "Each card keeps the customer details, request reference, and stage controls together.",
            ),
            const SizedBox(height: 12),
            ...bookings.map((Map<String, dynamic> booking) {
              final Map<String, dynamic>? listing =
                  booking["listings"] as Map<String, dynamic>?;
              final String title = listing?["title"] as String? ?? "Listing";
              final String phone =
                  booking["customer_phone_number"] as String? ?? "";
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
                                  title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Customer: ${booking["customer_name"] ?? "-"}",
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          KodimaliStatusChip(
                            label: booking["booking_status"] as String? ?? "-",
                            highlight: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ManageMetaWrap(
                        items: <String>[
                          "Phone: ${booking["customer_phone_number"] ?? "-"}",
                          "Reference: ${booking["request_reference"] ?? "-"}",
                          "Requested ${DateFormatters.formatDateTime(booking["created_at"] as String?)}",
                        ],
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final bool stacked = constraints.maxWidth < 700;
                          final List<Widget> actions = <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: phone.isEmpty
                                    ? null
                                    : () => _runAction(() => Launchers.callPhone(phone)),
                                icon: const Icon(Icons.call_outlined),
                                label: const Text("Call"),
                              ),
                            ),
                            const SizedBox(width: 10, height: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: phone.isEmpty
                                    ? null
                                    : () => _runAction(() => Launchers.openWhatsApp(phone)),
                                icon: const Icon(Icons.chat_outlined),
                                label: const Text("WhatsApp"),
                              ),
                            ),
                            const SizedBox(width: 10, height: 10),
                            Expanded(
                              child: PopupMenuButton<BookingStatus>(
                                onSelected: (BookingStatus value) => _updateStatus(
                                  booking["id"] as String,
                                  value,
                                ),
                                itemBuilder: (BuildContext context) => BookingStatus
                                    .values
                                    .where(
                                      (BookingStatus item) =>
                                          item != BookingStatus.agentDelayed,
                                    )
                                    .map(
                                      (BookingStatus item) =>
                                          PopupMenuItem<BookingStatus>(
                                        value: item,
                                        child: Text(item.label),
                                      ),
                                    )
                                    .toList(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    "Update stage",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ];
                          if (stacked) {
                            return Column(children: actions);
                          }
                          return Row(children: actions);
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
