import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/manage_ui.dart';

class PromotionsTab extends StatefulWidget {
  const PromotionsTab({super.key});

  @override
  State<PromotionsTab> createState() => _PromotionsTabState();
}

class _PromotionsTabState extends State<PromotionsTab> {
  static const int _promotionMediaMaxBytes = 25 * 1024 * 1024;
  final ImagePicker _picker = ImagePicker();
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
  PlatformFile? _mediaFile;
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
    _titleController.dispose();
    _descriptionController.dispose();
    _ctaController.dispose();
    _urlController.dispose();
    _startAtController.dispose();
    _endAtController.dispose();
    _displayOrderController.dispose();
    super.dispose();
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
    });
  }

  void _resetForm() {
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
    });
  }

  Future<void> _pickMedia() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: <String>["png", "jpg", "jpeg", "webp", "mp4"],
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
          content: Text("Promotion media must be 25 MB or smaller."),
        ),
      );
      return;
    }
    setState(() => _mediaFile = file);
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (file == null) {
      return;
    }
    final PlatformFile? platformFile = await _platformFileFromXFile(file);
    if (platformFile != null) {
      setState(() => _mediaFile = platformFile);
    }
  }

  Future<void> _pickVideoFromGallery() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) {
      return;
    }
    final PlatformFile? platformFile = await _platformFileFromXFile(file);
    if (platformFile != null) {
      setState(() => _mediaFile = platformFile);
    }
  }

  Future<PlatformFile?> _platformFileFromXFile(XFile file) async {
    final int size = await file.length();
    if (size > _promotionMediaMaxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Promotion media must be 25 MB or smaller."),
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
    if (!_formKey.currentState!.validate()) {
      return;
    }
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
      displayOrder: int.tryParse(_displayOrderController.text.trim()) ?? 0,
      isActive: _isActive,
      startAtIso: _startAtController.text.trim(),
      endAtIso: _endAtController.text.trim(),
      mediaFile: _mediaFile,
    );
    _resetForm();
    await _refresh();
  }

  Future<void> _deletePromotion(String promotionId) async {
    await AppScope.of(context).repository.deletePromotion(promotionId);
    if (_editingPromotionId == promotionId) {
      _resetForm();
    }
    await _refresh();
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
                initialValue: _placement,
                decoration: const InputDecoration(labelText: "Placement"),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: "global", child: Text("global")),
                  DropdownMenuItem(value: "home_feed", child: Text("home_feed")),
                  DropdownMenuItem(value: "category_page", child: Text("category_page")),
                  DropdownMenuItem(value: "listing_detail", child: Text("listing_detail")),
                  DropdownMenuItem(value: "manage_dashboard", child: Text("manage_dashboard")),
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
                initialValue: _visibilityScope,
                decoration: const InputDecoration(labelText: "Visibility scope"),
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
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _startAtController,
                decoration: const InputDecoration(
                  labelText: "Start at ISO (optional)",
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _endAtController,
                decoration: const InputDecoration(
                  labelText: "End at ISO (optional)",
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayOrderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Display order"),
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
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text("Image from gallery"),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickVideoFromGallery,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text("Video from gallery"),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickMedia,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text("Pick file"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _mediaFile == null
                    ? "No media selected yet. Allowed: JPG, PNG, WebP, MP4 up to 25 MB."
                    : "Selected media: ${_mediaFile!.name}",
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(
                        _editingPromotionId == null
                            ? "Create promotion"
                            : "Save promotion",
                      ),
                    ),
                  ),
                  if (_editingPromotionId != null) ...<Widget>[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _resetForm,
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
                      onPressed: () => _deletePromotion(promotion["id"] as String),
                      child: const Text("Delete"),
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
                    Chip(label: Text("Media files: ${media.length}")),
                  ],
                ),
                const SizedBox(height: 10),
                if ((promotion["target_url"] as String?)?.isNotEmpty ?? false)
                  Text("Target: ${promotion["target_url"]}"),
                Text(
                  _placementDescription(promotion["placement"] as String? ?? "global"),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => _loadIntoForm(promotion),
                  child: const Text("Edit this promotion"),
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
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
          ) {
            final List<Map<String, dynamic>> promotions =
                snapshot.data ?? <Map<String, dynamic>>[];
            return ManagePageScrollView(
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
                                _buildPromotionList(promotions),
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
                        _buildPromotionList(promotions),
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
