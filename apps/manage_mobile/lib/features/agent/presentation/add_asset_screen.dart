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

  List<Map<String, dynamic>> _regions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _districts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _wards = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _areas = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _streets = <Map<String, dynamic>>[];

  List<XFile> _images = <XFile>[];
  XFile? _video;
  int _coverImageIndex = 0;

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
        _loadCountries(),
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

  Future<void> _loadCountries() async {
    final List<Map<String, dynamic>> countries = await AppScope.of(
      context,
    ).repository.fetchLocations(parentId: null, type: LocationType.country);
    final String? nextCountryId = countries.length == 1
        ? countries.first["id"] as String
        : null;
    if (!mounted) {
      return;
    }
    if (nextCountryId != null) {
      await _loadNextLevel(type: LocationType.region, parentId: nextCountryId);
    }
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

  Future<void> _loadNextLevel({
    required LocationType type,
    required String? parentId,
  }) async {
    final List<Map<String, dynamic>> items = await AppScope.of(
      context,
    ).repository.fetchLocations(parentId: parentId, type: type);
    if (!mounted) {
      return;
    }
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
          break;
        case LocationType.ward:
          _wards = items;
          _wardId = null;
          _areas = <Map<String, dynamic>>[];
          _streets = <Map<String, dynamic>>[];
          _areaId = null;
          _streetId = null;
          break;
        case LocationType.area:
          _areas = items;
          _areaId = null;
          _streets = <Map<String, dynamic>>[];
          _streetId = null;
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
    final int remaining = 8 - _images.length;
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

  String _computedPublicLocationLabel() {
    final String? regionName = _labelFor(_regions, _regionId);
    final String? wardName = _labelFor(_wards, _wardId);
    final String? areaName = _labelFor(_areas, _areaId);
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

  void _resetListingForm() {
    _titleController.clear();
    _descriptionController.clear();
    _priceController.clear();
    _depositController.clear();
    _rulesController.clear();
    _exactAddressController.clear();
    _latitudeController.clear();
    _longitudeController.clear();
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
    unawaited(_loadCountries());
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
    if (_regionId == null ||
        _districtId == null ||
        _wardId == null ||
        _areaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Region, district, ward, na area ni lazima."),
        ),
      );
      return;
    }
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pakia angalau picha moja.")),
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
    try {
      await AppScope.of(context).repository.submitDynamicListing(
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
        areaId: _areaId,
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
                  initialValue: _selectedCategory?["id"] as String?,
                  decoration: const InputDecoration(
                    labelText: "Assigned category",
                  ),
                  items: _categories
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: item["id"] as String,
                          child: Text(item["name"] as String? ?? "-"),
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
                    initialValue: _selectedOwnerId,
                    decoration: const InputDecoration(
                      labelText: "Select owner",
                    ),
                    items: _owners
                        .map(
                          (Map<String, dynamic> owner) =>
                              DropdownMenuItem<String>(
                                value: owner["id"] as String,
                                child: Text(
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
                "Follow the official location chain. Region, district, ward, and area are required before a listing can go live.",
            child: Column(
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _regionId,
                  decoration: const InputDecoration(labelText: "Region *"),
                  items: _regions
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: item["id"] as String,
                          child: Text(item["name"] as String? ?? "-"),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) async {
                    setState(() => _regionId = value);
                    await _loadNextLevel(
                      type: LocationType.district,
                      parentId: value,
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _districtId,
                  decoration: const InputDecoration(labelText: "District *"),
                  items: _districts
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: item["id"] as String,
                          child: Text(item["name"] as String? ?? "-"),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) async {
                    setState(() => _districtId = value);
                    await _loadNextLevel(
                      type: LocationType.ward,
                      parentId: value,
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _wardId,
                  decoration: const InputDecoration(labelText: "Ward *"),
                  items: _wards
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: item["id"] as String,
                          child: Text(item["name"] as String? ?? "-"),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) async {
                    setState(() => _wardId = value);
                    await _loadNextLevel(
                      type: LocationType.area,
                      parentId: value,
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _areaId,
                  decoration: const InputDecoration(labelText: "Area *"),
                  items: _areas
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: item["id"] as String,
                          child: Text(item["name"] as String? ?? "-"),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) async {
                    setState(() => _areaId = value);
                    await _loadNextLevel(
                      type: LocationType.street,
                      parentId: value,
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _streetId,
                  decoration: const InputDecoration(labelText: "Street"),
                  items: _streets
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: item["id"] as String,
                          child: Text(item["name"] as String? ?? "-"),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    setState(() => _streetId = value);
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
            subtitle:
                "Add up to 8 images and one video. Tap an image row to choose the cover asset.",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _images.length >= 8 ? null : _pickImages,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text("Pick images (${_images.length}/8)"),
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
            initialValue: _attributeSelections[key],
            decoration: InputDecoration(labelText: inputLabel),
            items: options
                .map(
                  (dynamic option) => DropdownMenuItem<String>(
                    value: option.toString(),
                    child: Text(option.toString()),
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
