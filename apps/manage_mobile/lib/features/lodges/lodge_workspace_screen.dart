import 'dart:async';
import 'package:flutter_core/lodge_photos.dart';
import 'package:flutter_core/listing_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_core/lodge_api.dart';
import 'package:flutter_core/lodge_form.dart';
import 'package:flutter_core/lodge_forms.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter_core/lodge_errors.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/media/listing_image_compressor.dart';

class LodgeWorkspaceScreen extends StatefulWidget {
  const LodgeWorkspaceScreen({
    super.key,
    this.lodgeId,
    this.section = 'dashboard',
    this.api,
  });
  final String? lodgeId;
  final String section;
  final LodgeApi? api;
  @override
  State<LodgeWorkspaceScreen> createState() => _LodgeWorkspaceScreenState();
}

class _LodgeWorkspaceScreenState extends State<LodgeWorkspaceScreen> {
  late final LodgeApi _api = widget.api ?? LodgeApi(Supabase.instance.client);
  LodgeRow _data = {};
  Map<String, String> _images = {};
  bool _loading = true, _busy = false;
  String? _error, _start, _end;
  int _offset = 0, _generation = 0;
  String _query = '', _roomType = '';
  StreamSubscription<AuthState>? _authSubscription;
  String? _lastUser;
  LodgeRow get _lodge =>
      Map<String, dynamic>.from(_data['lodge'] as Map? ?? {});
  List<LodgeRow> rows(String key) => (_data[key] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  bool can(String permission) =>
      ((_data['permissions'] as List? ?? []).contains('*') ||
      (_data['permissions'] as List? ?? []).contains(permission));
  @override
  void initState() {
    super.initState();
    _lastUser = _api.client.auth.currentUser?.id;
    _authSubscription = _api.client.auth.onAuthStateChange.listen((event) {
      final nextUser = event.session?.user.id;
      if (mounted && nextUser != _lastUser) {
        _lastUser = nextUser;
        _generation++;
        setState(() { _data = {}; _images = {}; });
        if (nextUser != null) _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LodgeWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.lodgeId != widget.lodgeId || old.section != widget.section) {
      _offset = 0;
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_generation;
    setState(() {
      _loading = true;
      _data = {};
      _images = {};
    });
    try {
      final data = await _api.workspace(
        lodgeId: widget.lodgeId,
        section: widget.section,
        start: _start,
        end: _end,
        offset: _offset,
        query: _query,
        roomType: _roomType,
      );
      final paths = <String>[];
      if (widget.section == 'rooms') {
        for (final room in (data['rows'] as List? ?? [])) {
          final photos = (room as Map)['photos'] as List? ?? [];
          if (photos.isNotEmpty) paths.add(photos.first.toString());
        }
      }
      if (widget.section == 'settings') {
        paths.addAll(
          ((data['lodge'] as Map?)?['photos'] as List? ?? []).cast<String>(),
        );
      }
      final images = await _api.images(paths);
      if (mounted && request == _generation) {
        setState(() {
          _images = images;
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _generation) {
        setState(
          () => _error = lodgeUserMessage(
            e,
            language: Localizations.localeOf(context).languageCode,
          ),
        );
      }
    } finally {
      if (mounted && request == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _command(String action, LodgeRow data, {String? lodgeId}) async {
    setState(() => _busy = true);
    try {
      await _api.command(lodgeId ?? widget.lodgeId!, action, data);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = lodgeUserMessage(
            e,
            language: Localizations.localeOf(context).languageCode,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<String>> _upload({bool single = false}) async {
    final singleFile = single
        ? await ImagePicker().pickImage(source: ImageSource.gallery)
        : null;
    final files = single
        ? (singleFile == null ? <XFile>[] : [singleFile])
        : await ImagePicker().pickMultiImage(limit: 20);
    final paths = <String>[];
    for (final file in files) {
      final compressed = await const ListingImageCompressor().compress(file);
      paths.add(
        await _api.uploadImage(widget.lodgeId!, await compressed.readAsBytes()),
      );
    }
    return paths;
  }

  Future<void> _edit(String action, [LodgeRow initial = const {}]) async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => LodgeFormScreen(
          api: _api,
          lodgeId: widget.lodgeId,
          action: action,
          initial: {...initial, 'lodge_timezone': _lodge['timezone']},
          uploadPhotos: widget.lodgeId == null
              ? null
              : () => _upload(single: action == 'save_room_type'),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (action == 'register' && result is String) {
      context.go('/lodges/$result/dashboard');
    } else {
      await _load();
    }
  }

  Widget button(String title, VoidCallback action) => OutlinedButton(
    onPressed: _busy ? null : action,
    child: LocalizedUiText(title),
  );
  Widget operation(String title, String action, LodgeRow data) =>
      button(title, () => _command(action, data));
  Widget _card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
  Future<void> _dates() async {
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDateRange: DateTimeRange(
        start:
            DateTime.tryParse(_start ?? _data['start']?.toString() ?? '') ??
            DateTime.now(),
        end:
            DateTime.tryParse(_end ?? _data['end']?.toString() ?? '') ??
            DateTime.now().add(const Duration(days: 30)),
      ),
    );
    if (value != null && mounted) {
      _start = value.start.toIso8601String().split('T').first;
      _end = value.end.toIso8601String().split('T').first;
      _offset = 0;
      await _load();
    }
  }

  List<Widget> _row(LodgeRow r) {
    final id = r['id'];
    switch (widget.section) {
      case 'room-types':
        return [
          LodgePhotoPreview(
            paths: r['main_image'] == null ? [] : [r['main_image'].toString()],
            api: _api,
          ),
          Text(
            r['name'].toString(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(r['description'].toString()),
          Text('${r['currency']} ${r['nightly_rate']}'),
          Text("${mobileUi(context, 'Active rooms')}: ${r['total_rooms']}"),
          Text(
            "${mobileUi(context, 'Occupied now')}: ${r['occupied_rooms']} / ${mobileUi(context, 'Ready now')}: ${r['ready_now']}",
          ),
          Text(
            "${mobileUi(context, 'Rooms available for selected dates')}: ${r['available_rooms']}",
          ),
          if (can('rooms.write'))
            button('Edit room type', () => _edit('save_room_type', r)),
        ];
      case 'rooms':
        return [
          if ((r['photos'] as List? ?? []).isNotEmpty &&
              _images[(r['photos'] as List).first] != null)
            SizedBox(
              height: 160,
              child: ListingImage(
                url: _images[(r['photos'] as List).first]!,
                cacheKey: (r['photos'] as List).first.toString(),
              ),
            ),
          Text(
            '${r['code']} / ${r['room_type']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '${r['currency']} ${r['nightly_rate']} / ${mobileUi(context, 'night')}',
          ),
          Text(
            '${r['beds']} / ${r['max_occupancy']} ${mobileUi(context, 'guests')}',
          ),
          LocalizedUiText(r['condition'].toString().replaceAll('_', ' ')),
          Text('${r['maintenance_notes'] ?? ''}'),
          Wrap(
            spacing: 8,
            children: [
              if (can('rooms.write'))
                button('Edit room', () => _edit('save_room', r)),
              if (can('rooms.write') || can('rooms.condition'))
                PopupMenuButton<String>(
                  enabled: r['condition'] != 'occupied',
                  onSelected: (value) => _command('room_condition', {
                    'id': id,
                    'condition': value,
                  }),
                  itemBuilder: (_) =>
                      ['ready', 'cleaning', 'maintenance', 'out_of_service']
                          .map(
                            (s) => PopupMenuItem(
                              value: s,
                              child: LocalizedUiText(s.replaceAll('_', ' ')),
                            ),
                          )
                          .toList(),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: LocalizedUiText('Set room condition'),
                  ),
                ),
            ],
          ),
        ];
      case 'calendar':
        return [
          Text(
            '${r['code']} / ${r['room_type']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          LocalizedUiText(r['condition'].toString().replaceAll('_', ' ')),
          for (final b in rows('stays').where((b) => b['room_id'] == id))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text('${b['arrival']} - ${b['departure']}'),
              subtitle: LocalizedUiText(
                b['status'].toString().replaceAll('_', ' '),
              ),
            ),
        ];
      case 'reservations':
        return [
          Text(
            '${r['code']} / ${r['full_name'] ?? mobileUi(context, 'Room block')}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('${r['arrival']} - ${r['departure']}'),
          LocalizedUiText(r['status'].toString().replaceAll('_', ' ')),
          LocalizedUiText(r['channel'].toString().replaceAll('_', ' ')),
          Text('${r['phone'] ?? ''}'),
          Text('${r['currency']} ${r['total_amount']}'),
          if (r['paid'] != null)
            Text(
              '${mobileUi(context, 'Outstanding balance')}: ${(num.tryParse('${r['total_amount']}') ?? 0) - (num.tryParse('${r['paid']}') ?? 0)}',
            ),
          Wrap(
            spacing: 8,
            children: [
              if (can('reservations.write')) ...[
                if ([
                  'pending',
                  'confirmed',
                  'blocked',
                ].contains(r['status'])) ...[
                  button(
                    'Modify reservation',
                    () => _edit('reservation_update', r),
                  ),
                  button('Cancel reservation', () => _edit('cancel', r)),
                ],
                if (r['status'] == 'confirmed')
                  operation('Check in', 'check_in', {'id': id}),
                if (r['status'] == 'checked_in')
                  operation('Check out', 'check_out', {'id': id}),
              ],
              if (can('payments.write') && r['status'] != 'blocked')
                button(
                  'Record lodge payment',
                  () => _edit('record_payment', {'reservation_id': id}),
                ),
            ],
          ),
        ];
      case 'guests':
        return [
          Text(
            '${r['full_name']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('${r['phone'] ?? ''}'),
          Text('${r['email'] ?? ''}'),
          if (can('guests.write'))
            button('Edit guest', () => _edit('save_guest', r)),
        ];
      case 'payments':
        return [
          Text(
            '${r['currency']} ${r['amount']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('${r['method']} / ${r['reference'] ?? ''}'),
          Text('${r['received_at']}'),
          Text('${mobileUi(context, 'Reservation')}: ${r['reservation_id']}'),
          if (r['reverses_id'] != null)
            Text('${mobileUi(context, 'Reversal')}: ${r['reason']}')
          else if (r['reversed'] == true)
            const LocalizedUiText('Reversed')
          else if (can('payments.reverse'))
            button('Reverse payment', () => _edit('reverse_payment', r)),
          if (can('payments.reverse') &&
              can('payments.write') &&
              r['reverses_id'] == null &&
              r['reversed'] != true)
            button('Correct payment', () => _edit('correct_payment', r)),
        ];
      case 'staff':
        return [
          Text(
            '${r['full_name']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          LocalizedUiText('${r['role']}'),
          LocalizedUiText(r['active'] == true ? 'Active' : 'Inactive'),
          Text(
            (r['permissions'] as List? ?? [])
                .map(
                  (p) => mobileUi(
                    context,
                    (lodgeDefinitions['permissionLabels'] as Map)[p]
                            ?.toString() ??
                        p.toString(),
                  ),
                )
                .join(', '),
          ),
          if (can('staff.manage') &&
              r['role'] != 'owner' &&
              r['active'] == true &&
              (r['role'] != 'manager' || can('*')))
            button('Change role and permissions', () => _edit('set_staff', r)),
          if (can('staff.manage') &&
              r['role'] != 'owner' &&
              r['active'] == true)
            operation('Remove access', 'remove_staff', {
              'profile_id': r['profile_id'],
            }),
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final stat = Map<String, dynamic>.from(_data['stats'] as Map? ?? {});
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.go(widget.lodgeId == null ? '/splash' : '/lodges'),
        ),
        title: LocalizedUiText(
          widget.lodgeId == null
              ? 'Lodge workspace'
              : section[0].toUpperCase() + section.substring(1),
        ),
        actions: [
          IconButton(
            tooltip: mobileUi(context, 'Refresh'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const KodimaliLoading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    _card([
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      button('Retry', _load),
                    ]),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LocalizedUiText(
                      'Reservations and payments are managed directly by the lodge. KODIMALI does not collect or verify these payments.',
                    ),
                  ),
                  if (widget.lodgeId == null) ...[
                    FilledButton.icon(
                      onPressed: () => _edit('register'),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const LocalizedUiText('Register a lodge'),
                    ),
                    for (final lodge in rows('lodges'))
                      Card(
                        child: ListTile(
                          title: Text('${lodge['name']}'),
                          subtitle: Text(
                            '${lodge['location_label']} / ${mobileUi(context, lodge['verification_status'].toString())}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.go('/lodges/${lodge['id']}/dashboard'),
                        ),
                      ),
                    for (final invitation in rows('invitations'))
                      _card([
                        Text(
                          '${invitation['name']} / ${mobileUi(context, invitation['role'].toString())}',
                        ),
                        button(
                          'Accept invitation',
                          () => _command(
                            'accept_invitation',
                            {'id': invitation['id']},
                            lodgeId: invitation['lodge_id'].toString(),
                          ),
                        ),
                      ]),
                    if (rows('lodges').isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: LocalizedUiText(
                          'Register your first lodge or accept an invitation below.',
                        ),
                      ),
                  ] else ...[
                    Text(
                      '${_lodge['name'] ?? ''}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final page in lodgeDefinitions['sections'] as List)
                          if ((lodgeDefinitions['sectionPermissions']
                                      as Map)[page] ==
                                  null ||
                              can(
                                (lodgeDefinitions['sectionPermissions']
                                        as Map)[page]
                                    as String,
                              ))
                            ChoiceChip(
                              label: LocalizedUiText(
                                page.toString()[0].toUpperCase() +
                                    page
                                        .toString()
                                        .substring(1)
                                        .replaceAll('-', ' '),
                              ),
                              selected: page == section,
                              onSelected: (_) =>
                                  context.go('/lodges/${widget.lodgeId}/$page'),
                            ),
                      ],
                    ),
                    if ([
                      'room-types',
                      'calendar',
                      'reservations',
                      'reports',
                      'dashboard',
                    ].contains(section))
                      button(
                        '${_data['start'] ?? ''} - ${_data['end'] ?? ''} / ${_lodge['timezone'] ?? ''}',
                        _dates,
                      ),
                    if ([
                          'rooms',
                          'calendar',
                          'reservations',
                        ].contains(section) &&
                        can('reservations.write'))
                      button('Block room dates', () => _edit('block_room')),
                    if ([
                      'rooms',
                      'calendar',
                      'reservations',
                      'guests',
                      'payments',
                    ].contains(section))
                      TextFormField(
                        initialValue: _query,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Search'),
                          suffixIcon: const Icon(Icons.search),
                        ),
                        onFieldSubmitted: (value) {
                          _query = value;
                          _offset = 0;
                          _load();
                        },
                      ),
                    if (['rooms', 'calendar'].contains(section))
                      TextFormField(
                        initialValue: _roomType,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Room type'),
                        ),
                        onFieldSubmitted: (value) {
                          _roomType = value;
                          _offset = 0;
                          _load();
                        },
                      ),
                    if (section == 'room-types' && can('rooms.write'))
                      button(
                        'Add room type',
                        () => _edit('save_room_type', {
                          'active': true,
                          'currency': 'TZS',
                          'max_occupancy': 2,
                        }),
                      ),
                    if (section == 'rooms' && can('rooms.write'))
                      button(
                        'Add room',
                        () => _edit('save_room', {
                          'active': true,
                          'currency': 'TZS',
                          'max_occupancy': 2,
                        }),
                      ),
                    if (section == 'reservations' && can('reservations.write'))
                      button(
                        'New reservation',
                        () => _edit('reserve', {
                          'guests': 1,
                          'status': 'confirmed',
                          'channel': 'walk_in',
                        }),
                      ),
                    if (section == 'payments' && can('payments.write'))
                      button(
                        'Record lodge payment',
                        () => _edit('record_payment'),
                      ),
                    if (section == 'staff' && can('staff.manage'))
                      button(
                        'Invite staff',
                        () => _edit('invite', {'role': 'receptionist'}),
                      ),
                    if (section == 'settings')
                      _card([
                        LodgePhotoPreview(
                          api: _api,
                          paths: (_lodge['photos'] as List? ?? [])
                              .cast<String>(),
                        ),
                        LocalizedUiText('${_lodge['verification_status']}'),
                        Text('${_lodge['location_label']}'),
                        Text('${_lodge['description']}'),
                        Text('${_lodge['phone']}'),
                        Text('${_lodge['timezone']}'),
                        if (can('settings.write'))
                          button(
                            'Edit lodge settings',
                            () => _edit('settings', _lodge),
                          ),
                        if (_data['super_admin'] == true) ...[
                          operation('Approve publication', 'review', {
                            'approved': true,
                            'notes': 'Reviewed lodge application',
                          }),
                          operation('Withdraw publication', 'review', {
                            'approved': false,
                            'notes': 'Publication withdrawn after review',
                          }),
                        ],
                      ]),
                    for (final entry in stat.entries)
                      _card([
                        LocalizedUiText(entry.key.replaceAll('_', ' ')),
                        Text(
                          '${entry.value}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ]),
                    for (final key in ['arrivals', 'departures', 'pending'])
                      if (_data.containsKey(key))
                        _card([
                          LocalizedUiText(key),
                          Text(
                            '${_data[key]}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ]),
                    if (_data.containsKey('capacity_room_nights'))
                      _card([
                        const LocalizedUiText('Occupancy'),
                        Text(
                          '${(num.tryParse('${_data['capacity_room_nights']}') ?? 0) > 0 ? (100 * (num.tryParse('${_data['occupied_room_nights']}') ?? 0) / (num.tryParse('${_data['capacity_room_nights']}') ?? 1)).toStringAsFixed(1) : 0}%',
                        ),
                        Text(
                          '${_data['occupied_room_nights']} / ${_data['capacity_room_nights']} ${mobileUi(context, 'room nights')}',
                        ),
                      ]),
                    for (final row in rows('revenue'))
                      _card([
                        const LocalizedUiText('Net lodge payments recorded'),
                        Text('${row['currency']} ${row['net_recorded']}'),
                      ]),
                    for (final row in rows('rows')) _card(_row(row)),
                    if (section == 'reservations')
                      for (final row in rows('enquiries'))
                        _card([
                          const LocalizedUiText('Reservation enquiry'),
                          Text('${row['arrival']} - ${row['departure']}'),
                          Text('${row['message']}'),
                          Text('${row['contact_phone']}'),
                          if (can('reservations.write'))
                            Wrap(
                              spacing: 6,
                              children: [
                                if (row['reservation_id'] == null)
                                  operation(
                                    'Confirm and allocate room',
                                    'confirm_enquiry',
                                    {'id': row['id']},
                                  ),
                                operation('Mark contacted', 'enquiry_status', {
                                  'id': row['id'],
                                  'status': 'contacted',
                                }),
                                operation('Close enquiry', 'enquiry_status', {
                                  'id': row['id'],
                                  'status': 'closed',
                                }),
                              ],
                            ),
                        ]),
                    if (section == 'staff') ...[
                      for (final row in rows('invitations'))
                        _card([
                          Text(
                            '${row['email']} / ${mobileUi(context, row['role'].toString())}',
                          ),
                          if (can('staff.manage'))
                            operation(
                              'Revoke invitation',
                              'revoke_invitation',
                              {'id': row['id']},
                            ),
                        ]),
                      for (final row in rows('applications'))
                        _card([
                          Text('${row['notes']}'),
                          if (can('staff.manage')) ...[
                            operation(
                              'Approve management application',
                              'review_access',
                              {'id': row['id'], 'approved': true},
                            ),
                            operation('Reject application', 'review_access', {
                              'id': row['id'],
                              'approved': false,
                            }),
                          ],
                        ]),
                    ],
                    if (_data.containsKey('total'))
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _offset == 0
                                ? null
                                : () {
                                    _offset = (_offset - 30).clamp(0, 1 << 30);
                                    _load();
                                  },
                            child: const LocalizedUiText('Previous'),
                          ),
                          Text(
                            '${(_data['total'] as num) > 0 ? _offset + 1 : 0}-${(_offset + 30).clamp(0, (_data['total'] as num).toInt())} / ${_data['total']}',
                          ),
                          TextButton(
                            onPressed: _offset + 30 >= (_data['total'] as num)
                                ? null
                                : () {
                                    _offset += 30;
                                    _load();
                                  },
                            child: const LocalizedUiText('Next'),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
