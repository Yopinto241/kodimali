import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';
import 'booking_workspace_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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
    return AppScope.of(context).repository.fetchNotifications();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _markAsRead(String id) async {
    await AppScope.of(context).repository.markNotificationRead(id);
    await _refresh();
  }

  String? _bookingIdFor(Map<String, dynamic> item) {
    final String? direct = item["booking_request_id"] as String?;
    if (direct?.isNotEmpty == true) {
      return direct;
    }
    final Map<String, dynamic>? payload = (item["payload"] as Map?)
        ?.cast<String, dynamic>();
    return payload?["bookingRequestId"] as String? ??
        payload?["booking_request_id"] as String?;
  }

  Future<void> _openRequest(Map<String, dynamic> item) async {
    final String? bookingId = _bookingIdFor(item);
    if (bookingId == null) {
      return;
    }
    try {
      if (item["read_at"] == null) {
        await AppScope.of(
          context,
        ).repository.markNotificationRead(item["id"] as String);
      }
      if (!mounted) {
        return;
      }
      final bool isAdmin =
          AppScope.of(context).controller.highestRole == AppRole.admin;
      final Map<String, dynamic>? booking = await AppScope.of(
        context,
      ).repository.fetchBookingById(bookingId, isAdmin: isAdmin);
      if (!mounted) {
        return;
      }
      if (booking == null) {
        throw StateError("This request is no longer available.");
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => BookingWorkspaceScreen(
            booking: booking,
            isAdmin: isAdmin,
            onChanged: _refresh,
          ),
        ),
      );
      if (mounted) {
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
      }
    }
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
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            final List<Map<String, dynamic>> items =
                snapshot.data ?? <Map<String, dynamic>>[];
            if (items.isEmpty) {
              return const KodimaliEmptyState(
                title: "Hakuna taarifa",
                message: "Taarifa za maombi na updates zitaonekana hapa.",
              );
            }

            final int unreadCount = items.where((Map<String, dynamic> item) {
              return item["read_at"] == null;
            }).length;

            return ManagePageScrollView(
              onRefresh: _refresh,
              children: <Widget>[
                ManageHeroCard(
                  title: "Notifications",
                  subtitle:
                      "Track unread updates, moderation notices, and request activity in one clean feed.",
                  bottom: ManageMetaWrap(
                    items: <String>[
                      "$unreadCount unread",
                      "${items.length} total update${items.length == 1 ? "" : "s"}",
                      "Pull down to refresh",
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ...items.map((Map<String, dynamic> item) {
                  final bool unread = item["read_at"] == null;
                  final String? bookingId = _bookingIdFor(item);
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
                                child: Text(
                                  item["title"] as String? ?? "-",
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              if (unread)
                                const KodimaliStatusChip(
                                  label: "Unread",
                                  highlight: true,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(item["body"] as String? ?? "-"),
                          const SizedBox(height: 12),
                          ManageMetaWrap(
                            items: <String>[
                              DateFormatters.formatDateTime(
                                item["created_at"] as String?,
                              ),
                              unread
                                  ? "Needs your attention"
                                  : "Already reviewed",
                            ],
                          ),
                          if (unread || bookingId != null) ...<Widget>[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: <Widget>[
                                if (bookingId != null)
                                  FilledButton.tonalIcon(
                                    onPressed: () => _openRequest(item),
                                    icon: const Icon(Icons.open_in_new_rounded),
                                    label: const Text("Open request"),
                                  ),
                                if (unread)
                                  OutlinedButton(
                                    onPressed: () =>
                                        _markAsRead(item["id"] as String),
                                    child: const Text("Mark as read"),
                                  ),
                              ],
                            ),
                          ],
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
