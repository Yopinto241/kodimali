import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/media/listing_video_compressor.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/manage_ui.dart';

class PromotionsTab extends StatefulWidget {
  const PromotionsTab({super.key});

  @override
  State<PromotionsTab> createState() => _PromotionsTabState();
}

class _AdminPromotionCustomerPreview extends StatelessWidget {
  const _AdminPromotionCustomerPreview({required this.promotion});

  final Map<String, dynamic> promotion;

  @override
  Widget build(BuildContext context) {
    final String title = promotion["title"]?.toString() ?? "Sponsored update";
    final String description = promotion["description"]?.toString() ?? "";
    final String cta =
        promotion["cta_label"]?.toString().trim().isNotEmpty == true
        ? promotion["cta_label"].toString().trim()
        : "Open promotion";
    final String? mediaUrl = promotion["media_url"] as String?;
    final String? thumbnailUrl = promotion["thumbnail_url"] as String?;
    final bool isVideo = promotion["media_type"]?.toString() == "video";
    final String? displayMedia = isVideo ? thumbnailUrl : mediaUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF102A56),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.campaign_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      SizedBox(width: 6),
                      Text(
                        "Sponsored",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Icon(isVideo ? Icons.videocam_outlined : Icons.photo_outlined),
              ],
            ),
          ),
          if (displayMedia != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.network(
                    displayMedia,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(
                          color: Color(0xFFE7ECF4),
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                  ),
                  if (isVideo)
                    const Center(
                      child: CircleAvatar(
                        radius: 27,
                        child: Icon(Icons.play_arrow_rounded, size: 34),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(description),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(cta),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromotionsTabState extends State<PromotionsTab> {
  static const int _promotionMediaMaxBytes = 30 * 1024 * 1024;
  static const double _menuMaxHeight = 360;
  final ImagePicker _picker = ImagePicker();
  final ListingVideoCompressor _videoCompressor = ListingVideoCompressor();
  late Future<List<Map<String, dynamic>>> _future;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _ctaController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _startAtController = TextEditingController();
  final TextEditingController _endAtController = TextEditingController();
  final TextEditingController _displayOrderController = TextEditingController(
    text: "0",
  );
  bool _isActive = true;
  String _placement = "global";
  String _visibilityScope = "all";
  String? _editingPromotionId;
  int _formRevision = 0;
  PlatformFile? _mediaFile;
  bool _initialized = false;
  bool _saving = false;
  bool _compressingVideo = false;
  double _videoCompressionProgress = 0;
  final Set<String> _deletingPromotionIds = <String>{};
  bool _loadingLocations = false;
  Future<void>? _locationBootstrap;
  String? _locationError;
  String? _countryId;
  Map<String, List<Map<String, dynamic>>> _locationChildrenCache =
      <String, List<Map<String, dynamic>>>{};
  String? _targetRegionId;
  String? _targetDistrictId;
  String? _targetWardId;
  String? _targetAreaId;
  List<Map<String, dynamic>> _regions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _districts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _wards = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _areas = <Map<String, dynamic>>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _future = _load();
    _locationBootstrap = _bootstrapLocations();
    unawaited(_locationBootstrap);
  }

  @override
  void dispose() {
    unawaited(_disposeVideoCompressor());
    _titleController.dispose();
    _descriptionController.dispose();
    _ctaController.dispose();
    _urlController.dispose();
    _startAtController.dispose();
    _endAtController.dispose();
    _displayOrderController.dispose();
    super.dispose();
  }

  Future<void> _disposeVideoCompressor() async {
    await _videoCompressor.cancel();
    await _videoCompressor.clearCache();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return AppScope.of(context).repository.fetchPromotionsForAdmin();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _loadIntoForm(Map<String, dynamic> promotion) {
    final String? savedRegionId = promotion["target_region_id"] as String?;
    final String? savedDistrictId = promotion["target_district_id"] as String?;
    final String? savedWardId = promotion["target_ward_id"] as String?;
    final String? savedAreaId = promotion["target_area_id"] as String?;
    final int revision = ++_formRevision;
    setState(() {
      _editingPromotionId = promotion["id"] as String?;
      _titleController.text = promotion["title"] as String? ?? "";
      _descriptionController.text = promotion["description"] as String? ?? "";
      _ctaController.text = promotion["cta_label"] as String? ?? "";
      _urlController.text = promotion["target_url"] as String? ?? "";
      _startAtController.text = promotion["start_at"] as String? ?? "";
      _endAtController.text = promotion["end_at"] as String? ?? "";
      _displayOrderController.text = (promotion["display_order"] ?? 0)
          .toString();
      _placement = promotion["placement"] as String? ?? "global";
      _visibilityScope = promotion["visibility_scope"] as String? ?? "all";
      _isActive = promotion["is_active"] as bool? ?? true;
      _mediaFile = null;
      _targetRegionId = null;
      _targetDistrictId = null;
      _targetWardId = null;
      _targetAreaId = null;
      _districts = <Map<String, dynamic>>[];
      _wards = <Map<String, dynamic>>[];
      _areas = <Map<String, dynamic>>[];
    });
    unawaited(
      _restoreTargetLocationSelection(
        regionId: savedRegionId,
        districtId: savedDistrictId,
        wardId: savedWardId,
        areaId: savedAreaId,
        formRevision: revision,
      ),
    );
  }

  void _resetForm() {
    _formRevision += 1;
    unawaited(_videoCompressor.clearCache());
    setState(() {
      _editingPromotionId = null;
      _titleController.clear();
      _descriptionController.clear();
      _ctaController.clear();
      _urlController.clear();
      _startAtController.clear();
      _endAtController.clear();
      _displayOrderController.text = "0";
      _placement = "global";
      _visibilityScope = "all";
      _isActive = true;
      _mediaFile = null;
      _targetRegionId = null;
      _targetDistrictId = null;
      _targetWardId = null;
      _targetAreaId = null;
      _districts = <Map<String, dynamic>>[];
      _wards = <Map<String, dynamic>>[];
      _areas = <Map<String, dynamic>>[];
    });
  }

  Future<void> _bootstrapLocations() async {
    setState(() {
      _loadingLocations = true;
      _locationError = null;
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
      final String? countryId = countries.isEmpty
          ? null
          : countries.first["id"] as String?;
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
        _countryId = countryId;
        _locationChildrenCache = childrenCache;
        _regions = countryId == null
            ? <Map<String, dynamic>>[]
            : _childrenOf(parentId: countryId, type: LocationType.region);
        _loadingLocations = false;
        _locationError = countries.isEmpty
            ? "Location targeting is unavailable, but you can still publish to all locations."
            : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingLocations = false;
        _locationError = userFacingError(
          error,
          fallback:
              "Location targeting could not load, but all-locations promotions remain available.",
        );
      });
    }
  }

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

  Future<void> _loadDistricts(String? regionId, {String? selectedId}) async {
    final List<Map<String, dynamic>> districts = regionId == null
        ? <Map<String, dynamic>>[]
        : _childrenOf(parentId: regionId, type: LocationType.district);
    if (!mounted) {
      return;
    }
    setState(() {
      _districts = districts;
      _targetDistrictId =
          districts.any((Map<String, dynamic> item) => item["id"] == selectedId)
          ? selectedId
          : null;
      if (_targetDistrictId == null) {
        _wards = <Map<String, dynamic>>[];
        _targetWardId = null;
        _areas = <Map<String, dynamic>>[];
        _targetAreaId = null;
      }
    });
  }

  Future<void> _loadWards(String? districtId, {String? selectedId}) async {
    final List<Map<String, dynamic>> wards = districtId == null
        ? <Map<String, dynamic>>[]
        : _childrenOf(parentId: districtId, type: LocationType.ward);
    if (!mounted) {
      return;
    }
    setState(() {
      _wards = wards;
      _targetWardId =
          wards.any((Map<String, dynamic> item) => item["id"] == selectedId)
          ? selectedId
          : null;
      if (_targetWardId == null) {
        _areas = <Map<String, dynamic>>[];
        _targetAreaId = null;
      }
    });
  }

  Future<void> _loadAreas(String? wardId, {String? selectedId}) async {
    final List<Map<String, dynamic>> areas = wardId == null
        ? <Map<String, dynamic>>[]
        : _childrenOf(parentId: wardId, type: LocationType.area);
    if (!mounted) {
      return;
    }
    setState(() {
      _areas = areas;
      _targetAreaId =
          areas.any((Map<String, dynamic> item) => item["id"] == selectedId)
          ? selectedId
          : null;
    });
  }

  Future<void> _restoreTargetLocationSelection({
    required String? regionId,
    required String? districtId,
    required String? wardId,
    required String? areaId,
    required int formRevision,
  }) async {
    if (_locationBootstrap != null) {
      await _locationBootstrap;
    } else if (_countryId == null && !_loadingLocations) {
      _locationBootstrap = _bootstrapLocations();
      await _locationBootstrap;
    }
    if (!mounted || formRevision != _formRevision) {
      return;
    }
    final String? restoredRegionId =
        _regions.any((Map<String, dynamic> item) => item["id"] == regionId)
        ? regionId
        : null;
    setState(() {
      _targetRegionId = restoredRegionId;
      _targetDistrictId = null;
      _targetWardId = null;
      _targetAreaId = null;
      if (regionId != null && restoredRegionId == null) {
        _locationError =
            "This promotion targeted a location that is no longer active. Choose a new target or use all locations before saving.";
      } else if (_regions.isNotEmpty) {
        _locationError = null;
      }
    });
    await _loadDistricts(restoredRegionId, selectedId: districtId);
    if (!mounted || formRevision != _formRevision) {
      return;
    }
    await _loadWards(_targetDistrictId, selectedId: wardId);
    if (!mounted || formRevision != _formRevision) {
      return;
    }
    await _loadAreas(_targetWardId, selectedId: areaId);
  }

  Widget _menuText(String value) {
    return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  String _promotionTargetLabel(Map<String, dynamic> promotion) {
    for (final String key in <String>[
      "target_area",
      "target_ward",
      "target_district",
      "target_region",
    ]) {
      final Map<String, dynamic>? item =
          promotion[key] as Map<String, dynamic>?;
      final String name = item?["name"] as String? ?? "";
      if (name.isNotEmpty) {
        return name;
      }
    }
    return "All locations";
  }

  Future<void> _pickMedia() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: <String>[
          "png",
          "jpg",
          "jpeg",
          "webp",
          "gif",
          "heic",
          "heif",
          "mp4",
          "mov",
          "m4v",
          "webm",
          "avi",
          "mkv",
        ],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final PlatformFile file = result.files.single;
      if (file.size > _promotionMediaMaxBytes) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Promotion media must be 30 MB or smaller."),
          ),
        );
        return;
      }
      if (file.bytes == null || file.bytes!.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "The selected file could not be read. Choose it again, or use Image/Video from gallery.",
            ),
          ),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() => _mediaFile = file);
    } catch (error) {
      _showMediaError(error);
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (file == null) {
        return;
      }
      final PlatformFile? platformFile = await _platformFileFromXFile(file);
      if (platformFile != null && mounted) {
        setState(() => _mediaFile = platformFile);
      }
    } catch (error) {
      _showMediaError(error);
    }
  }

  Future<void> _pickVideoFromGallery() async {
    if (_compressingVideo) {
      return;
    }
    try {
      final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _compressingVideo = true;
        _videoCompressionProgress = 0;
      });
      final ListingVideoCompressionResult result = await _videoCompressor
          .compress(
            file,
            onProgress: (double progress) {
              if (mounted) {
                setState(() => _videoCompressionProgress = progress);
              }
            },
          );
      final PlatformFile? platformFile = await _platformFileFromXFile(
        result.video,
      );
      if (platformFile != null && mounted) {
        setState(() => _mediaFile = platformFile);
        final double originalMb = result.originalBytes / (1024 * 1024);
        final double compressedMb = result.compressedBytes / (1024 * 1024);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Video prepared: ${originalMb.toStringAsFixed(1)} MB to ${compressedMb.toStringAsFixed(1)} MB.",
            ),
          ),
        );
      }
    } on ListingVideoCompressionCancelled {
      // The explicit cancel button already communicates the action.
    } catch (error) {
      _showMediaError(error);
    } finally {
      await _videoCompressor.clearCache();
      if (mounted) {
        setState(() {
          _compressingVideo = false;
          _videoCompressionProgress = 0;
        });
      }
    }
  }

  Future<void> _cancelVideoCompression() async {
    await _videoCompressor.cancel();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Video compression cancelled.")),
      );
    }
  }

  void _showMediaError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userFacingError(
            error,
            fallback:
                "Promotion media could not be opened. Check media permission and choose the file again.",
          ),
        ),
      ),
    );
  }

  Future<PlatformFile?> _platformFileFromXFile(XFile file) async {
    final int size = await file.length();
    if (size > _promotionMediaMaxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Promotion media must be 30 MB or smaller."),
          ),
        );
      }
      return null;
    }
    final Uint8List bytes = await file.readAsBytes();
    return PlatformFile(
      name: file.name,
      size: size,
      bytes: bytes,
      path: file.path,
    );
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final DateTime? startAt = _parseOptionalDate(
      _startAtController.text,
      "start date",
    );
    final DateTime? endAt = _parseOptionalDate(
      _endAtController.text,
      "end date",
    );
    if ((_startAtController.text.trim().isNotEmpty && startAt == null) ||
        (_endAtController.text.trim().isNotEmpty && endAt == null)) {
      return;
    }
    if (startAt != null && endAt != null && !endAt.isAfter(startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Promotion end date must be after its start date."),
        ),
      );
      return;
    }

    final bool creating = _editingPromotionId == null;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repository.savePromotion(
        promotionId: _editingPromotionId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        ctaLabel: _ctaController.text.trim().isEmpty
            ? null
            : _ctaController.text.trim(),
        targetUrl: _urlController.text.trim().isEmpty
            ? null
            : _urlController.text.trim(),
        placement: _placement,
        visibilityScope: _visibilityScope,
        displayOrder: int.parse(_displayOrderController.text.trim()),
        isActive: _isActive,
        startAtIso: startAt?.toIso8601String(),
        endAtIso: endAt?.toIso8601String(),
        targetRegionId: _targetRegionId,
        targetDistrictId: _targetDistrictId,
        targetWardId: _targetWardId,
        targetAreaId: _targetAreaId,
        mediaFile: _mediaFile,
      );
      if (!mounted) {
        return;
      }
      _resetForm();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              creating
                  ? "Promotion created successfully."
                  : "Promotion updated successfully.",
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                error,
                fallback: "Promotion could not be saved. Please try again.",
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deletePromotion(String promotionId) async {
    if (_deletingPromotionIds.contains(promotionId)) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Delete promotion?"),
        content: const Text(
          "This removes the promotion from every customer, agent, admin, and website placement.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _deletingPromotionIds.add(promotionId));
    try {
      await AppScope.of(context).repository.deletePromotion(promotionId);
      if (!mounted) {
        return;
      }
      if (_editingPromotionId == promotionId) {
        _resetForm();
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Promotion deleted.")));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                error,
                fallback: "Promotion could not be deleted. Please try again.",
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingPromotionIds.remove(promotionId));
      }
    }
  }

  DateTime? _parseOptionalDate(String value, String label) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Enter a valid promotion $label, for example 2026-07-20T10:00:00+03:00.",
          ),
        ),
      );
    }
    return parsed;
  }

  String _placementDescription(String placement) {
    return switch (placement) {
      "global" => "Shows broadly across allowed surfaces.",
      "home_feed" => "Appears on customer home feed.",
      "category_page" => "Appears inside category browsing pages.",
      "listing_detail" => "Appears on public listing detail screens.",
      "manage_dashboard" => "Appears in the agent/admin manage workspace.",
      "website" => "Appears on the public website pages.",
      _ => "Custom placement",
    };
  }

  List<String> _deliveryIssues(Map<String, dynamic> promotion) {
    final List<String> issues = <String>[];
    final DateTime now = DateTime.now().toUtc();
    if (promotion["is_active"] != true) issues.add("Campaign is switched off");
    final DateTime? starts = DateTime.tryParse(
      promotion["start_at"]?.toString() ?? "",
    )?.toUtc();
    final DateTime? ends = DateTime.tryParse(
      promotion["end_at"]?.toString() ?? "",
    )?.toUtc();
    if (starts != null && starts.isAfter(now)) {
      issues.add("Scheduled for later");
    }
    if (ends != null && !ends.isAfter(now)) issues.add("Campaign has expired");
    final String visibility =
        promotion["visibility_scope"]?.toString() ?? "all";
    if (!<String>{"public", "all"}.contains(visibility)) {
      issues.add("Not visible to customers");
    }
    final String placement = promotion["placement"]?.toString() ?? "global";
    if (!<String>{
      "global",
      "home_feed",
      "category_page",
      "listing_detail",
    }.contains(placement)) {
      issues.add("Not placed on a customer-app surface");
    }
    return issues;
  }

  Future<void> _previewPromotion(Map<String, dynamic> promotion) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: FutureBuilder<Map<String, dynamic>>(
            future: AppScope.of(
              context,
            ).repository.preparePromotionPreview(promotion),
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<Map<String, dynamic>> snapshot,
                ) {
                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                "Customer preview",
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const Text(
                          "This reproduces the sponsored card customers will see.",
                        ),
                        const SizedBox(height: 14),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Center(child: CircularProgressIndicator())
                        else
                          Flexible(
                            child: SingleChildScrollView(
                              child: _AdminPromotionCustomerPreview(
                                promotion: snapshot.data ?? promotion,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _editingPromotionId == null
                    ? "Create promotion"
                    : "Edit promotion",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                "Choose the exact placement so the admin knows where the promotion will appear.",
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: "Title"),
                validator: (String? value) =>
                    value == null || value.trim().isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: "Description"),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>("placement-$_placement"),
                isExpanded: true,
                menuMaxHeight: _menuMaxHeight,
                initialValue: _placement,
                decoration: const InputDecoration(labelText: "Placement"),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: "global", child: Text("global")),
                  DropdownMenuItem(
                    value: "home_feed",
                    child: Text("home_feed"),
                  ),
                  DropdownMenuItem(
                    value: "category_page",
                    child: Text("category_page"),
                  ),
                  DropdownMenuItem(
                    value: "listing_detail",
                    child: Text("listing_detail"),
                  ),
                  DropdownMenuItem(
                    value: "manage_dashboard",
                    child: Text("manage_dashboard"),
                  ),
                  DropdownMenuItem(value: "website", child: Text("website")),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _placement = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(_placementDescription(_placement)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>("visibility-$_visibilityScope"),
                isExpanded: true,
                menuMaxHeight: _menuMaxHeight,
                initialValue: _visibilityScope,
                decoration: const InputDecoration(
                  labelText: "Visibility scope",
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: "all", child: Text("all")),
                  DropdownMenuItem(value: "public", child: Text("public")),
                  DropdownMenuItem(value: "manage", child: Text("manage")),
                  DropdownMenuItem(value: "admin", child: Text("admin")),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _visibilityScope = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Text(
                "Target location",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_locationError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_locationError!),
                ),
              DropdownButtonFormField<String>(
                key: ValueKey<String>("region-${_targetRegionId ?? "all"}"),
                isExpanded: true,
                menuMaxHeight: _menuMaxHeight,
                initialValue: _targetRegionId ?? "",
                decoration: const InputDecoration(
                  labelText: "Region",
                  helperText: "Leave blank to publish to all locations.",
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: "",
                    child: Text("All locations"),
                  ),
                  ..._regions.map(
                    (Map<String, dynamic> item) => DropdownMenuItem<String>(
                      value: item["id"] as String,
                      child: _menuText(item["name"] as String? ?? "-"),
                    ),
                  ),
                ],
                onChanged: _loadingLocations
                    ? null
                    : (String? value) async {
                        final String? nextRegionId =
                            value == null || value.isEmpty ? null : value;
                        setState(() {
                          _targetRegionId = nextRegionId;
                          _targetDistrictId = null;
                          _targetWardId = null;
                          _targetAreaId = null;
                          _districts = <Map<String, dynamic>>[];
                          _wards = <Map<String, dynamic>>[];
                          _areas = <Map<String, dynamic>>[];
                        });
                        await _loadDistricts(nextRegionId);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  "district-${_targetRegionId ?? "all"}-${_targetDistrictId ?? "none"}",
                ),
                isExpanded: true,
                menuMaxHeight: _menuMaxHeight,
                initialValue: _targetDistrictId ?? "",
                decoration: const InputDecoration(
                  labelText: "District",
                  helperText: "Leave blank to target the whole region.",
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: "",
                    child: Text(
                      "Use region only",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ..._districts.map(
                    (Map<String, dynamic> item) => DropdownMenuItem<String>(
                      value: item["id"] as String,
                      child: _menuText(item["name"] as String? ?? "-"),
                    ),
                  ),
                ],
                onChanged: _targetRegionId == null || _loadingLocations
                    ? null
                    : (String? value) async {
                        final String? nextDistrictId =
                            value == null || value.isEmpty ? null : value;
                        setState(() {
                          _targetDistrictId = nextDistrictId;
                          _targetWardId = null;
                          _targetAreaId = null;
                          _areas = <Map<String, dynamic>>[];
                        });
                        await _loadWards(nextDistrictId);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  "ward-${_targetDistrictId ?? "none"}-${_targetWardId ?? "none"}",
                ),
                isExpanded: true,
                menuMaxHeight: _menuMaxHeight,
                initialValue: _targetWardId ?? "",
                decoration: const InputDecoration(
                  labelText: "Ward",
                  helperText: "Leave blank to target the whole district.",
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: "",
                    child: Text(
                      "Use district only",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ..._wards.map(
                    (Map<String, dynamic> item) => DropdownMenuItem<String>(
                      value: item["id"] as String,
                      child: _menuText(item["name"] as String? ?? "-"),
                    ),
                  ),
                ],
                onChanged: _targetDistrictId == null || _loadingLocations
                    ? null
                    : (String? value) async {
                        final String? nextWardId =
                            value == null || value.isEmpty ? null : value;
                        setState(() {
                          _targetWardId = nextWardId;
                          _targetAreaId = null;
                        });
                        await _loadAreas(nextWardId);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  "area-${_targetWardId ?? "none"}-${_targetAreaId ?? "none"}",
                ),
                isExpanded: true,
                menuMaxHeight: _menuMaxHeight,
                initialValue: _targetAreaId ?? "",
                decoration: const InputDecoration(
                  labelText: "Area",
                  helperText: "Leave blank to target the whole ward.",
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: "",
                    child: Text(
                      "Use ward only",
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
                onChanged: _targetWardId == null || _loadingLocations
                    ? null
                    : (String? value) {
                        setState(() {
                          _targetAreaId = value == null || value.isEmpty
                              ? null
                              : value;
                        });
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ctaController,
                decoration: const InputDecoration(labelText: "CTA label"),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: "Target URL or destination link",
                ),
                validator: (String? value) {
                  final String target = value?.trim() ?? "";
                  if (target.isEmpty) {
                    return null;
                  }
                  final Uri? uri = Uri.tryParse(target);
                  if (uri == null || !uri.hasScheme) {
                    return "Use a complete link such as https://kodimali.co.tz";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _startAtController,
                decoration: const InputDecoration(
                  labelText: "Start at ISO (optional)",
                  helperText: "Example: 2026-07-20T10:00:00+03:00",
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _endAtController,
                decoration: const InputDecoration(
                  labelText: "End at ISO (optional)",
                  helperText: "Must be after the start time.",
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayOrderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Display order"),
                validator: (String? value) {
                  if (int.tryParse(value?.trim() ?? "") == null) {
                    return "Enter a whole number";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                title: const Text("Promotion is active"),
                onChanged: (bool value) {
                  setState(() => _isActive = value);
                },
              ),
              const SizedBox(height: 8),
              Text(
                "Promotion media",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _saving || _compressingVideo
                        ? null
                        : _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text("Image from gallery"),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving || _compressingVideo
                        ? null
                        : _pickVideoFromGallery,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text("Video from gallery"),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving || _compressingVideo ? null : _pickMedia,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text("Pick file"),
                  ),
                ],
              ),
              if (_compressingVideo) ...<Widget>[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _videoCompressionProgress),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        "Preparing an upload-safe MP4 below 29 MB...",
                      ),
                    ),
                    TextButton(
                      onPressed: _cancelVideoCompression,
                      child: const Text("Cancel"),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _mediaFile == null
                    ? _editingPromotionId == null
                          ? "No media selected yet. Media is optional. Allowed: JPG, PNG, WebP, GIF, HEIC, HEIF, MP4, MOV, M4V, WebM, AVI, MKV up to 30 MB."
                          : "No replacement media selected. Existing promotion media will be kept."
                    : "Selected media: ${_mediaFile!.name}",
              ),
              if (_mediaFile != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving || _compressingVideo
                        ? null
                        : () => setState(() => _mediaFile = null),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text("Clear selected media"),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving || _compressingVideo ? null : _save,
                      child: Text(
                        _saving
                            ? "Saving..."
                            : _editingPromotionId == null
                            ? "Create promotion"
                            : "Save promotion",
                      ),
                    ),
                  ),
                  if (_editingPromotionId != null) ...<Widget>[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _saving || _compressingVideo
                          ? null
                          : _resetForm,
                      child: const Text("Clear form"),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromotionList(List<Map<String, dynamic>> promotions) {
    if (promotions.isEmpty) {
      return const KodimaliEmptyState(
        title: "Hakuna promotions",
        message: "Admin promotions zitaonekana hapa baada ya kuundwa.",
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: promotions.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) {
        final Map<String, dynamic> promotion = promotions[index];
        final List<dynamic> media =
            promotion["platform_promotion_media"] as List<dynamic>? ??
            <dynamic>[];
        final String promotionId = promotion["id"] as String;
        final bool deleting = _deletingPromotionIds.contains(promotionId);
        final List<String> deliveryIssues = _deliveryIssues(promotion);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        promotion["title"] as String? ?? "-",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: deleting || _saving || _compressingVideo
                          ? null
                          : () => _deletePromotion(promotionId),
                      child: Text(deleting ? "Deleting..." : "Delete"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(promotion["description"] as String? ?? "-"),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(label: Text("Placement: ${promotion["placement"]}")),
                    Chip(
                      label: Text(
                        "Visibility: ${promotion["visibility_scope"]}",
                      ),
                    ),
                    Chip(
                      label: Text(
                        "Location: ${_promotionTargetLabel(promotion)}",
                      ),
                    ),
                    Chip(label: Text("Media files: ${media.length}")),
                    Chip(
                      avatar: Icon(
                        deliveryIssues.isEmpty
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        size: 18,
                      ),
                      label: Text(
                        deliveryIssues.isEmpty
                            ? "Eligible for customers now"
                            : deliveryIssues.join(" · "),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if ((promotion["target_url"] as String?)?.isNotEmpty ?? false)
                  Text("Target: ${promotion["target_url"]}"),
                Text(
                  _placementDescription(
                    promotion["placement"] as String? ?? "global",
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: _saving || deleting || _compressingVideo
                          ? null
                          : () => _loadIntoForm(promotion),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text("Edit promotion"),
                    ),
                    OutlinedButton.icon(
                      onPressed: deleting
                          ? null
                          : () => _previewPromotion(promotion),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text("Preview as customer"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        final List<Map<String, dynamic>> promotions =
            snapshot.data ?? <Map<String, dynamic>>[];
        final Widget promotionList;
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          promotionList = const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          promotionList = ManagePanel(
            title: "Promotions could not load",
            subtitle: userFacingError(
              snapshot.error!,
              fallback:
                  "The promotion list could not be loaded. Check the connection and try again.",
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Try again"),
              ),
            ),
          );
        } else {
          promotionList = _buildPromotionList(promotions);
        }
        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Promotions",
              subtitle:
                  "Create and place platform promotions with clearer control over media, visibility, and placement.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${promotions.length} promotion${promotions.length == 1 ? "" : "s"}",
                  "Keep manage-only placements away from anonymous users",
                ],
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= 1100;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 5, child: _buildFormCard()),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: Column(
                          children: <Widget>[
                            ManageSectionTitle(
                              title: "Existing promotions",
                              subtitle:
                                  "Open any item to edit the message or replace its media.",
                            ),
                            const SizedBox(height: 12),
                            promotionList,
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: <Widget>[
                    _buildFormCard(),
                    const SizedBox(height: 16),
                    const ManageSectionTitle(
                      title: "Existing promotions",
                      subtitle:
                          "Open any item to edit the message or replace its media.",
                    ),
                    const SizedBox(height: 12),
                    promotionList,
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}
