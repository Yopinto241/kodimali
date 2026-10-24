import 'package:flutter/material.dart';

import '../../../core/data/manage_repository.dart';
import '../../../core/widgets/app_scope.dart';

class InformationAdministrationTab extends StatefulWidget {
  const InformationAdministrationTab({super.key});

  @override
  State<InformationAdministrationTab> createState() =>
      _InformationAdministrationTabState();
}

class _InformationAdministrationTabState
    extends State<InformationAdministrationTab> {
  late Future<List<JsonMap>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(context).repository.fetchInformationSubmissions();
  }

  void _reload() => setState(
    () =>
        _future = AppScope.of(context).repository.fetchInformationSubmissions(),
  );

  Future<void> _advance(JsonMap row) async {
    const List<String> states = <String>[
      'submitted',
      'triage',
      'contacting_owner',
      'field_verification',
      'verified',
      'publication_review',
      'published',
    ];
    final String current = row['status']?.toString() ?? 'submitted';
    final int index = states.indexOf(current);
    if (index < 0 || index == states.length - 1) return;
    await AppScope.of(context).repository.updateInformationSubmission(
      id: row['id'].toString(),
      status: states[index + 1],
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<JsonMap>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Taarifa hazikuweza kupakiwa: ${snapshot.error}'),
                ),
              ],
            );
          }
          final rows = snapshot.data ?? <JsonMap>[];
          if (rows.isEmpty) {
            return ListView(
              children: const <Widget>[
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Hakuna taarifa mpya kwa sasa.'),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${row['reference']} · ${row['category']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Chip(
                            label: Text(
                              row['status']?.toString() ?? 'submitted',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(row['location_description']?.toString() ?? ''),
                      const SizedBox(height: 6),
                      Text(
                        row['description']?.toString() ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _advance(row),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Hatua inayofuata'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
