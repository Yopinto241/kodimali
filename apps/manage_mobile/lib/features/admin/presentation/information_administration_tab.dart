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
  final Set<String> _saving = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(context).repository.fetchInformationSubmissions();
  }

  void _reload() => setState(
    () =>
        _future = AppScope.of(context).repository.fetchInformationSubmissions(),
  );

  Future<void> _openWorkflow(JsonMap row) async {
    const List<String> states = <String>[
      'submitted',
      'triage',
      'duplicate_review',
      'contacting_owner',
      'field_verification',
      'verified',
      'publication_review',
      'published',
      'ineligible',
      'closed',
    ];
    const List<String> outcomes = <String>[
      'rented',
      'sold',
      'owner_declined',
      'duplicate',
      'not_available',
      'invalid',
      'cancelled',
    ];
    String status = row['status']?.toString() ?? 'submitted';
    String eligibility = row['eligibility_status']?.toString() ?? 'pending';
    String? outcome = row['outcome']?.toString();
    DateTime? followUp = DateTime.tryParse(
      row['next_follow_up_at']?.toString() ?? '',
    );
    final TextEditingController note = TextEditingController();
    final TextEditingController listing = TextEditingController(
      text: row['linked_listing_id']?.toString() ?? '',
    );
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
          title: Text('Simamia ${row['reference']}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Hatua'),
                    items: states
                        .map(
                          (String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value.replaceAll('_', ' ')),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) =>
                        setDialogState(() => status = value ?? status),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: eligibility,
                    decoration: const InputDecoration(
                      labelText: 'Reward eligibility',
                    ),
                    items:
                        const <String>[
                              'pending',
                              'eligible',
                              'ineligible',
                              'paid',
                            ]
                            .map(
                              (String value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (String? value) => setDialogState(
                      () => eligibility = value ?? eligibility,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: listing,
                    decoration: const InputDecoration(
                      labelText: 'Linked listing ID',
                      helperText: 'Required before marking the lead published.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime? date = await showDatePicker(
                        context: context,
                        initialDate:
                            followUp ??
                            DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (date != null) {
                        setDialogState(() => followUp = date);
                      }
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      followUp == null
                          ? 'Weka follow-up date'
                          : 'Follow-up: ${followUp!.day}/${followUp!.month}/${followUp!.year}',
                    ),
                  ),
                  if (status == 'closed') ...<Widget>[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: outcome,
                      decoration: const InputDecoration(
                        labelText: 'Business outcome',
                      ),
                      items: outcomes
                          .map(
                            (String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value.replaceAll('_', ' ')),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) =>
                          setDialogState(() => outcome = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Follow-up note',
                      hintText:
                          'Uliwasiliana na nani, matokeo na hatua inayofuata.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save follow-up'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !mounted) {
      note.dispose();
      listing.dispose();
      return;
    }
    final String id = row['id'].toString();
    setState(() => _saving.add(id));
    try {
      await AppScope.of(context).repository.updateInformationSubmission(
        id: id,
        status: status,
        followUpNote: note.text,
        nextFollowUpAt: followUp,
        linkedListingId: listing.text,
        eligibilityStatus: eligibility,
        outcome: outcome,
      );
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Follow-up imehifadhiwa.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Haikuweza kuhifadhiwa: $error')),
        );
      }
    } finally {
      note.dispose();
      listing.dispose();
      if (mounted) setState(() => _saving.remove(id));
    }
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Chip(
                            label: Text(
                              'Reward: ${row['eligibility_status'] ?? 'pending'}',
                            ),
                          ),
                          if (row['next_follow_up_at'] != null)
                            Chip(
                              label: Text(
                                'Follow-up: ${row['next_follow_up_at']}',
                              ),
                            ),
                          if (row['target_completion_at'] != null)
                            Chip(
                              label: Text(
                                'Target: ${row['target_completion_at']}',
                              ),
                            ),
                          if (row['outcome'] != null)
                            Chip(label: Text('Outcome: ${row['outcome']}')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Follow-ups: ${(row['information_follow_ups'] as List?)?.length ?? 0}',
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: _saving.contains(row['id'].toString())
                              ? null
                              : () => _openWorkflow(row),
                          icon: const Icon(Icons.manage_history_rounded),
                          label: Text(
                            _saving.contains(row['id'].toString())
                                ? 'Saving...'
                                : 'Manage follow-up',
                          ),
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
