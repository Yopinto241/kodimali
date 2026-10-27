import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/manage_localization.dart';

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
      bookableListings = [],
      bookingPolicies = [],
      bookings = [],
      statements = [],
      agreements = [],
      invitations = [],
      notices = [],
      verifiedAgents = [],
      agentDelegations = [];
  Map<String, dynamic>? ownerBookingAgreement;
  bool ownerBookingAgreementAccepted = false;
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
        bookableListings = <Map<String, dynamic>>[];
        bookingPolicies = <Map<String, dynamic>>[];
        ownerBookingAgreement = null;
        ownerBookingAgreementAccepted = false;
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
        final assetIds = assets
            .where((claim) => claim['status'] == 'verified')
            .map((claim) => claim['asset_id'])
            .whereType<String>()
            .toList(growable: false);
        if (assetIds.isNotEmpty) {
          bookableListings = _rows(
            await db
                .from('listings')
                .select(
                  'id,asset_id,title,category,status,approval_status,booking_configurations(id,booking_mode,authority_status,deterministic_pricing,availability_reliable,policy_id,hold_duration_minutes,balance_deadline_configuration,fulfillment_configuration)',
                )
                .inFilter('asset_id', assetIds)
                .order('created_at', ascending: false),
          );
        }
        try {
          verifiedAgents = _rows(
            await db
                .from('agents')
                .select('id,display_name,business_name,public_location_label')
                .eq('verification_status', 'approved')
                .eq('account_status', 'active')
                .order('display_name'),
          );
          agentDelegations = _rows(
            await db
                .from('asset_agent_delegations')
                .select(
                  'id,asset_id,agent_id,scopes,status,starts_at,ends_at,agents(display_name,business_name)',
                )
                .eq('owner_id', oid)
                .order('created_at', ascending: false),
          );
        } on PostgrestException catch (delegationError) {
          if (delegationError.code != '42P01' &&
              delegationError.code != 'PGRST205') {
            rethrow;
          }
          verifiedAgents = <Map<String, dynamic>>[];
          agentDelegations = <Map<String, dynamic>>[];
        }
        bookingPolicies = _rows(
          await db
              .from('booking_policies')
              .select(
                'id,category,version,title,active_from,active_until,cancellation_policy_version_id',
              )
              .eq('is_active', true)
              .order('version', ascending: false),
        );
        ownerBookingAgreement = await db
            .from('owner_booking_agreement_versions')
            .select('id,version,title,body,effective_from')
            .eq('is_active', true)
            .maybeSingle();
        if (ownerBookingAgreement != null) {
          final acceptance = await db
              .from('owner_booking_agreement_acceptances')
              .select('id')
              .eq('owner_id', oid)
              .eq('agreement_version_id', ownerBookingAgreement!['id'])
              .maybeSingle();
          ownerBookingAgreementAccepted = acceptance != null;
        }
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

  Future<void> _claimListing() async {
    final TextEditingController listing = TextEditingController();
    String authority = owner?['owner_type'] == 'authorized_manager'
        ? 'authorized_manager'
        : 'owner';
    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              title: Text(
                context.isSwahili ? 'Unganisha mali' : 'Connect an item',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: listing,
                    decoration: InputDecoration(
                      labelText: context.isSwahili
                          ? 'Link au ID ya tangazo'
                          : 'Listing link or ID',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: authority,
                    decoration: InputDecoration(
                      labelText: context.isSwahili
                          ? 'Mamlaka yako'
                          : 'Your authority',
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'owner', child: Text('Owner')),
                      DropdownMenuItem(
                        value: 'authorized_manager',
                        child: Text('Authorized manager'),
                      ),
                    ],
                    onChanged: (String? value) {
                      if (value != null) {
                        setDialogState(() => authority = value);
                      }
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(context.isSwahili ? 'Ghairi' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(context.isSwahili ? 'Tuma' : 'Submit'),
                ),
              ],
            ),
      ),
    );
    if (submit != true) {
      listing.dispose();
      return;
    }
    try {
      final String raw = listing.text.trim().replaceFirst(RegExp(r'/$'), '');
      final String listingId = raw.split('/').last;
      await Supabase.instance.client.rpc(
        'submit_owner_listing_claim',
        params: <String, dynamic>{
          'p_listing_id': listingId,
          'p_authority_type': authority,
          'p_evidence_paths': <dynamic>[],
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.isSwahili
                  ? 'Ombi limetumwa kwa uhakiki wa admin.'
                  : 'The item was submitted for administrator verification.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      listing.dispose();
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
            onPressed: _claimListing,
            icon: const Icon(Icons.add_business_outlined),
            tooltip: context.isSwahili ? 'Unganisha mali' : 'Connect an item',
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

  Map<String, dynamic> _bookingConfiguration(Map<String, dynamic> listing) {
    final value = listing['booking_configurations'];
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return <String, dynamic>{};
  }

  Future<void> _acceptOwnerBookingAgreement() async {
    final agreement = ownerBookingAgreement;
    if (agreement == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(agreement['title'].toString()),
        content: SingleChildScrollView(
          child: Text(agreement['body'].toString()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.isSwahili ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              context.isSwahili ? 'Nakubali masharti' : 'Accept agreement',
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'accept_owner_booking_agreement',
        params: <String, dynamic>{'p_agreement_version_id': agreement['id']},
      );
      setState(() => loading = true);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _configureListingBooking(Map<String, dynamic> listing) async {
    final current = _bookingConfiguration(listing);
    String mode = current['booking_mode']?.toString() ?? 'request_booking';
    bool deterministic = current['deterministic_pricing'] == true;
    bool reliable = current['availability_reliable'] == true;
    int holdMinutes = (current['hold_duration_minutes'] as num?)?.round() ?? 30;
    String? policyId = current['policy_id']?.toString();
    final category = listing['category']?.toString();
    final policies = bookingPolicies
        .where(
          (policy) =>
              policy['category'] == null || policy['category'] == category,
        )
        .toList(growable: false);
    if (policyId != null && !policies.any((item) => item['id'] == policyId)) {
      policyId = null;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            context.isSwahili
                ? 'Booking ya ${listing['title']}'
                : 'Booking for ${listing['title']}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: InputDecoration(
                    labelText: context.isSwahili
                        ? 'Namna ya booking'
                        : 'Booking mode',
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'not_bookable',
                      child: Text('Booking off'),
                    ),
                    DropdownMenuItem(
                      value: 'request_booking',
                      child: Text('Request Booking'),
                    ),
                    DropdownMenuItem(
                      value: 'instant_booking',
                      child: Text('Instant Booking'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialog(() => mode = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: policyId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.isSwahili
                        ? 'Masharti ya booking'
                        : 'Booking policy',
                  ),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        context.isSwahili ? 'Hayajachaguliwa' : 'Not selected',
                      ),
                    ),
                    ...policies.map(
                      (policy) => DropdownMenuItem<String?>(
                        value: policy['id'].toString(),
                        child: Text(
                          '${policy['title']} · v${policy['version']}${policy['cancellation_policy_version_id'] == null ? ' · not ready for Instant Booking' : ''}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setDialog(() => policyId = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deterministic,
                  title: Text(
                    context.isSwahili
                        ? 'Bei inaweza kuhesabiwa moja kwa moja'
                        : 'Price is deterministic',
                  ),
                  onChanged: (value) => setDialog(() => deterministic = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reliable,
                  title: Text(
                    context.isSwahili
                        ? 'Kalenda ya upatikanaji ni sahihi'
                        : 'Availability calendar is reliable',
                  ),
                  onChanged: (value) => setDialog(() => reliable = value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.isSwahili
                        ? 'Ulinzi wa checkout: dakika $holdMinutes'
                        : 'Checkout protection: $holdMinutes minutes',
                  ),
                  subtitle: Slider(
                    value: holdMinutes.toDouble(),
                    min: 5,
                    max: 60,
                    divisions: 11,
                    label: '$holdMinutes',
                    onChanged: (value) =>
                        setDialog(() => holdMinutes = value.round()),
                  ),
                ),
                if (mode == 'instant_booking' && !ownerBookingAgreementAccepted)
                  Text(
                    context.isSwahili
                        ? 'Kubali makubaliano ya booking kabla ya kuwasha Instant Booking.'
                        : 'Accept the owner booking agreement before enabling Instant Booking.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (mode == 'instant_booking' &&
                    !policies.any(
                      (policy) =>
                          policy['id']?.toString() == policyId &&
                          policy['cancellation_policy_version_id'] != null,
                    ))
                  Text(
                    context.isSwahili
                        ? 'Admin lazima aunganishe masharti haya na cancellation policy iliyoidhinishwa.'
                        : 'An administrator must link this booking policy to an approved cancellation policy.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.isSwahili ? 'Ghairi' : 'Cancel'),
            ),
            FilledButton(
              onPressed:
                  mode == 'instant_booking' &&
                      (!ownerBookingAgreementAccepted ||
                          !policies.any(
                            (policy) =>
                                policy['id']?.toString() == policyId &&
                                policy['cancellation_policy_version_id'] !=
                                    null,
                          ))
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(context.isSwahili ? 'Hifadhi' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'configure_owned_listing_booking',
        params: <String, dynamic>{
          'p_listing_id': listing['id'],
          'p_booking_mode': mode,
          'p_policy_id': policyId,
          'p_deterministic_pricing': deterministic,
          'p_availability_reliable': reliable,
          'p_hold_duration_minutes': holdMinutes,
          'p_balance_deadline_configuration':
              current['balance_deadline_configuration'] ?? <String, dynamic>{},
          'p_fulfillment_configuration':
              current['fulfillment_configuration'] ?? <String, dynamic>{},
        },
      );
      setState(() => loading = true);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _delegateAsset(Map<String, dynamic> claim) async {
    if (verifiedAgents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isSwahili
                ? 'Hakuna agent aliyethibitishwa anayepatikana.'
                : 'No verified agent is available.',
          ),
        ),
      );
      return;
    }
    String agentId = verifiedAgents.first['id'].toString();
    final scopes = <String>{
      'bookings.manage',
      'availability.manage',
      'fulfillment.manage',
      'customers.communicate',
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            context.isSwahili ? 'Mruhusu agent' : 'Authorize an agent',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: agentId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.isSwahili ? 'Agent' : 'Agent',
                  ),
                  items: verifiedAgents
                      .map(
                        (agent) => DropdownMenuItem<String>(
                          value: agent['id'].toString(),
                          child: Text(
                            agent['business_name']?.toString().isNotEmpty ==
                                    true
                                ? agent['business_name'].toString()
                                : agent['display_name'].toString(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialog(() => agentId = value);
                  },
                ),
                const SizedBox(height: 12),
                for (final permission in const <(String, String)>[
                  ('bookings.manage', 'Bookings'),
                  ('availability.manage', 'Availability'),
                  ('fulfillment.manage', 'Fulfillment'),
                  ('customers.communicate', 'Customer communication'),
                ])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: scopes.contains(permission.$1),
                    title: Text(permission.$2),
                    onChanged: (value) => setDialog(() {
                      if (value == true) {
                        scopes.add(permission.$1);
                      } else {
                        scopes.remove(permission.$1);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.isSwahili ? 'Ghairi' : 'Cancel'),
            ),
            FilledButton(
              onPressed: scopes.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(context.isSwahili ? 'Ruhusu' : 'Authorize'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'grant_asset_agent_delegation',
        params: <String, dynamic>{
          'p_asset_id': claim['asset_id'],
          'p_agent_id': agentId,
          'p_scopes': scopes.toList(),
          'p_ends_at': null,
        },
      );
      setState(() => loading = true);
      await _load();
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _revokeDelegation(Map<String, dynamic> delegation) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.isSwahili ? 'Ondoa ruhusa' : 'Revoke access'),
        content: TextField(
          controller: reason,
          decoration: InputDecoration(
            labelText: context.isSwahili ? 'Sababu' : 'Reason',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.isSwahili ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.isSwahili ? 'Ondoa' : 'Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.text.trim().isEmpty || !mounted) {
      reason.dispose();
      return;
    }
    try {
      await Supabase.instance.client.rpc(
        'revoke_asset_agent_delegation',
        params: <String, dynamic>{
          'p_delegation_id': delegation['id'],
          'p_reason': reason.text.trim(),
        },
      );
      setState(() => loading = true);
      await _load();
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      reason.dispose();
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
      if (ownerBookingAgreement != null && !ownerBookingAgreementAccepted)
        _ownerBookingAgreementCard(),
      _list('My assets', assets),
      _agentDelegationControls(),
      _bookingControls(),
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

  Widget _ownerBookingAgreementCard() => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              ownerBookingAgreement!['title'].toString(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.isSwahili
                  ? 'Soma na ukubali makubaliano haya kabla ya kuwasha Instant Booking.'
                  : 'Review and accept this agreement before enabling Instant Booking.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _acceptOwnerBookingAgreement,
              child: Text(
                context.isSwahili ? 'Soma makubaliano' : 'Review agreement',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _bookingControls() => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.isSwahili ? 'Booking za mali zangu' : 'My asset bookings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              context.isSwahili
                  ? 'Chagua kama mali inapokea booking request au Instant Booking.'
                  : 'Choose whether each item accepts booking requests or Instant Booking.',
            ),
            const SizedBox(height: 12),
            if (bookableListings.isEmpty)
              Text(
                context.isSwahili
                    ? 'Hakuna listing iliyounganishwa na mali iliyothibitishwa.'
                    : 'No listing is connected to a verified asset.',
              )
            else
              ...bookableListings.map((listing) {
                final config = _bookingConfiguration(listing);
                final mode =
                    config['booking_mode']?.toString() ?? 'request_booking';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(listing['title'].toString()),
                  subtitle: Text(
                    '${mode.replaceAll('_', ' ')} · ${listing['approval_status']} · ${listing['status']}',
                  ),
                  trailing: OutlinedButton(
                    onPressed: () => _configureListingBooking(listing),
                    child: Text(context.isSwahili ? 'Badili' : 'Configure'),
                  ),
                );
              }),
          ],
        ),
      ),
    ),
  );

  Widget _agentDelegationControls() => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.isSwahili ? 'Ruhusa za agent' : 'Agent access',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              context.isSwahili
                  ? 'Agent anafanya kazi kwenye mali hii baada ya wewe kumpa ruhusa.'
                  : 'An agent can operate this asset only after you authorize them.',
            ),
            const SizedBox(height: 12),
            for (final claim in assets.where(
              (item) => item['status'] == 'verified',
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(
                  (claim['rental_assets'] as Map?)?['display_name']
                          ?.toString() ??
                      claim['asset_id'].toString(),
                ),
                trailing: OutlinedButton(
                  onPressed: () => _delegateAsset(claim),
                  child: Text(context.isSwahili ? 'Ruhusu' : 'Authorize'),
                ),
              ),
            if (agentDelegations.isNotEmpty) const Divider(),
            for (final delegation in agentDelegations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  (delegation['agents'] as Map?)?['business_name']
                              ?.toString()
                              .isNotEmpty ==
                          true
                      ? (delegation['agents'] as Map)['business_name']
                            .toString()
                      : (delegation['agents'] as Map?)?['display_name']
                                ?.toString() ??
                            'Agent',
                ),
                subtitle: Text(
                  '${delegation['status']} · ${(delegation['scopes'] as List? ?? const <dynamic>[]).join(', ')}',
                ),
                trailing: delegation['status'] == 'active'
                    ? TextButton(
                        onPressed: () => _revokeDelegation(delegation),
                        child: Text(context.isSwahili ? 'Ondoa' : 'Revoke'),
                      )
                    : null,
              ),
          ],
        ),
      ),
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
