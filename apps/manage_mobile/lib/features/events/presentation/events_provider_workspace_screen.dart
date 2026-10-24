import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/manage_localization.dart';

class EventsProviderWorkspaceScreen extends StatefulWidget {
  const EventsProviderWorkspaceScreen({super.key});
  @override
  State<EventsProviderWorkspaceScreen> createState() =>
      _EventsProviderWorkspaceScreenState();
}

class _EventsProviderWorkspaceScreenState
    extends State<EventsProviderWorkspaceScreen> {
  bool loading = true;
  String? error;
  String? ownerId;
  Map<String, dynamic>? serviceProfile;
  List<Map<String, dynamic>> equipment = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];

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
      ownerId = (await db.rpc('current_owner_id'))?.toString();
      serviceProfile = await db
          .from('event_service_profiles')
          .select()
          .eq('profile_id', db.auth.currentUser!.id)
          .maybeSingle();
      if (ownerId != null && ownerId != 'null') {
        equipment =
            (await db
                        .from('event_equipment_items')
                        .select(
                          '*, event_equipment_categories(name_sw,name_en)',
                        )
                        .eq('owner_id', ownerId!)
                        .order('created_at')
                    as List)
                .cast<Map<String, dynamic>>();
      } else {
        equipment = <Map<String, dynamic>>[];
      }
      requests = <Map<String, dynamic>>[];
      final equipmentIds = equipment
          .map((row) => row['id'].toString())
          .toList();
      if (equipmentIds.isNotEmpty) {
        final rows =
            (await db
                        .from('event_plan_items')
                        .select(
                          '*, event_plans(reference,event_period,status), event_individual_bookings(id,status)',
                        )
                        .inFilter('equipment_id', equipmentIds)
                        .order('created_at')
                    as List)
                .cast<Map<String, dynamic>>();
        requests.addAll(
          rows.map(
            (row) => <String, dynamic>{...row, '_request_kind': 'equipment'},
          ),
        );
      }
      if (serviceProfile != null) {
        final offerings =
            (await db
                        .from('event_service_offerings')
                        .select('id')
                        .eq('provider_id', serviceProfile!['id'])
                    as List)
                .cast<Map<String, dynamic>>();
        final offeringIds = offerings
            .map((row) => row['id'].toString())
            .toList();
        if (offeringIds.isNotEmpty) {
          final rows =
              (await db
                          .from('event_plan_items')
                          .select(
                            '*, event_plans(reference,event_period,status), event_individual_bookings(id,status)',
                          )
                          .inFilter('offering_id', offeringIds)
                          .order('created_at')
                      as List)
                  .cast<Map<String, dynamic>>();
          requests.addAll(
            rows.map(
              (row) => <String, dynamic>{...row, '_request_kind': 'service'},
            ),
          );
        }
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(sw ? 'Usimamizi wa Matukio' : 'Events workspace'),
        actions: <Widget>[
          IconButton(
            onPressed: serviceProfile == null ? _registerService : _addOffering,
            icon: Icon(
              serviceProfile == null
                  ? Icons.person_add_alt
                  : Icons.add_business_outlined,
            ),
            tooltip: serviceProfile == null
                ? (sw ? 'Sajili huduma' : 'Register service')
                : (sw ? 'Ongeza huduma' : 'Add offering'),
          ),
        ],
      ),
      floatingActionButton: ownerId != null && ownerId != 'null'
          ? FloatingActionButton.extended(
              onPressed: _addEquipment,
              icon: const Icon(Icons.add),
              label: Text(sw ? 'Ongeza vifaa' : 'Add equipment'),
            )
          : serviceProfile == null
          ? FloatingActionButton.extended(
              onPressed: _registerService,
              icon: const Icon(Icons.person_add_alt),
              label: Text(sw ? 'Sajili huduma' : 'Register service'),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF102438), Color(0xFF147D8C)],
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'KODIMALI EVENTS',
                          style: TextStyle(
                            color: Color(0xFFD6A75B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sw
                              ? 'Vifaa, huduma na ratiba zako'
                              : 'Your equipment, services and schedules',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(error!),
                    ),
                  _section(
                    sw ? 'Vifaa vyangu' : 'My equipment',
                    equipment,
                    sw ? 'Bado hujaongeza vifaa.' : 'No equipment added yet.',
                  ),
                  _requestSection(
                    sw ? 'Maombi na ratiba' : 'Requests and schedule',
                    requests,
                    sw ? 'Hakuna maombi kwa sasa.' : 'No requests yet.',
                  ),
                  if (serviceProfile != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: Text(serviceProfile!['display_name'].toString()),
                        subtitle: Text(
                          '${serviceProfile!['provider_kind']} · ${serviceProfile!['verification_status']}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rows,
    String empty,
  ) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(empty)
        else
          ...rows.map(
            (row) => Card(
              child: ListTile(
                title: Text(
                  (row['name'] ?? row['status'] ?? row['id']).toString(),
                ),
                subtitle: Text(
                  (row['verification_status'] ?? row['status'] ?? '')
                      .toString()
                      .replaceAll('_', ' '),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _requestSection(
    String title,
    List<Map<String, dynamic>> rows,
    String empty,
  ) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(empty)
        else
          ...rows.map((row) {
            final plan = row['event_plans'] as Map?;
            final pending = row['status'] == 'requested';
            final individualValue = row['event_individual_bookings'];
            final individual = individualValue is List
                ? (individualValue.isEmpty
                      ? null
                      : individualValue.first as Map)
                : individualValue as Map?;
            return Card(
              child: ListTile(
                title: Text((plan?['reference'] ?? row['id']).toString()),
                subtitle: Text('${row['_request_kind']} · ${row['status']}'),
                trailing: pending && individual?['status'] == 'requested'
                    ? FilledButton(
                        onPressed: () => _confirmRequest(row),
                        child: Text(
                          context.isSwahili ? 'Thibitisha' : 'Confirm',
                        ),
                      )
                    : individual?['status'] == 'provider_approved'
                    ? FilledButton.tonal(
                        onPressed: () => _sendIndividualQuote(individual!),
                        child: Text(
                          context.isSwahili ? 'Tuma quotation' : 'Send quote',
                        ),
                      )
                    : null,
              ),
            );
          }),
      ],
    ),
  );

  Future<void> _confirmRequest(Map<String, dynamic> row) async {
    try {
      final individualValue = row['event_individual_bookings'];
      final individual = individualValue is List
          ? (individualValue.isEmpty ? null : individualValue.first as Map)
          : individualValue as Map?;
      if (individual != null) {
        await Supabase.instance.client.rpc(
          'respond_individual_event_booking',
          params: <String, dynamic>{
            'p_booking_id': individual['id'],
            'p_approve': true,
            'p_response': null,
          },
        );
        await _load();
        return;
      }
      final function = row['_request_kind'] == 'equipment'
          ? 'confirm_event_equipment_item'
          : 'confirm_event_service_item';
      final params = row['_request_kind'] == 'equipment'
          ? <String, dynamic>{
              'p_plan_item_id': row['id'],
              'p_hold_minutes': 1440,
            }
          : <String, dynamic>{
              'p_plan_item_id': row['id'],
              'p_travel_buffer_minutes': 60,
              'p_hold_minutes': 1440,
            };
      await Supabase.instance.client.rpc(function, params: params);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _sendIndividualQuote(Map individual) async {
    final sw = context.isSwahili;
    final amount = TextEditingController();
    final terms = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(sw ? 'Quotation ya booking' : 'Booking quotation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'TZS'),
            ),
            TextField(
              controller: terms,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: sw ? 'Maelezo na masharti' : 'Description and terms',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(sw ? 'Tuma' : 'Send'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Supabase.instance.client.rpc(
          'send_individual_booking_quote',
          params: <String, dynamic>{
            'p_booking_id': individual['id'],
            'p_amount_tzs': num.parse(amount.text),
            'p_terms': terms.text.trim(),
            'p_expires_at': DateTime.now()
                .add(const Duration(days: 3))
                .toUtc()
                .toIso8601String(),
          },
        );
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
    amount.dispose();
    terms.dispose();
  }

  Future<void> _registerService() async {
    final sw = context.isSwahili;
    final name = TextEditingController();
    final bio = TextEditingController();
    String kind = 'planner';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          sw ? 'Sajili huduma ya kitaalamu' : 'Register professional service',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: sw ? 'Jina la huduma' : 'Display name',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: kind,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: 'planner',
                  child: Text('Event planner'),
                ),
                DropdownMenuItem(value: 'decorator', child: Text('Decorator')),
                DropdownMenuItem(
                  value: 'photographer',
                  child: Text('Photographer'),
                ),
                DropdownMenuItem(value: 'dj', child: Text('DJ')),
                DropdownMenuItem(value: 'caterer', child: Text('Caterer')),
                DropdownMenuItem(value: 'mc_host', child: Text('MC / Host')),
              ],
              onChanged: (v) {
                if (v != null) kind = v;
              },
            ),
            TextField(
              controller: bio,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: sw ? 'Kuhusu huduma' : 'About the service',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(sw ? 'Tuma kwa uhakiki' : 'Submit for review'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Supabase.instance.client
            .from('event_service_profiles')
            .insert(<String, dynamic>{
              'profile_id': Supabase.instance.client.auth.currentUser!.id,
              'display_name': name.text.trim(),
              'provider_kind': kind,
              'biography': bio.text.trim(),
            });
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
    name.dispose();
    bio.dispose();
  }

  Future<void> _addEquipment() async {
    final sw = context.isSwahili;
    final db = Supabase.instance.client;
    final categories =
        (await db
                    .from('event_equipment_categories')
                    .select('id,name_sw,name_en')
                    .eq('is_active', true)
                    .order('display_order')
                as List)
            .cast<Map<String, dynamic>>();
    if (!mounted || categories.isEmpty) return;
    String categoryId = categories.first['id'].toString();
    final name = TextEditingController();
    final quantity = TextEditingController();
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(sw ? 'Ongeza vifaa' : 'Add equipment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              items: categories
                  .map(
                    (row) => DropdownMenuItem(
                      value: row['id'].toString(),
                      child: Text(
                        (sw ? row['name_sw'] : row['name_en']).toString(),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) categoryId = v;
              },
            ),
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: sw ? 'Jina la vifaa' : 'Equipment name',
              ),
            ),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: sw ? 'Idadi iliyopo' : 'Total quantity',
              ),
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: sw ? 'Bei kwa tukio (TZS)' : 'Price per event (TZS)',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(sw ? 'Tuma kwa uhakiki' : 'Submit for review'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await db.from('event_equipment_items').insert(<String, dynamic>{
          'owner_id': ownerId,
          'category_id': categoryId,
          'name': name.text.trim(),
          'condition': 'good',
          'total_quantity': int.parse(quantity.text),
          'price_amount_tzs': num.parse(price.text),
          'price_unit': 'item_event',
        });
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
    name.dispose();
    quantity.dispose();
    price.dispose();
  }

  Future<void> _addOffering() async {
    if (serviceProfile == null) return;
    final sw = context.isSwahili;
    final title = TextEditingController();
    final description = TextEditingController();
    final price = TextEditingController();
    String mode = 'fixed';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(sw ? 'Ongeza huduma' : 'Add service offering'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: title,
              decoration: InputDecoration(
                labelText: sw ? 'Jina la huduma' : 'Service title',
              ),
            ),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: sw ? 'Maelezo' : 'Description',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: mode,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'fixed', child: Text('Fixed price')),
                DropdownMenuItem(value: 'from', child: Text('Starting from')),
                DropdownMenuItem(
                  value: 'custom_quote',
                  child: Text('Custom quotation'),
                ),
              ],
              onChanged: (value) {
                if (value != null) mode = value;
              },
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: sw
                    ? 'Bei (TZS, si lazima kwa custom)'
                    : 'Price (TZS, optional for custom)',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(sw ? 'Hifadhi' : 'Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Supabase.instance.client
            .from('event_service_offerings')
            .insert(<String, dynamic>{
              'provider_id': serviceProfile!['id'],
              'title': title.text.trim(),
              'description': description.text.trim(),
              'pricing_mode': mode,
              'price_amount_tzs': num.tryParse(price.text),
            });
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
    title.dispose();
    description.dispose();
    price.dispose();
  }
}
