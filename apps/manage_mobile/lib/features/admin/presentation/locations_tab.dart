import 'dart:async';

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
  final TextEditingController _searchController = TextEditingController();

  LocationType _type = LocationType.region;
  String? _parentId;
  bool _initialized = false;
  bool _saving = false;
  String? _deletingLocationId;

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
    _searchController.dispose();
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
    final String trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      return;
    }
    if (_supportsParent(_type) && (_parentId == null || _parentId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Choose a ${_expectedParentLabel(_type)} first."),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await AppScope.of(context).repository.addLocation(
        name: trimmedName,
        type: _type,
        parentId: _parentId,
      );
      if (!mounted) {
        return;
      }
      _nameController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Location added.")));
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteLocation(Map<String, dynamic> location) async {
    final String locationId = location["id"] as String? ?? "";
    final String locationName = location["name"] as String? ?? "this location";
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Delete location?"),
        content: Text(
          "$locationName will be deleted only if it has no child locations and is not already in use.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true || locationId.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _deletingLocationId = locationId);
    final repository = AppScope.of(context).repository;
    try {
      await repository.deleteLocation(locationId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Location deleted.")));
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _deletingLocationId = null);
      }
    }
  }

  bool _supportsParent(LocationType type) {
    return type != LocationType.country;
  }

  bool _isValidParent(LocationType childType, Map<String, dynamic> candidate) {
    if (candidate["is_active"] != true) {
      return false;
    }
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

  LocationType? _expectedParentType(LocationType childType) {
    switch (childType) {
      case LocationType.country:
        return null;
      case LocationType.region:
        return LocationType.country;
      case LocationType.district:
        return LocationType.region;
      case LocationType.ward:
        return LocationType.district;
      case LocationType.area:
        return LocationType.ward;
      case LocationType.street:
        return LocationType.area;
    }
  }

  String _expectedParentLabel(LocationType childType) {
    return _expectedParentType(childType)?.storageValue ?? "parent location";
  }

  String _typeLabel(LocationType type) {
    final String raw = type.storageValue.replaceAll("_", " ");
    return raw[0].toUpperCase() + raw.substring(1);
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

  bool _matchesSearch(
    Map<String, dynamic> item,
    Map<String, Map<String, dynamic>> byId,
    String query,
  ) {
    final String normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final Map<String, dynamic>? parent = byId[item["parent_id"]];
    final Iterable<String> haystack = <String>[
      item["name"] as String? ?? "",
      item["location_type"] as String? ?? "",
      parent?["name"] as String? ?? "",
      parent?["location_type"] as String? ?? "",
    ];
    for (final String value in haystack) {
      if (value.toLowerCase().contains(normalizedQuery)) {
        return true;
      }
    }
    return false;
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
            final String query = searchController.text.trim().toLowerCase();
            final List<Map<String, dynamic>> filteredItems = items
                .where((Map<String, dynamic> item) {
                  final String label = item["name"] as String? ?? "";
                  return query.isEmpty || label.toLowerCase().contains(query);
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
                    child:
                        filteredItems.isEmpty &&
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
                                final String value =
                                    item["id"] as String? ?? "";
                                final String label =
                                    item["name"] as String? ?? "-";
                                final String type =
                                    item["location_type"] as String? ?? "";
                                return ListTile(
                                  title: Text(label),
                                  subtitle: Text(type),
                                  trailing: selectedId == value
                                      ? const Icon(Icons.check_rounded)
                                      : null,
                                  onTap: () => Navigator.of(context).pop(value),
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
            Expanded(
              child: Text(
                valueText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }

  List<String> _summaryItems(List<Map<String, dynamic>> locations) {
    final Map<String, int> counts = <String, int>{};
    for (final LocationType type in LocationType.values) {
      counts[type.storageValue] = locations.where((Map<String, dynamic> item) {
        return item["location_type"] == type.storageValue &&
            item["is_active"] == true;
      }).length;
    }
    return <String>[
      "${counts[LocationType.region.storageValue] ?? 0} regions",
      "${counts[LocationType.district.storageValue] ?? 0} districts",
      "${counts[LocationType.ward.storageValue] ?? 0} wards",
      "${counts[LocationType.area.storageValue] ?? 0} areas",
      "${counts[LocationType.street.storageValue] ?? 0} streets",
    ];
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
        final Map<String, Map<String, dynamic>> byId =
            <String, Map<String, dynamic>>{
              for (final Map<String, dynamic> item in locations)
                if ((item["id"] as String?) != null) item["id"] as String: item,
            };
        final List<Map<String, dynamic>> parentOptions = locations
            .where((Map<String, dynamic> item) => _isValidParent(_type, item))
            .toList(growable: false);
        final String? selectedParentId =
            parentOptions.any(
              (Map<String, dynamic> item) => item["id"] == _parentId,
            )
            ? _parentId
            : null;
        final String searchQuery = _searchController.text.trim();
        final List<Map<String, dynamic>> matchingLocations = locations
            .where((Map<String, dynamic> item) {
              return _matchesSearch(item, byId, searchQuery);
            })
            .toList(growable: false);
        final List<Map<String, dynamic>> visibleLocations = matchingLocations
            .take(160)
            .toList(growable: false);

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Locations",
              subtitle:
                  "Add official regions, districts, wards, areas, and streets in a controlled hierarchy, then clean up unused mistakes safely.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${locations.length} total records",
                  ..._summaryItems(locations),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Add location",
              subtitle:
                  "Choose the exact parent level so the hierarchy stays valid across customer app, manage app, and web.",
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: "Location name",
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<LocationType>(
                    isExpanded: true,
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: "Location type",
                    ),
                    items: LocationType.values
                        .map(
                          (LocationType item) => DropdownMenuItem<LocationType>(
                            value: item,
                            child: Text(_typeLabel(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (LocationType? value) {
                      if (value == null) {
                        return;
                      }
                      final List<Map<String, dynamic>> nextParents = locations
                          .where(
                            (Map<String, dynamic> item) =>
                                _isValidParent(value, item),
                          )
                          .toList(growable: false);
                      setState(() {
                        _type = value;
                        _parentId = nextParents.length == 1
                            ? nextParents.first["id"] as String?
                            : null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _selectionField(
                    label: "Parent location",
                    valueText: !_supportsParent(_type)
                        ? "Country has no parent"
                        : (_labelFor(parentOptions, selectedParentId) ??
                              "Choose ${_expectedParentLabel(_type)}"),
                    enabled: _supportsParent(_type),
                    helperText: !_supportsParent(_type)
                        ? null
                        : "Required parent type: ${_expectedParentLabel(_type)}",
                    onTap: () async {
                      final String? value = await _pickLocation(
                        title: "Choose ${_expectedParentLabel(_type)}",
                        items: parentOptions,
                        selectedId: selectedParentId ?? "",
                        emptyValue: "",
                        emptyLabel: "Clear parent selection",
                      );
                      if (!mounted || value == null) {
                        return;
                      }
                      setState(() => _parentId = value.isEmpty ? null : value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving || _nameController.text.trim().isEmpty
                          ? null
                          : _addLocation,
                      child: Text(_saving ? "Saving..." : "Add location"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Search and delete",
              subtitle:
                  "To keep the app fast, this view shows matching results only. Delete works only for unused locations with no child nodes.",
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: "Search locations",
                      hintText:
                          "Type a region, district, ward, area, or street",
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      searchQuery.isEmpty
                          ? "Showing the first ${visibleLocations.length} records. Search to narrow down faster."
                          : "Showing ${visibleLocations.length} of ${matchingLocations.length} matching locations.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (visibleLocations.isEmpty)
                    const KodimaliEmptyState(
                      title: "No matching locations",
                      message:
                          "Try another search term or add the missing location above.",
                    )
                  else
                    SizedBox(
                      height: 460,
                      child: ListView.separated(
                        itemCount: visibleLocations.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> item =
                              visibleLocations[index];
                          final String itemId = item["id"] as String? ?? "";
                          final Map<String, dynamic>? parent =
                              byId[item["parent_id"] as String?];
                          final bool deleting = _deletingLocationId == itemId;
                          final bool canDelete =
                              (item["location_type"] as String? ?? "") !=
                              LocationType.country.storageValue;
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              title: Text(item["name"] as String? ?? "-"),
                              subtitle: Text(
                                [
                                  item["location_type"] as String? ?? "-",
                                  if (parent != null)
                                    "Parent: ${parent["name"]} (${parent["location_type"]})",
                                  if (item["is_active"] != true) "Inactive",
                                ].join("  •  "),
                              ),
                              trailing: canDelete
                                  ? IconButton(
                                      tooltip: "Delete location",
                                      onPressed: deleting
                                          ? null
                                          : () => _deleteLocation(item),
                                      icon: deleting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_outline_rounded,
                                            ),
                                    )
                                  : null,
                            ),
                          );
                        },
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 8),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
