import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/manage_localization.dart';

class EventCoordinatorScreen extends StatefulWidget {
  const EventCoordinatorScreen({super.key});
  @override
  State<EventCoordinatorScreen> createState() => _EventCoordinatorScreenState();
}

class _EventCoordinatorScreenState extends State<EventCoordinatorScreen> {
  bool loading = true;
  List<Map<String, dynamic>> plans = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> equipment = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> providers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> escalations = <Map<String, dynamic>>[];
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final db = Supabase.instance.client;
      final values = await Future.wait<dynamic>(<Future<dynamic>>[
        db
            .from('event_plans')
            .select(
              '*, event_types(name_sw,name_en), event_plan_items(id,item_kind,requested_quantity,status,equipment_id,offering_id,event_equipment_items(name),event_service_offerings(title))',
            )
            .order('created_at'),
        db
            .from('event_equipment_items')
            .select('id,name,total_quantity,verification_status,owner_id')
            .order('created_at'),
        db
            .from('event_service_profiles')
            .select(
              'id,display_name,provider_kind,verification_status,profile_id',
            )
            .order('created_at'),
        db
            .from('event_emergency_escalations')
            .select('*, event_plans(reference,title)')
            .order('created_at'),
      ]);
      plans = (values[0] as List).cast<Map<String, dynamic>>();
      equipment = (values[1] as List).cast<Map<String, dynamic>>();
      providers = (values[2] as List).cast<Map<String, dynamic>>();
      escalations = (values[3] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            sw ? 'Uratibu wa Sherehe na Matukio' : 'Events coordination',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            sw
                ? 'Thibitisha providers, fuatilia confirmations, andaa quotation na shughulikia dharura.'
                : 'Verify providers, track confirmations, prepare quotations and handle emergencies.',
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          _heading(sw ? 'Mipango ya wateja' : 'Customer event plans'),
          if (plans.isEmpty)
            Text(sw ? 'Hakuna mipango.' : 'No event plans.')
          else
            ...plans.map((plan) {
              final items = (plan['event_plan_items'] as List? ?? <dynamic>[])
                  .cast<Map<String, dynamic>>();
              final confirmed = items
                  .where((item) => item['status'] == 'provider_confirmed')
                  .length;
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
                              (plan['title'] ?? plan['reference']).toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              plan['status'].toString().replaceAll('_', ' '),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${plan['reference']} · $confirmed/${items.length} ${sw ? 'wamethibitisha' : 'confirmed'}',
                      ),
                      const SizedBox(height: 10),
                      ...items.map(
                        (item) => Text(
                          '• ${(item['event_equipment_items'] as Map?)?['name'] ?? (item['event_service_offerings'] as Map?)?['title'] ?? item['item_kind']} — ${item['status']}',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          FilledButton(
                            onPressed: items.isEmpty
                                ? null
                                : () => _prepareQuote(plan, items),
                            child: Text(
                              sw ? 'Andaa quotation' : 'Prepare quotation',
                            ),
                          ),
                          if (plan['status'] == 'agreement_pending')
                            OutlinedButton(
                              onPressed: () => _sendAgreement(plan),
                              child: Text(
                                sw ? 'Tuma makubaliano' : 'Send agreement',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          _heading(sw ? 'Uhakiki wa vifaa' : 'Equipment verification'),
          ...equipment.map(
            (item) => Card(
              child: ListTile(
                title: Text(item['name'].toString()),
                subtitle: Text(
                  '${item['total_quantity']} · ${item['verification_status']}',
                ),
                trailing: item['verification_status'] == 'pending'
                    ? FilledButton(
                        onPressed: () => _verify(
                          'event_equipment_items',
                          item['id'].toString(),
                        ),
                        child: Text(sw ? 'Thibitisha' : 'Verify'),
                      )
                    : null,
              ),
            ),
          ),
          _heading(sw ? 'Uhakiki wa wataalamu' : 'Professional verification'),
          ...providers.map(
            (item) => Card(
              child: ListTile(
                title: Text(item['display_name'].toString()),
                subtitle: Text(
                  '${item['provider_kind']} · ${item['verification_status']}',
                ),
                trailing: item['verification_status'] == 'pending'
                    ? FilledButton(
                        onPressed: () => _verify(
                          'event_service_profiles',
                          item['id'].toString(),
                        ),
                        child: Text(sw ? 'Thibitisha' : 'Verify'),
                      )
                    : null,
              ),
            ),
          ),
          _heading(sw ? 'Dharura na mbadala' : 'Emergency and substitutions'),
          if (escalations.isEmpty)
            Text(
              sw
                  ? 'Hakuna dharura iliyoripotiwa.'
                  : 'No emergency escalations.',
            )
          else
            ...escalations.map(
              (row) => Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(row['reason'].toString()),
                  subtitle: Text(row['status'].toString()),
                  trailing: row['status'] == 'open'
                      ? TextButton(
                          onPressed: () =>
                              _updateEscalation(row['id'].toString()),
                          child: Text(sw ? 'Anza uratibu' : 'Coordinate'),
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heading(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      value,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
  Future<void> _verify(String table, String id) async {
    try {
      final db = Supabase.instance.client;
      await db
          .from(table)
          .update(<String, dynamic>{
            'verification_status': 'verified',
            if (table == 'event_equipment_items')
              'publication_status': 'published',
          })
          .eq('id', id);
      if (table == 'event_service_profiles') {
        await db
            .from('event_service_offerings')
            .update(<String, dynamic>{'publication_status': 'published'})
            .eq('provider_id', id)
            .eq('is_active', true);
      }
      await _load();
    } catch (e) {
      _message(e.toString());
    }
  }

  Future<void> _updateEscalation(String id) async {
    try {
      await Supabase.instance.client
          .from('event_emergency_escalations')
          .update(<String, dynamic>{
            'status': 'coordinating',
            'assigned_admin_id': Supabase.instance.client.auth.currentUser!.id,
          })
          .eq('id', id);
      await _load();
    } catch (e) {
      _message(e.toString());
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _prepareQuote(
    Map<String, dynamic> plan,
    List<Map<String, dynamic>> items,
  ) async {
    final sw = context.isSwahili;
    final controllers = items.map((_) => TextEditingController()).toList();
    final additional = TextEditingController(text: '0');
    String itemName(Map<String, dynamic> item) =>
        ((item['event_equipment_items'] as Map?)?['name'] ??
                (item['event_service_offerings'] as Map?)?['title'] ??
                item['item_kind'])
            .toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(sw ? 'Quotation yenye vipengele' : 'Itemized quotation'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var index = 0; index < items.length; index++)
                  TextField(
                    controller: controllers[index],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '${itemName(items[index])} (TZS)',
                    ),
                  ),
                TextField(
                  controller: additional,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: sw
                        ? 'Gharama nyingine (TZS)'
                        : 'Additional costs (TZS)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(sw ? 'Tuma quotation' : 'Send quotation'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final lines = <Map<String, dynamic>>[];
        for (var index = 0; index < items.length; index++) {
          final amount = num.parse(controllers[index].text);
          final item = items[index];
          final quantity = item['requested_quantity'] as num? ?? 1;
          lines.add(<String, dynamic>{
            'plan_item_id': item['id'],
            'description': itemName(item),
            'quantity': quantity,
            'unit_price_tzs': amount / quantity,
          });
        }
        await Supabase.instance.client.rpc(
          'create_event_quote_revision',
          params: <String, dynamic>{
            'p_plan_id': plan['id'],
            'p_expires_at': DateTime.now()
                .add(const Duration(days: 3))
                .toUtc()
                .toIso8601String(),
            'p_items': lines,
            'p_additional_costs_tzs': num.tryParse(additional.text) ?? 0,
          },
        );
        _message(
          sw
              ? 'Quotation imetumwa kwa mteja.'
              : 'Quotation sent to the customer.',
        );
        await _load();
      } catch (e) {
        _message(e.toString());
      }
    }
    for (final controller in controllers) {
      controller.dispose();
    }
    additional.dispose();
  }

  Future<void> _sendAgreement(Map<String, dynamic> plan) async {
    final sw = context.isSwahili;
    final terms = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(sw ? 'Makubaliano ya mwisho' : 'Final event agreement'),
        content: TextField(
          controller: terms,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: sw
                ? 'Masharti, majukumu na sera ya cancellation'
                : 'Terms, responsibilities and cancellation policy',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(sw ? 'Tuma kwa mteja' : 'Send to customer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Supabase.instance.client.rpc(
          'send_event_agreement',
          params: <String, dynamic>{
            'p_plan_id': plan['id'],
            'p_terms': terms.text.trim(),
          },
        );
        _message(sw ? 'Makubaliano yametumwa.' : 'Agreement sent.');
        await _load();
      } catch (e) {
        _message(e.toString());
      }
    }
    terms.dispose();
  }
}
