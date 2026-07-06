import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import 'app_scope.dart';

class AgentLocationSelection {
  const AgentLocationSelection({
    this.regionId,
    this.districtId,
    this.wardId,
    this.savedAreaId,
    this.manualAreaName = "",
    this.savedAreaCount = 0,
  });

  final String? regionId;
  final String? districtId;
  final String? wardId;
  final String? savedAreaId;
  final String manualAreaName;
  final int savedAreaCount;

  bool get canCreateNewArea => wardId != null && savedAreaCount < 100;
  bool get hasAreaSelection =>
      (savedAreaId != null && savedAreaId!.isNotEmpty) ||
      manualAreaName.trim().isNotEmpty;
}

class AgentLocationFields extends StatefulWidget {
  const AgentLocationFields({super.key, required this.onChanged});

  final ValueChanged<AgentLocationSelection> onChanged;

  @override
  State<AgentLocationFields> createState() => _AgentLocationFieldsState();
}

class _AgentLocationFieldsState extends State<AgentLocationFields> {
  final TextEditingController _manualAreaController = TextEditingController();

  bool _bootstrapped = false;
  bool _loading = true;
  String? _error;
  String? _regionId;
  String? _districtId;
  String? _wardId;
  String? _savedAreaId;

  Map<String, List<Map<String, dynamic>>> _childrenCache =
      <String, List<Map<String, dynamic>>>{};
  List<Map<String, dynamic>> _regions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _districts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _wards = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _areas = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _manualAreaController.addListener(_handleManualAreaChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _manualAreaController
      ..removeListener(_handleManualAreaChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = AppScope.of(context).repository;
      final List<Map<String, dynamic>> locations = await repository
          .fetchAgentLocationHierarchy();
      final List<Map<String, dynamic>> countries = locations
          .where(
            (Map<String, dynamic> item) =>
                item["location_type"] == LocationType.country.storageValue,
          )
          .toList(growable: false);
      if (countries.length != 1) {
        throw StateError(
          "Expected one active country before agent location registration can continue.",
        );
      }
      if (!mounted) {
        return;
      }
      final String countryId = countries.first["id"] as String;
      final Map<String, List<Map<String, dynamic>>> childrenCache =
          <String, List<Map<String, dynamic>>>{};
      for (final Map<String, dynamic> item in locations) {
        final String? parentId = item["parent_id"] as String?;
        final String? locationType = item["location_type"] as String?;
        if (parentId == null || locationType == null) {
          continue;
        }
        final String cacheKey = "$parentId::$locationType";
        final List<Map<String, dynamic>> bucket =
            childrenCache.putIfAbsent(
              cacheKey,
              () => <Map<String, dynamic>>[],
            );
        bucket.add(Map<String, dynamic>.from(item));
      }
      setState(() {
        _childrenCache = childrenCache;
        _regions = _childrenOf(parentId: countryId, type: LocationType.region);
        _loading = false;
      });
      _emit();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<Map<String, dynamic>> _childrenOf({
    required String parentId,
    required LocationType type,
  }) {
    final List<Map<String, dynamic>> children =
        _childrenCache["$parentId::${type.storageValue}"] ??
        <Map<String, dynamic>>[];
    return children
        .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  void _loadDistricts(String? regionId) {
    setState(() {
      _districts = regionId == null
          ? <Map<String, dynamic>>[]
          : _childrenOf(parentId: regionId, type: LocationType.district);
      _districtId = null;
      _wards = <Map<String, dynamic>>[];
      _wardId = null;
      _areas = <Map<String, dynamic>>[];
      _savedAreaId = null;
      _manualAreaController.clear();
    });
    _emit();
  }

  void _loadWards(String? districtId) {
    setState(() {
      _wards = districtId == null
          ? <Map<String, dynamic>>[]
          : _childrenOf(parentId: districtId, type: LocationType.ward);
      _wardId = null;
      _areas = <Map<String, dynamic>>[];
      _savedAreaId = null;
      _manualAreaController.clear();
    });
    _emit();
  }

  void _loadAreas(String? wardId) {
    setState(() {
      _areas = wardId == null
          ? <Map<String, dynamic>>[]
          : _childrenOf(parentId: wardId, type: LocationType.area);
      _savedAreaId = null;
      _manualAreaController.clear();
    });
    _emit();
  }

  void _handleManualAreaChanged() {
    if (_manualAreaController.text.trim().isNotEmpty && _savedAreaId != null) {
      setState(() => _savedAreaId = null);
    }
    _emit();
  }

  void _emit() {
    widget.onChanged(
      AgentLocationSelection(
        regionId: _regionId,
        districtId: _districtId,
        wardId: _wardId,
        savedAreaId: _savedAreaId,
        manualAreaName: _manualAreaController.text.trim(),
        savedAreaCount: _areas.length,
      ),
    );
  }

  String? _labelFor(List<Map<String, dynamic>> items, String? id) {
    if (id == null) {
      return null;
    }
    for (final Map<String, dynamic> item in items) {
      if (item["id"] == id) {
        return item["name"] as String?;
      }
    }
    return null;
  }

  Widget _menuText(String value) {
    return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  bool _matchesSearch(String label, String query) {
    final String normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(normalizedQuery);
  }

  Future<String?> _pickLocation({
    required String title,
    required List<Map<String, dynamic>> items,
    String? selectedId,
    String? emptyValue,
    String? emptyLabel,
  }) async {
    final TextEditingController searchController = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final String query = searchController.text;
            final List<Map<String, dynamic>> filteredItems = items
                .where((Map<String, dynamic> item) {
                  final String label = item["name"] as String? ?? "";
                  return _matchesSearch(label, query);
                })
                .toList(growable: false);
            return FractionallySizedBox(
              heightFactor: 0.92,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        labelText: "Search",
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filteredItems.isEmpty &&
                            (emptyValue == null || emptyLabel == null)
                        ? const Center(
                            child: Text("No matching locations found."),
                          )
                        : ListView(
                            children: <Widget>[
                              if (emptyValue != null && emptyLabel != null)
                                ListTile(
                                  title: Text(emptyLabel),
                                  trailing: selectedId == emptyValue
                                      ? const Icon(Icons.check_rounded)
                                      : null,
                                  onTap: () =>
                                      Navigator.of(context).pop(emptyValue),
                                ),
                              ...filteredItems.map((Map<String, dynamic> item) {
                                final String value = item["id"] as String? ?? "";
                                final String label =
                                    item["name"] as String? ?? "-";
                                return ListTile(
                                  title: _menuText(label),
                                  trailing: selectedId == value
                                      ? const Icon(Icons.check_rounded)
                                      : null,
                                  onTap: () =>
                                      Navigator.of(context).pop(value),
                                );
                              }),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(searchController.dispose);
  }

  Widget _selectionField({
    required String label,
    required String valueText,
    required bool enabled,
    String? helperText,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: enabled ? () => unawaited(onTap()) : null,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          enabled: enabled,
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: _menuText(valueText)),
            const SizedBox(width: 12),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_error!),
      );
    }

    final bool wardReady = _wardId != null;
    final bool canCreateArea = wardReady && _areas.length < 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _selectionField(
          label: "Region *",
          valueText: _labelFor(_regions, _regionId) ?? "Choose region",
          enabled: _regions.isNotEmpty,
          onTap: () async {
            final String? value = await _pickLocation(
              title: "Choose region",
              items: _regions,
              selectedId: _regionId,
            );
            if (!mounted || value == null) {
              return;
            }
            setState(() => _regionId = value);
            _loadDistricts(value);
          },
        ),
        const SizedBox(height: 16),
        _selectionField(
          label: "District *",
          valueText: _labelFor(_districts, _districtId) ?? "Choose district",
          enabled: _districts.isNotEmpty,
          onTap: () async {
            final String? value = await _pickLocation(
              title: "Choose district",
              items: _districts,
              selectedId: _districtId,
            );
            if (!mounted || value == null) {
              return;
            }
            setState(() => _districtId = value);
            _loadWards(value);
          },
        ),
        const SizedBox(height: 16),
        _selectionField(
          label: "Ward *",
          valueText: _labelFor(_wards, _wardId) ?? "Choose ward",
          enabled: _wards.isNotEmpty,
          onTap: () async {
            final String? value = await _pickLocation(
              title: "Choose ward",
              items: _wards,
              selectedId: _wardId,
            );
            if (!mounted || value == null) {
              return;
            }
            setState(() => _wardId = value);
            _loadAreas(value);
          },
        ),
        const SizedBox(height: 16),
        _selectionField(
          label: "Saved area",
          helperText: "Reuse an existing area in this ward if it already exists.",
          valueText: _savedAreaId == null
              ? "Type a new area or choose one below"
              : (_labelFor(_areas, _savedAreaId) ?? "Saved area selected"),
          enabled: wardReady,
          onTap: () async {
            final String? value = await _pickLocation(
              title: "Choose saved area",
              items: _areas,
              selectedId: _savedAreaId ?? "",
              emptyValue: "",
              emptyLabel: "Type a new area or choose one below",
            );
            if (!mounted || value == null) {
              return;
            }
            setState(() {
              _savedAreaId = value.isEmpty ? null : value;
              if (_savedAreaId != null) {
                _manualAreaController.clear();
              }
            });
            _emit();
          },
        ),
        const SizedBox(height: 8),
        Text(
          "Saved areas in this ward: ${_areas.length}/100",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _manualAreaController,
          enabled: canCreateArea,
          decoration: InputDecoration(
            labelText: "New area name",
            helperText: !wardReady
                ? "Choose region, district, and ward first."
                : canCreateArea
                ? "If this area does not exist yet, type it here and it will be saved under the selected ward."
                : "This ward already has 100 saved areas, so only the saved list can be used.",
          ),
        ),
      ],
    );
  }
}
