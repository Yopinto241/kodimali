import '../../app.dart' show CustomerSponsoredCards;
import 'package:flutter_core/localized_ui.dart';
// Advisor widgets remain unreachable only to preserve source compatibility with
// historical plans while the customer-facing entry points are removed.
// ignore_for_file: unused_element_parameter

import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'event_ui.dart';

import '../../core/data/customer_public_repository.dart';
import '../../core/ads/sponsored_layout.dart';
import '../../core/localization/customer_localization.dart';
import 'event_location_picker.dart';
import 'event_recovery_controls.dart';

class EventsMarketplaceScreen extends StatefulWidget {
  const EventsMarketplaceScreen({
    super.key,
    required this.repository,
    this.initialRegionId,
    this.initialDistrictId,
    this.initialWardId,
    this.initialAreaId,
  });
  final CustomerPublicRepository repository;
  final String? initialRegionId;
  final String? initialDistrictId;
  final String? initialWardId;
  final String? initialAreaId;

  @override
  State<EventsMarketplaceScreen> createState() =>
      _EventsMarketplaceScreenState();
}

class _EventsMarketplaceScreenState extends State<EventsMarketplaceScreen> {
  late Future<JsonMap> _future;
  late Future<List<JsonMap>> _adsFuture;
  late EventLocationSelection _adLocation;
  Future<List<JsonMap>> _loadAds() => widget.repository.fetchPromotions(
    surface: 'customer_app',
    placement: 'category_page',
    categorySlug: 'events',
    regionId: _adLocation.regionId,
    districtId: _adLocation.districtId,
    wardId: _adLocation.wardId,
    areaId: _adLocation.areaId,
  );
  String _categoryKey = 'all';
  int _offset = 0;
  int _generation = 0;
  bool _loadingMore = false;
  String _search = '';
  Timer? _filterTimer;
  void _scheduleFilters() {
    _filterTimer?.cancel();
    _filterTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if ((_minPrice ?? 0) < 0 ||
          (_maxPrice ?? 0) < 0 ||
          (_minPrice != null && _maxPrice != null && _minPrice! > _maxPrice!)) {
        return;
      }
      _reload();
    });
  }

  @override
  void dispose() {
    _filterTimer?.cancel();
    super.dispose();
  }

  String? _browseLocation;
  String _browseLocationLabel = '';
  num? _minPrice, _maxPrice;
  String _sort = 'recommended';
  DateTime? _browseStart, _browseEnd;
  Future<void> _pickBrowseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 1095)),
    );
    if (range == null || !mounted) return;
    final startTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (startTime == null || !mounted) return;
    final endTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (endTime == null || !mounted) return;
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
      startTime.hour,
      startTime.minute,
    );
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      endTime.hour,
      endTime.minute,
    );
    if (!start.isAfter(DateTime.now()) || !end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isSwahili
                ? mobileUi(context, 'Chagua muda sahihi wa baadaye.')
                : mobileUi(context, 'Choose a valid future start and end.'),
          ),
        ),
      );
      return;
    }
    setState(() {
      _browseStart = start;
      _browseEnd = end;
    });
    await _reload();
  }

  @override
  void initState() {
    super.initState();
    _adLocation = EventLocationSelection(
      regionId: widget.initialRegionId,
      districtId: widget.initialDistrictId,
      wardId: widget.initialWardId,
      areaId: widget.initialAreaId,
      label: '',
    );
    _adsFuture = _loadAds();
    _browseLocation =
        widget.initialAreaId ??
        widget.initialWardId ??
        widget.initialDistrictId ??
        widget.initialRegionId;
    _future = widget.repository.fetchEventsMarketplace(
      locationId:
          widget.initialAreaId ??
          widget.initialWardId ??
          widget.initialDistrictId ??
          widget.initialRegionId,
    );
  }

  Future<void> _reload() async {
    _adsFuture = _loadAds();
    _offset = 0;
    _generation++;
    final next = widget.repository.fetchEventsMarketplace(
      locationId: _browseLocation,
      search: _search.isEmpty ? null : _search,
      categoryId: _categoryKey.startsWith('equipment:')
          ? _categoryKey.substring(10)
          : null,
      providerKind: _categoryKey.startsWith('service:')
          ? _categoryKey.substring(8)
          : null,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      sort: _sort,
      startsAt: _browseStart,
      endsAt: _browseEnd,
    );
    setState(() => _future = next);
    await next;
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final generation = _generation;
    try {
      final previous = await _future;
      final next = await widget.repository.fetchEventsMarketplace(
        locationId: _browseLocation,
        search: _search.isEmpty ? null : _search,
        categoryId: _categoryKey.startsWith('equipment:')
            ? _categoryKey.substring(10)
            : null,
        providerKind: _categoryKey.startsWith('service:')
            ? _categoryKey.substring(8)
            : null,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        sort: _sort,
        startsAt: _browseStart,
        endsAt: _browseEnd,
        offset: _offset + 30,
      );
      if (!mounted) return;
      if (generation != _generation) return;
      _offset += 30;
      setState(
        () => _future = Future.value({
          ...next,
          'equipment': [
            ...(previous['equipment'] as List),
            ...(next['equipment'] as List),
          ],
          'services': [
            ...(previous['services'] as List),
            ...(next['services'] as List),
          ],
        }),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedUiText('Events'),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _IndividualBookingsHistoryScreen(
                  repository: widget.repository,
                ),
              ),
            ),
            icon: const Icon(Icons.event_note_outlined),
            tooltip: sw ? 'Booking za vifaa na huduma' : 'Individual bookings',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    _MyEventPlansScreen(repository: widget.repository),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: sw ? 'Mipango yangu' : 'My event plans',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPlanner(sw),
        icon: const Icon(Icons.event_available_outlined),
        label: Text(
          sw
              ? mobileUi(context, 'Panga tukio')
              : mobileUi(context, 'Plan event'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<JsonMap>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: <Widget>[
                  Text(
                    sw
                        ? mobileUi(context, 'Imeshindwa kupakia matukio.')
                        : mobileUi(context, 'Could not load events.'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _reload,
                    child: Text(
                      sw
                          ? mobileUi(context, 'Jaribu tena')
                          : mobileUi(context, 'Retry'),
                    ),
                  ),
                ],
              );
            }
            final data = snapshot.data ?? <String, dynamic>{};
            final types = (data['types'] as List? ?? const <dynamic>[])
                .cast<JsonMap>();
            final equipment = (data['equipment'] as List? ?? const <dynamic>[])
                .cast<JsonMap>();
            final services = (data['services'] as List? ?? const <dynamic>[])
                .cast<JsonMap>();
            final categoryRows = {
              for (final c
                  in (data['categories'] as List? ?? []).cast<JsonMap>())
                c['id'].toString(): c,
            };
            final visibleEquipment = _categoryKey == 'all'
                ? equipment
                : _categoryKey.startsWith('equipment:')
                ? equipment
                      .where(
                        (item) =>
                            item['category_id'].toString() ==
                            _categoryKey.substring(10),
                      )
                      .toList()
                : <JsonMap>[];
            final visibleServices =
                _categoryKey == 'all' || _categoryKey == 'professionals'
                ? services
                : _categoryKey.startsWith('service:')
                ? services
                      .where(
                        (item) =>
                            item['provider_kind'] == _categoryKey.substring(8),
                      )
                      .toList()
                : <JsonMap>[];
            return FutureBuilder<List<JsonMap>>(
              future: _adsFuture,
              builder: (context, adSnapshot) {
                final adLayout = sponsoredLayout(
                  adSnapshot.data ?? const [],
                  visibleEquipment.length + visibleServices.length,
                );
                Widget adAfter(int index) {
                  if ((index + 1) % listingsPerSponsoredCard != 0) {
                    return const SizedBox.shrink();
                  }
                  final slot = index ~/ listingsPerSponsoredCard;
                  if (slot >= adLayout.inline.length) {
                    return const SizedBox.shrink();
                  }
                  return CustomerSponsoredCards(
                    promotions: [adLayout.inline[slot]],
                    inline: true,
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFF075B35), Color(0xFF087443)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          LocalizedUiText(
                            'KODIMALI EVENTS',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            sw
                                ? mobileUi(
                                    context,
                                    'Panga sherehe yako, sehemu moja.',
                                  )
                                : mobileUi(
                                    context,
                                    'Plan your event in one place.',
                                  ),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            sw
                                ? mobileUi(
                                    context,
                                    'Vifaa, wataalamu na quotation moja iliyo wazi.',
                                  )
                                : mobileUi(
                                    context,
                                    'Equipment, professionals and one clear quotation.',
                                  ),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      decoration: InputDecoration(
                        labelText: sw
                            ? mobileUi(context, 'Tafuta vifaa au huduma')
                            : mobileUi(context, 'Search equipment or services'),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _reload,
                        ),
                      ),
                      onChanged: (value) {
                        _search = value;
                        _scheduleFilters();
                      },
                      onSubmitted: (_) => _reload(),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _browseLocation == null
                              ? (sw
                                    ? mobileUi(context, 'Maeneo yote')
                                    : mobileUi(context, 'All locations'))
                              : _browseLocationLabel.isEmpty
                              ? (sw
                                    ? mobileUi(
                                        context,
                                        'Eneo la akaunti limetumika',
                                      )
                                    : mobileUi(
                                        context,
                                        'Account location applied',
                                      ))
                              : _browseLocationLabel,
                        ),
                        TextButton(
                          onPressed: () async {
                            final value = await Navigator.of(context)
                                .push<EventLocationSelection>(
                                  MaterialPageRoute(
                                    builder: (_) => EventLocationPicker(
                                      repository: widget.repository,
                                      swahili: sw,
                                    ),
                                  ),
                                );
                            if (value != null && mounted) {
                              setState(() {
                                _adLocation = value;
                                _browseLocation = value.locationId;
                                _browseLocationLabel = value.label;
                              });
                              await _reload();
                            }
                          },
                          child: Text(
                            sw
                                ? mobileUi(context, 'Badili eneo')
                                : mobileUi(context, 'Change location'),
                          ),
                        ),
                        if (_browseLocation != null)
                          IconButton(
                            tooltip: sw ? 'Maeneo yote' : 'All locations',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _adLocation = const EventLocationSelection(
                                  label: '',
                                );
                                _browseLocation = null;
                                _browseLocationLabel = '';
                              });
                              _reload();
                            },
                          ),
                      ],
                    ),
                    ExpansionTile(
                      title: Text(
                        sw
                            ? mobileUi(context, 'Vichujio: bei na tarehe')
                            : mobileUi(context, 'Filters: price and dates'),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      decoration: InputDecoration(
                                        labelText: sw
                                            ? mobileUi(
                                                context,
                                                'Bei ya chini (TZS)',
                                              )
                                            : mobileUi(
                                                context,
                                                'Minimum price (TZS)',
                                              ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) {
                                        _minPrice = num.tryParse(v);
                                        _scheduleFilters();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      decoration: InputDecoration(
                                        labelText: sw
                                            ? mobileUi(
                                                context,
                                                'Bei ya juu (TZS)',
                                              )
                                            : mobileUi(
                                                context,
                                                'Maximum price (TZS)',
                                              ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) {
                                        _maxPrice = num.tryParse(v);
                                        _scheduleFilters();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              DropdownButtonFormField<String>(
                                initialValue: _sort,
                                decoration: InputDecoration(
                                  labelText: sw
                                      ? mobileUi(context, 'Panga matokeo')
                                      : mobileUi(context, 'Sort results'),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'recommended',
                                    child: Text(
                                      sw
                                          ? mobileUi(
                                              context,
                                              'Zilizopendekezwa',
                                            )
                                          : mobileUi(context, 'Recommended'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'newest',
                                    child: Text(
                                      sw
                                          ? mobileUi(context, 'Mpya')
                                          : mobileUi(context, 'Newest'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'price_low',
                                    child: Text(
                                      sw
                                          ? mobileUi(
                                              context,
                                              'Bei ndogo kwanza',
                                            )
                                          : mobileUi(context, 'Lowest price'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'price_high',
                                    child: Text(
                                      sw
                                          ? mobileUi(
                                              context,
                                              'Bei kubwa kwanza',
                                            )
                                          : mobileUi(context, 'Highest price'),
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    _sort = v;
                                    _scheduleFilters();
                                  }
                                },
                              ),
                              TextButton.icon(
                                onPressed: _pickBrowseDates,
                                icon: const Icon(Icons.date_range),
                                label: Text(
                                  _browseStart == null
                                      ? (sw
                                            ? mobileUi(
                                                context,
                                                'Chagua tarehe na saa',
                                              )
                                            : mobileUi(
                                                context,
                                                'Choose dates and times',
                                              ))
                                      : '${eventDateLabel(context, _browseStart!)} - ${eventDateLabel(context, _browseEnd!)}',
                                ),
                              ),
                              if (_browseStart != null)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _browseStart = null;
                                      _browseEnd = null;
                                    });
                                    _reload();
                                  },
                                  child: Text(
                                    sw
                                        ? mobileUi(context, 'Ondoa tarehe')
                                        : mobileUi(context, 'Clear dates'),
                                  ),
                                ),
                              FilledButton(
                                onPressed: () {
                                  if ((_minPrice ?? 0) < 0 ||
                                      (_maxPrice ?? 0) < 0 ||
                                      (_minPrice != null &&
                                          _maxPrice != null &&
                                          _minPrice! > _maxPrice!)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          sw
                                              ? mobileUi(
                                                  context,
                                                  'Kagua kiwango cha bei.',
                                                )
                                              : mobileUi(
                                                  context,
                                                  'Check the price range.',
                                                ),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  _reload();
                                },
                                child: Text(
                                  sw
                                      ? mobileUi(context, 'Tumia vichujio')
                                      : mobileUi(context, 'Apply filters'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                sw
                                    ? mobileUi(context, 'Vyote')
                                    : mobileUi(context, 'All'),
                              ),
                              selected: _categoryKey == 'all',
                              onSelected: (_) {
                                setState(() => _categoryKey = 'all');
                                _reload();
                              },
                            ),
                          ),
                          ...categoryRows.entries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  (sw
                                          ? entry.value['name_sw']
                                          : entry.value['name_en'])
                                      .toString(),
                                ),
                                selected:
                                    _categoryKey == 'equipment:${entry.key}',
                                onSelected: (_) {
                                  setState(
                                    () =>
                                        _categoryKey = 'equipment:${entry.key}',
                                  );
                                  _reload();
                                },
                              ),
                            ),
                          ),
                          ChoiceChip(
                            label: Text(
                              sw
                                  ? mobileUi(context, 'Wataalamu')
                                  : mobileUi(context, 'Professionals'),
                            ),
                            selected: _categoryKey == 'professionals',
                            onSelected: (_) {
                              setState(() => _categoryKey = 'professionals');
                              _reload();
                            },
                          ),
                          ...services
                              .map((i) => i['provider_kind'].toString())
                              .toSet()
                              .map(
                                (kind) => Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: ChoiceChip(
                                    label: Text(eventServiceLabel(kind, sw)),
                                    selected: _categoryKey == 'service:$kind',
                                    onSelected: (_) {
                                      setState(
                                        () => _categoryKey = 'service:$kind',
                                      );
                                      _reload();
                                    },
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                    _title(sw ? 'Aina ya tukio' : 'Event types'),
                    SizedBox(
                      height: 108,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: types.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 10),
                        itemBuilder: (_, i) => SizedBox(
                          width: 190,
                          child: Card(
                            child: InkWell(
                              onTap: () => _openPlanner(
                                sw,
                                initialTypeId: types[i]['id'].toString(),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  (sw
                                          ? types[i]['name_sw']
                                          : types[i]['name_en'])
                                      .toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_categoryKey != 'professionals' &&
                        !_categoryKey.startsWith('service:'))
                      _title(sw ? 'Vifaa vya kukodisha' : 'Equipment for rent'),
                    if (_categoryKey != 'professionals' &&
                        !_categoryKey.startsWith('service:') &&
                        visibleEquipment.isEmpty)
                      Text(
                        sw
                            ? mobileUi(
                                context,
                                'Hakuna vifaa vinavyolingana. Badili kundi au eneo.',
                              )
                            : mobileUi(
                                context,
                                'No matching equipment. Change category or location.',
                              ),
                      ),
                    ...visibleEquipment.asMap().entries.map((entry) {
                      final item = entry.value;
                      return Column(
                        children: [
                          Card(
                            child: ListTile(
                              leading: EventThumbnail(
                                repository: widget.repository,
                                item: item,
                              ),
                              title: Text(item['name'].toString()),
                              subtitle: Text(
                                '${eventPriceLabel(item, sw)}\n${_browseStart == null ? (sw ? mobileUi(context, 'Jumla ya vifaa') : mobileUi(context, 'Total quantity')) : (sw ? mobileUi(context, 'Inayopatikana') : mobileUi(context, 'Available quantity'))}: ${_browseStart == null ? item['total_quantity'] : item['available_quantity']}',
                              ),
                              isThreeLine: true,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _IndividualEventDetailScreen(
                                    repository: widget.repository,
                                    kind: 'equipment',
                                    id: item['id'].toString(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          adAfter(entry.key),
                        ],
                      );
                    }),
                    if (!_categoryKey.startsWith('equipment:'))
                      _title(
                        sw ? 'Wataalamu wa matukio' : 'Event professionals',
                      ),
                    if (!_categoryKey.startsWith('equipment:') &&
                        visibleServices.isEmpty)
                      Text(
                        sw
                            ? mobileUi(
                                context,
                                'Hakuna wataalamu waliothibitishwa kwa sasa.',
                              )
                            : mobileUi(
                                context,
                                'No verified professionals yet.',
                              ),
                      )
                    else
                      ...visibleServices.asMap().entries.map((entry) {
                        final item = entry.value;
                        return Column(
                          children: [
                            Card(
                              child: ListTile(
                                leading: EventThumbnail(
                                  repository: widget.repository,
                                  item: item,
                                ),
                                title: Text(
                                  (item['title'] ?? item['display_name'])
                                      .toString(),
                                ),
                                subtitle: Text(
                                  '${item['display_name']} / ${eventServiceLabel(item['provider_kind'], sw)}\n${eventPriceLabel(item, sw)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: item['offering_id'] == null
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              _IndividualEventDetailScreen(
                                                repository: widget.repository,
                                                kind: 'service',
                                                id: item['offering_id']
                                                    .toString(),
                                              ),
                                        ),
                                      ),
                              ),
                            ),
                            adAfter(visibleEquipment.length + entry.key),
                          ],
                        );
                      }),
                    CustomerSponsoredCards(promotions: adLayout.remaining),
                    if (data['has_more'] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: OutlinedButton(
                          onPressed: _loadingMore ? null : _loadMore,
                          child: Text(
                            _loadingMore
                                ? (sw
                                      ? mobileUi(context, 'Inapakia...')
                                      : mobileUi(context, 'Loading...'))
                                : (sw
                                      ? mobileUi(context, 'Onyesha zaidi')
                                      : mobileUi(context, 'Load more')),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _title(String value) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      value,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  Future<void> _openPlanner(bool sw, {String? initialTypeId}) async {
    JsonMap marketplace;
    try {
      marketplace = await _future;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final types = (marketplace['types'] as List? ?? const <dynamic>[])
        .cast<JsonMap>();
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sw
                ? mobileUi(
                    context,
                    'Hakuna aina za tukio. Jaribu tena baadaye.',
                  )
                : mobileUi(
                    context,
                    'Event types are unavailable. Please retry later.',
                  ),
          ),
        ),
      );
      return;
    }
    String typeId = initialTypeId ?? types.first['id'].toString();
    final title = TextEditingController();
    final location = TextEditingController();
    EventLocationSelection? selectedLocation;
    DateTime start = DateTime.now().add(const Duration(days: 7));
    DateTime end = start.add(const Duration(hours: 5));
    final preferences = await SharedPreferences.getInstance();
    try {
      final saved =
          jsonDecode(preferences.getString('event-details-draft') ?? '{}')
              as Map<String, dynamic>;
      title.text = saved['title'] as String? ?? '';
      if (initialTypeId == null && types.any((t) => t['id'] == saved['type'])) {
        typeId = saved['type'];
      }
      final a = DateTime.tryParse(saved['start'] ?? '');
      final b = DateTime.tryParse(saved['end'] ?? '');
      if (a != null && b != null && a.isAfter(DateTime.now()) && b.isAfter(a)) {
        start = a;
        end = b;
      }
      if (saved['location'] is Map) {
        final loc = saved['location'] as Map;
        selectedLocation = EventLocationSelection(
          regionId: loc['region'],
          districtId: loc['district'],
          wardId: loc['ward'],
          areaId: loc['area'],
          label: loc['label'] ?? '',
        );
      }
    } catch (_) {
      /* Ignore an obsolete draft. */
    }
    void saveDetails() {
      preferences.setString(
        'event-details-draft',
        jsonEncode({
          'title': title.text,
          'type': typeId,
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
          'location': selectedLocation == null
              ? null
              : {
                  'region': selectedLocation!.regionId,
                  'district': selectedLocation!.districtId,
                  'ward': selectedLocation!.wardId,
                  'area': selectedLocation!.areaId,
                  'label': selectedLocation!.label,
                },
        }),
      );
    }

    if (!mounted) {
      title.dispose();
      location.dispose();
      return;
    }

    final save = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (plannerContext) => StatefulBuilder(
          builder: (context, setPlannerState) => Scaffold(
            appBar: AppBar(
              title: Text(
                sw
                    ? mobileUi(context, 'Panga tukio')
                    : mobileUi(context, 'Plan an event'),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      sw
                          ? mobileUi(
                              context,
                              'Weka taarifa za tukio lako kwa utaratibu. Unaweza kuchagua vifaa na huduma baada ya kuhifadhi.',
                            )
                          : mobileUi(
                              context,
                              'Add your event details clearly. You can choose equipment and services after saving.',
                            ),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: typeId,
                      items: types
                          .map(
                            (type) => DropdownMenuItem(
                              value: type['id'].toString(),
                              child: Text(
                                (sw ? type['name_sw'] : type['name_en'])
                                    .toString(),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          typeId = value;
                          saveDetails();
                        }
                      },
                    ),
                    TextField(
                      controller: title,
                      onChanged: (_) => saveDetails(),
                      decoration: InputDecoration(
                        labelText: sw
                            ? mobileUi(context, 'Jina la tukio')
                            : mobileUi(context, 'Event name'),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text(
                          selectedLocation?.label ??
                              (sw
                                  ? mobileUi(context, 'Chagua eneo la tukio')
                                  : mobileUi(context, 'Choose event location')),
                        ),
                        subtitle: Text(
                          sw
                              ? mobileUi(context, 'Mkoa, wilaya, kata na eneo')
                              : mobileUi(
                                  context,
                                  'Region, district, ward and area',
                                ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final value = await Navigator.of(context)
                              .push<EventLocationSelection>(
                                MaterialPageRoute(
                                  builder: (_) => EventLocationPicker(
                                    repository: widget.repository,
                                    swahili: sw,
                                    initialRegionId:
                                        selectedLocation?.regionId ??
                                        widget.initialRegionId,
                                    initialDistrictId:
                                        selectedLocation?.districtId ??
                                        widget.initialDistrictId,
                                    initialWardId:
                                        selectedLocation?.wardId ??
                                        widget.initialWardId,
                                    initialAreaId:
                                        selectedLocation?.areaId ??
                                        widget.initialAreaId,
                                  ),
                                ),
                              );
                          if (value != null) {
                            setPlannerState(() => selectedLocation = value);
                            saveDetails();
                          }
                        },
                      ),
                    ),
                    ...[false, true].map(
                      (isEnd) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          isEnd
                              ? (sw
                                    ? mobileUi(
                                        context,
                                        'Tarehe na saa ya kumaliza',
                                      )
                                    : mobileUi(context, 'End date and time'))
                              : (sw
                                    ? mobileUi(
                                        context,
                                        'Tarehe na saa ya kuanza',
                                      )
                                    : mobileUi(context, 'Start date and time')),
                        ),
                        subtitle: Text(
                          eventDateLabel(context, isEnd ? end : start),
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: () async {
                          final current = isEnd ? end : start;
                          final day = await showDatePicker(
                            context: context,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1095),
                            ),
                            initialDate: current,
                          );
                          if (day == null || !context.mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(current),
                          );
                          if (time == null || !context.mounted) return;
                          setPlannerState(() {
                            final chosen = DateTime(
                              day.year,
                              day.month,
                              day.day,
                              time.hour,
                              time.minute,
                            );
                            if (isEnd) {
                              end = chosen;
                            } else {
                              start = chosen;
                            }
                          });
                          saveDetails();
                        },
                      ),
                    ),
                    Text(
                      sw
                          ? mobileUi(
                              context,
                              'Hatua ya 1 kati ya 3 / Rasimu inahifadhiwa kwenye kifaa hiki.',
                            )
                          : mobileUi(
                              context,
                              'Step 1 of 3 / Your draft is saved on this device.',
                            ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () {
                        if (selectedLocation?.locationId == null ||
                            !start.isAfter(DateTime.now()) ||
                            !end.isAfter(start)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                sw
                                    ? mobileUi(
                                        context,
                                        'Chagua eneo na muda sahihi wa baadaye.',
                                      )
                                    : mobileUi(
                                        context,
                                        'Choose a location and a valid future start/end time.',
                                      ),
                              ),
                            ),
                          );
                          return;
                        }
                        saveDetails();
                        Navigator.pop(plannerContext, true);
                      },
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        sw
                            ? mobileUi(context, 'Hifadhi na uchague huduma')
                            : mobileUi(context, 'Save and choose services'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(plannerContext, false),
                      child: Text(
                        sw
                            ? mobileUi(context, 'Ghairi')
                            : mobileUi(context, 'Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (save != true || !mounted) {
      title.dispose();
      location.dispose();
      return;
    }
    if (selectedLocation?.locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sw
                ? mobileUi(context, 'Chagua eneo la tukio kwanza.')
                : mobileUi(context, 'Choose the event location first.'),
          ),
        ),
      );
      title.dispose();
      location.dispose();
      return;
    }
    try {
      final result = await widget.repository.createEventPlan(
        eventTypeId: typeId,
        startsAt: start,
        endsAt: end,
        locationId: selectedLocation!.locationId,
        locationDetails: null,
        attendance: 1,
        budgetTzs: null,
        title: title.text,
      );
      final planCatalog = await widget.repository.fetchEventsMarketplace(
        locationId: selectedLocation!.locationId,
        startsAt: start,
        endsAt: end,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${sw ? mobileUi(context, 'Mpango umeanzishwa') : mobileUi(context, 'Event plan created')}: ${result['reference']}',
            ),
          ),
        );
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ChooseEventComponentsScreen(
              repository: widget.repository,
              planId: result['id'].toString(),
              marketplace: planCatalog,
              start: start,
              end: end,
              locationId: selectedLocation!.locationId!,
              locationLabel: selectedLocation!.label,
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
    }
    title.dispose();
    location.dispose();
  }
}

class _ChooseEventComponentsScreen extends StatefulWidget {
  const _ChooseEventComponentsScreen({
    required this.repository,
    required this.planId,
    required this.marketplace,
    required this.start,
    required this.end,
    required this.locationId,
    required this.locationLabel,
  });
  final CustomerPublicRepository repository;
  final String planId;
  final JsonMap marketplace;
  final DateTime start, end;
  final String locationId, locationLabel;
  @override
  State<_ChooseEventComponentsScreen> createState() =>
      _ChooseEventComponentsScreenState();
}

class _ChooseEventComponentsScreenState
    extends State<_ChooseEventComponentsScreen> {
  final Map<String, int> quantities = <String, int>{};
  final Set<String> providers = <String>{};
  bool busy = false;
  bool loadingMore = false;
  String search = '';
  String componentCategory = '';
  final Map<String, String> choiceNames = {};
  bool ready = false;
  bool submitted = false;
  void change(VoidCallback action) {
    setState(action);
    if (ready && !submitted) _save();
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw =
          jsonDecode(
                preferences.getString('event-selection-${widget.planId}') ??
                    '{}',
              )
              as Map<String, dynamic>;
      quantities.addAll(
        (raw['quantities'] as Map? ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
      );
      providers.addAll((raw['providers'] as List? ?? []).cast<String>());
      choiceNames.addAll(
        (raw['names'] as Map? ?? {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
    } catch (_) {}
    if (mounted) setState(() => ready = true);
  }

  Future<void> _save() async {
    if (submitted) return;
    for (final item
        in (widget.marketplace['equipment'] as List).cast<JsonMap>()) {
      choiceNames[item['id'].toString()] = item['name'].toString();
    }
    for (final item
        in (widget.marketplace['services'] as List).cast<JsonMap>()) {
      choiceNames[item['offering_id'].toString()] =
          (item['title'] ?? item['display_name']).toString();
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'event-selection-${widget.planId}',
      jsonEncode({
        'quantities': quantities,
        'providers': providers.toList(),
        'names': choiceNames,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    final equipment = (widget.marketplace['equipment'] as List? ?? <dynamic>[])
        .cast<JsonMap>();
    final services = (widget.marketplace['services'] as List? ?? <dynamic>[])
        .cast<JsonMap>();
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            sw
                ? mobileUi(context, 'Chagua mahitaji ya tukio')
                : mobileUi(context, 'Choose event components'),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: <Widget>[
            Text(
              sw
                  ? mobileUi(context, 'Hatua ya 2 kati ya 3 / Vifaa na huduma')
                  : mobileUi(context, 'Step 2 of 3 / Equipment and services'),
            ),
            Text(
              '${eventDateLabel(context, widget.start)} - ${eventDateLabel(context, widget.end)}\n${widget.locationLabel}',
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: sw
                    ? mobileUi(context, 'Tafuta katika chaguo zilizopakiwa')
                    : mobileUi(context, 'Search loaded options'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => change(() => search = v.toLowerCase()),
            ),
            DropdownButtonFormField<String>(
              initialValue: componentCategory,
              decoration: InputDecoration(
                labelText: sw
                    ? mobileUi(context, 'Kundi')
                    : mobileUi(context, 'Category'),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    sw
                        ? mobileUi(context, 'Makundi yote')
                        : mobileUi(context, 'All categories'),
                  ),
                ),
                for (final c
                    in (widget.marketplace['categories'] as List? ?? [])
                        .cast<JsonMap>())
                  DropdownMenuItem(
                    value: c['id'].toString(),
                    child: Text((sw ? c['name_sw'] : c['name_en']).toString()),
                  ),
                DropdownMenuItem(
                  value: 'professionals',
                  child: Text(
                    sw
                        ? mobileUi(context, 'Wataalamu')
                        : mobileUi(context, 'Professionals'),
                  ),
                ),
              ],
              onChanged: (value) =>
                  change(() => componentCategory = value ?? ''),
            ),
            Text(
              sw
                  ? mobileUi(
                      context,
                      'Upatikanaji utathibitishwa kabla ya booking. Gharama za usafiri na jumla zitaonyeshwa kwenye quotation.',
                    )
                  : mobileUi(
                      context,
                      'Availability is confirmed before booking. Delivery charges and your total are provided in the quotation.',
                    ),
            ),
            Text(
              sw
                  ? mobileUi(context, 'Vifaa na idadi')
                  : mobileUi(context, 'Equipment and quantities'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            ...equipment
                .where(
                  (i) =>
                      (componentCategory.isEmpty ||
                          i['category_id'] == componentCategory) &&
                      i['name'].toString().toLowerCase().contains(search),
                )
                .map((item) {
                  final id = item['id'].toString();
                  final quantity = quantities[id] ?? 0;
                  final maximum =
                      ((item['available_quantity'] as num?)?.toInt() ??
                              (item['total_quantity'] as num?)?.toInt() ??
                              1)
                          .clamp(1, 999);
                  return Card(
                    color: quantity > 0
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              EventThumbnail(
                                repository: widget.repository,
                                item: item,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'].toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(eventPriceLabel(item, sw)),
                                    Text(
                                      '${sw ? mobileUi(context, 'Inayopatikana kwa tarehe hizi') : mobileUi(context, 'Available for these dates')}: ${item['available_quantity'] ?? item['total_quantity']}',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                sw
                                    ? mobileUi(context, 'Idadi')
                                    : mobileUi(context, 'Quantity'),
                              ),
                              IconButton(
                                tooltip: sw ? 'Punguza' : 'Decrease',
                                onPressed: quantity == 0
                                    ? null
                                    : () => change(() {
                                        if (quantity <= 1) {
                                          quantities.remove(id);
                                        } else {
                                          quantities[id] = quantity - 1;
                                        }
                                      }),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text(
                                '$quantity',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                tooltip: sw ? 'Ongeza' : 'Increase',
                                onPressed:
                                    quantity >= maximum ||
                                        (item['available_quantity'] as num? ??
                                                0) <=
                                            0
                                    ? null
                                    : () => change(
                                        () => quantities[id] = quantity + 1,
                                      ),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            const SizedBox(height: 20),
            Text(
              sw
                  ? mobileUi(context, 'Wataalamu')
                  : mobileUi(context, 'Professionals'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            ...services
                .where(
                  (i) =>
                      (componentCategory.isEmpty ||
                          componentCategory == 'professionals') &&
                      '${i['title']} ${i['display_name']}'
                          .toLowerCase()
                          .contains(search),
                )
                .map((provider) {
                  final id = provider['offering_id'].toString();
                  return CheckboxListTile(
                    value: providers.contains(id),
                    onChanged: provider['is_available'] == false
                        ? null
                        : (selected) => change(() {
                            if (selected == true) {
                              providers.add(id);
                            } else {
                              providers.remove(id);
                            }
                          }),
                    title: Text(
                      (provider['title'] ?? provider['display_name'])
                          .toString(),
                    ),
                    subtitle: Text(
                      '${provider['display_name']} / ${eventServiceLabel(provider['provider_kind'], sw)}\n${eventPriceLabel(provider, sw)}',
                    ),
                  );
                }),
            if (widget.marketplace['has_more'] == true)
              OutlinedButton(
                onPressed: loadingMore ? null : _loadMoreComponents,
                child: Text(
                  sw
                      ? mobileUi(context, 'Onyesha vifaa na huduma zaidi')
                      : mobileUi(context, 'Load more equipment and services'),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed:
                  busy || !ready || (quantities.isEmpty && providers.isEmpty)
                  ? null
                  : _submit,
              child: Text(
                '${quantities.length + providers.length} / ${sw ? mobileUi(context, 'Kagua mpango') : mobileUi(context, 'Review plan')}',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadMoreComponents() async {
    change(() => loadingMore = true);
    try {
      final equipment = widget.marketplace['equipment'] as List;
      final services = widget.marketplace['services'] as List;
      final offset = equipment.length > services.length
          ? equipment.length
          : services.length;
      final next = await widget.repository.fetchEventsMarketplace(
        offset: offset,
        locationId: widget.locationId,
        startsAt: widget.start,
        endsAt: widget.end,
      );
      if (!mounted) return;
      change(() {
        widget.marketplace['equipment'] = [
          ...equipment,
          ...(next['equipment'] as List),
        ];
        widget.marketplace['services'] = [
          ...services,
          ...(next['services'] as List),
        ];
        widget.marketplace['has_more'] = next['has_more'];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) change(() => loadingMore = false);
    }
  }

  Future<void> _submit() async {
    final sw = context.isSwahili;
    if (quantities.isEmpty && providers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sw
                ? mobileUi(context, 'Chagua angalau kifaa au mtaalamu.')
                : mobileUi(
                    context,
                    'Choose at least one item or professional.',
                  ),
          ),
        ),
      );
      return;
    }
    await _save();
    change(() => busy = true);
    try {
      final items = <JsonMap>[
        for (final e in quantities.entries)
          {'kind': 'equipment', 'id': e.key, 'quantity': e.value},
        for (final id in providers) {'kind': 'service', 'id': id},
      ];
      final checks = await widget.repository.checkEventSelection(
        items: items,
        start: widget.start,
        end: widget.end,
        locationId: widget.locationId,
      );
      if (checks.length != items.length ||
          checks.any((c) => c['is_available'] != true)) {
        throw StateError(
          sw
              ? 'Baadhi ya chaguo hazipatikani kwa muda, eneo au idadi hii. Hariri chaguo zako.'
              : 'Some selections are unavailable for this time, location or quantity. Edit your selections.',
        );
      }
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            sw
                ? mobileUi(context, 'Hatua ya 3 / Kagua mpango')
                : mobileUi(context, 'Step 3 / Review your plan'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${eventDateLabel(context, widget.start)} - ${eventDateLabel(context, widget.end)}\n${widget.locationLabel}',
                ),
                const SizedBox(height: 12),
                for (final e in quantities.entries)
                  Text(
                    '${(widget.marketplace['equipment'] as List).cast<JsonMap>().where((i) => i['id'] == e.key).firstOrNull?['name'] ?? choiceNames[e.key] ?? e.key} ? ${e.value}',
                  ),
                for (final id in providers)
                  Text(
                    '${(widget.marketplace['services'] as List).cast<JsonMap>().where((i) => i['offering_id'] == id).firstOrNull?['title'] ?? choiceNames[id] ?? id}',
                  ),
                const SizedBox(height: 12),
                Text(
                  sw
                      ? mobileUi(
                          context,
                          'Jumla, usafiri na dhamana vitathibitishwa kwenye quotation. Hakuna malipo sasa.',
                        )
                      : mobileUi(
                          context,
                          'Your total, delivery and deposit will be confirmed in the quotation. No payment is due now.',
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                sw ? mobileUi(context, 'Hariri') : mobileUi(context, 'Edit'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                sw
                    ? mobileUi(context, 'Omba quotation ya tukio')
                    : mobileUi(context, 'Request event quotation'),
              ),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      await widget.repository.submitEventDraft(widget.planId, [
        for (final entry in quantities.entries)
          {'kind': 'equipment', 'id': entry.key, 'quantity': entry.value},
        for (final id in providers) {'kind': 'service', 'id': id},
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sw
                  ? mobileUi(context, 'Ombi la quotation limetumwa.')
                  : mobileUi(context, 'Quotation request sent.'),
            ),
          ),
        );
        submitted = true;
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove('event-selection-${widget.planId}');
        await preferences.remove('event-details-draft');
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              sw
                  ? mobileUi(context, 'Ombi limetumwa')
                  : mobileUi(context, 'Request sent'),
            ),
            content: Text(
              sw
                  ? mobileUi(
                      context,
                      'Fuatilia quotation na makubaliano kwenye mipango yako kabla ya kulipa.',
                    )
                  : mobileUi(
                      context,
                      'Follow your event plans for the quotation and agreement before paying.',
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  sw
                      ? mobileUi(context, 'Angalia mipango yangu')
                      : mobileUi(context, 'View my event plans'),
                ),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.pop(context);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _MyEventPlansScreen(repository: widget.repository),
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
      if (mounted) change(() => busy = false);
    }
  }
}

class _MyEventPlansScreen extends StatefulWidget {
  const _MyEventPlansScreen({required this.repository});
  final CustomerPublicRepository repository;
  @override
  State<_MyEventPlansScreen> createState() => _MyEventPlansScreenState();
}

class _MyEventPlansScreenState extends State<_MyEventPlansScreen> {
  late Future<List<JsonMap>> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = widget.repository.fetchMyEventPlans();
  }

  void reload() =>
      setState(() => future = widget.repository.fetchMyEventPlans());
  Future<void> _resumeDraft(JsonMap plan) async {
    try {
      final parts = plan['event_period']
          .toString()
          .replaceAll('"', '')
          .substring(1)
          .split(',');
      final start = DateTime.parse(parts[0]);
      final end = DateTime.parse(
        parts[1].replaceAll(')', '').replaceAll(']', ''),
      );
      final locationId = plan['location_id']?.toString();
      if (locationId == null) throw StateError('Event location is missing.');
      final catalog = await widget.repository.fetchEventsMarketplace(
        locationId: locationId,
        startsAt: start,
        endsAt: end,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ChooseEventComponentsScreen(
            repository: widget.repository,
            planId: plan['id'].toString(),
            marketplace: catalog,
            start: start,
            end: end,
            locationId: locationId,
            locationLabel: plan['location_details']?.toString() ?? '',
          ),
        ),
      );
      reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          sw
              ? mobileUi(context, 'Mipango yangu ya matukio')
              : mobileUi(context, 'My event plans'),
        ),
      ),
      body: FutureBuilder<List<JsonMap>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? <JsonMap>[];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                sw
                    ? mobileUi(context, 'Bado huna mpango wa tukio.')
                    : mobileUi(context, 'No event plans yet.'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              reload();
              await future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: rows.map((plan) {
                final quotes =
                    (plan['event_quote_revisions'] as List? ?? <dynamic>[])
                        .cast<Map<String, dynamic>>();
                final sent = quotes
                    .where((quote) => quote['status'] == 'sent')
                    .firstOrNull;
                final agreements =
                    (plan['event_agreements'] as List? ?? <dynamic>[])
                        .cast<Map<String, dynamic>>();
                final agreement = agreements
                    .where((row) => row['status'] == 'sent')
                    .firstOrNull;
                final payment = Map<String, dynamic>.from(
                  plan['payment_summary'] as Map? ?? const <String, dynamic>{},
                );
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
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
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
                          '${plan['reference']} · ${sw ? mobileUi(context, 'Wageni') : mobileUi(context, 'Guests')} ${plan['attendance']}',
                        ),
                        if (plan['status'] == 'draft')
                          OutlinedButton.icon(
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                              sw
                                  ? mobileUi(context, 'Endelea kupanga')
                                  : mobileUi(context, 'Resume planning'),
                            ),
                            onPressed: () => _resumeDraft(plan),
                          ),
                        EventRecoveryControls(
                          repository: widget.repository,
                          planId: plan['id'].toString(),
                          status: plan['status'].toString(),
                          onChanged: reload,
                        ),
                        if (sent != null) ...<Widget>[
                          const Divider(height: 28),
                          Text(
                            '${sw ? mobileUi(context, 'Quotation') : mobileUi(context, 'Quotation')} #${sent['revision']} · TZS ${sent['total_tzs']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => accept(sent['id'].toString()),
                            child: Text(
                              sw
                                  ? mobileUi(context, 'Kubali quotation')
                                  : mobileUi(context, 'Accept quotation'),
                            ),
                          ),
                        ],
                        if (agreement != null) ...<Widget>[
                          const Divider(height: 28),
                          Text(
                            '${sw ? mobileUi(context, 'Makubaliano ya mwisho') : mobileUi(context, 'Final agreement')} · v${agreement['version']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(agreement['terms'].toString()),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => acceptAgreement(
                                    agreement['id'].toString(),
                                  ),
                            child: Text(
                              sw
                                  ? mobileUi(context, 'Kubali makubaliano')
                                  : mobileUi(context, 'Accept agreement'),
                            ),
                          ),
                        ],
                        if (plan['status'] == 'payment_pending') ...<Widget>[
                          const Divider(height: 28),
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => pay(
                                    plan['id'].toString(),
                                    purpose: 'event_deposit',
                                  ),
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(
                              sw
                                  ? mobileUi(context, 'Lipa deposit')
                                  : mobileUi(context, 'Pay deposit'),
                            ),
                          ),
                        ],
                        if ((payment['total'] as num? ?? 0) > 0) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            mobileUiFormat(
                              context,
                              "{0}: TZS {1} · Balance: TZS {2}",
                              [
                                sw
                                    ? mobileUi(context, 'Deposit iliyobaki')
                                    : mobileUi(context, 'Deposit remaining'),
                                payment['deposit_remaining'],
                                payment['balance_remaining'],
                              ],
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                        if (plan['status'] == 'confirmed' &&
                            (payment['deposit_remaining'] as num? ?? 0) == 0 &&
                            (payment['balance_remaining'] as num? ?? 0) >
                                0) ...<Widget>[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => pay(
                                    plan['id'].toString(),
                                    purpose: 'event_balance',
                                  ),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                            label: Text(
                              sw
                                  ? mobileUi(context, 'Lipa balance')
                                  : mobileUi(context, 'Pay balance'),
                            ),
                          ),
                        ],
                        if (sent == null &&
                            agreement == null &&
                            plan['status'] != 'confirmed' &&
                            plan['status'] != 'payment_pending')
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              sw
                                  ? mobileUi(
                                      context,
                                      'Quotation bado inaandaliwa.',
                                    )
                                  : mobileUi(
                                      context,
                                      'Quotation is being prepared.',
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Future<void> accept(String id) async {
    setState(() => busy = true);
    try {
      await widget.repository.acceptEventQuote(id);
      reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> acceptAgreement(String id) async {
    setState(() => busy = true);
    try {
      await widget.repository.acceptEventAgreement(id);
      reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pay(String planId, {required String purpose}) async {
    final sw = context.isSwahili;
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          sw
              ? mobileUi(context, 'Namba ya malipo')
              : mobileUi(context, 'Payment number'),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: mobileUi(context, '2557XXXXXXXX'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(
              sw
                  ? mobileUi(context, 'Tuma ombi')
                  : mobileUi(context, 'Send request'),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (phone == null || phone.isEmpty || !mounted) return;
    setState(() => busy = true);
    try {
      final started = await widget.repository.createPlatformPayment(
        purpose: purpose,
        resourceId: planId,
        phoneNumber: phone,
      );
      var status = started['paymentStatus']?.toString() ?? 'pending';
      final paymentId = started['paymentId'].toString();
      for (
        var attempt = 0;
        attempt < 30 &&
            !<String>{
              'paid',
              'failed',
              'cancelled',
              'expired',
            }.contains(status);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final checked = await widget.repository.checkPlatformPayment(paymentId);
        status = checked['paymentStatus']?.toString() ?? status;
      }
      if (status != 'paid') {
        throw StateError(
          sw
              ? 'Malipo bado hayajathibitishwa.'
              : 'Payment has not been confirmed.',
        );
      }
      reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sw
                  ? mobileUi(context, 'Malipo yamethibitishwa.')
                  : mobileUi(context, 'Payment confirmed.'),
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
      if (mounted) setState(() => busy = false);
    }
  }
}

class _IndividualEventDetailScreen extends StatefulWidget {
  const _IndividualEventDetailScreen({
    required this.repository,
    required this.kind,
    required this.id,
  });
  final CustomerPublicRepository repository;
  final String kind;
  final String id;
  @override
  State<_IndividualEventDetailScreen> createState() =>
      _IndividualEventDetailScreenState();
}

class _IndividualBookingsHistoryScreen extends StatelessWidget {
  const _IndividualBookingsHistoryScreen({required this.repository});
  final CustomerPublicRepository repository;
  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          sw
              ? mobileUi(context, 'Booking zangu')
              : mobileUi(context, 'My bookings'),
        ),
      ),
      body: FutureBuilder<List<JsonMap>>(
        future: repository.fetchMyIndividualEventBookings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? <JsonMap>[];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                sw
                    ? mobileUi(context, 'Bado huna booking.')
                    : mobileUi(context, 'No bookings yet.'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final item = row['event_plan_items'] as Map?;
              final equipment = item?['event_equipment_items'] as Map?;
              final offering = item?['event_service_offerings'] as Map?;
              final title =
                  equipment?['name'] ?? offering?['title'] ?? 'Event booking';
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
                              title.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              row['status'].toString().replaceAll('_', ' '),
                            ),
                          ),
                        ],
                      ),
                      Text(row['reference'].toString()),
                      if (row['requested_quantity'] != null)
                        Text(
                          '${sw ? mobileUi(context, 'Idadi') : mobileUi(context, 'Quantity')}: ${row['requested_quantity']}',
                        ),
                      if (row['quoted_amount_tzs'] != null)
                        Text(
                          'TZS ${row['quoted_amount_tzs']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      Text(
                        '${sw ? mobileUi(context, 'Malipo') : mobileUi(context, 'Payment')}: ${row['payment_status'].toString().replaceAll('_', ' ')}',
                      ),
                      if (row['provider_response'] != null)
                        Text(row['provider_response'].toString()),
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

class _EventAdvisorScreen extends StatefulWidget {
  const _EventAdvisorScreen({
    required this.repository,
    this.initialRegionId,
    this.initialDistrictId,
    this.initialWardId,
    this.initialAreaId,
  });
  final CustomerPublicRepository repository;
  final String? initialRegionId,
      initialDistrictId,
      initialWardId,
      initialAreaId;
  @override
  State<_EventAdvisorScreen> createState() => _EventAdvisorScreenState();
}

class _EventAdvisorScreenState extends State<_EventAdvisorScreen> {
  late Future<List<JsonMap>> templatesFuture;
  final guests = TextEditingController();
  final budget = TextEditingController();
  final location = TextEditingController();
  final accessibility = TextEditingController();
  String? templateId;
  String setting = 'indoor';
  String venueStatus = 'needed';
  DateTime date = DateTime.now().add(const Duration(days: 30));
  bool busy = false;
  List<JsonMap> recommendations = <JsonMap>[];
  EventLocationSelection? selectedLocation;
  @override
  void initState() {
    super.initState();
    templatesFuture = widget.repository.fetchEventTemplates();
  }

  @override
  void dispose() {
    guests.dispose();
    budget.dispose();
    location.dispose();
    accessibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(title: const LocalizedUiText('Event Advisor')),
      body: FutureBuilder<List<JsonMap>>(
        future: templatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final templates = snapshot.data ?? <JsonMap>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                sw
                    ? mobileUi(context, 'Tukusaidie kupanga')
                    : mobileUi(context, 'Let us help you plan'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                sw
                    ? mobileUi(
                        context,
                        'Mapendekezo yanatokana na template iliyothibitishwa. Bei na availability hazitabuniwa.',
                      )
                    : mobileUi(
                        context,
                        'Recommendations come from approved templates. Prices and availability are never invented.',
                      ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: templateId,
                decoration: InputDecoration(
                  labelText: sw
                      ? mobileUi(context, 'Aina ya mpango')
                      : mobileUi(context, 'Planning template'),
                ),
                items: templates
                    .map(
                      (row) => DropdownMenuItem(
                        value: row['id'].toString(),
                        child: Text(
                          (sw ? row['name_sw'] : row['name_en']).toString(),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => templateId = value),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(
                    selectedLocation?.label ??
                        (sw
                            ? mobileUi(context, 'Chagua eneo la tukio')
                            : mobileUi(context, 'Choose event location')),
                  ),
                  subtitle: Text(
                    sw
                        ? mobileUi(context, 'Mkoa, wilaya, kata na eneo')
                        : mobileUi(context, 'Region, district, ward and area'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final value = await Navigator.of(context)
                        .push<EventLocationSelection>(
                          MaterialPageRoute(
                            builder: (_) => EventLocationPicker(
                              repository: widget.repository,
                              swahili: sw,
                              initialRegionId:
                                  selectedLocation?.regionId ??
                                  widget.initialRegionId,
                              initialDistrictId:
                                  selectedLocation?.districtId ??
                                  widget.initialDistrictId,
                              initialWardId:
                                  selectedLocation?.wardId ??
                                  widget.initialWardId,
                              initialAreaId:
                                  selectedLocation?.areaId ??
                                  widget.initialAreaId,
                            ),
                          ),
                        );
                    if (value != null) setState(() => selectedLocation = value);
                  },
                ),
              ),
              TextField(
                controller: guests,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: sw
                      ? mobileUi(context, 'Wageni')
                      : mobileUi(context, 'Guests'),
                ),
              ),
              TextField(
                controller: budget,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: sw
                      ? mobileUi(context, 'Bajeti (TZS)')
                      : mobileUi(context, 'Budget (TZS)'),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: setting,
                decoration: InputDecoration(
                  labelText: sw
                      ? mobileUi(context, 'Mpangilio')
                      : mobileUi(context, 'Setting'),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'indoor',
                    child: LocalizedUiText('Indoor'),
                  ),
                  DropdownMenuItem(
                    value: 'outdoor',
                    child: LocalizedUiText('Outdoor'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => setting = value);
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: venueStatus,
                decoration: InputDecoration(
                  labelText: sw
                      ? mobileUi(context, 'Hali ya venue')
                      : mobileUi(context, 'Venue status'),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'needed',
                    child: LocalizedUiText('Need a venue'),
                  ),
                  DropdownMenuItem(
                    value: 'shortlisted',
                    child: LocalizedUiText('Shortlisted'),
                  ),
                  DropdownMenuItem(
                    value: 'booked_elsewhere',
                    child: LocalizedUiText('Already booked'),
                  ),
                  DropdownMenuItem(
                    value: 'booked_kodimali',
                    child: LocalizedUiText('Booked on KODIMALI'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => venueStatus = value);
                },
              ),
              TextField(
                controller: accessibility,
                decoration: InputDecoration(
                  labelText: sw
                      ? mobileUi(context, 'Accessibility na usalama')
                      : mobileUi(context, 'Accessibility and safety'),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  sw
                      ? mobileUi(context, 'Tarehe ya tukio')
                      : mobileUi(context, 'Event date'),
                ),
                subtitle: Text(date.toString()),
                onTap: () async {
                  final next = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 1095)),
                    initialDate: date,
                  );
                  if (next != null) {
                    setState(
                      () =>
                          date = DateTime(next.year, next.month, next.day, 10),
                    );
                  }
                },
              ),
              FilledButton(
                onPressed: busy ? null : () => _run(templates),
                child: Text(
                  busy
                      ? (sw
                            ? mobileUi(context, 'Inaandaa…')
                            : mobileUi(context, 'Preparing…'))
                      : (sw
                            ? mobileUi(context, 'Tengeneza mapendekezo')
                            : mobileUi(context, 'Create recommendations')),
                ),
              ),
              if (recommendations.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                Text(
                  sw
                      ? mobileUi(context, 'Mapendekezo yako')
                      : mobileUi(context, 'Your recommendations'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                ...recommendations.map(
                  (row) => Card(
                    child: ListTile(
                      title: Text(
                        (sw ? row['title_sw'] : row['title_en'])
                            .toString()
                            .replaceAll('_', ' '),
                      ),
                      subtitle: Text(
                        (sw ? row['reason_sw'] : row['reason_en']).toString(),
                      ),
                      trailing: row['suggested_quantity'] == null
                          ? null
                          : Chip(
                              label: Text(row['suggested_quantity'].toString()),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _run(List<JsonMap> templates) async {
    if (templateId == null ||
        int.tryParse(guests.text) == null ||
        selectedLocation?.locationId == null) {
      return;
    }
    setState(() => busy = true);
    try {
      final template = templates.firstWhere(
        (row) => row['id'].toString() == templateId,
      );
      final plan = await widget.repository.createEventPlan(
        eventTypeId: template['event_type_id']?.toString() ?? '',
        startsAt: date,
        endsAt: date.add(const Duration(hours: 6)),
        locationId: selectedLocation!.locationId,
        locationDetails: null,
        attendance: int.parse(guests.text),
        budgetTzs: double.tryParse(budget.text),
        title: mobileUi(context, 'Event Advisor plan'),
      );
      final rows = await widget.repository.runEventAdvisor(
        planId: plan['id'].toString(),
        templateId: templateId!,
        setting: setting,
        venueStatus: venueStatus,
        accessibility: accessibility.text,
      );
      if (mounted) {
        setState(() => recommendations = rows);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
}

class _IndividualEventDetailScreenState
    extends State<_IndividualEventDetailScreen> {
  late Future<JsonMap> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = widget.repository.fetchIndividualEventDetail(
      kind: widget.kind,
      id: widget.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          sw
              ? mobileUi(context, 'Maelezo ya booking')
              : mobileUi(context, 'Booking details'),
        ),
      ),
      body: FutureBuilder<JsonMap>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final row = snapshot.data!;
          final provider = row['event_service_profiles'] as Map?;
          final title = (row['name'] ?? row['title']).toString();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: EventThumbnail(
                  repository: widget.repository,
                  item: widget.kind == 'equipment'
                      ? row
                      : {
                          ...row,
                          'portfolio_media': provider?['portfolio_media'],
                        },
                  size: 220,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (provider != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${provider['display_name']} · ${eventServiceLabel(provider['provider_kind'], sw)}',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                (row['description'] ?? provider?['biography'] ?? '').toString(),
              ),
              const SizedBox(height: 16),
              Text(
                eventPriceLabel(row, sw),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (widget.kind == 'equipment') ...<Widget>[
                _detail(
                  sw ? 'Idadi iliyopo' : 'Total stock',
                  row['total_quantity'],
                ),
                _detail(sw ? 'Eneo' : 'Location', row['public_location_label']),
                _detail(
                  sw ? 'Dhamana' : 'Security deposit',
                  row['security_deposit_tzs'],
                ),
                _detail(
                  sw ? 'Uharibifu na urejeshaji' : 'Damage and return',
                  row['damage_rules'] ?? row['return_procedure'],
                ),
              ] else ...<Widget>[
                _detail(
                  sw ? 'Muda wa huduma' : 'Duration',
                  row['duration_minutes'],
                ),
                _detail(
                  sw ? 'Vifaa vinavyojumuishwa' : 'Included equipment',
                  row['included_equipment'],
                ),
                _detail(
                  sw ? 'Mahitaji maalum' : 'Special requirements',
                  row['requirements'],
                ),
              ],
              _detail(
                sw ? 'Kughairi' : 'Cancellation',
                row['cancellation_policy'],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : () => _request(row),
                icon: const Icon(Icons.event_available_outlined),
                label: Text(
                  sw
                      ? mobileUi(context, 'Tuma ombi la booking')
                      : mobileUi(context, 'Request booking'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                sw
                    ? mobileUi(
                        context,
                        'Mtoa huduma atathibitisha upatikanaji. Chaguo la malipo litaonyeshwa baada ya quotation na makubaliano.',
                      )
                    : mobileUi(
                        context,
                        'The provider will confirm availability. Payment options are shown after the quote and agreement.',
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detail(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value?.toString() ?? '—'),
      ],
    ),
  );

  Future<void> _request(JsonMap row) async {
    final sw = context.isSwahili;
    DateTime start = DateTime.now().add(const Duration(days: 7));
    DateTime end = start.add(
      Duration(hours: widget.kind == 'equipment' ? 8 : 3),
    );
    final quantity = TextEditingController(text: '1');
    final notes = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            sw
                ? mobileUi(context, 'Ombi la booking')
                : mobileUi(context, 'Booking request'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ...[false, true].map(
                  (isEnd) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      isEnd
                          ? (sw
                                ? mobileUi(context, 'Tarehe na saa ya kumaliza')
                                : mobileUi(context, 'End date and time'))
                          : (sw
                                ? mobileUi(context, 'Tarehe na saa ya kuanza')
                                : mobileUi(context, 'Start date and time')),
                    ),
                    subtitle: Text(
                      eventDateLabel(context, isEnd ? end : start),
                    ),
                    onTap: () async {
                      final current = isEnd ? end : start;
                      final day = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 1095),
                        ),
                        initialDate: current,
                      );
                      if (day == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(current),
                      );
                      if (time == null || !context.mounted) return;
                      setDialogState(() {
                        final selected = DateTime(
                          day.year,
                          day.month,
                          day.day,
                          time.hour,
                          time.minute,
                        );
                        if (isEnd) {
                          end = selected;
                        } else {
                          start = selected;
                        }
                      });
                    },
                  ),
                ),
                if (widget.kind == 'equipment')
                  TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: sw
                          ? mobileUi(context, 'Idadi')
                          : mobileUi(context, 'Quantity'),
                    ),
                  ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: sw
                        ? mobileUi(context, 'Maelezo ya ombi')
                        : mobileUi(context, 'Request notes'),
                  ),
                ),
              ],
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
              onPressed: () {
                if (!start.isAfter(DateTime.now()) || !end.isAfter(start)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        sw
                            ? mobileUi(
                                context,
                                'Chagua muda sahihi wa baadaye.',
                              )
                            : mobileUi(
                                context,
                                'Choose a valid future start and end.',
                              ),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                sw ? mobileUi(context, 'Tuma') : mobileUi(context, 'Send'),
              ),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      setState(() => busy = true);
      try {
        final booking = await widget.repository.createIndividualEventBooking(
          kind: widget.kind,
          id: widget.id,
          startsAt: start,
          endsAt: end,
          quantity: widget.kind == 'equipment'
              ? int.parse(quantity.text)
              : null,
          message: notes.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${sw ? mobileUi(context, 'Ombi limetumwa') : mobileUi(context, 'Request sent')}: ${booking['reference']}',
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
        if (mounted) {
          setState(() => busy = false);
        }
      }
    }
    quantity.dispose();
    notes.dispose();
  }
}
