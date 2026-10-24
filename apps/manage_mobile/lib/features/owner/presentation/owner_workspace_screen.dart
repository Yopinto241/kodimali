import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/manage_localization.dart';
import '../../events/presentation/events_provider_workspace_screen.dart';

class OwnerWorkspaceScreen extends StatefulWidget {
  const OwnerWorkspaceScreen({super.key});
  @override
  State<OwnerWorkspaceScreen> createState() => _OwnerWorkspaceScreenState();
}

class _OwnerWorkspaceScreenState extends State<OwnerWorkspaceScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? owner;
  List<Map<String, dynamic>> assets = [],
      bookings = [],
      statements = [],
      agreements = [],
      invitations = [],
      notices = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser!.id;
      final profile = await db
          .from('owner_profiles')
          .select()
          .eq('profile_id', uid)
          .maybeSingle();
      owner = profile;
      if (profile != null && profile['verification_status'] == 'verified') {
        final oid = profile['id'];
        final values = await Future.wait([
          db
              .from('owner_asset_claims')
              .select(
                '*, rental_assets(display_name,category,verification_status)',
              )
              .eq('owner_id', oid),
          db
              .from('booking_requests')
              .select(
                'id,request_reference,owner_approval_status,booking_status,requested_start_at,requested_end_at',
              )
              .order('created_at'),
          db
              .from('owner_statement_entries')
              .select()
              .eq('owner_id', oid)
              .order('occurred_at'),
          db
              .from('rental_agreements')
              .select('*, rental_assets(display_name)')
              .eq('owner_id', oid),
          db.from('tenant_move_out_notices').select().order('created_at'),
          db
              .from('tenant_invitations')
              .select('*, rental_assets(display_name)')
              .eq('owner_id', oid)
              .order('created_at'),
        ]);
        assets = _rows(values[0]);
        bookings = _rows(values[1]);
        statements = _rows(values[2]);
        agreements = _rows(values[3]);
        notices = _rows(values[4]);
        invitations = _rows(values[5]);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List).cast<Map<String, dynamic>>();
  Future<void> _respond(String id, bool approve) async {
    try {
      await Supabase.instance.client.rpc(
        'owner_respond_to_booking',
        params: {'p_booking_request_id': id, 'p_approve': approve},
      );
      setState(() => loading = true);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _inviteTenant() async {
    if (assets.isEmpty) return;
    String assetId = assets.first['asset_id'].toString();
    final email = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.isSwahili ? 'Mwalike mpangaji' : 'Invite a renter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: assetId,
              items: assets
                  .map(
                    (a) => DropdownMenuItem(
                      value: a['asset_id'].toString(),
                      child: Text(
                        ((a['rental_assets'] as Map?)?['display_name'] ??
                                a['asset_id'])
                            .toString(),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) assetId = v;
              },
              decoration: InputDecoration(
                labelText: context.isSwahili
                    ? 'Mali iliyothibitishwa'
                    : 'Verified asset',
              ),
            ),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: phone,
              decoration: InputDecoration(
                labelText: context.isSwahili ? 'Simu' : 'Phone',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EventsProviderWorkspaceScreen(),
              ),
            ),
            icon: const Icon(Icons.celebration_outlined),
            tooltip: context.isSwahili ? 'Sherehe na Matukio' : 'Events',
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.isSwahili ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.isSwahili ? 'Tuma mwaliko' : 'Send invitation'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final result = await Supabase.instance.client.rpc(
        'invite_tenant',
        params: {
          'p_asset_id': assetId,
          'p_email': email.text.trim().isEmpty ? null : email.text.trim(),
          'p_phone_number': phone.text.trim().isEmpty
              ? null
              : phone.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.isSwahili ? 'Namba ya mwaliko' : 'Invitation token'}: ${result['token']}',
            ),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      email.dispose();
      phone.dispose();
    }
  }

  Future<void> _createAgreement() async {
    final accepted = invitations
        .where((i) => i['status'] == 'accepted')
        .toList();
    if (accepted.isEmpty) return;
    final sw = context.isSwahili;
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 1825)),
      helpText: sw ? 'Chagua tarehe ya kuanza' : 'Choose start date',
    );
    if (start == null || !mounted) return;
    String invitationId = accepted.first['id'].toString();
    String rentPeriod = 'month';
    final rent = TextEditingController();
    final terms = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(sw ? 'Andaa mkataba' : 'Create agreement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: invitationId,
              items: accepted
                  .map(
                    (i) => DropdownMenuItem(
                      value: i['id'].toString(),
                      child: Text(
                        (i['email'] ?? i['phone_number'] ?? i['id']).toString(),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) invitationId = v;
              },
            ),
            TextField(
              controller: rent,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: sw ? 'Kiasi cha kodi (TZS)' : 'Rent amount (TZS)',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: rentPeriod,
              decoration: InputDecoration(
                labelText: sw ? 'Kipindi cha malipo' : 'Payment period',
              ),
              items: [
                DropdownMenuItem(
                  value: 'day',
                  child: Text(sw ? 'Siku' : 'Daily'),
                ),
                DropdownMenuItem(
                  value: 'week',
                  child: Text(sw ? 'Wiki' : 'Weekly'),
                ),
                DropdownMenuItem(
                  value: 'month',
                  child: Text(sw ? 'Mwezi' : 'Monthly'),
                ),
                DropdownMenuItem(
                  value: 'year',
                  child: Text(sw ? 'Mwaka' : 'Yearly'),
                ),
              ],
              onChanged: (value) {
                if (value != null) rentPeriod = value;
              },
            ),
            TextField(
              controller: terms,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: sw ? 'Masharti ya mkataba' : 'Agreement terms',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(sw ? 'Tuma kwa mpangaji' : 'Send to renter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc(
        'create_rental_agreement_from_invitation',
        params: {
          'p_invitation_id': invitationId,
          'p_starts_on': start.toIso8601String().substring(0, 10),
          'p_ends_on': null,
          'p_rent_amount_tzs': num.parse(rent.text),
          'p_rent_period': rentPeriod,
          'p_terms': {'summary': terms.text.trim()},
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      rent.dispose();
      terms.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(body: Center(child: Text(error!)));
    }
    if (owner == null || owner!['verification_status'] != 'verified') {
      return Scaffold(
        appBar: AppBar(title: const Text('Owner access')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your owner application is not verified yet. Apply on the KODIMALI website or wait for the verification review.',
          ),
        ),
      );
    }
    final sections = <Widget>[
      _summary(),
      _list('My assets', assets),
      _list(
        context.isSwahili ? 'Mialiko ya wapangaji' : 'Renter invitations',
        invitations,
      ),
      _bookings(),
      _list('Rental agreements', agreements),
      _list('Payments and statements', statements),
      _list('Move-out notices', notices),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(owner!['display_name']?.toString() ?? 'Owner workspace'),
        actions: [
          IconButton(
            onPressed: assets.isEmpty ? null : _inviteTenant,
            icon: const Icon(Icons.person_add_alt),
            tooltip: context.isSwahili ? 'Mwalike mpangaji' : 'Invite renter',
          ),
          IconButton(
            onPressed: invitations.any((i) => i['status'] == 'accepted')
                ? _createAgreement
                : null,
            icon: const Icon(Icons.description_outlined),
            tooltip: context.isSwahili ? 'Andaa mkataba' : 'Create agreement',
          ),
          IconButton(
            onPressed: () => context.go('/workspaces'),
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Switch workspace',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: sections),
      ),
    );
  }

  Widget _summary() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF17323A), Color(0xFF1F5052)],
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OWNER OVERVIEW',
          style: TextStyle(
            color: Color(0xFFD78A55),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your rental business',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${assets.length} assets  ·  ${bookings.length} bookings',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );
  Widget _list(String title, List<Map<String, dynamic>> rows) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Text('Nothing found.')
            else
              ...rows
                  .take(8)
                  .map(
                    (r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (r['display_name'] ??
                                r['entry_type'] ??
                                r['status'] ??
                                r['id'])
                            .toString(),
                      ),
                      subtitle: Text(
                        (r['status'] ?? r['verification_status'] ?? 'recorded')
                            .toString()
                            .replaceAll('_', ' '),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    ),
  );
  Widget _bookings() => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bookings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (bookings.isEmpty)
              const Text('Nothing found.')
            else
              ...bookings.map(
                (r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r['request_reference'].toString()),
                  subtitle: Text(
                    r['owner_approval_status'].toString().replaceAll('_', ' '),
                  ),
                  trailing: r['owner_approval_status'] == 'pending'
                      ? Wrap(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  _respond(r['id'].toString(), true),
                              icon: const Icon(Icons.check_circle_outline),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _respond(r['id'].toString(), false),
                              icon: const Icon(Icons.cancel_outlined),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
