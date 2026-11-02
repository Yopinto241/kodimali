import 'package:flutter_core/localized_ui.dart';
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
  static const List<String> _fieldTypes = <String>[
    'text',
    'textarea',
    'number',
    'boolean',
    'select',
  ];

  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      AppScope.of(context).repository.fetchCategoriesForAdmin();

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  List<Map<String, dynamic>> _schemaFor(Map<String, dynamic>? category) {
    final dynamic raw = category?['field_schema'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((Map item) {
      final Map<String, dynamic> field = item.cast<String, dynamic>();
      return <String, dynamic>{
        'key': field['key']?.toString() ?? '',
        'label': field['label']?.toString() ?? field['key']?.toString() ?? '',
        'type': field['type']?.toString() ?? 'text',
        'required': field['required'] == true,
        'active': field['active'] != false,
        if (field['help_text']?.toString().trim().isNotEmpty == true)
          'help_text': field['help_text'].toString().trim(),
        if (field['options'] is List)
          'options': List<String>.from(
            (field['options'] as List).map((dynamic value) => value.toString()),
          ),
      };
    }).toList();
  }

  String _fieldKeyFromLabel(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<Map<String, dynamic>?> _openFieldEditor({
    Map<String, dynamic>? field,
    required Set<String> usedKeys,
  }) async {
    final bool editing = field != null;
    final TextEditingController keyController = TextEditingController(
      text: field?['key']?.toString() ?? '',
    );
    final TextEditingController labelController = TextEditingController(
      text: field?['label']?.toString() ?? '',
    );
    final TextEditingController helpController = TextEditingController(
      text: field?['help_text']?.toString() ?? '',
    );
    final TextEditingController optionsController = TextEditingController(
      text: (field?['options'] as List<dynamic>?)?.join('\n') ?? '',
    );
    String type = field?['type']?.toString() ?? 'text';
    bool required = field?['required'] == true;
    bool active = field?['active'] != false;
    String? error;

    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            title: Text(
              editing
                  ? mobileUi(context, 'Edit listing field')
                  : mobileUi(context, 'Add listing field'),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Field label *'),
                      ),
                      onChanged: (String value) {
                        if (!editing && keyController.text.trim().isEmpty) {
                          keyController.text = _fieldKeyFromLabel(value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyController,
                      readOnly: editing,
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Database key *'),
                        helperText: editing
                            ? mobileUi(
                                context,
                                'Keys are locked to protect values on existing listings.',
                              )
                            : mobileUi(
                                context,
                                'Lowercase letters, numbers, and underscores only.',
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _fieldTypes.contains(type) ? type : 'text',
                      disabledHint: Text(type),
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Field type'),
                      ),
                      items: _fieldTypes
                          .map(
                            (String value) => DropdownMenuItem<String>(
                              value: value,
                              child: LocalizedUiText(value),
                            ),
                          )
                          .toList(),
                      onChanged: editing
                          ? null
                          : (String? value) =>
                                setDialogState(() => type = value ?? 'text'),
                    ),
                    if (type == 'select') ...<Widget>[
                      const SizedBox(height: 12),
                      TextField(
                        controller: optionsController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Options *'),
                          helperText: mobileUi(
                            context,
                            'Enter one option per line.',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: helpController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Help text (optional)'),
                      ),
                    ),
                    SwitchListTile(
                      value: required,
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedUiText('Required for new listings'),
                      onChanged: (bool value) =>
                          setDialogState(() => required = value),
                    ),
                    SwitchListTile(
                      value: active,
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedUiText('Show this field'),
                      subtitle: const LocalizedUiText(
                        'Turn this off to retire a field without deleting stored data.',
                      ),
                      onChanged: (bool value) =>
                          setDialogState(() => active = value),
                    ),
                    if (error != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const LocalizedUiText('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final String key = keyController.text.trim().toLowerCase();
                  final String label = labelController.text.trim();
                  final List<String> options = optionsController.text
                      .split(RegExp(r'[\r\n,]+'))
                      .map((String item) => item.trim())
                      .where((String item) => item.isNotEmpty)
                      .toSet()
                      .toList();
                  if (label.isEmpty) {
                    setDialogState(() => error = 'Enter a field label.');
                    return;
                  }
                  if (!RegExp(r'^[a-z][a-z0-9_]{0,62}$').hasMatch(key)) {
                    setDialogState(() => error = 'Enter a valid database key.');
                    return;
                  }
                  if (!editing && usedKeys.contains(key)) {
                    setDialogState(
                      () => error = 'That database key is already in use.',
                    );
                    return;
                  }
                  if (type == 'select' && options.isEmpty) {
                    setDialogState(
                      () => error = 'Add at least one select option.',
                    );
                    return;
                  }
                  Navigator.of(context).pop(<String, dynamic>{
                    'key': key,
                    'label': label,
                    'type': type,
                    'required': required,
                    'active': active,
                    if (helpController.text.trim().isNotEmpty)
                      'help_text': helpController.text.trim(),
                    if (type == 'select') 'options': options,
                  });
                },
                child: const LocalizedUiText('Save field'),
              ),
            ],
          );
        },
      ),
    );
    keyController.dispose();
    labelController.dispose();
    helpController.dispose();
    optionsController.dispose();
    return result;
  }

  Future<void> _openEditor([Map<String, dynamic>? category]) async {
    final TextEditingController nameController = TextEditingController(
      text: category?['name'] as String? ?? '',
    );
    final TextEditingController slugController = TextEditingController(
      text: category?['slug'] as String? ?? '',
    );
    final TextEditingController descriptionController = TextEditingController(
      text: category?['description'] as String? ?? '',
    );
    final TextEditingController iconKeyController = TextEditingController(
      text: category?['icon_key'] as String? ?? '',
    );
    final TextEditingController orderController = TextEditingController(
      text: (category?['display_order'] ?? 0).toString(),
    );
    final TextEditingController weightController = TextEditingController(
      text: (category?['home_feed_weight'] ?? 1).toString(),
    );
    final List<Map<String, dynamic>> fields = _schemaFor(category);
    bool isActive = category?['is_active'] as bool? ?? true;
    bool saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          Future<void> editField([int? index]) async {
            final Set<String> usedKeys = fields
                .asMap()
                .entries
                .where(
                  (MapEntry<int, Map<String, dynamic>> entry) =>
                      entry.key != index,
                )
                .map(
                  (MapEntry<int, Map<String, dynamic>> entry) =>
                      entry.value['key'].toString(),
                )
                .toSet();
            final Map<String, dynamic>? result = await _openFieldEditor(
              field: index == null ? null : fields[index],
              usedKeys: usedKeys,
            );
            if (result == null) return;
            setDialogState(() {
              if (index == null) {
                fields.add(result);
              } else {
                fields[index] = result;
              }
            });
          }

          return AlertDialog(
            title: Text(
              category == null
                  ? mobileUi(context, 'New category')
                  : mobileUi(context, 'Edit category'),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Name *'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: slugController,
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Slug *'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Description'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: iconKeyController,
                      decoration: InputDecoration(
                        labelText: mobileUi(context, 'Icon key'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: orderController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: mobileUi(context, 'Display order'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: weightController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: mobileUi(context, 'Home feed weight'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: LocalizedUiText(
                            'Listing fields',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => editField(),
                          icon: const Icon(Icons.add),
                          label: const LocalizedUiText('Add field'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (fields.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: LocalizedUiText(
                          'No extra listing fields configured.',
                        ),
                      )
                    else
                      ...fields.asMap().entries.map((
                        MapEntry<int, Map<String, dynamic>> entry,
                      ) {
                        final Map<String, dynamic> field = entry.value;
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              field['active'] == false
                                  ? Icons.visibility_off_outlined
                                  : Icons.dynamic_form_outlined,
                            ),
                            title: Text(field['label'].toString()),
                            subtitle: Text(
                              '${field['key']} · ${field['type']}${field['required'] == true ? mobileUi(context, ' · required') : ''}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: mobileUi(context, 'Edit field'),
                              onPressed: () => editField(entry.key),
                            ),
                            onTap: () => editField(entry.key),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: isActive,
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedUiText('Category active'),
                      onChanged: (bool value) =>
                          setDialogState(() => isActive = value),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: const LocalizedUiText('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final NavigatorState navigator = Navigator.of(context);
                        if (nameController.text.trim().isEmpty ||
                            slugController.text.trim().isEmpty) {
                          setDialogState(
                            () => error = 'Name and slug are required.',
                          );
                          return;
                        }
                        setDialogState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await AppScope.of(
                            this.context,
                          ).repository.saveCategory(
                            categoryId: category?['id'] as String?,
                            name: nameController.text.trim(),
                            slug: slugController.text.trim(),
                            description:
                                descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                            iconKey: iconKeyController.text.trim().isEmpty
                                ? null
                                : iconKeyController.text.trim(),
                            displayOrder:
                                int.tryParse(orderController.text.trim()) ?? 0,
                            isActive: isActive,
                            homeFeedWeight:
                                int.tryParse(weightController.text.trim()) ?? 1,
                            fieldSchema: fields,
                          );
                          if (!mounted) return;
                          navigator.pop();
                          await _refresh();
                        } catch (exception) {
                          setDialogState(() {
                            saving = false;
                            error = exception.toString();
                          });
                        }
                      },
                child: Text(
                  saving
                      ? mobileUi(context, 'Saving...')
                      : mobileUi(context, 'Save category'),
                ),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    slugController.dispose();
    descriptionController.dispose();
    iconKeyController.dispose();
    orderController.dispose();
    weightController.dispose();
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
        final List<Map<String, dynamic>> categories =
            snapshot.data ?? <Map<String, dynamic>>[];
        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: mobileUi(context, 'Categories & listing fields'),
              subtitle: mobileUi(
                context,
                'Add and edit reusable listing fields without changing the app code or adding database columns.',
              ),
              bottom: ManageMetaWrap(
                items: <String>[
                  '${categories.length} categories',
                  '${categories.fold<int>(0, (int count, Map<String, dynamic> category) => count + _schemaFor(category).length)} configured fields',
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: mobileUi(context, 'Manage categories'),
              subtitle: mobileUi(
                context,
                'Open a category to manage the fields agents complete for every listing.',
              ),
              action: FilledButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.add),
                label: const LocalizedUiText('Add category'),
              ),
              child: categories.isEmpty
                  ? KodimaliEmptyState(
                      title: mobileUi(context, 'Hakuna categories'),
                      message: mobileUi(
                        context,
                        'Admin anaweza kuongeza categories mpya hapa.',
                      ),
                    )
                  : Column(
                      children: categories.map((Map<String, dynamic> category) {
                        final List<Map<String, dynamic>> fields = _schemaFor(
                          category,
                        );
                        final int activeFields = fields
                            .where(
                              (Map<String, dynamic> field) =>
                                  field['active'] != false,
                            )
                            .length;
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
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            category['name'] as String? ?? '-',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            category['is_active'] == true
                                                ? mobileUi(context, 'active')
                                                : mobileUi(context, 'inactive'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ManageMetaWrap(
                                      items: <String>[
                                        'Slug: ${category['slug'] ?? '-'}',
                                        '$activeFields active listing fields',
                                        'Display order: ${category['display_order'] ?? 0}',
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
