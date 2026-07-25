import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_constants/shared_constants.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/media/listing_media_validator.dart';
import '../../../core/media/listing_video_compressor.dart';
import '../../../core/validation/listing_content_validator.dart';
import '../../../core/models/upload_task.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/manage_ui.dart';

class AddAssetScreen extends StatefulWidget {
  const AddAssetScreen({super.key});

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen>
    with WidgetsBindingObserver {
  static const double _menuMaxHeight = 360;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final ListingVideoCompressor _videoCompressor = ListingVideoCompressor();

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
  Timer? _draftTimer;
  bool _draftReady = false;
  bool _draftRestored = false;
  DateTime? _draftSavedAt;

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
  ListingVideoCompressionResult? _videoCompressionResult;
  bool _compressingVideo = false;
  double _videoCompressionProgress = 0;
  int _coverImageIndex = 0;

  String? _stringValue(dynamic value) => value is String ? value : null;

  String? _nonEmptyId(dynamic value) {
    final String? text = _stringValue(value);
    if (text == null) {
      return null;
    }
    final String normalized = text.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _requiredRowId(Map<String, dynamic> row, String label) {
    final String? id = _nonEmptyId(row["id"]);
    if (id == null) {
      throw StateError(
        "$label data is missing its identifier. Refresh the app and try "
        "again.",
      );
    }
    return id;
  }

  List<Map<String, dynamic>> _rowsWithIdentifiers(
    List<Map<String, dynamic>> rows,
  ) {
    return rows
        .where((Map<String, dynamic> row) => _nonEmptyId(row["id"]) != null)
        .map(
          (Map<String, dynamic> row) => <String, dynamic>{
            ...row,
            "id": _nonEmptyId(row["id"]),
          },
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _manualAreaController.addListener(_handleManualAreaChanged);
    for (final TextEditingController controller in _draftTextControllers) {
      controller.addListener(_scheduleDraftSave);
    }
  }

  List<TextEditingController> get _draftTextControllers =>
      <TextEditingController>[
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
      ];

  String get _draftStorageKey {
    final String userId =
        AppScope.of(context).controller.currentUser?.id ?? "anonymous";
    return "manage_listing_draft_v1_$userId";
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveDraft());
    }
  }

  void _scheduleDraftSave() {
    if (!_draftReady || _submitting) {
      return;
    }
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_saveDraft());
    });
  }

  Map<String, dynamic> _draftPayload() {
    return <String, dynamic>{
      "category_id": _selectedCategory?["id"],
      "creating_owner": _creatingOwner,
      "selected_owner_id": _selectedOwnerId,
      "owner_name": _ownerNameController.text,
      "owner_phone": _ownerPhoneController.text,
      "owner_notes": _ownerNotesController.text,
      "title": _titleController.text,
      "description": _descriptionController.text,
      "price": _priceController.text,
      "deposit": _depositController.text,
      "rules": _rulesController.text,
      "price_period": _pricePeriod.storageValue,
      "availability_status": _availabilityStatus,
      "region_id": _regionId,
      "district_id": _districtId,
      "ward_id": _wardId,
      "area_id": _areaId,
      "street_id": _streetId,
      "manual_area": _manualAreaController.text,
      "exact_address": _exactAddressController.text,
      "latitude": _latitudeController.text,
      "longitude": _longitudeController.text,
      "attributes": _buildAttributes(),
      "saved_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _saveDraft() async {
    if (!_draftReady || _submitting || !mounted) {
      return;
    }
    final String storageKey = _draftStorageKey;
    final Map<String, dynamic> payload = _draftPayload();
    final bool hasContent = <String>[
      _titleController.text,
      _descriptionController.text,
      _priceController.text,
      _ownerNameController.text,
      _manualAreaController.text,
    ].any((String value) => value.trim().isNotEmpty);
    if (!hasContent) {
      return;
    }
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(payload));
    if (mounted) {
      setState(() => _draftSavedAt = DateTime.now());
    }
  }

  Future<void> _restoreDraft() async {
    final String storageKey = _draftStorageKey;
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? encoded = preferences.getString(storageKey);
    if (encoded == null || encoded.trim().isEmpty) {
      _draftReady = true;
      return;
    }
    try {
      final Map<String, dynamic> draft = (jsonDecode(encoded) as Map)
          .cast<String, dynamic>();
      final String? categoryId = _nonEmptyId(draft["category_id"]);
      final Map<String, dynamic>? category = _categories
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (Map<String, dynamic>? item) => item?["id"] == categoryId,
            orElse: () => null,
          );
      if (category != null) {
        _selectedCategory = category;
        _applyCategorySchema(category);
      }
      if (draft["creating_owner"] is bool) {
        _creatingOwner = draft["creating_owner"] as bool;
      }
      final String? ownerId = _nonEmptyId(draft["selected_owner_id"]);
      if (_owners.any((Map<String, dynamic> owner) => owner["id"] == ownerId)) {
        _selectedOwnerId = ownerId;
      }
      _ownerNameController.text = _stringValue(draft["owner_name"]) ?? "";
      _ownerPhoneController.text = _stringValue(draft["owner_phone"]) ?? "";
      _ownerNotesController.text = _stringValue(draft["owner_notes"]) ?? "";
      _titleController.text = _stringValue(draft["title"]) ?? "";
      _descriptionController.text = _stringValue(draft["description"]) ?? "";
      _priceController.text = _stringValue(draft["price"]) ?? "";
      _depositController.text = _stringValue(draft["deposit"]) ?? "";
      _rulesController.text = _stringValue(draft["rules"]) ?? "";
      _exactAddressController.text = _stringValue(draft["exact_address"]) ?? "";
      _latitudeController.text = _stringValue(draft["latitude"]) ?? "";
      _longitudeController.text = _stringValue(draft["longitude"]) ?? "";
      _manualAreaController.text = _stringValue(draft["manual_area"]) ?? "";
      final String? pricePeriod = _stringValue(draft["price_period"]);
      _pricePeriod = PricePeriod.values.firstWhere(
        (PricePeriod item) => item.storageValue == pricePeriod,
        orElse: () => PricePeriod.day,
      );
      _availabilityStatus =
          _nonEmptyId(draft["availability_status"]) ?? "available";

      final String? regionId = _nonEmptyId(draft["region_id"]);
      if (regionId != null &&
          _regions.any((Map<String, dynamic> item) => item["id"] == regionId)) {
        _regionId = regionId;
        _districts = _childrenOf(
          parentId: regionId,
          type: LocationType.district,
        );
      }
      final String? districtId = _nonEmptyId(draft["district_id"]);
      if (districtId != null &&
          _districts.any(
            (Map<String, dynamic> item) => item["id"] == districtId,
          )) {
        _districtId = districtId;
        _wards = _childrenOf(parentId: districtId, type: LocationType.ward);
      }
      final String? wardId = _nonEmptyId(draft["ward_id"]);
      if (wardId != null &&
          _wards.any((Map<String, dynamic> item) => item["id"] == wardId)) {
        _wardId = wardId;
        _areas = _childrenOf(parentId: wardId, type: LocationType.area);
      }
      final String? areaId = _nonEmptyId(draft["area_id"]);
      if (areaId != null &&
          _areas.any((Map<String, dynamic> item) => item["id"] == areaId)) {
        _areaId = areaId;
        _streets = _childrenOf(parentId: areaId, type: LocationType.street);
      }
      final String? streetId = _nonEmptyId(draft["street_id"]);
      if (streetId != null &&
          _streets.any((Map<String, dynamic> item) => item["id"] == streetId)) {
        _streetId = streetId;
      }

      final dynamic rawAttributes = draft["attributes"];
      final Map<String, dynamic> attributes = rawAttributes is Map
          ? Map<String, dynamic>.from(rawAttributes)
          : <String, dynamic>{};
      for (final MapEntry<String, TextEditingController> entry
          in _attributeControllers.entries) {
        final dynamic value = attributes[entry.key];
        if (value != null) {
          entry.value.text = value.toString();
        }
      }
      for (final String key in _attributeBooleans.keys.toList()) {
        _attributeBooleans[key] = attributes[key] == true;
      }
      for (final String key in _attributeSelections.keys.toList()) {
        _attributeSelections[key] = attributes[key]?.toString();
      }
      _draftRestored = true;
      _draftSavedAt = DateTime.tryParse(
        draft["saved_at"]?.toString() ?? "",
      )?.toLocal();
    } catch (_) {
      await preferences.remove(storageKey);
    } finally {
      _draftReady = true;
    }
  }

  Future<void> _clearSavedDraft() async {
    _draftTimer?.cancel();
    final String storageKey = _draftStorageKey;
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
    if (mounted) {
      setState(() {
        _draftRestored = false;
        _draftSavedAt = null;
      });
    }
  }

  Future<void> _discardDraft() async {
    _draftReady = false;
    if (_compressingVideo) {
      await _videoCompressor.cancel();
    }
    await _videoCompressor.clearCache();
    if (!mounted) {
      return;
    }
    setState(_resetListingForm);
    await _clearSavedDraft();
    _draftReady = true;
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
      await _restoreDraft();
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
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    if (_compressingVideo) {
      unawaited(_videoCompressor.cancel());
    }
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
    final List<Map<String, dynamic>> loadedOwners = await AppScope.of(
      context,
    ).repository.fetchOwnersForCurrentAgent();
    final List<Map<String, dynamic>> owners = _rowsWithIdentifiers(
      loadedOwners,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _owners = owners;
      if (_owners.isNotEmpty) {
        final bool selectionStillExists = _owners.any(
          (Map<String, dynamic> owner) => owner["id"] == _selectedOwnerId,
        );
        _selectedOwnerId = selectionStillExists
            ? _selectedOwnerId
            : _nonEmptyId(_owners.first["id"]);
        _creatingOwner = false;
      } else {
        _selectedOwnerId = null;
        _creatingOwner = true;
      }
    });
  }

  Future<void> _loadLocationHierarchy() async {
    final List<Map<String, dynamic>> loadedLocations = await AppScope.of(
      context,
    ).repository.fetchAgentLocationHierarchy();
    final List<Map<String, dynamic>> locations =
        _rowsWithIdentifiers(loadedLocations)
            .where((Map<String, dynamic> item) {
              return _nonEmptyId(item["location_type"]) != null;
            })
            .toList(growable: false);
    if (loadedLocations.isNotEmpty && locations.isEmpty) {
      throw StateError(
        "Location data is incomplete because its identifiers are missing. "
        "Refresh the app or ask an administrator to repair locations.",
      );
    }
    final List<Map<String, dynamic>> countries = locations
        .where(
          (Map<String, dynamic> item) =>
              item["location_type"] == LocationType.country.storageValue,
        )
        .toList(growable: false);
    final String? nextCountryId = countries.length == 1
        ? _nonEmptyId(countries.first["id"])
        : null;
    final Map<String, List<Map<String, dynamic>>> childrenCache =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> item in locations) {
      final String? parentId = _nonEmptyId(item["parent_id"]);
      final String? locationType = _nonEmptyId(item["location_type"]);
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
    final List<Map<String, dynamic>> loadedCategories = await AppScope.of(
      context,
    ).repository.fetchActiveCategories();
    final List<Map<String, dynamic>> categories = _rowsWithIdentifiers(
      loadedCategories,
    );
    if (loadedCategories.isNotEmpty && categories.isEmpty) {
      throw StateError(
        "Assigned category data is missing its identifiers. Refresh the app "
        "or ask an administrator to repair the category assignment.",
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _categories = categories;
      if (_categories.isNotEmpty) {
        final String? selectedId = _nonEmptyId(_selectedCategory?["id"]);
        _selectedCategory = _categories.firstWhere(
          (Map<String, dynamic> category) => category["id"] == selectedId,
          orElse: () => _categories.first,
        );
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
          return key.isNotEmpty && field["active"] != false;
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
      final String key = field["key"]?.toString().trim() ?? "";
      final String type = _nonEmptyId(field["type"])?.toLowerCase() ?? "text";
      if (key.isEmpty) {
        continue;
      }
      if (type == "boolean") {
        _attributeBooleans[key] = false;
      } else if (type == "select") {
        _attributeSelections[key] = null;
      } else {
        final TextEditingController controller = TextEditingController();
        controller.addListener(_scheduleDraftSave);
        _attributeControllers[key] = controller;
      }
    }
  }

  String get _selectedCategorySlug =>
      _nonEmptyId(_selectedCategory?["slug"]) ?? "";

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
    _scheduleDraftSave();
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> picked = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (picked.isEmpty || !mounted) {
        return;
      }
      final int remaining = _maxImagesAllowed - _images.length;
      if (remaining <= 0) {
        _showMediaError(
          'This category allows up to $_maxImagesAllowed images.',
        );
        return;
      }
      final List<XFile> accepted = picked.take(remaining).toList();
      await ListingMediaValidator.validateImages(accepted);
      if (!mounted) {
        return;
      }
      setState(() {
        _images = <XFile>[..._images, ...accepted];
        if (_coverImageIndex >= _images.length) {
          _coverImageIndex = 0;
        }
      });
      if (picked.length > remaining) {
        _showMediaError(
          'Only $remaining more image${remaining == 1 ? '' : 's'} could be '
          'added for this category.',
        );
      }
      _scheduleDraftSave();
    } catch (error) {
      if (mounted) {
        _showMediaError(_friendlyMediaError(error));
      }
    }
  }

  Future<void> _pickVideo() async {
    if (_compressingVideo || _submitting) {
      return;
    }
    try {
      final XFile? picked = await _picker.pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _compressingVideo = true;
        _videoCompressionProgress = 0;
      });
      final ListingVideoCompressionResult result = await _videoCompressor
          .compress(
            picked,
            onProgress: (double progress) {
              if (mounted) {
                setState(() => _videoCompressionProgress = progress);
              }
            },
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _video = result.video;
        _videoCompressionResult = result;
        _videoCompressionProgress = 1;
      });
      _scheduleDraftSave();
    } on ListingVideoCompressionCancelled {
      if (mounted) {
        _showMediaError('Video compression cancelled.');
      }
    } catch (error) {
      if (mounted) {
        _showMediaError(_friendlyMediaError(error));
      }
      await _videoCompressor.clearCache();
    } finally {
      if (mounted) {
        setState(() => _compressingVideo = false);
      }
    }
  }

  Future<void> _cancelVideoCompression() async {
    await _videoCompressor.cancel();
  }

  Future<void> _removeVideo() async {
    setState(() {
      _video = null;
      _videoCompressionResult = null;
      _videoCompressionProgress = 0;
    });
    await _videoCompressor.clearCache();
    _scheduleDraftSave();
  }

  void _showMediaError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _friendlyMediaError(Object error) => error
      .toString()
      .replaceAll('Bad state: ', '')
      .replaceAll('Exception: ', '')
      .trim();

  void _removeImage(int index) {
    if (index < 0 || index >= _images.length) {
      return;
    }
    final XFile? cover = _images.isEmpty ? null : _images[_coverImageIndex];
    setState(() {
      _images = List<XFile>.from(_images)..removeAt(index);
      if (_images.isEmpty) {
        _coverImageIndex = 0;
      } else if (cover != null && _images.contains(cover)) {
        _coverImageIndex = _images.indexOf(cover);
      } else {
        _coverImageIndex = 0;
      }
    });
    _scheduleDraftSave();
  }

  void _moveImage(int from, int to) {
    if (from < 0 ||
        from >= _images.length ||
        to < 0 ||
        to >= _images.length ||
        from == to) {
      return;
    }
    final XFile cover = _images[_coverImageIndex];
    setState(() {
      final List<XFile> reordered = List<XFile>.from(_images);
      final XFile image = reordered.removeAt(from);
      reordered.insert(to, image);
      _images = reordered;
      _coverImageIndex = _images.indexOf(cover);
    });
    _scheduleDraftSave();
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
        return _stringValue(item["name"]);
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
                  final String? id = _nonEmptyId(item["id"]);
                  final String label = _stringValue(item["name"]) ?? "";
                  return id != null && _matchesSearch(label, query);
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
                                final String value = _requiredRowId(
                                  item,
                                  "Location",
                                );
                                final String label =
                                    _stringValue(item["name"]) ?? "-";
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
    _videoCompressionResult = null;
    _videoCompressionProgress = 0;
    _coverImageIndex = 0;
    _applyCategorySchema(_selectedCategory);
  }

  Future<void> _submit() async {
    if (_submitting || _compressingVideo) {
      if (_compressingVideo) {
        _showMediaError(
          'Wait for video compression to finish before publishing.',
        );
      }
      return;
    }
    final FormState? formState = _formKey.currentState;
    if (formState == null) {
      _showMediaError(
        "The listing form is not ready yet. Wait a moment and try again.",
      );
      return;
    }
    if (!formState.validate()) {
      return;
    }
    final Map<String, dynamic>? selectedCategory = _selectedCategory;
    if (selectedCategory == null) {
      _showMediaError(
        "No assigned category yet. Ask admin to assign one first.",
      );
      return;
    }
    final String? categoryId = _nonEmptyId(selectedCategory["id"]);
    if (categoryId == null) {
      _showMediaError(
        "The selected category is missing its identifier. Refresh the form "
        "and choose the category again.",
      );
      return;
    }
    final String? regionId = _nonEmptyId(_regionId);
    final String? districtId = _nonEmptyId(_districtId);
    final String? wardId = _nonEmptyId(_wardId);
    if (regionId == null || districtId == null || wardId == null) {
      _showMediaError(
        "Choose a valid region, district, and ward before publishing.",
      );
      return;
    }
    final String? selectedAreaId = _nonEmptyId(_areaId);
    final String? selectedStreetId = _nonEmptyId(_streetId);
    final List<XFile> images = List<XFile>.unmodifiable(_images);
    if (images.isEmpty) {
      _showMediaError("Add at least one listing image before publishing.");
      return;
    }
    final int maximumImages =
        _nonEmptyId(selectedCategory["slug"]) == "apartment" ? 15 : 8;
    if (images.length > maximumImages) {
      _showMediaError("This category allows up to $maximumImages images.");
      return;
    }
    final bool creatingOwner = _creatingOwner;
    final String ownerName = _ownerNameController.text.trim();
    final String ownerPhone = _ownerPhoneController.text.trim();
    final String ownerNotes = _ownerNotesController.text.trim();
    final String? existingOwnerId = creatingOwner
        ? null
        : _nonEmptyId(_selectedOwnerId);
    if (creatingOwner && (ownerName.isEmpty || ownerPhone.isEmpty)) {
      _showMediaError("Enter the owner's name and phone number.");
      return;
    }
    if (!creatingOwner && existingOwnerId == null) {
      _showMediaError("Choose a valid owner before publishing.");
      return;
    }
    final double? priceAmount = double.tryParse(_priceController.text.trim());
    if (priceAmount == null || priceAmount <= 0) {
      _showMediaError("Enter a valid price greater than zero.");
      return;
    }
    final String depositText = _depositController.text.trim();
    final double? parsedDeposit = depositText.isEmpty
        ? 0
        : double.tryParse(depositText);
    if (parsedDeposit == null || parsedDeposit < 0) {
      _showMediaError("Enter a valid deposit amount, or leave it blank.");
      return;
    }
    final XFile? video = _video;
    if (video != null && _videoCompressionResult == null) {
      _showMediaError(
        "Select the video again so KODIMALI can compress it before upload.",
      );
      return;
    }
    final int coverImageIndex = _coverImageIndex;
    final String manualAreaName = _manualAreaController.text.trim();
    final String title = _titleController.text.trim();
    final String description = _descriptionController.text.trim();
    final String rules = _rulesController.text.trim();
    final String exactAddress = _exactAddressController.text.trim();
    final String latitude = _latitudeController.text.trim();
    final String longitude = _longitudeController.text.trim();
    final PricePeriod pricePeriod = _pricePeriod;
    final String availabilityStatus = _availabilityStatus;
    final Map<String, dynamic> listingAttributes = Map<String, dynamic>.from(
      _buildAttributes(),
    );

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
      await ListingMediaValidator.validateImages(images);
      if (video != null) {
        await ListingMediaValidator.validateCompressedVideo(video);
      }
      final String? resolvedAreaId =
          selectedAreaId != null || manualAreaName.isNotEmpty
          ? await repository.resolveWardAreaLocation(
              selectedAreaId: selectedAreaId,
              wardId: wardId,
              manualAreaName: manualAreaName,
            )
          : null;
      await repository.submitDynamicListing(
        categoryId: categoryId,
        existingOwnerId: existingOwnerId,
        ownerName: ownerName,
        ownerPhone: ownerPhone,
        ownerNotes: ownerNotes,
        title: title,
        description: description,
        priceAmount: priceAmount,
        pricePeriod: pricePeriod,
        depositAmount: parsedDeposit,
        rules: rules,
        availabilityStatus: availabilityStatus,
        regionId: regionId,
        districtId: districtId,
        wardId: wardId,
        areaId: resolvedAreaId,
        streetId: selectedStreetId,
        exactAddress: exactAddress,
        latitude: latitude,
        longitude: longitude,
        listingAttributes: listingAttributes,
        images: images,
        video: video,
        coverImageIndex: coverImageIndex,
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
      await _videoCompressor.clearCache();
      if (!mounted) {
        return;
      }
      _draftReady = false;
      setState(() {
        _resetListingForm();
      });
      await _clearSavedDraft();
      if (!mounted) {
        return;
      }
      _draftReady = true;
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
      ).showSnackBar(SnackBar(content: Text(_friendlyMediaError(error))));
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

  int get _completedListingSteps {
    int count = 0;
    if (_selectedCategory != null &&
        _titleController.text.trim().isNotEmpty &&
        _priceController.text.trim().isNotEmpty) {
      count += 1;
    }
    if ((!_creatingOwner && _selectedOwnerId != null) ||
        (_creatingOwner &&
            _ownerNameController.text.trim().isNotEmpty &&
            _ownerPhoneController.text.trim().isNotEmpty)) {
      count += 1;
    }
    if (_regionId != null && _districtId != null && _wardId != null) {
      count += 1;
    }
    if (_images.isNotEmpty) {
      count += 1;
    }
    return count;
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
                _stringValue(_selectedCategory?["name"]) ??
                    "No category assigned",
                _images.isEmpty
                    ? "No images yet"
                    : "${_images.length} images selected",
                _compressingVideo
                    ? "Compressing video ${(_videoCompressionProgress * 100).round()}%"
                    : _video == null
                    ? "No video selected"
                    : "Compressed video ready",
                "$_completedListingSteps/4 required steps ready",
                _draftSavedAt == null
                    ? "Draft autosave ready"
                    : "Draft saved ${TimeOfDay.fromDateTime(_draftSavedAt!).format(context)}",
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_draftRestored) ...<Widget>[
            ManagePanel(
              title: "Draft restored",
              subtitle:
                  "Your text, owner, category, price, and location were restored on this device. For privacy and reliability, select images and video again.",
              action: TextButton.icon(
                onPressed: _discardDraft,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text("Discard"),
              ),
              child: const Text(
                "Continue where you stopped; changes save automatically while you type.",
              ),
            ),
            const SizedBox(height: 16),
          ],
          ManagePanel(
            title: "Publishing checklist",
            subtitle:
                "The listing can publish after all four required sections are ready.",
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(
                  avatar: Icon(
                    _selectedCategory != null &&
                            _titleController.text.trim().isNotEmpty &&
                            _priceController.text.trim().isNotEmpty
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  label: const Text("Basics"),
                ),
                Chip(
                  avatar: Icon(
                    (!_creatingOwner && _selectedOwnerId != null) ||
                            (_creatingOwner &&
                                _ownerNameController.text.trim().isNotEmpty &&
                                _ownerPhoneController.text.trim().isNotEmpty)
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  label: const Text("Owner"),
                ),
                Chip(
                  avatar: Icon(
                    _regionId != null && _districtId != null && _wardId != null
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  label: const Text("Location"),
                ),
                Chip(
                  avatar: Icon(
                    _images.isNotEmpty
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  label: const Text("Media"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                  initialValue: _nonEmptyId(_selectedCategory?["id"]),
                  decoration: const InputDecoration(
                    labelText: "Assigned category",
                  ),
                  items: _categories
                      .map(
                        (Map<String, dynamic> item) => DropdownMenuItem<String>(
                          value: _requiredRowId(item, "Category"),
                          child: _menuText(_stringValue(item["name"]) ?? "-"),
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
                    _scheduleDraftSave();
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: "Title"),
                  validator: ListingContentValidator.titleError,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: "Description *",
                    helperText: "At least 10 characters",
                  ),
                  validator: ListingContentValidator.descriptionError,
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
                                _scheduleDraftSave();
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
                                _scheduleDraftSave();
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
                      _scheduleDraftSave();
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
                      _scheduleDraftSave();
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
                                value: _requiredRowId(owner, "Owner"),
                                child: _menuText(
                                  _stringValue(owner["full_name"]) ?? "-",
                                ),
                              ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      setState(() => _selectedOwnerId = value);
                      _scheduleDraftSave();
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
                    _scheduleDraftSave();
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
          if (_selectedCategory
              case final Map<String, dynamic> selectedCategory)
            ManagePanel(
              title: "Category fields",
              subtitle:
                  "These fields come directly from the selected category schema so new categories work without app rewrites.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[..._buildDynamicFields(selectedCategory)],
              ),
            ),
          const SizedBox(height: 16),
          ManagePanel(
            title: "Media upload",
            subtitle: _selectedCategorySlug == "apartment"
                ? "Apartment listings support up to 15 images. Selected video is compressed to MP4 below 29 MB before upload; the server maximum is 30 MB."
                : "Add up to 8 images. Selected video is compressed to MP4 below 29 MB before upload; the server maximum is 30 MB.",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed:
                          _images.length >= _maxImagesAllowed ||
                              _submitting ||
                              _compressingVideo
                          ? null
                          : _pickImages,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        "Pick images (${_images.length}/$_maxImagesAllowed)",
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _video != null || _compressingVideo || _submitting
                          ? null
                          : _pickVideo,
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text(
                        _compressingVideo
                            ? "Compressing ${(_videoCompressionProgress * 100).round()}%"
                            : _video == null
                            ? "Pick and compress video"
                            : "Compressed video ready",
                      ),
                    ),
                  ],
                ),
                if (_compressingVideo) ...<Widget>[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _videoCompressionProgress),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          "Preparing a smaller MP4 on this device. Keep the app open until this finishes.",
                        ),
                      ),
                      TextButton(
                        onPressed: _cancelVideoCompression,
                        child: const Text("Cancel"),
                      ),
                    ],
                  ),
                ],
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: "Move up",
                              onPressed:
                                  _submitting ||
                                      _compressingVideo ||
                                      item.key == 0
                                  ? null
                                  : () => _moveImage(item.key, item.key - 1),
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                            IconButton(
                              tooltip: "Move down",
                              onPressed:
                                  _submitting ||
                                      _compressingVideo ||
                                      item.key == _images.length - 1
                                  ? null
                                  : () => _moveImage(item.key, item.key + 1),
                              icon: const Icon(Icons.arrow_downward_rounded),
                            ),
                            IconButton(
                              tooltip: "Remove image",
                              onPressed: _submitting || _compressingVideo
                                  ? null
                                  : () => _removeImage(item.key),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                        onTap: _submitting || _compressingVideo
                            ? null
                            : () => setState(() => _coverImageIndex = item.key),
                      ),
                    ),
                  ),
                if (_video != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.videocam_outlined),
                      title: Text(
                        _videoCompressionResult?.originalName ?? _video!.name,
                      ),
                      subtitle: Text(
                        _videoCompressionResult == null
                            ? "Video must be selected again before publishing."
                            : "Compressed ${_videoCompressionResult!.reductionPercent.toStringAsFixed(0)}% to "
                                  "${ListingMediaValidator.formatMiB(_videoCompressionResult!.compressedBytes)}. "
                                  "MP4 is ready for upload.",
                      ),
                      trailing: IconButton(
                        tooltip: "Remove video",
                        onPressed: _submitting ? null : _removeVideo,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  ),
                ],
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
            onPressed: _submitting || _compressingVideo ? null : _submit,
            icon: const Icon(Icons.publish_outlined),
            label: Text(
              _submitting
                  ? "Inatuma..."
                  : _compressingVideo
                  ? "Compressing video..."
                  : "Publish listing",
            ),
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
      final String key = field["key"]?.toString().trim() ?? "";
      final String label = _nonEmptyId(field["label"]) ?? key;
      final String type = _nonEmptyId(field["type"])?.toLowerCase() ?? "text";
      final dynamic rawOptions = field["options"];
      final List<dynamic> options = rawOptions is List
          ? List<dynamic>.from(rawOptions)
          : <dynamic>[];
      final bool required = field["required"] == true;
      final String? helpText = _nonEmptyId(field["help_text"]);
      final String inputLabel = required ? "$label *" : label;

      if (type == "boolean") {
        return CheckboxListTile(
          value: _attributeBooleans[key] ?? false,
          onChanged: (bool? value) {
            setState(() => _attributeBooleans[key] = value ?? false);
            _scheduleDraftSave();
          },
          title: Text(label),
          subtitle: helpText == null ? null : Text(helpText),
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
            decoration: InputDecoration(
              labelText: inputLabel,
              helperText: helpText,
            ),
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
              _scheduleDraftSave();
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
          decoration: InputDecoration(
            labelText: inputLabel,
            helperText: helpText,
          ),
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
