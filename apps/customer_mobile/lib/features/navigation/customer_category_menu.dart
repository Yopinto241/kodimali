import 'package:flutter/material.dart';
import 'package:flutter_core/localized_ui.dart';

import '../../core/localization/customer_localization.dart';

/// The home category shortcut has a visible purpose and a full-sized touch target.
class CustomerCategoryMenu extends StatelessWidget {
  const CustomerCategoryMenu({
    super.key,
    required this.categories,
    required this.onOpenAll,
    required this.onOpenCategory,
  });

  final List<Map<String, dynamic>> categories;
  final VoidCallback onOpenAll;
  final ValueChanged<Map<String, dynamic>> onOpenCategory;

  Future<void> _open(BuildContext context) async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.82,
        child: _CategorySheet(categories: categories),
      ),
    );
    if (!context.mounted || selected == null) return;
    if (selected['__all__'] == true) {
      onOpenAll();
    } else {
      onOpenCategory(selected);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => _open(context),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white54),
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    icon: const Icon(Icons.grid_view_rounded, size: 20),
    label: Text(context.tr('nav.categories')),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.categories});
  final List<Map<String, dynamic>> categories;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final categories = widget.categories.where((category) {
      final name = category['name']?.toString() ?? '';
      return name.toLowerCase().contains(query) ||
          translateMobileUi('sw', name).toLowerCase().contains(query) ||
          translateMobileUi('en', name).toLowerCase().contains(query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('heading.browseCategories'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: mobileUi(context, 'Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: mobileUi(context, 'Search category'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            itemCount: categories.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    ListTile(
                      minVerticalPadding: 14,
                      leading: const Icon(Icons.apps_rounded),
                      title: Text(context.tr('heading.browseCategories')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, <String, dynamic>{
                        '__all__': true,
                      }),
                    ),
                    const Divider(height: 1),
                    if (categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: LocalizedUiText(
                          'No category matches your search.',
                        ),
                      ),
                  ],
                );
              }
              final category = categories[index - 1];
              return ListTile(
                minVerticalPadding: 14,
                title: LocalizedUiText(category['name']?.toString() ?? '-'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, category),
              );
            },
          ),
        ),
      ],
    );
  }
}
