import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _initialized = false;
  int _offset = 0;
  final Set<String> _saving = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = AppScope.of(context).repository.fetchInformationSubmissions();
  }

  Future<void> _reload() async {
    setState(() {
      _future = AppScope.of(
        context,
      ).repository.fetchInformationSubmissions(offset: _offset);
    });
    await _future;
  }

  Future<void> _terms(JsonMap row) async {
    final raw = row['referral_agreements'];
    final agreement = raw is List
        ? (raw.isEmpty
              ? <String, dynamic>{}
              : (raw.first as Map).cast<String, dynamic>())
        : (raw as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    if (agreement['contributor_accepted_at'] != null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const LocalizedUiText('Accepted referral terms'),
          content: Text(agreement['terms'].toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const LocalizedUiText('Close'),
            ),
          ],
        ),
      );
      return;
    }
    String type = agreement['reward_type']?.toString() ?? 'fixed';
    final amount = TextEditingController(
      text:
          (agreement['fixed_amount_tzs'] ?? agreement['percentage_rate'] ?? '')
              .toString(),
    );
    final terms = TextEditingController(
      text: agreement['terms']?.toString() ?? '',
    );
    final form = GlobalKey<FormState>();
    bool busy = false;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const LocalizedUiText('Contributor reward terms'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LocalizedUiText(
                      'The contributor must accept these terms. Finance approves rewards after a completed booking and verified service fee. Deposits are excluded.',
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: const [
                        DropdownMenuItem(
                          value: 'fixed',
                          child: LocalizedUiText('Fixed amount TZS'),
                        ),
                        DropdownMenuItem(
                          value: 'percentage',
                          child: LocalizedUiText(
                            'Percentage of verified service fee',
                          ),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setDialog(() => type = v!),
                    ),
                    TextFormField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Amount or percentage'),
                      ),
                      validator: (v) {
                        final n = num.tryParse(v ?? '');
                        return n == null ||
                                !n.isFinite ||
                                n <= 0 ||
                                (type == 'percentage' && n > 100)
                            ? mobileUi(
                                context,
                                'Enter a valid positive amount or percentage.',
                              )
                            : null;
                      },
                    ),
                    TextFormField(
                      controller: terms,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: mobileUi(
                          context,
                          'Terms for the contributor',
                        ),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 10
                          ? mobileUi(
                              context,
                              'Explain the terms (at least 10 characters).',
                            )
                          : null,
                    ),
                    if (error != null) LocalizedUiText(error!),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(c, false),
              child: const LocalizedUiText('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setDialog(() => busy = true);
                      try {
                        await Supabase.instance.client.rpc(
                          'set_information_referral_terms',
                          params: {
                            'p_submission_id': row['id'],
                            'p_reward_type': type,
                            'p_amount': double.parse(amount.text),
                            'p_terms': terms.text.trim(),
                          },
                        );
                        if (c.mounted) Navigator.pop(c, true);
                      } catch (e) {
                        if (c.mounted) {
                          setDialog(
                            () => error = e is PostgrestException
                                ? e.message
                                : 'Could not save terms.',
                          );
                        }
                      } finally {
                        if (c.mounted) setDialog(() => busy = false);
                      }
                    },
              child: const LocalizedUiText('Save terms'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    terms.dispose();
    if (saved == true && mounted) await _reload();
  }

  Future<void> _details(JsonMap row) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(row['reference'].toString()),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(row['location_description'].toString()),
              const SizedBox(height: 12),
              Text(row['description'].toString()),
              const SizedBox(height: 12),
              Text(
                mobileUiFormat(context, "Source: {0}", [
                  row['information_source'],
                ]),
              ),
              if (row['owner_contact_authorized'] == true) ...[
                const Divider(),
                const LocalizedUiText('Private owner contact'),
                SelectableText(
                  '${row['owner_name'] ?? 'Not provided'}\n${row['owner_phone'] ?? 'Not provided'}',
                ),
              ],
              const Divider(),
              const LocalizedUiText('Internal follow-up history'),
              ...((row['information_follow_ups'] as List?) ?? [])
                  .whereType<Map>()
                  .map(
                    (follow) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${follow['created_at']}\n${follow['summary']}',
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const LocalizedUiText('Close'),
        ),
      ],
    ),
  );

  Future<void> _openWorkflow(JsonMap row) async {
    List<JsonMap> agents, listings;
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        Supabase.instance.client.rpc('get_assignable_verified_agents'),
        Supabase.instance.client
            .from('listings')
            .select('id,title,agent_id')
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(200),
      ]);
      agents = (results[0] as List).cast<JsonMap>();
      listings = (results[1] as List).cast<JsonMap>();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedUiText(
              'Could not load assignment options. Please retry.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    String? agentId = row['assigned_agent_id']?.toString();
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
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              title: Text(
                mobileUiFormat(context, "Simamia {0}", [row['reference']]),
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Hatua'),
                        ),
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
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Reward eligibility'),
                        ),
                        items:
                            <String>[
                                  'pending',
                                  'eligible',
                                  'ineligible',
                                  if (row['eligibility_status'] == 'paid')
                                    'paid',
                                ]
                                .map(
                                  (String value) => DropdownMenuItem<String>(
                                    value: value,
                                    child: LocalizedUiText(value),
                                  ),
                                )
                                .toList(),
                        onChanged: row['eligibility_status'] == 'paid'
                            ? null
                            : (String? value) => setDialogState(
                                () => eligibility = value ?? eligibility,
                              ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: agents.any((a) => a['id'] == agentId)
                            ? agentId
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: mobileUi(
                            context,
                            'Responsible verified agent',
                          ),
                        ),
                        items: agents
                            .map(
                              (a) => DropdownMenuItem<String>(
                                value: a['id'].toString(),
                                child: Text(
                                  (a['business_name'] ?? a['display_name'])
                                      .toString(),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setDialogState(() {
                          agentId = v;
                          listing.clear();
                        }),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey(agentId),
                        initialValue:
                            listings.any(
                              (l) =>
                                  l['id'] == listing.text &&
                                  (agentId == null || l['agent_id'] == agentId),
                            )
                            ? listing.text
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Published listing'),
                        ),
                        items: listings
                            .where(
                              (l) =>
                                  agentId == null || l['agent_id'] == agentId,
                            )
                            .map(
                              (l) => DropdownMenuItem<String>(
                                value: l['id'].toString(),
                                child: Text(l['title'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => listing.text = v ?? ''),
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
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                          );
                          if (date != null) {
                            setDialogState(() => followUp = date);
                          }
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          followUp == null
                              ? mobileUi(context, 'Weka follow-up date')
                              : mobileUiFormat(
                                  context,
                                  "Follow-up: {0}/{1}/{2}",
                                  [
                                    followUp!.day,
                                    followUp!.month,
                                    followUp!.year,
                                  ],
                                ),
                        ),
                      ),
                      if (status == 'closed') ...<Widget>[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: outcome,
                          decoration: InputDecoration(
                            labelText: mobileUi(context, 'Business outcome'),
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
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Follow-up note'),
                          hintText: mobileUi(
                            context,
                            'Uliwasiliana na nani, matokeo na hatua inayofuata.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const LocalizedUiText('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const LocalizedUiText('Save follow-up'),
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
    setState(() {
      _saving.add(id);
    });
    try {
      await AppScope.of(context).repository.updateInformationSubmission(
        id: id,
        status: status,
        followUpNote: note.text,
        nextFollowUpAt: followUp,
        linkedListingId: listing.text,
        eligibilityStatus: eligibility == 'paid' ? null : eligibility,
        assignedAgentId: agentId,
        outcome: outcome,
      );
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedUiText('Follow-up imehifadhiwa.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mobileUiFormat(context, "Haikuweza kuhifadhiwa: {0}", [
                userMessage(context, error),
              ]),
            ),
          ),
        );
      }
    } finally {
      note.dispose();
      listing.dispose();
      if (mounted) {
        setState(() {
          _saving.remove(id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
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
                  child: Text(
                    mobileUiFormat(
                      context,
                      "Taarifa hazikuweza kupakiwa: {0}",
                      [snapshot.error],
                    ),
                  ),
                ),
              ],
            );
          }
          final rows = snapshot.data ?? <JsonMap>[];
          if (rows.isEmpty) {
            return ListView(
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: LocalizedUiText('Hakuna taarifa mpya kwa sasa.'),
                ),
                if (_offset > 0)
                  TextButton(
                    onPressed: () {
                      _offset -= 20;
                      _reload();
                    },
                    child: const LocalizedUiText('Previous page'),
                  ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _offset == 0
                          ? null
                          : () {
                              _offset -= 20;
                              _reload();
                            },
                      child: const LocalizedUiText('Previous'),
                    ),
                    Text(
                      mobileUiFormat(context, "Page {0}", [_offset ~/ 20 + 1]),
                    ),
                    TextButton(
                      onPressed: rows.length < 20
                          ? null
                          : () {
                              _offset += 20;
                              _reload();
                            },
                      child: const LocalizedUiText('Next'),
                    ),
                  ],
                );
              }
              final row = rows[index - 1];
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
                              mobileUiFormat(context, "Reward: {0}", [
                                row['eligibility_status'] ?? 'pending',
                              ]),
                            ),
                          ),
                          if (row['next_follow_up_at'] != null)
                            Chip(
                              label: Text(
                                mobileUiFormat(context, "Follow-up: {0}", [
                                  row['next_follow_up_at'],
                                ]),
                              ),
                            ),
                          if (row['target_completion_at'] != null)
                            Chip(
                              label: Text(
                                mobileUiFormat(context, "Target: {0}", [
                                  row['target_completion_at'],
                                ]),
                              ),
                            ),
                          if (row['outcome'] != null)
                            Chip(
                              label: Text(
                                mobileUiFormat(context, "Outcome: {0}", [
                                  row['outcome'],
                                ]),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mobileUiFormat(context, "Follow-ups: {0}", [
                          (row['information_follow_ups'] as List?)?.length ?? 0,
                        ]),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _details(row),
                            child: const LocalizedUiText('Full information'),
                          ),
                          TextButton(
                            onPressed: () => _terms(row),
                            child: const LocalizedUiText('Reward terms'),
                          ),
                        ],
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
                                ? mobileUi(context, 'Saving...')
                                : mobileUi(context, 'Manage follow-up'),
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
