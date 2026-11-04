import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgentRecommendationsScreen extends StatefulWidget {
  const AgentRecommendationsScreen({super.key, this.admin = false});
  final bool admin;
  @override
  State<AgentRecommendationsScreen> createState() =>
      _AgentRecommendationsScreenState();
}

class _AgentRecommendationsScreenState
    extends State<AgentRecommendationsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      (await Supabase.instance.client
              .from('owner_agent_recommendations')
              .select(
                'id,suggested_name,suggested_phone,notes,status,registered_agent_id,review_notes',
              )
              .order('created_at', ascending: false)
              .limit(100))
          .cast<Map<String, dynamic>>();
  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _recommend() async {
    final name = TextEditingController(),
        phone = TextEditingController(),
        notes = TextEditingController();
    final form = GlobalKey<FormState>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const LocalizedUiText('Recommend your own agent'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Agent name'),
                ),
                validator: (v) => (v?.trim().length ?? 0) < 2
                    ? mobileUi(context, 'Enter the agent name.')
                    : null,
              ),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Agent phone'),
                ),
                validator: (v) => (v?.trim().length ?? 0) < 8
                    ? mobileUi(context, 'Enter a valid phone.')
                    : null,
              ),
              TextFormField(
                controller: notes,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Recommendation note'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const LocalizedUiText('Submit recommendation'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _perform(
        () => Supabase.instance.client.rpc(
          'recommend_owner_agent',
          params: {
            'p_name': name.text.trim(),
            'p_phone': phone.text.trim(),
            'p_notes': notes.text.trim(),
          },
        ),
      );
    }
    name.dispose();
    phone.dispose();
    notes.dispose();
  }

  Future<void> _review(Map<String, dynamic> item) async {
    List<Map<String, dynamic>> agents;
    try {
      agents =
          (await Supabase.instance.client.rpc('get_assignable_verified_agents')
                  as List)
              .cast<Map<String, dynamic>>();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedUiText('Could not load verified agents.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    String status = item['status'] == 'submitted'
        ? 'contacting'
        : item['status'].toString();
    String? agentId = item['registered_agent_id']?.toString();
    final note = TextEditingController(
      text: item['review_notes']?.toString() ?? '',
    );
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(item['suggested_name'].toString()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item['suggested_phone'].toString()),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  items: ['contacting', 'accepted', 'rejected']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: LocalizedUiText(value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => status = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: agents.any((a) => a['id'] == agentId)
                      ? agentId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Linked verified agent'),
                  ),
                  items: agents
                      .map(
                        (a) => DropdownMenuItem(
                          value: a['id'].toString(),
                          child: Text(
                            (a['business_name'] ?? a['display_name'])
                                .toString(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => agentId = v),
                ),
                TextField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Review note for owner'),
                  ),
                ),
                const LocalizedUiText(
                  'Accepting a recommendation does not activate an unverified account or grant asset authority. The owner authorizes a verified agent separately.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const LocalizedUiText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const LocalizedUiText('Save review'),
            ),
          ],
        ),
      ),
    );
    if (yes == true) {
      await _perform(
        () => Supabase.instance.client.rpc(
          'review_owner_agent_recommendation',
          params: {
            'p_id': item['id'],
            'p_status': status,
            'p_agent_id': agentId,
            'p_notes': note.text.trim(),
          },
        ),
      );
    }
    note.dispose();
  }

  Future<void> _perform(Future<dynamic> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.admin
            ? mobileUi(context, 'Owner-recommended agents')
            : mobileUi(context, 'My agent recommendations'),
      ),
    ),
    floatingActionButton: widget.admin
        ? null
        : FloatingActionButton.extended(
            onPressed: _busy ? null : _recommend,
            icon: const Icon(Icons.person_add_outlined),
            label: const LocalizedUiText('Recommend agent'),
          ),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: LocalizedUiText('Could not load recommendations.'),
                ),
                TextButton(
                  onPressed: _reload,
                  child: const LocalizedUiText('Retry'),
                ),
              ],
            );
          }
          final items = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: LocalizedUiText(
                    'Owners may recommend a trusted person, even before registration. Agent Manager reviews and verifies them. Owners grant asset access separately after verification.',
                  ),
                ),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: LocalizedUiText('No recommendations yet.'),
                ),
              ...items.map(
                (item) => Card(
                  child: ListTile(
                    title: Text(item['suggested_name'].toString()),
                    subtitle: Text(
                      '${item['suggested_phone']} · ${item['status']}\n${item['review_notes'] ?? item['notes'] ?? ''}',
                    ),
                    trailing: widget.admin
                        ? IconButton(
                            onPressed: _busy ? null : () => _review(item),
                            icon: const Icon(Icons.fact_check_outlined),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
