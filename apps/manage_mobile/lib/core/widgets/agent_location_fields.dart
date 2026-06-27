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
  String? _countryId;
  String? _regionId;
  String? _districtId;
  String? _wardId;
  String? _savedAreaId;

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
      final List<Map<String, dynamic>> countries = await repository
          .fetchLocations(parentId: null, type: LocationType.country);
      if (countries.length != 1) {
        throw StateError(
          "Expected one active country before agent location registration can continue.",
        );
      }
      _countryId = countries.first["id"] as String;
      _regions = await repository.fetchLocations(
        parentId: _countryId,
        type: LocationType.region,
      );
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
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

  Future<void> _loadDistricts(String? regionId) async {
    final repository = AppScope.of(context).repository;
    final List<Map<String, dynamic>> districts = regionId == null
        ? <Map<String, dynamic>>[]
        : await repository.fetchLocations(
            parentId: regionId,
            type: LocationType.district,
          );
    if (!mounted) {
      return;
    }
    setState(() {
      _districts = districts;
      _districtId = null;
      _wards = <Map<String, dynamic>>[];
      _wardId = null;
      _areas = <Map<String, dynamic>>[];
      _savedAreaId = null;
      _manualAreaController.clear();
    });
    _emit();
  }

  Future<void> _loadWards(String? districtId) async {
    final repository = AppScope.of(context).repository;
    final List<Map<String, dynamic>> wards = districtId == null
        ? <Map<String, dynamic>>[]
        : await repository.fetchLocations(
            parentId: districtId,
            type: LocationType.ward,
          );
    if (!mounted) {
      return;
    }
    setState(() {
      _wards = wards;
      _wardId = null;
      _areas = <Map<String, dynamic>>[];
      _savedAreaId = null;
      _manualAreaController.clear();
    });
    _emit();
  }

  Future<void> _loadAreas(String? wardId) async {
    final repository = AppScope.of(context).repository;
    final List<Map<String, dynamic>> areas = wardId == null
        ? <Map<String, dynamic>>[]
        : await repository.fetchLocations(
            parentId: wardId,
            type: LocationType.area,
          );
    if (!mounted) {
      return;
    }
    setState(() {
      _areas = areas;
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

  Widget _menuText(String value) {
    return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
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
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _regionId,
          decoration: const InputDecoration(labelText: "Region *"),
          items: _regions
              .map(
                (Map<String, dynamic> item) => DropdownMenuItem<String>(
                  value: item["id"] as String,
                  child: _menuText(item["name"] as String? ?? "-"),
                ),
              )
              .toList(),
          onChanged: (String? value) async {
            setState(() => _regionId = value);
            await _loadDistricts(value);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _districtId,
          decoration: const InputDecoration(labelText: "District *"),
          items: _districts
              .map(
                (Map<String, dynamic> item) => DropdownMenuItem<String>(
                  value: item["id"] as String,
                  child: _menuText(item["name"] as String? ?? "-"),
                ),
              )
              .toList(),
          onChanged: (String? value) async {
            setState(() => _districtId = value);
            await _loadWards(value);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _wardId,
          decoration: const InputDecoration(labelText: "Ward *"),
          items: _wards
              .map(
                (Map<String, dynamic> item) => DropdownMenuItem<String>(
                  value: item["id"] as String,
                  child: _menuText(item["name"] as String? ?? "-"),
                ),
              )
              .toList(),
          onChanged: (String? value) async {
            setState(() => _wardId = value);
            await _loadAreas(value);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _savedAreaId ?? "",
          decoration: const InputDecoration(
            labelText: "Saved area",
            helperText:
                "Reuse an existing area in this ward if it already exists.",
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: "",
              child: Text(
                "Type a new area or choose one below",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ..._areas.map(
              (Map<String, dynamic> item) => DropdownMenuItem<String>(
                value: item["id"] as String,
                child: _menuText(item["name"] as String? ?? "-"),
              ),
            ),
          ],
          onChanged: !wardReady
              ? null
              : (String? value) {
                  setState(() {
                    _savedAreaId = value == null || value.isEmpty
                        ? null
                        : value;
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
