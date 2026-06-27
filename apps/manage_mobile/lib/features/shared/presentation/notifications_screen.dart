import 'package:flutter/material.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

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
                          DateFormatters.formatDateTime(item["created_at"] as String?),
                          unread ? "Needs your attention" : "Already reviewed",
                        ],
                      ),
                      if (unread) ...<Widget>[
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(
                            onPressed: () => _markAsRead(item["id"] as String),
                            child: const Text("Mark as read"),
                          ),
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
