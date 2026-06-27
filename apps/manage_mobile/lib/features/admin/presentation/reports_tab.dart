import 'package:flutter/material.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
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
    return AppScope.of(context).repository.fetchReports();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
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
        final List<Map<String, dynamic>> reports =
            snapshot.data ?? <Map<String, dynamic>>[];
        if (reports.isEmpty) {
          return const KodimaliEmptyState(
            title: "Hakuna reports",
            message: "Complaints na report za listings zitaonekana hapa.",
          );
        }

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Reports queue",
              subtitle:
                  "Monitor complaints and reported listings with a cleaner review feed.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${reports.length} report${reports.length == 1 ? "" : "s"}",
                  "Pull down to refresh moderation data",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ...reports.map((Map<String, dynamic> report) {
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
                              report["report_reason"] as String? ?? "-",
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          KodimaliStatusChip(label: report["status"] as String? ?? "-"),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(report["details"] as String? ?? "-"),
                      const SizedBox(height: 12),
                      ManageMetaWrap(
                        items: <String>[
                          DateFormatters.formatDateTime(report["created_at"] as String?),
                        ],
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
