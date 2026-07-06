import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

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

bool _looksLikeEmail(String value) {
  return value.contains("@");
}

String _normalizedBookingPhone(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty || _looksLikeEmail(trimmed)) {
    return "";
  }
  return trimmed;
}

String _normalizedBookingEmail(String phoneValue, String emailValue) {
  final String trimmedEmail = emailValue.trim();
  if (trimmedEmail.isNotEmpty) {
    return trimmedEmail;
  }
  final String trimmedPhone = phoneValue.trim();
  if (_looksLikeEmail(trimmedPhone)) {
    return trimmedPhone;
  }
  return "";
}

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
    await AppScope.of(
      context,
    ).repository.updateBookingStatus(bookingId: bookingId, status: status);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
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
              final String rawPhone =
                  booking["customer_phone_number"] as String? ?? "";
              final String rawEmail = booking["customer_email"] as String? ?? "";
              final String phone = _normalizedBookingPhone(rawPhone);
              final String email = _normalizedBookingEmail(rawPhone, rawEmail);
              final List<dynamic> requestedServices =
                  booking["requested_service_codes"] as List<dynamic>? ??
                  <dynamic>[];
              final String requestedDates =
                  booking["requested_start_at"] != null &&
                      booking["requested_end_at"] != null
                  ? "${DateFormatters.formatDateTime(booking['requested_start_at'] as String?)} to ${DateFormatters.formatDateTime(booking['requested_end_at'] as String?)}"
                  : "";
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
                                Text(
                                  "Customer: ${booking["customer_name"] ?? "-"}",
                                ),
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
                          "Phone: ${phone.isEmpty ? "-" : phone}",
                          "Email: ${email.isEmpty ? "-" : email}",
                          "Reference: ${booking["request_reference"] ?? "-"}",
                          "Requested ${DateFormatters.formatDateTime(booking["created_at"] as String?)}",
                          if (requestedDates.isNotEmpty)
                            "Stay: $requestedDates",
                          if (booking["guest_count"] != null)
                            "Guests: ${booking["guest_count"]}",
                          if (requestedServices.isNotEmpty)
                            "Services: ${requestedServices.map(_formatRequestedService).where((String item) => item.isNotEmpty).join(", ")}",
                        ],
                      ),
                      if ((booking["request_message"] as String?)
                              ?.trim()
                              .isNotEmpty ==
                          true) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          booking["request_message"] as String,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PopupMenuButton<BookingStatus>(
                          onSelected: (BookingStatus value) =>
                              _updateStatus(booking["id"] as String, value),
                          itemBuilder: (BuildContext context) => BookingStatus
                              .values
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
