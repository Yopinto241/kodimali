import 'package:flutter_core/localized_ui.dart';
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
  List<Map<String, dynamic>> offerings = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> escalations = <Map<String, dynamic>>[];
  String? error;
  bool canSettle = false;
  List<Map<String, dynamic>> paymentReviews = [];
  List<Map<String, dynamic>> cancellations = [];

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
      canSettle =
          await db.rpc(
            'has_admin_permission',
            params: {'p_permission': 'payments.manage'},
          ) ==
          true;
      paymentReviews = canSettle
          ? (await db
                    .from('financial_reconciliation_cases')
                    .select(
                      'id,reason,status,payment_intents!inner(resource_type,resource_id,amount_minor)',
                    )
                    .eq('payment_intents.resource_type', 'event_plan')
                    .inFilter('status', ['open', 'investigating']))
                .cast<Map<String, dynamic>>()
          : [];
      cancellations =
          (await db
                  .from('event_cancellations')
                  .select(
                    'id,plan_id,party,reason,status,resolution,refundable_amount_tzs',
                  )
                  .order('created_at'))
              .cast<Map<String, dynamic>>();
      final values = await Future.wait<dynamic>(<Future<dynamic>>[
        db
            .from('event_plans')
            .select(
              '*, event_types(name_sw,name_en), event_plan_items(id,item_kind,requested_quantity,status,equipment_id,offering_id,event_equipment_items(name),event_service_offerings(title))',
            )
            .order('created_at'),
        db
            .from('event_equipment_items')
            .select(
              'id,name,total_quantity,verification_status,publication_status,owner_id',
            )
            .order('created_at'),
        db
            .from('event_service_profiles')
            .select(
              'id,display_name,provider_kind,verification_status,profile_id',
            )
            .order('created_at'),
        db
            .from('event_service_offerings')
            .select(
              'id,title,publication_status,provider_id,event_service_profiles(display_name,verification_status)',
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
      offerings = (values[3] as List).cast<Map<String, dynamic>>();
      escalations = (values[4] as List).cast<Map<String, dynamic>>();
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
            sw
                ? mobileUi(context, 'Uratibu wa Sherehe na Matukio')
                : mobileUi(context, 'Events coordination'),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            sw
                ? mobileUi(
                    context,
                    'Thibitisha providers, fuatilia confirmations, andaa quotation na shughulikia dharura.',
                  )
                : mobileUi(
                    context,
                    'Verify providers, track confirmations, prepare quotations and handle emergencies.',
                  ),
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: LocalizedUiText(error!)),
          _heading(sw ? 'Mipango ya wateja' : 'Customer event plans'),
          if (plans.isEmpty)
            Text(
              sw
                  ? mobileUi(context, 'Hakuna mipango.')
                  : mobileUi(context, 'No event plans.'),
            )
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
                        '${plan['reference']} · $confirmed/${items.length} ${sw ? mobileUi(context, 'wamethibitisha') : mobileUi(context, 'confirmed')}',
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
                              sw
                                  ? mobileUi(context, 'Andaa quotation')
                                  : mobileUi(context, 'Prepare quotation'),
                            ),
                          ),
                          if (plan['status'] == 'agreement_pending')
                            OutlinedButton(
                              onPressed: () => _sendAgreement(plan),
                              child: Text(
                                sw
                                    ? mobileUi(context, 'Tuma makubaliano')
                                    : mobileUi(context, 'Send agreement'),
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
                  '${item['total_quantity']} / ${item['publication_status']} · ${item['verification_status']}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => _reviewEquipment(item, action),
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'publish',
                      child: Text(
                        sw
                            ? mobileUi(context, 'Thibitisha na chapisha')
                            : mobileUi(context, 'Verify and publish'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'paused',
                      child: Text(
                        sw
                            ? mobileUi(context, 'Sitisha')
                            : mobileUi(context, 'Pause'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'rejected',
                      child: Text(
                        sw
                            ? mobileUi(context, 'Kataa')
                            : mobileUi(context, 'Reject'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'suspended',
                      child: Text(
                        sw
                            ? mobileUi(context, 'Zuia')
                            : mobileUi(context, 'Suspend'),
                      ),
                    ),
                  ],
                ),
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
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'verified') {
                      await _verify(
                        'event_service_profiles',
                        item['id'].toString(),
                      );
                    } else {
                      try {
                        await Supabase.instance.client
                            .from('event_service_profiles')
                            .update({'verification_status': action})
                            .eq('id', item['id']);
                        await _load();
                      } catch (e) {
                        _message(e.toString());
                      }
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'verified',
                      child: Text(
                        sw
                            ? mobileUi(context, 'Thibitisha')
                            : mobileUi(context, 'Verify'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'rejected',
                      child: Text(
                        sw
                            ? mobileUi(context, 'Kataa')
                            : mobileUi(context, 'Reject'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'suspended',
                      child: Text(
                        sw
                            ? mobileUi(context, 'Zuia')
                            : mobileUi(context, 'Suspend'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _heading(sw ? 'Uchapishaji wa huduma' : 'Service publication'),
          if (offerings.isEmpty)
            Text(
              sw
                  ? mobileUi(context, 'Hakuna huduma.')
                  : mobileUi(context, 'No service offerings.'),
            )
          else
            ...offerings.map((item) {
              final provider = item['event_service_profiles'] as Map?;
              final canPublish =
                  item['publication_status'] != 'published' &&
                  provider?['verification_status'] == 'verified';
              return Card(
                child: ListTile(
                  title: Text(item['title'].toString()),
                  subtitle: Text(
                    '${provider?['display_name'] ?? ''} · ${item['publication_status']}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'published') {
                        await _publishOffering(item['id'].toString());
                      } else {
                        try {
                          await Supabase.instance.client
                              .from('event_service_offerings')
                              .update({'publication_status': action})
                              .eq('id', item['id']);
                          await _load();
                        } catch (e) {
                          _message(e.toString());
                        }
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      if (canPublish)
                        PopupMenuItem(
                          value: 'published',
                          child: Text(
                            sw
                                ? mobileUi(context, 'Chapisha')
                                : mobileUi(context, 'Publish'),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'paused',
                        child: Text(
                          sw
                              ? mobileUi(context, 'Sitisha')
                              : mobileUi(context, 'Pause'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'rejected',
                        child: Text(
                          sw
                              ? mobileUi(context, 'Kataa')
                              : mobileUi(context, 'Reject'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'suspended',
                        child: Text(
                          sw
                              ? mobileUi(context, 'Zuia')
                              : mobileUi(context, 'Suspend'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (canSettle) _heading(sw ? 'Ukaguzi wa malipo' : 'Payment reviews'),
          ...paymentReviews.map(
            (row) => Card(
              child: ListTile(
                title: Text(row['reason'].toString()),
                subtitle: Text(row['status'].toString()),
                trailing: TextButton(
                  onPressed: () => _resolvePaymentReview(row),
                  child: Text(
                    sw
                        ? mobileUi(context, 'Rekodi suluhu')
                        : mobileUi(context, 'Record resolution'),
                  ),
                ),
              ),
            ),
          ),
          _heading(sw ? 'Maombi ya kughairi' : 'Cancellation reviews'),
          ...cancellations.map(
            (row) => Card(
              child: ListTile(
                title: Text(row['reason'].toString()),
                subtitle: Text('${row['status']} / ${row['resolution'] ?? ''}'),
                trailing: canSettle && row['status'] != 'completed'
                    ? TextButton(
                        onPressed: () => _recordSettlement(row),
                        child: Text(
                          sw
                              ? mobileUi(context, 'Rekodi suluhu ya fedha')
                              : mobileUi(context, 'Record settlement'),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          _heading(sw ? 'Dharura na mbadala' : 'Emergency and substitutions'),
          if (escalations.isEmpty)
            Text(
              sw
                  ? mobileUi(context, 'Hakuna dharura iliyoripotiwa.')
                  : mobileUi(context, 'No emergency escalations.'),
            )
          else
            ...escalations.map(
              (row) => Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(row['reason'].toString()),
                  subtitle: Text(row['status'].toString()),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'coordinate') {
                        _updateEscalation(row['id'].toString());
                      } else if (action == 'replace') {
                        _proposeReplacement(row);
                      } else {
                        _resolveEscalation(row);
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        value: 'coordinate',
                        child: Text(
                          sw
                              ? mobileUi(context, 'Anza uratibu')
                              : mobileUi(context, 'Coordinate'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'replace',
                        child: Text(
                          sw
                              ? mobileUi(context, 'Pendekeza mbadala')
                              : mobileUi(context, 'Propose replacement'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'resolve',
                        child: Text(
                          sw
                              ? mobileUi(context, 'Maliza')
                              : mobileUi(context, 'Resolve'),
                        ),
                      ),
                    ],
                  ),
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
            .eq('is_active', true)
            .eq('publication_status', 'draft');
      }
      await _load();
    } catch (e) {
      _message(e.toString());
    }
  }

  Future<void> _publishOffering(String id) async {
    try {
      await Supabase.instance.client
          .from('event_service_offerings')
          .update(<String, dynamic>{'publication_status': 'published'})
          .eq('id', id);
      await _load();
    } catch (e) {
      _message(e.toString());
    }
  }

  Future<void> _resolvePaymentReview(Map<String, dynamic> row) async {
    final reference = TextEditingController();
    String decision = 'refund_recorded';
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const LocalizedUiText('Resolve event payment review'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LocalizedUiText(
                  'This screen records a completed refund or keeps verified funds as credit after customer replacement consent. It does not send money.',
                ),
                DropdownButtonFormField<String>(
                  initialValue: decision,
                  items: const [
                    DropdownMenuItem(
                      value: 'refund_recorded',
                      child: LocalizedUiText('Full refund already sent'),
                    ),
                    DropdownMenuItem(
                      value: 'credit_for_replacement',
                      child: LocalizedUiText(
                        'Customer-approved replacement credit',
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      update(() => decision = value ?? decision),
                ),
                TextField(
                  controller: reference,
                  decoration: InputDecoration(
                    labelText: mobileUi(
                      context,
                      'Refund transaction or review reference',
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const LocalizedUiText('Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const LocalizedUiText('Record resolution'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await Supabase.instance.client.rpc(
          'resolve_event_payment_review',
          params: {
            'p_case_id': row['id'],
            'p_decision': decision,
            'p_reference': reference.text.trim(),
          },
        );
        await _load();
      }
    } catch (e) {
      _message(e.toString());
    } finally {
      reference.dispose();
    }
  }

  Future<void> _recordSettlement(Map<String, dynamic> row) async {
    final reference = TextEditingController();
    final amount = TextEditingController(text: '0');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LocalizedUiText('Record completed external settlement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LocalizedUiText(
                'Send any approved refund outside this screen first, then record its reference. This button does not transfer money. For a reviewed zero-refund outcome, enter the review reference.',
              ),
              TextField(
                controller: reference,
                decoration: InputDecoration(
                  labelText: mobileUi(
                    context,
                    'Transaction or review reference',
                  ),
                ),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Refund already sent (TZS)'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedUiText('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedUiText('Record settlement'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await Supabase.instance.client.rpc(
          'record_event_cancellation_settlement',
          params: {
            'p_cancellation_id': row['id'],
            'p_transaction_reference': reference.text.trim(),
            'p_refund_amount_tzs': num.parse(amount.text),
          },
        );
        await _load();
      }
    } catch (e) {
      _message(e.toString());
    } finally {
      reference.dispose();
      amount.dispose();
    }
  }

  Future<void> _reviewEquipment(
    Map<String, dynamic> item,
    String action,
  ) async {
    try {
      await Supabase.instance.client
          .from('event_equipment_items')
          .update(<String, dynamic>{
            'publication_status': action == 'publish' ? 'published' : action,
            if (action == 'publish') 'verification_status': 'verified',
            if (action == 'rejected' || action == 'suspended')
              'verification_status': action,
          })
          .eq('id', item['id']);
      await _load();
    } catch (e) {
      _message(e.toString());
    }
  }

  Future<void> _proposeReplacement(Map<String, dynamic> escalation) async {
    final db = Supabase.instance.client;
    final reason = TextEditingController();
    final difference = TextEditingController(text: '0');
    try {
      if (escalation['plan_item_id'] == null) {
        throw StateError(
          'Select a supplier cancellation with an item before proposing a replacement.',
        );
      }
      final item = await db
          .from('event_plan_items')
          .select('item_kind')
          .eq('id', escalation['plan_item_id'])
          .single();
      final equipmentKind = item['item_kind'] == 'equipment';
      final candidates = equipmentKind
          ? await db.rpc(
              'search_public_event_equipment',
              params: {'p_limit': 50},
            )
          : await db.rpc(
              'search_public_event_services',
              params: {'p_limit': 50},
            );
      final rows = (candidates as List).cast<Map<String, dynamic>>();
      String? selected;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              context.isSwahili
                  ? mobileUi(context, 'Pendekeza mbadala')
                  : mobileUi(context, 'Propose replacement'),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: mobileUi(context, 'Replacement'),
                    ),
                    items: rows
                        .map(
                          (row) => DropdownMenuItem(
                            value: (row['id'] ?? row['offering_id']).toString(),
                            child: Text(
                              (row['name'] ?? row['title']).toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() => selected = value),
                  ),
                  TextField(
                    controller: reason,
                    decoration: InputDecoration(
                      labelText: mobileUi(
                        context,
                        'Reason and supplier details',
                      ),
                    ),
                  ),
                  TextField(
                    controller: difference,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: mobileUi(
                        context,
                        'Price change (TZS, negative for a reduction)',
                      ),
                    ),
                  ),
                  const LocalizedUiText(
                    'Customer consent, supplier confirmation and a revised quotation are required. No new charge is authorized here.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const LocalizedUiText('Cancel'),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const LocalizedUiText('Send proposal'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await db.rpc(
          'propose_event_replacement',
          params: {
            'p_item_id': escalation['plan_item_id'],
            'p_replacement_id': selected,
            'p_reason': reason.text.trim(),
            'p_price_change_tzs': num.parse(difference.text),
          },
        );
        _message('Proposal sent for customer approval.');
        await _load();
      }
    } catch (e) {
      _message(e.toString());
    } finally {
      reason.dispose();
      difference.dispose();
    }
  }

  Future<void> _resolveEscalation(Map<String, dynamic> row) async {
    final resolution = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LocalizedUiText('Resolve event issue'),
          content: TextField(
            controller: resolution,
            decoration: InputDecoration(
              labelText: mobileUi(
                context,
                'Resolution and settlement reference',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedUiText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedUiText('Resolve'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await Supabase.instance.client.rpc(
          'resolve_event_escalation',
          params: {
            'p_escalation_id': row['id'],
            'p_resolution': resolution.text.trim(),
          },
        );
        await _load();
      }
    } catch (e) {
      _message(e.toString());
    } finally {
      resolution.dispose();
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
        title: Text(
          sw
              ? mobileUi(context, 'Quotation yenye vipengele')
              : mobileUi(context, 'Itemized quotation'),
        ),
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
                        ? mobileUi(context, 'Gharama nyingine (TZS)')
                        : mobileUi(context, 'Additional costs (TZS)'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              sw ? mobileUi(context, 'Ghairi') : mobileUi(context, 'Cancel'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              sw
                  ? mobileUi(context, 'Tuma quotation')
                  : mobileUi(context, 'Send quotation'),
            ),
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
        title: Text(
          sw
              ? mobileUi(context, 'Makubaliano ya mwisho')
              : mobileUi(context, 'Final event agreement'),
        ),
        content: TextField(
          controller: terms,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: sw
                ? mobileUi(
                    context,
                    'Masharti, majukumu na sera ya cancellation',
                  )
                : mobileUi(
                    context,
                    'Terms, responsibilities and cancellation policy',
                  ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              sw ? mobileUi(context, 'Ghairi') : mobileUi(context, 'Cancel'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              sw
                  ? mobileUi(context, 'Tuma kwa mteja')
                  : mobileUi(context, 'Send to customer'),
            ),
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
