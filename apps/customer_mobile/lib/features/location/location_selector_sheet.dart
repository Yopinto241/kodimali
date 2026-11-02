import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_core/localized_ui.dart';
import '../../core/data/customer_public_repository.dart';

class LocationSelectorSheet extends StatefulWidget {
  const LocationSelectorSheet({
    super.key,
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
  State<LocationSelectorSheet> createState() => _LocationSelectorSheetState();
}

class _LocationSelectorSheetState extends State<LocationSelectorSheet> {
  final _cache = <String, List<JsonMap>>{};
  List<String?> _ids = List.filled(4, null);
  List<List<JsonMap>> _options = List.generate(4, (_) => []);
  int _request = 0;
  bool _loading = true;
  bool _booting = true;
  String? _error;
  static const _types = ['region', 'district', 'ward', 'area'];
  static const _labels = ['Region', 'District', 'Ward', 'Area'];
  @override
  void initState() {
    super.initState();
    _ids = [
      widget.initialRegionId,
      widget.initialDistrictId,
      widget.initialWardId,
      widget.initialAreaId,
    ];
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final countries = await widget.repository.fetchLocations(
        parentId: null,
        locationType: 'country',
      );
      final country =
          countries
              .where(
                (row) => row['name'].toString().toLowerCase() == 'tanzania',
              )
              .firstOrNull ??
          countries.firstOrNull;
      final regions = await widget.repository.fetchLocations(
        parentId: country?['id'] as String?,
        locationType: 'region',
      );
      if (!mounted || request != _request) return;
      if (!regions.any((row) => row['id'] == _ids[0])) {
        _ids = List.filled(4, null);
      }
      setState(() {
        _options = [regions, [], [], []];
        _booting = false;
      });
      await _children();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = 'Could not load locations. Please try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _children() async {
    final request = ++_request;
    final ids = List<String?>.from(_ids);
    final options = <List<JsonMap>>[_options[0], [], [], []];
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      for (var level = 1; level < 4; level++) {
        final parent = ids[level - 1];
        if (parent == null) break;
        final key = '${_types[level]}:$parent';
        final rows =
            _cache[key] ??
            await widget.repository.fetchLocations(
              parentId: parent,
              locationType: _types[level],
            );
        if (!mounted || request != _request) return;
        _cache[key] = rows;
        options[level] = rows;
        if (ids[level] != null && !rows.any((row) => row['id'] == ids[level])) {
          for (var child = level; child < 4; child++) {
            ids[child] = null;
          }
        }
      }
      if (mounted && request == _request) {
        setState(() {
          _ids = ids;
          _options = options;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = 'Could not load locations. Please try again.';
          _loading = false;
        });
      }
    }
  }

  void _select(int level, String? id) {
    setState(() {
      for (var index = level; index < 4; index++) {
        _ids[index] = index == level && id?.isNotEmpty == true ? id : null;
        if (index > level) _options[index] = [];
      }
    });
    _children();
  }

  void _apply(List<String?> ids) => Navigator.pop(context, {
    'regionId': ids[0],
    'districtId': ids[1],
    'wardId': ids[2],
    'areaId': ids[3],
  });
  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: math.min(
        660,
        (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .88,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocalizedUiText(
                'Choose location',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const LocalizedUiText(
                'Choose only the location levels you need. Other filters stay unchanged.',
              ),
              if (_loading) const LinearProgressIndicator(),
              Column(
                children: [
                  if (!_booting)
                    for (var index = 0; index < 4; index++)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(
                            '${_types[index]}:${_ids.take(index).join(":")}',
                          ),
                          initialValue: _ids[index] ?? '',
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: mobileUi(context, _labels[index]),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: LocalizedUiText(
                                [
                                  'All regions',
                                  'All districts',
                                  'All wards',
                                  'All areas',
                                ][index],
                              ),
                            ),
                            ..._options[index].map(
                              (row) => DropdownMenuItem(
                                value: row['id'] as String,
                                child: Text(
                                  row['name'].toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged:
                              index > 0 && (_ids[index - 1] == null || _loading)
                              ? null
                              : (id) => _select(index, id),
                        ),
                      ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          LocalizedUiText(_error!),
                          TextButton(
                            onPressed: _booting ? _bootstrap : _children,
                            child: const LocalizedUiText('Retry'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _apply(List.filled(4, null)),
                    child: const LocalizedUiText('All locations'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LocalizedUiText('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _loading || _error != null
                        ? null
                        : () => _apply(_ids),
                    child: const LocalizedUiText('Show results'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
