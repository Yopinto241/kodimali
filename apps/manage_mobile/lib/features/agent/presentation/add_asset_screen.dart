import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_constants/shared_constants.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/models/upload_task.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/manage_ui.dart';

class AddAssetScreen extends StatefulWidget {
  const AddAssetScreen({super.key});

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  static const double _menuMaxHeight = 360;
  static const int _listingVideoMaxBytes = 30 * 1024 * 1024;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _ownerPhoneController = TextEditingController();
  final TextEditingController _ownerNotesController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
  final TextEditingController _rulesController = TextEditingController();
  final TextEditingController _exactAddressController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _manualAreaController = TextEditingController();

  final Map<String, TextEditingController> _attributeControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _attributeBooleans = <String, bool>{};
  final Map<String, String?> _attributeSelections = <String, String?>{};

  bool _creatingOwner = true;
  bool _submitting = false;
  bool _bootstrapped = false;
  bool _bootstrapLoading = true;
  String? _bootstrapError;
  PricePeriod _pricePeriod = PricePeriod.day;
  String _availabilityStatus = "available";
  UploadTaskController? _uploadController;
  UploadProgressSnapshot? _uploadProgress;

  List<Map<String, dynamic>> _owners = <Map<String, dynamic>>[];
  String? _selectedOwnerId;

  List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[];
  Map<String, dynamic>? _selectedCategory;

  String? _regionId;
  String? _districtId;
  String? _wardId;
  String? _areaId;
  String? _streetId;

  Map<String, List<Map<String, dynamic>>> _locationChildrenCache =
      <String, List<Map<String, dynamic>>>{};
  List<Map<String, dynamic>> _regions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _districts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _wards = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _areas = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _streets = <Map<String, dynamic>>[];

  List<XFile> _images = <XFile>[];
  XFile? _video;
  int _coverImageIndex = 0;

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapLoading = true;
      _bootstrapError = null;
    });
    try {
      await Future.wait<void>(<Future<void>>[
        _loadOwners(),
        _loadLocationHierarchy(),
        _loadCategories(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() => _bootstrapLoading = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _bootstrapLoading = false;
        _bootstrapError = error.toString();
      });
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _ownerNameController,
      _ownerPhoneController,
      _ownerNotesController,
      _titleController,
      _descriptionController,
      _priceController,
      _depositController,
      _rulesController,
      _exactAddressController,
      _latitudeController,
      _longitudeController,
      _manualAreaController,
      ..._attributeControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOwners() async {
    final List<Map<String, dynamic>> owners = await AppScope.of(
      context,
    ).repository.fetchOwnersForCurrentAgent();
    if (!mounted) {
      return;
    }
    setState(() {
      _owners = owners;
      if (_owners.isNotEmpty) {
        _selectedOwnerId ??= _owners.first["id"] as String;
        _creatingOwner = false;
      }
    });
  }

  Future<void> _loadLocationHierarchy() async {
    final List<Map<String, dynamic>> locations = await AppScope.of(
      context,
    ).repository.fetchAgentLocationHierarchy();
    final List<Map<String, dynamic>> countries = locations
        .where(
          (Map<String, dynamic> item) =>
              item["location_type"] == LocationType.country.storageValue,
        )
        .toList(growable: false);
    final String? nextCountryId = countries.length == 1
        ? countries.first["id"] as String?
        : null;
    final Map<String, List<Map<String, dynamic>>> childrenCache =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> item in locations) {
      final String? parentId = item["parent_id"] as String?;
      final String? locationType = item["location_type"] as String?;
      if (parentId == null || locationType == null) {
        continue;
      }
      final String cacheKey = "$parentId::$locationType";
      final List<Map<String, dynamic>> bucket = childrenCache.putIfAbsent(
        cacheKey,
        () => <Map<String, dynamic>>[],
      );
      bucket.add(Map<String, dynamic>.from(item));
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _locationChildrenCache = childrenCache;
      _regions = nextCountryId == null
          ? <Map<String, dynamic>>[]
          : _childrenOf(parentId: nextCountryId, type: LocationType.region);
      _districts = <Map<String, dynamic>>[];
      _wards = <Map<String, dynamic>>[];
      _areas = <Map<String, dynamic>>[];
      _streets = <Map<String, dynamic>>[];
      _regionId = null;
      _districtId = null;
      _wardId = null;
      _areaId = null;
      _streetId = null;
    });
  }

  Future<void> _loadCategories() async {
    final List<Map<String, dynamic>> categories = await AppScope.of(
      context,
    ).repository.fetchActiveCategories();
    if (!mounted) {
      return;
    }
    setState(() {
      _categories = categories;
      if (_categories.isNotEmpty) {
        _selectedCategory ??= _categories.first;
        _applyCategorySchema(_selectedCategory);
      } else {
        _selectedCategory = null;
      }
    });
  }

  List<Map<String, dynamic>> _schemaFieldsFor(Map<String, dynamic>? category) {
    if (category == null) {
      return const <Map<String, dynamic>>[];
    }
    dynamic rawSchema = category["field_schema"];
    if (rawSchema is String) {
      final String trimmed = rawSchema.trim();
      if (trimmed.isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      try {
        rawSchema = jsonDecode(trimmed);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
    if (rawSchema is Map) {
      final dynamic nested =
          rawSchema["fields"] ?? rawSchema["items"] ?? rawSchema["schema"];
      if (nested is List) {
        rawSchema = nested;
      } else if (rawSchema["key"] != null) {
        rawSchema = <dynamic>[rawSchema];
      } else {
        return rawSchema.entries
            .where((MapEntry<dynamic, dynamic> entry) => entry.value is Map)
            .map((MapEntry<dynamic, dynamic> entry) {
              final Map<String, dynamic> field = (entry.value as Map)
                  .cast<String, dynamic>();
              return <String, dynamic>{
                "key": field["key"] ?? entry.key.toString(),
                ...field,
              };
            })
            .toList();
      }
    }
    if (rawSchema is! List) {
      return const <Map<String, dynamic>>[];
    }
    return rawSchema
        .whereType<Map>()
        .map((Map item) => item.cast<String, dynamic>())
        .where((Map<String, dynamic> field) {
          final String key = field["key"]?.toString().trim() ?? "";
          return key.isNotEmpty;
        })
        .toList();
  }

  void _applyCategorySchema(Map<String, dynamic>? category) {
    for (final TextEditingController controller
        in _attributeControllers.values) {
      controller.dispose();
    }
    _attributeControllers.clear();
    _attributeBooleans.clear();
    _attributeSelections.clear();

    for (final Map<String, dynamic> field in _schemaFieldsFor(category)) {
      final String key = field["key"] as String? ?? "";
      final String type = field["type"] as String? ?? "text";
      if (key.isEmpty) {
        continue;
      }
      if (type == "boolean") {
        _attributeBooleans[key] = false;
      } else if (type == "select") {
        _attributeSelections[key] = null;
      } else {
        _attributeControllers[key] = TextEditingController();
      }
    }
  }

  String get _selectedCategorySlug =>
      _selectedCategory?["slug"] as String? ?? "";

  int get _maxImagesAllowed => _selectedCategorySlug == "apartment" ? 15 : 8;

  List<Map<String, dynamic>> _childrenOf({
    required String parentId,
    required LocationType type,
  }) {
    final List<Map<String, dynamic>> children =
        _locationChildrenCache["$parentId::${type.storageValue}"] ??
        <Map<String, dynamic>>[];
    return children
        .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  void _loadNextLevel({required LocationType type, required String? parentId}) {
    final List<Map<String, dynamic>> items = parentId == null
        ? <Map<String, dynamic>>[]
        : _childrenOf(parentId: parentId, type: type);
    setState(() {
      switch (type) {
        case LocationType.region:
          _regions = items;
          _regionId = null;
          _districts = <Map<String, dynamic>>[];
          _wards = <Map<String, dynamic>>[];
          _areas = <Map<String, dynamic>>[];
          _streets = <Map<String, dynamic>>[];
          _districtId = null;
          _wardId = null;
          _areaId = null;
          _streetId = null;
          _manualAreaController.clear();
          break;
        case LocationType.district:
          _districts = items;
          _districtId = null;
          _wards = <Map<String, dynamic>>[];
          _areas = <Map<String, dynamic>>[];
          _streets = <Map<String, dynamic>>[];
          _wardId = null;
          _areaId = null;
          _streetId = null;
          _manualAreaController.clear();
          break;
        case LocationType.ward:
          _wards = items;
          _wardId = null;
          _areas = <Map<String, dynamic>>[];
          _streets = <Map<String, dynamic>>[];
          _areaId = null;
          _streetId = null;
          _manualAreaController.clear();
          break;
        case LocationType.area:
          _areas = items;
          _areaId = null;
          _streets = <Map<String, dynamic>>[];
          _streetId = null;
          _manualAreaController.clear();
          break;
        case LocationType.street:
          _streets = items;
          _streetId = null;
          break;
        case LocationType.country:
          break;
      }
    });
  }

  Future<void> _pickImages() async {
    final List<XFile> picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) {
      return;
    }
    final int remaining = _maxImagesAllowed - _images.length;
    setState(() {
      _images = <XFile>[..._images, ...picked.take(remaining)];
      if (_coverImageIndex >= _images.length) {
        _coverImageIndex = 0;
      }
    });
  }

  Future<void> _pickVideo() async {
    final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      final int size = await picked.length();
      if (size > _listingVideoMaxBytes) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Video must be 30 MB or smaller.")),
        );
        return;
      }
      setState(() => _video = picked);
    }
  }

  Map<String, dynamic> _buildAttributes() {
    final Map<String, dynamic> attributes = <String, dynamic>{};

    for (final MapEntry<String, TextEditingController> entry
        in _attributeControllers.entries) {
      final String value = entry.value.text.trim();
      if (value.isNotEmpty) {
        final dynamic parsed = num.tryParse(value);
        attributes[entry.key] = parsed ?? value;
      }
    }

    for (final MapEntry<String, bool> entry in _attributeBooleans.entries) {
      attributes[entry.key] = entry.value;
    }

    for (final MapEntry<String, String?> entry
        in _attributeSelections.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        attributes[entry.key] = entry.value;
      }
    }

    return attributes;
  }

  String _selectedDeepestLocationId() {
    return _streetId ?? _areaId ?? _wardId ?? _districtId ?? "";
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
                                return ListTile(
                                  title: _menuText(label),
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
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: enabled ? () => unawaited(onTap()) : null,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, enabled: enabled),
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

  String _computedPublicLocationLabel() {
    final String? regionName = _labelFor(_regions, _regionId);
    final String? wardName = _labelFor(_wards, _wardId);
    final String? areaName = _manualAreaController.text.trim().isNotEmpty
        ? _manualAreaController.text.trim()
        : _labelFor(_areas, _areaId);
    final String? districtName = _labelFor(_districts, _districtId);
    final String? safeLocalName = areaName ?? wardName ?? districtName;
    if (safeLocalName == null && regionName == null) {
      return "Itazalishwa baada ya kuchagua eneo.";
    }
    return <String?>[
      safeLocalName,
      regionName,
    ].whereType<String>().where((String value) => value.isNotEmpty).join(", ");
  }

  void _handleManualAreaChanged() {
    if (_manualAreaController.text.trim().isEmpty) {
      return;
    }
    if (_areaId != null || _streetId != null || _streets.isNotEmpty) {
      setState(() {
        _areaId = null;
        _streetId = null;
        _streets = <Map<String, dynamic>>[];
      });
    }
  }

  void _resetListingForm() {
    _titleController.clear();
    _descriptionController.clear();
    _priceController.clear();
    _depositController.clear();
    _rulesController.clear();
    _exactAddressController.clear();
    _latitudeController.clear();
    _longitudeController.clear();
    _manualAreaController.clear();
    _ownerNameController.clear();
    _ownerPhoneController.clear();
    _ownerNotesController.clear();
    _pricePeriod = PricePeriod.day;
    _availabilityStatus = "available";
    _regionId = null;
    _districtId = null;
    _wardId = null;
    _areaId = null;
    _streetId = null;
    _districts = <Map<String, dynamic>>[];
    _wards = <Map<String, dynamic>>[];
    _areas = <Map<String, dynamic>>[];
    _streets = <Map<String, dynamic>>[];
    _images = <XFile>[];
    _video = null;
    _coverImageIndex = 0;
    _applyCategorySchema(_selectedCategory);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No assigned category yet. Ask admin to assign one first.",
          ),
        ),
      );
      return;
    }
    if (_regionId == null || _districtId == null || _wardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Region, district, na ward ni lazima.")),
      );
      return;
    }
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pakia angalau picha moja.")),
      );
      return;
    }
    if (_images.length > _maxImagesAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Category hii inaruhusu picha hadi $_maxImagesAllowed tu.",
          ),
        ),
      );
      return;
    }
    if (_creatingOwner &&
        (_ownerNameController.text.trim().isEmpty ||
            _ownerPhoneController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Jaza taarifa za owner.")));
      return;
    }
    if (!_creatingOwner && _selectedOwnerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Chagua owner.")));
      return;
    }

    final UploadTaskController controller = UploadTaskController();
    setState(() {
      _submitting = true;
      _uploadController = controller;
      _uploadProgress = const UploadProgressSnapshot(
        value: 0.02,
        label: "Preparing listing upload...",
      );
    });
    final repository = AppScope.of(context).repository;
    try {
      final String? resolvedAreaId =
          (_areaId != null && _areaId!.isNotEmpty) ||
              _manualAreaController.text.trim().isNotEmpty
          ? await repository.resolveWardAreaLocation(
              selectedAreaId: _areaId,
              wardId: _wardId,
              manualAreaName: _manualAreaController.text.trim(),
            )
          : null;
      await repository.submitDynamicListing(
        categoryId: _selectedCategory!["id"] as String,
        existingOwnerId: _creatingOwner ? null : _selectedOwnerId,
        ownerName: _ownerNameController.text.trim(),
        ownerPhone: _ownerPhoneController.text.trim(),
        ownerNotes: _ownerNotesController.text.trim(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priceAmount: double.tryParse(_priceController.text.trim()) ?? 0,
        pricePeriod: _pricePeriod,
        depositAmount: double.tryParse(_depositController.text.trim()) ?? 0,
        rules: _rulesController.text.trim(),
        availabilityStatus: _availabilityStatus,
        regionId: _regionId!,
        districtId: _districtId!,
        wardId: _wardId,
        areaId: resolvedAreaId,
        streetId: _streetId,
        exactAddress: _exactAddressController.text.trim(),
        latitude: _latitudeController.text.trim(),
        longitude: _longitudeController.text.trim(),
        listingAttributes: _buildAttributes(),
        images: _images,
        video: _video,
        coverImageIndex: _coverImageIndex,
        uploadController: controller,
        onProgress: (UploadProgressSnapshot progress) {
          if (!mounted) {
            return;
          }
          setState(() => _uploadProgress = progress);
        },
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Listing is now live on the marketplace."),
        ),
      );
      setState(() {
        _resetListingForm();
      });
      await _loadOwners();
    } on UploadCancelledException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Upload cancelled.")));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadController = null;
          _uploadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bootstrapError != null) {
      return ManagePageScrollView(
        children: <Widget>[
          ManagePanel(
            title: "Add asset could not load",
            subtitle: _bootstrapError!,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Try again"),
              ),
            ),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: ManagePageScrollView(
        children: <Widget>[
          ManageHeroCard(
            title: "Add asset",
            subtitle:
                "Publish only inside the categories assigned to your agent account. This flow keeps owner, location, media, and category fields in one structured workspace.",
            bottom: ManageMetaWrap(
              items: <String>[
                _selectedCategory?["name"] as String? ?? "No category assigned",
                _images.isEmpty
                    ? "No images yet"
                    : "${_images.length} images selected",
                _video == null ? "No video selected" : "Video ready",
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_categories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ManagePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    Text("No category assigned yet"),
                    SizedBox(height: 8),
                    Text(
                      "Admin must assign one or more categories before you can publish a listing.",
                    ),
                  ],
                ),
              ),
            ),
          ManagePanel(
            title: "Listing basics",
            subtitle:
                "Pick the assigned category first, then add the main marketplace details customers will see.",
            child: Column(
              children: <Widget>[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  menuMaxHeight: _menuMaxHeight,
                  initialValue: _selectedCategory?["id"] as String?,
                  decoration: const InputDecoration(
                    labelText: "Assigned category",
                  ),
                  items: _categories
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: item["id"] as String,
                          child: _menuText(item["name"] as String? ?? "-"),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    final Map<String, dynamic> next = _categories.firstWhere(
                      (Map<String, dynamic> item) => item["id"] == value,
                      orElse: () => <String, dynamic>{},
                    );
                    setState(() {
                      _selectedCategory = next.isEmpty ? null : next;
                      _applyCategorySchema(_selectedCategory);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: "Title"),
                  validator: (String? value) =>
                      value == null || value.trim().isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: "Description"),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool stacked = constraints.maxWidth < 720;
                    if (stacked) {
                      return Column(
                        children: <Widget>[
                          TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Price amount *",
                            ),
                            validator: (String? value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Price is required";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<PricePeriod>(
                            isExpanded: true,
                            menuMaxHeight: _menuMaxHeight,
                            initialValue: _pricePeriod,
                            decoration: const InputDecoration(
                              labelText: "Price period *",
                            ),
                            items: pricePeriods
                                .map(
                                  (PricePeriod item) =>
                                      DropdownMenuItem<PricePeriod>(
                                        value: item,
                                        child: Text(item.label),
                                      ),
                                )
                                .toList(),
                            onChanged: (PricePeriod? value) {
                              if (value != null) {
                                setState(() => _pricePeriod = value);
                              }
                            },
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: <Widget>[
                        Expanded(
                          child: TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Price amount *",
                            ),
                            validator: (String? value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Price is required";
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<PricePeriod>(
                            isExpanded: true,
                            menuMaxHeight: _menuMaxHeight,
                            initialValue: _pricePeriod,
                            decoration: const InputDecoration(
                              labelText: "Price period *",
                            ),
                            items: pricePeriods
                                .map(
                                  (PricePeriod item) =>
                                      DropdownMenuItem<PricePeriod>(
                                        value: item,
                                        child: Text(item.label),
                                      ),
                                )
                                .toList(),
                            onChanged: (PricePeriod? value) {
                              if (value != null) {
                                setState(() => _pricePeriod = value);
                              }
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _depositController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Deposit amount",
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  menuMaxHeight: _menuMaxHeight,
                  initialValue: _availabilityStatus,
                  decoration: const InputDecoration(labelText: "Availability"),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: "available",
                      child: Text("Available"),
                    ),
                    DropdownMenuItem(
                      value: "reserved",
                      child: Text("Reserved"),
                    ),
                    DropdownMenuItem(value: "rented", child: Text("Rented")),
                    DropdownMenuItem(
                      value: "unavailable",
                      child: Text("Unavailable"),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value != null) {
                      setState(() => _availabilityStatus = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rulesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: "Rules"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: "Owner information",
            subtitle:
                "Attach this listing to an existing owner or create a fresh owner record before publishing.",
            child: Column(
              children: <Widget>[
                if (_owners.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _creatingOwner,
                    title: const Text("Create new owner"),
                    onChanged: (bool value) {
                      setState(() => _creatingOwner = value);
                    },
                  ),
                if (!_creatingOwner && _owners.isNotEmpty)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    menuMaxHeight: _menuMaxHeight,
                    initialValue: _selectedOwnerId,
                    decoration: const InputDecoration(
                      labelText: "Select owner",
                    ),
                    items: _owners
                        .map(
                          (Map<String, dynamic> owner) =>
                              DropdownMenuItem<String>(
                                value: owner["id"] as String,
                                child: _menuText(
                                  owner["full_name"] as String? ?? "-",
                                ),
                              ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      setState(() => _selectedOwnerId = value);
                    },
                  ),
                if (_creatingOwner) ...<Widget>[
                  TextFormField(
                    controller: _ownerNameController,
                    decoration: const InputDecoration(
                      labelText: "Owner full name",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ownerPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: "Owner phone number",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ownerNotesController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: "Owner notes"),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: "Marketplace location",
            subtitle:
                "Follow the official location chain. Region, district, and ward are required. Area is optional, and a new area can be saved for future use when needed.",
            child: Column(
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
                    _loadNextLevel(
                      type: LocationType.district,
                      parentId: value,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _selectionField(
                  label: "District *",
                  valueText:
                      _labelFor(_districts, _districtId) ?? "Choose district",
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
                    _loadNextLevel(type: LocationType.ward, parentId: value);
                  },
                ),
                const SizedBox(height: 12),
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
                    _loadNextLevel(type: LocationType.area, parentId: value);
                  },
                ),
                const SizedBox(height: 12),
                _selectionField(
                  label: "Saved area",
                  valueText: _areaId == null
                      ? "Leave blank or choose a saved area"
                      : (_labelFor(_areas, _areaId) ?? "Saved area selected"),
                  enabled: _wardId != null,
                  onTap: () async {
                    final String? value = await _pickLocation(
                      title: "Choose saved area",
                      items: _areas,
                      selectedId: _areaId ?? "",
                      emptyValue: "",
                      emptyLabel: "Leave area blank or type a new one",
                    );
                    if (!mounted || value == null) {
                      return;
                    }
                    setState(() {
                      _areaId = value.isEmpty ? null : value;
                      _streetId = null;
                      if (_areaId != null) {
                        _manualAreaController.clear();
                      }
                    });
                    _loadNextLevel(
                      type: LocationType.street,
                      parentId: _areaId,
                    );
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Saved areas in this ward: ${_areas.length}/100",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _manualAreaController,
                  enabled: _wardId != null && _areas.length < 100,
                  decoration: InputDecoration(
                    labelText: "New area name (optional)",
                    helperText: _wardId == null
                        ? "Choose region, district, and ward first."
                        : _areas.length < 100
                        ? "If the area is missing, type it here and it will be saved for future use."
                        : "This ward already has 100 saved areas, so use the saved list only.",
                  ),
                ),
                const SizedBox(height: 12),
                _selectionField(
                  label: "Street",
                  valueText: _labelFor(_streets, _streetId) ?? "Choose street",
                  enabled: _streets.isNotEmpty,
                  onTap: () async {
                    final String? value = await _pickLocation(
                      title: "Choose street",
                      items: _streets,
                      selectedId: _streetId ?? "",
                      emptyValue: "",
                      emptyLabel: "No street",
                    );
                    if (!mounted || value == null) {
                      return;
                    }
                    setState(() => _streetId = value.isEmpty ? null : value);
                  },
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Public location label",
                  ),
                  child: Text(_computedPublicLocationLabel()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _exactAddressController,
                  decoration: const InputDecoration(
                    labelText: "Exact address (private)",
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _latitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: "Private latitude",
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _longitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: "Private longitude",
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_selectedCategory != null)
            ManagePanel(
              title: "Category fields",
              subtitle:
                  "These fields come directly from the selected category schema so new categories work without app rewrites.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[..._buildDynamicFields(_selectedCategory!)],
              ),
            ),
          const SizedBox(height: 16),
          ManagePanel(
            title: "Media upload",
            subtitle: _selectedCategorySlug == "apartment"
                ? "Apartment listings support up to 15 images and one video up to 30 MB. Tap an image row to choose the cover asset."
                : "Add up to 8 images and one video up to 30 MB. Tap an image row to choose the cover asset.",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _images.length >= _maxImagesAllowed
                          ? null
                          : _pickImages,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        "Pick images (${_images.length}/$_maxImagesAllowed)",
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _video != null ? null : _pickVideo,
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text(_video == null ? "Pick video" : _video!.name),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_images.isEmpty)
                  const Text("No images selected yet.")
                else
                  ..._images.asMap().entries.map(
                    (MapEntry<int, XFile> item) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Icon(
                          item.key == _coverImageIndex
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(item.value.name),
                        subtitle: Text(
                          item.key == _coverImageIndex
                              ? "Current cover image"
                              : "Tap to set as cover",
                        ),
                        onTap: () =>
                            setState(() => _coverImageIndex = item.key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_submitting && _uploadProgress != null) ...<Widget>[
            ManagePanel(
              title: "Upload progress",
              subtitle:
                  "Files upload step by step. Cancel stops the next remaining steps.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(value: _uploadProgress!.value),
                  const SizedBox(height: 10),
                  Text(_uploadProgress!.label),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _uploadProgress!.canCancel
                        ? () => _uploadController?.cancel()
                        : null,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text("Cancel upload"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.publish_outlined),
            label: Text(_submitting ? "Inatuma..." : "Publish listing"),
          ),
          const SizedBox(height: 10),
          ManageMetaWrap(
            items: <String>[
              "Selected marketplace location: ${_selectedDeepestLocationId().isEmpty ? "not set" : _selectedDeepestLocationId()}",
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDynamicFields(Map<String, dynamic> category) {
    final List<Map<String, dynamic>> schema = _schemaFieldsFor(category);
    if (schema.isEmpty) {
      return const <Widget>[Text("No extra fields configured.")];
    }

    return schema.map((Map<String, dynamic> field) {
      final String key = field["key"] as String? ?? "";
      final String label = field["label"] as String? ?? key;
      final String type = field["type"] as String? ?? "text";
      final List<dynamic> options =
          field["options"] as List<dynamic>? ?? <dynamic>[];
      final bool required = field["required"] == true;
      final String inputLabel = required ? "$label *" : label;

      if (type == "boolean") {
        return CheckboxListTile(
          value: _attributeBooleans[key] ?? false,
          onChanged: (bool? value) {
            setState(() => _attributeBooleans[key] = value ?? false);
          },
          title: Text(label),
          contentPadding: EdgeInsets.zero,
        );
      }

      if (type == "select") {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            menuMaxHeight: _menuMaxHeight,
            initialValue: _attributeSelections[key],
            decoration: InputDecoration(labelText: inputLabel),
            items: options
                .map(
                  (dynamic option) => DropdownMenuItem<String>(
                    value: option.toString(),
                    child: _menuText(option.toString()),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              setState(() => _attributeSelections[key] = value);
            },
            validator: required
                ? (String? value) => (value == null || value.trim().isEmpty)
                      ? "$label is required"
                      : null
                : null,
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _attributeControllers[key],
          maxLines: type == "textarea" ? 3 : 1,
          keyboardType: type == "number"
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: inputLabel),
          validator: required
              ? (String? value) => value == null || value.trim().isEmpty
                    ? "$label is required"
                    : null
              : null,
        ),
      );
    }).toList();
  }
}
