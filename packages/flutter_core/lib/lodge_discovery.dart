import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:url_launcher/url_launcher.dart';
import 'lodge_api.dart';
import 'lodge_form.dart';
import 'listing_media.dart';
import 'localized_ui.dart';
import 'lodge_errors.dart';

class LodgeDiscoveryScreen extends StatefulWidget {
  const LodgeDiscoveryScreen({super.key, required this.api, this.lodgeId});
  final LodgeApi api;
  final String? lodgeId;
  @override
  State<LodgeDiscoveryScreen> createState() => _LodgeDiscoveryScreenState();
}

class _LodgeDiscoveryScreenState extends State<LodgeDiscoveryScreen> {
  final _search = TextEditingController();
  List<LodgeRow> _rows = [], _requests = [];
  StreamSubscription<dynamic>? _authSubscription;
  Map<String, String> _images = {};
  bool _loading = true;
  String? _error, _location, _arrival, _departure;
  int _offset = 0, _total = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
    _authSubscription = widget.api.client.auth.onAuthStateChange.listen((_) {
      if (mounted) {
        setState(() => _requests = []);
        _load();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_generation;
    setState(() {
      _loading = true;
      _rows = [];
      _images = {};
    });
    try {
      final data = await widget.api.discover(
        id: widget.lodgeId,
        search: _search.text,
        locationId: _location,
        arrival: _arrival,
        departure: _departure,
        offset: _offset,
      );
      final rows = (data['rows'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final requests =
          widget.lodgeId != null && widget.api.client.auth.currentUser != null
          ? await widget.api.myRequests(widget.lodgeId!)
          : <LodgeRow>[];
      final images = await widget.api.images(
        rows
            .expand(
              (r) => [
                ...(r['photos'] as List? ?? []).cast<String>(),
                for (final t in (r['room_types'] as List? ?? []))
                  if ((t as Map)['main_image'] != null)
                    t['main_image'].toString(),
              ],
            )
            .toList(),
      );
      if (mounted && request == _generation) {
        setState(() {
          _rows = rows;
          _requests = requests;
          _images = images;
          _total = (data['total'] as num).toInt();
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

  Future<void> _edit(String lodge, String action, {String? roomType}) async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => LodgeFormScreen(
          api: widget.api,
          action: action,
          lodgeId: lodge,
          initial: {
            'arrival': _arrival,
            'departure': _departure,
            'guests': 1,
            'room_type_id': roomType,
          },
        ),
      ),
    );
    if (result != null && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedUiText(
            action == 'enquire'
                ? 'Enquiry sent. The lodge confirms directly.'
                : 'Application submitted for lodge-owner review.',
          ),
        ),
      );
    }
  }

  Future<void> _dates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (range != null) {
      _arrival = range.start.toIso8601String().split('T').first;
      _departure = range.end.toIso8601String().split('T').first;
      _offset = 0;
      await _load();
    }
  }

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedUiText('Could not open this link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedUiText('Lodges & Guesthouses')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const LocalizedUiText(
            'Browse anywhere. Contact the lodge directly to arrange your stay and payment.',
          ),
          if (widget.lodgeId == null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: mobileUi(
                  context,
                  'Search by lodge, location or facilities',
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    _offset = 0;
                    _load();
                  },
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) {
                _offset = 0;
                _load();
              },
            ),
            LodgeLocationSearch(
              api: widget.api,
              onSelected: (id, label) {
                _location = id;
                _offset = 0;
                _load();
              },
            ),
          ],
          OutlinedButton.icon(
            onPressed: _dates,
            icon: const Icon(Icons.date_range),
            label: LocalizedUiText(
              _arrival == null
                  ? 'Choose stay dates'
                  : '$_arrival - $_departure',
            ),
          ),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const LocalizedUiText('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading)
            const SizedBox(height: 120, child: KodimaliLoading())
          else if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: LocalizedUiText('No published lodges match this search.'),
            )
          else
            for (final lodge in _rows)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if ((lodge['photos'] as List? ?? []).isNotEmpty)
                      SizedBox(
                        height: widget.lodgeId == null
                            ? 224
                            : MediaQuery.sizeOf(context).width * 1.2,
                        child: PageView(
                          children: [
                            for (final path in (lodge['photos'] as List).take(
                              widget.lodgeId == null ? 1 : 20,
                            ))
                              if (_images[path] != null)
                                ListingImage(
                                  url: _images[path]!,
                                  cacheKey: path.toString(),
                                ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${lodge['name']}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text('${lodge['location_label']}'),
                          const LocalizedUiText('Verified lodge'),
                          if (widget.lodgeId != null)
                            Text('${lodge['description']}'),
                          Text(
                            (lodge['facilities'] as List? ?? []).join(' · '),
                          ),
                          for (final room
                              in (lodge['room_types'] as List? ?? [])
                                  .cast<Map>())
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.lodgeId != null)
                                    Semantics(
                                      label:
                                          '${room['room_type']} representative photograph',
                                      image: true,
                                      child: AspectRatio(
                                        aspectRatio: 4 / 3,
                                        child:
                                            room['main_image'] != null &&
                                                _images[room['main_image']] !=
                                                    null
                                            ? ListingImage(
                                                url:
                                                    _images[room['main_image']]!,
                                                cacheKey: room['main_image']
                                                    .toString(),
                                                fit: BoxFit.cover,
                                              )
                                            : const ColoredBox(
                                                color: Color(0xffeef5f2),
                                                child: Center(
                                                  child: LocalizedUiText(
                                                    'No authorized photograph available',
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                  if (widget.lodgeId != null)
                                    const LocalizedUiText(
                                      'Representative room-type photograph; the assigned room may differ.',
                                    ),
                                  Text(
                                    '${room['room_type']}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    '${room['currency']} ${room['from_price']} / ${mobileUi(context, 'night')}',
                                  ),
                                  Text(
                                    '${mobileUi(context, 'Up to')} ${room['max_occupancy']} ${mobileUi(context, 'guests')}',
                                  ),
                                  if (widget.lodgeId != null)
                                    Text('${room['description'] ?? ''}'),
                                  if (widget.lodgeId != null)
                                    Text(
                                      (room['facilities'] as List? ?? []).join(
                                        ' · ',
                                      ),
                                    ),
                                  if (widget.lodgeId != null)
                                    FilledButton(
                                      onPressed: () => _edit(
                                        lodge['id'].toString(),
                                        'enquire',
                                        roomType: room['id'].toString(),
                                      ),
                                      child: const LocalizedUiText(
                                        'Request reservation',
                                      ),
                                    ),
                                  room['available_rooms'] == null
                                      ? const LocalizedUiText(
                                          'Ask the lodge to confirm availability.',
                                        )
                                      : Text(
                                          '${mobileUi(context, 'Rooms available for selected dates')}: ${room['available_rooms']}',
                                        ),
                                ],
                              ),
                            ),
                          if (_arrival != null &&
                              lodge['publish_availability'] == true)
                            const LocalizedUiText(
                              'Availability checked against lodge reservations. It may change before confirmation.',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (widget.lodgeId == null)
                                FilledButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => LodgeDiscoveryScreen(
                                        api: widget.api,
                                        lodgeId: lodge['id'].toString(),
                                      ),
                                    ),
                                  ),
                                  child: const LocalizedUiText('View lodge'),
                                ),
                              if (lodge['phone'] != null)
                                OutlinedButton(
                                  onPressed: () => _launch(
                                    Uri(
                                      scheme: 'tel',
                                      path: lodge['phone'].toString(),
                                    ),
                                  ),
                                  child: Text('${lodge['phone']}'),
                                ),
                              if (lodge['phone'] != null)
                                OutlinedButton(
                                  onPressed: () {
                                    var phone = lodge['phone']
                                        .toString()
                                        .replaceAll(RegExp(r'\D'), '');
                                    if (phone.startsWith('0')) {
                                      phone = '255${phone.substring(1)}';
                                    }
                                    _launch(Uri.https('wa.me', '/$phone'));
                                  },
                                  child: const Text('WhatsApp'),
                                ),
                            ],
                          ),
                          if (widget.lodgeId != null) ...[
                            for (final stat
                                in (lodge['room_counts'] as Map? ?? {}).entries
                                    .where((s) => s.value != null))
                              Text(
                                "${mobileUi(context, const {'total_active': 'Active rooms', 'occupied': 'Occupied now', 'ready_now': 'Ready now', 'cleaning': 'Cleaning', 'maintenance': 'Maintenance', 'selected_dates_available': 'Rooms available for selected dates'}[stat.key] ?? stat.key.toString())}: ${stat.value}",
                              ),
                            const LocalizedUiText('Check-in policy'),
                            Text('${lodge['check_in_policy'] ?? ''}'),
                            const LocalizedUiText('Check-out policy'),
                            Text('${lodge['check_out_policy'] ?? ''}'),
                          ],
                          if (widget.lodgeId != null) ...[
                            const LocalizedUiText(
                              'Sign in to send an enquiry. The lodge confirms your reservation directly; no KODIMALI checkout is required.',
                            ),
                            FilledButton(
                              onPressed: () =>
                                  _edit(lodge['id'].toString(), 'enquire'),
                              child: const LocalizedUiText(
                                'Send a reservation enquiry',
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _edit(lodge['id'].toString(), 'apply_access'),
                              child: const LocalizedUiText(
                                'Apply to manage this lodge',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          if (widget.lodgeId != null) ...[
            for (final request in _requests)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${request['room_type']}'),
                      Text('${request['arrival']} — ${request['departure']}'),
                      LocalizedUiText(
                        request['confirmed'] == true
                            ? 'Reservation confirmed'
                            : 'Awaiting lodge confirmation',
                      ),
                      Text(request['status'].toString()),
                    ],
                  ),
                ),
              ),
            if (_requests.isNotEmpty)
              TextButton(
                onPressed: _load,
                child: const LocalizedUiText('Refresh requests'),
              ),
          ],
          if (widget.lodgeId == null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _offset == 0
                      ? null
                      : () {
                          _offset = (_offset - 20).clamp(0, 1 << 30);
                          _load();
                        },
                  child: const LocalizedUiText('Previous'),
                ),
                Text('${_total > 0 ? _offset + 1 : 0} / $_total'),
                TextButton(
                  onPressed: _offset + 20 >= _total
                      ? null
                      : () {
                          _offset += 20;
                          _load();
                        },
                  child: const LocalizedUiText('Next'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
