import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/manage_ui.dart';

class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});

  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab> {
  late Future<List<Map<String, dynamic>>> _future;
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

  Future<List<Map<String, dynamic>>> _load() {
    return AppScope.of(context).repository.fetchCategoriesForAdmin();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openEditor([Map<String, dynamic>? category]) async {
    final TextEditingController nameController = TextEditingController(
      text: category?["name"] as String? ?? "",
    );
    final TextEditingController slugController = TextEditingController(
      text: category?["slug"] as String? ?? "",
    );
    final TextEditingController descriptionController = TextEditingController(
      text: category?["description"] as String? ?? "",
    );
    final TextEditingController iconKeyController = TextEditingController(
      text: category?["icon_key"] as String? ?? "",
    );
    final TextEditingController orderController = TextEditingController(
      text: (category?["display_order"] ?? 0).toString(),
    );
    final TextEditingController weightController = TextEditingController(
      text: (category?["home_feed_weight"] ?? 1).toString(),
    );
    final TextEditingController schemaController = TextEditingController(
      text: category?["field_schema"] == null
          ? "[]"
          : const JsonEncoder.withIndent("  ").convert(category?["field_schema"]),
    );
    bool isActive = category?["is_active"] as bool? ?? true;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(void Function()) setDialogState,
          ) {
            return AlertDialog(
              title: Text(category == null ? "New category" : "Edit category"),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: "Name"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: slugController,
                        decoration: const InputDecoration(labelText: "Slug"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: "Description"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: iconKeyController,
                        decoration: const InputDecoration(labelText: "Icon key"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: orderController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Display order"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: weightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Home feed weight"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: schemaController,
                        maxLines: 6,
                        decoration: const InputDecoration(labelText: "Field schema JSON"),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: isActive,
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Active"),
                        onChanged: (bool value) {
                          setDialogState(() => isActive = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () async {
                    final repository = AppScope.of(this.context).repository;
                    final navigator = Navigator.of(context);
                    await repository.saveCategory(
                      categoryId: category?["id"] as String?,
                      name: nameController.text.trim(),
                      slug: slugController.text.trim(),
                      description: descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                      iconKey: iconKeyController.text.trim().isEmpty
                          ? null
                          : iconKeyController.text.trim(),
                      displayOrder: int.tryParse(orderController.text.trim()) ?? 0,
                      isActive: isActive,
                      homeFeedWeight: int.tryParse(weightController.text.trim()) ?? 1,
                      fieldSchemaJson: schemaController.text.trim().isEmpty
                          ? "[]"
                          : schemaController.text.trim(),
                    );
                    if (!mounted) {
                      return;
                    }
                    navigator.pop();
                    await _refresh();
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (
        BuildContext context,
        AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
      ) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final List<Map<String, dynamic>> categories =
            snapshot.data ?? <Map<String, dynamic>>[];

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Categories",
              subtitle:
                  "Control the asset taxonomy, weights, and schema fields without changing Flutter code.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${categories.length} category${categories.length == 1 ? "" : "ies"}",
                  "New categories should map through category_id and field_schema",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Manage categories",
              subtitle:
                  "Add a new category or open any existing one to adjust schema, weight, and visibility.",
              action: FilledButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.add),
                label: const Text("Add category"),
              ),
              child: categories.isEmpty
                  ? const KodimaliEmptyState(
                      title: "Hakuna categories",
                      message: "Admin anaweza kuongeza categories mpya hapa.",
                    )
                  : Column(
                      children: categories.map((Map<String, dynamic> category) {
                        final bool active = category["is_active"] as bool? ?? false;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ManagePanel(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => _openEditor(category),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            category["name"] as String? ?? "-",
                                            style: Theme.of(context).textTheme.titleLarge,
                                          ),
                                        ),
                                        Chip(
                                          label: Text(active ? "active" : "inactive"),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ManageMetaWrap(
                                      items: <String>[
                                        "Slug: ${category["slug"] ?? "-"}",
                                        "Weight: ${category["home_feed_weight"] ?? 1}",
                                        "Display order: ${category["display_order"] ?? 0}",
                                      ],
                                    ),
                                  ],
                                ),
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
