import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/manage_ui.dart';

class LocationsTab extends StatefulWidget {
  const LocationsTab({super.key});

  @override
  State<LocationsTab> createState() => _LocationsTabState();
}

class _LocationsTabState extends State<LocationsTab> {
  late Future<List<Map<String, dynamic>>> _future;
  final TextEditingController _nameController = TextEditingController();
  LocationType _type = LocationType.region;
  String? _parentId;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _future = _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return AppScope.of(context).repository.fetchLocationsForAdmin();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _addLocation() async {
    if (_nameController.text.trim().isEmpty) {
      return;
    }
    await AppScope.of(context).repository.addLocation(
      name: _nameController.text.trim(),
      type: _type,
      parentId: _parentId,
    );
    _nameController.clear();
    setState(() {
      _parentId = null;
    });
    await _refresh();
  }

  bool _supportsParent(LocationType type) {
    return type != LocationType.country;
  }

  bool _isValidParent(LocationType childType, Map<String, dynamic> candidate) {
    final String parentType = candidate["location_type"] as String? ?? "";
    switch (childType) {
      case LocationType.country:
        return false;
      case LocationType.region:
        return parentType == LocationType.country.storageValue;
      case LocationType.district:
        return parentType == LocationType.region.storageValue;
      case LocationType.ward:
        return parentType == LocationType.district.storageValue;
      case LocationType.area:
        return parentType == LocationType.ward.storageValue;
      case LocationType.street:
        return parentType == LocationType.area.storageValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final List<Map<String, dynamic>> locations =
            snapshot.data ?? <Map<String, dynamic>>[];
        final List<Map<String, dynamic>> parentOptions = locations
            .where((Map<String, dynamic> item) => _isValidParent(_type, item))
            .toList();
        if (_parentId != null &&
            !parentOptions.any(
              (Map<String, dynamic> item) => item["id"] == _parentId,
            )) {
          _parentId = null;
        }

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Locations",
              subtitle:
                  "Grow the official hierarchy carefully so selectors stay structured across apps and website.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${locations.length} location${locations.length == 1 ? "" : "s"}",
                  "Required chain: Region, District, Ward, Area",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Add location",
              subtitle:
                  "Use the parent field to keep the Region -> District -> Ward -> Area -> Street flow intact.",
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: _nameController,
                    onChanged: (String value) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: "Location name",
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<LocationType>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: "Location type",
                    ),
                    items: LocationType.values
                        .map(
                          (LocationType item) => DropdownMenuItem<LocationType>(
                            value: item,
                            child: Text(item.storageValue),
                          ),
                        )
                        .toList(),
                    onChanged: (LocationType? value) {
                      if (value != null) {
                        setState(() {
                          _type = value;
                          if (!_supportsParent(value)) {
                            _parentId = null;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _parentId,
                    decoration: const InputDecoration(
                      labelText: "Parent location",
                    ),
                    items: parentOptions
                        .map(
                          (Map<String, dynamic> item) =>
                              DropdownMenuItem<String>(
                                value: item["id"] as String,
                                child: Text(
                                  "${item["name"]} (${item["location_type"]})",
                                ),
                              ),
                        )
                        .toList(),
                    onChanged: !_supportsParent(_type)
                        ? null
                        : (String? value) {
                            setState(() => _parentId = value);
                          },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _parentId == null
                          ? null
                          : () => setState(() => _parentId = null),
                      child: const Text("Clear parent location"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _nameController.text.trim().isEmpty
                          ? null
                          : _addLocation,
                      child: const Text("Add location"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Current hierarchy",
              subtitle:
                  "Tap refresh anytime after adding a new official location node.",
              child: locations.isEmpty
                  ? const KodimaliEmptyState(
                      title: "Hakuna locations",
                      message:
                          "Admin anaweza kuongeza hierarchy ya maeneo hapa.",
                    )
                  : Column(
                      children: locations.map((Map<String, dynamic> item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              title: Text(item["name"] as String? ?? "-"),
                              subtitle: Text(
                                item["location_type"] as String? ?? "-",
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}
