import 'package:flutter/material.dart';

import '../../core/data/customer_public_repository.dart';

typedef _JsonMap = Map<String, dynamic>;

class EventLocationSelection {
  const EventLocationSelection({
    this.regionId,
    this.districtId,
    this.wardId,
    this.areaId,
    required this.label,
  });

  final String? regionId;
  final String? districtId;
  final String? wardId;
  final String? areaId;
  final String label;

  String? get locationId => areaId ?? wardId ?? districtId ?? regionId;
}

class EventLocationPicker extends StatefulWidget {
  const EventLocationPicker({
    super.key,
    required this.repository,
    required this.swahili,
    this.initialRegionId,
    this.initialDistrictId,
    this.initialWardId,
    this.initialAreaId,
  });

  final CustomerPublicRepository repository;
  final bool swahili;
  final String? initialRegionId;
  final String? initialDistrictId;
  final String? initialWardId;
  final String? initialAreaId;

  @override
  State<EventLocationPicker> createState() => _EventLocationPickerState();
}

class _EventLocationPickerState extends State<EventLocationPicker> {
  List<_JsonMap> regions = <_JsonMap>[];
  List<_JsonMap> districts = <_JsonMap>[];
  List<_JsonMap> wards = <_JsonMap>[];
  List<_JsonMap> areas = <_JsonMap>[];
  String? regionId;
  String? districtId;
  String? wardId;
  String? areaId;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final countries = await widget.repository.fetchLocations(
        parentId: null,
        locationType: 'country',
      );
      final countryId = countries.isEmpty
          ? null
          : countries.first['id']?.toString();
      regions = await widget.repository.fetchLocations(
        parentId: countryId,
        locationType: 'region',
      );
      if (regions.isEmpty) {
        regions = await widget.repository.fetchLocations(
          parentId: null,
          locationType: 'region',
        );
      }
      regionId = _existing(regions, widget.initialRegionId);
      if (regionId != null) await _selectRegion(regionId!, restoring: true);
      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.toString();
        });
      }
    }
  }

  String? _existing(List<_JsonMap> rows, String? id) =>
      id != null && rows.any((row) => row['id'] == id) ? id : null;

  Future<void> _selectRegion(String value, {bool restoring = false}) async {
    if (!restoring) setState(() => loading = true);
    regionId = value;
    districtId = wardId = areaId = null;
    wards = areas = <_JsonMap>[];
    districts = await widget.repository.fetchLocations(
      parentId: value,
      locationType: 'district',
    );
    districtId = _existing(districts, widget.initialDistrictId);
    if (districtId != null) await _selectDistrict(districtId!, restoring: true);
    if (mounted && !restoring) setState(() => loading = false);
  }

  Future<void> _selectDistrict(String value, {bool restoring = false}) async {
    if (!restoring) setState(() => loading = true);
    districtId = value;
    wardId = areaId = null;
    areas = <_JsonMap>[];
    wards = await widget.repository.fetchLocations(
      parentId: value,
      locationType: 'ward',
    );
    wardId = _existing(wards, widget.initialWardId);
    if (wardId != null) await _selectWard(wardId!, restoring: true);
    if (mounted && !restoring) setState(() => loading = false);
  }

  Future<void> _selectWard(String value, {bool restoring = false}) async {
    if (!restoring) setState(() => loading = true);
    wardId = value;
    areaId = null;
    areas = await widget.repository.fetchLocations(
      parentId: value,
      locationType: 'area',
    );
    areaId = _existing(areas, widget.initialAreaId);
    if (mounted && !restoring) setState(() => loading = false);
  }

  String _name(List<_JsonMap> rows, String? id) =>
      rows
          .where((row) => row['id'] == id)
          .map((row) => row['name']?.toString() ?? '')
          .firstOrNull ??
      '';

  @override
  Widget build(BuildContext context) {
    if (loading && regions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) return Center(child: Text(error!));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.swahili ? 'Chagua eneo la tukio' : 'Choose event location',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            widget.swahili
                ? 'Chagua mkoa, wilaya, kata na eneo kwa mpangilio.'
                : 'Choose the region, district, ward and area in order.',
          ),
          const SizedBox(height: 20),
          _dropdown(
            widget.swahili ? 'Mkoa' : 'Region',
            regions,
            regionId,
            (value) => _selectRegion(value),
          ),
          _dropdown(
            widget.swahili ? 'Wilaya' : 'District',
            districts,
            districtId,
            regionId == null ? null : (value) => _selectDistrict(value),
          ),
          _dropdown(
            widget.swahili ? 'Kata' : 'Ward',
            wards,
            wardId,
            districtId == null ? null : (value) => _selectWard(value),
          ),
          _dropdown(
            widget.swahili ? 'Eneo' : 'Area',
            areas,
            areaId,
            wardId == null
                ? null
                : (value) async => setState(() => areaId = value),
          ),
          if (loading) const LinearProgressIndicator(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: regionId == null
                ? null
                : () {
                    final names = <String>[
                      _name(areas, areaId),
                      _name(wards, wardId),
                      _name(districts, districtId),
                      _name(regions, regionId),
                    ].where((name) => name.isNotEmpty).toList();
                    Navigator.pop(
                      context,
                      EventLocationSelection(
                        regionId: regionId,
                        districtId: districtId,
                        wardId: wardId,
                        areaId: areaId,
                        label: names.join(', '),
                      ),
                    );
                  },
            icon: const Icon(Icons.check_rounded),
            label: Text(
              widget.swahili ? 'Tumia eneo hili' : 'Use this location',
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(
    String label,
    List<_JsonMap> rows,
    String? value,
    Future<void> Function(String value)? onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: rows
          .map(
            (row) => DropdownMenuItem<String>(
              value: row['id'].toString(),
              child: Text(row['name']?.toString() ?? '-'),
            ),
          )
          .toList(),
      onChanged: onChanged == null
          ? null
          : (next) {
              if (next != null) onChanged(next);
            },
    ),
  );
}
