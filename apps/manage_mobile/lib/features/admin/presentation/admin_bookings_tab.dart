import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class AdminBookingsTab extends StatefulWidget {
  const AdminBookingsTab({super.key});

  @override
  State<AdminBookingsTab> createState() => _AdminBookingsTabState();
}

class _AdminBookingsTabState extends State<AdminBookingsTab> {
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
    return AppScope.of(context).repository.fetchAdminBookings();
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
            message: "Maombi yote ya wateja yataonekana hapa.",
          );
        }

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Booking oversight",
              subtitle:
                  "Review cross-platform requests, verify ownership, and keep the workflow moving from one place.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${bookings.length} request${bookings.length == 1 ? "" : "s"} loaded",
                  "Admins can manage all assigned requests",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ...bookings.map((Map<String, dynamic> booking) {
              final Map<String, dynamic>? listing =
                  booking["listings"] as Map<String, dynamic>?;
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
                                const SizedBox(height: 6),
                                Text("Customer: ${booking["customer_name"] ?? "-"}"),
                              ],
                            ),
                          ),
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PopupMenuButton<BookingStatus>(
                          onSelected: (BookingStatus value) =>
                              _updateStatus(booking["id"] as String, value),
                          itemBuilder: (BuildContext context) => BookingStatus.values
                              .map(
                                (BookingStatus item) => PopupMenuItem<BookingStatus>(
                                  value: item,
                                  child: Text(item.label),
                                ),
                              )
                              .toList(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Text(
                              "Update request stage",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
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
