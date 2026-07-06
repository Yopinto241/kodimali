import 'package:flutter/material.dart';

import '../../../core/ads/admob_support.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';
import 'listing_detail_screen.dart';

class AgentListingsTab extends StatefulWidget {
  const AgentListingsTab({super.key});

  @override
  State<AgentListingsTab> createState() => _AgentListingsTabState();
}

class _AgentListingsTabState extends State<AgentListingsTab> {
  static const double _menuMaxHeight = 360;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedStatus;
  List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[];
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _future = _bootstrap();
  }

  Future<List<Map<String, dynamic>>> _bootstrap() async {
    _categories = await AppScope.of(context).repository.fetchActiveCategories();
    return _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return AppScope.of(context).repository.fetchMyListings(
      search: _searchController.text.trim(),
      category: _selectedCategoryId,
      status: _selectedStatus,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openDetail(String listingId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingDetailScreen(listingId: listingId),
      ),
    );
    await _refresh();
  }

  String _categoryLabel(Map<String, dynamic> listing) {
    final Map<String, dynamic>? category =
        listing["asset_categories"] as Map<String, dynamic>?;
    return category?["name"] as String? ?? listing["category"] as String? ?? "-";
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
        final List<Map<String, dynamic>> listings =
            snapshot.data ?? <Map<String, dynamic>>[];

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "My listings",
              subtitle:
                  "Search quickly, filter by category or status, and open any asset to update price, availability, or marketplace visibility.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${listings.length} listing${listings.length == 1 ? "" : "s"} loaded",
                  _selectedStatus == null ? "All statuses" : "Status: $_selectedStatus",
                  _selectedCategoryId == null ? "All categories" : "Category filter active",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Filter listings",
              subtitle:
                  "Use narrow filters when you need to update one category or find inactive assets fast.",
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _refresh(),
                    decoration: InputDecoration(
                      labelText: "Search title",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: _refresh,
                        icon: const Icon(Icons.tune),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final bool stacked = constraints.maxWidth < 680;
                      final Widget categoryField = DropdownButtonFormField<String>(
                        isExpanded: true,
                        menuMaxHeight: _menuMaxHeight,
                        initialValue: _selectedCategoryId,
                        decoration: const InputDecoration(labelText: "Category"),
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text("All categories"),
                          ),
                          ..._categories.map(
                            (Map<String, dynamic> category) => DropdownMenuItem<String>(
                              value: category["id"] as String,
                              child: Text(category["name"] as String? ?? "-"),
                            ),
                          ),
                        ],
                        onChanged: (String? value) {
                          setState(() => _selectedCategoryId = value);
                        },
                      );
                      final Widget statusField = DropdownButtonFormField<String>(
                        isExpanded: true,
                        menuMaxHeight: _menuMaxHeight,
                        initialValue: _selectedStatus,
                        decoration: const InputDecoration(labelText: "Status"),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: null,
                            child: Text("All statuses"),
                          ),
                          DropdownMenuItem(value: "active", child: Text("Active")),
                          DropdownMenuItem(value: "inactive", child: Text("Inactive")),
                          DropdownMenuItem(value: "suspended", child: Text("Suspended")),
                        ],
                        onChanged: (String? value) {
                          setState(() => _selectedStatus = value);
                        },
                      );

                      if (stacked) {
                        return Column(
                          children: <Widget>[
                            categoryField,
                            const SizedBox(height: 12),
                            statusField,
                          ],
                        );
                      }
                      return Row(
                        children: <Widget>[
                          Expanded(child: categoryField),
                          const SizedBox(width: 12),
                          Expanded(child: statusField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const Text("Apply filters"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _selectedCategoryId = null;
                            _selectedStatus = null;
                            _future = _load();
                          });
                        },
                        child: const Text("Reset"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const ManageInlineBannerAdCard(),
            const SizedBox(height: 12),
            const ManageAdPrivacyButton(),
            const SizedBox(height: 18),
            ManageSectionTitle(
              title: "Listing overview",
              subtitle: listings.isEmpty
                  ? "No assets match the current filters."
                  : "Tap any card to open the full listing editor.",
            ),
            const SizedBox(height: 12),
            if (listings.isEmpty)
              const KodimaliEmptyState(
                title: "Hakuna listings",
                message:
                    "Listings zako zitaonekana hapa baada ya kuongeza asset ya kwanza.",
              )
            else
              ...listings.map((Map<String, dynamic> listing) {
                final String status = listing["status"] as String? ?? "-";
                final String availability =
                    listing["availability_status"] as String? ?? "-";
                final String removedReason =
                    listing["removed_reason"] as String? ?? "";
                final num? priceAmount = listing["price_amount"] as num?;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ManagePanel(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _openDetail(listing["id"] as String),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        listing["title"] as String? ?? "-",
                                        style: Theme.of(context).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _categoryLabel(listing),
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        listing["public_location_label"] as String? ?? "-",
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    KodimaliStatusChip(
                                      label: status,
                                      highlight: status == "active",
                                    ),
                                    const SizedBox(height: 8),
                                    KodimaliStatusChip(label: availability),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ManageMetaWrap(
                              items: <String>[
                                "${DateFormatters.formatCurrency(priceAmount)} / ${listing["price_period"] ?? "-"}",
                                "Inquiries: ${listing["inquiry_count"] ?? 0}",
                                "Created ${DateFormatters.formatDateTime(listing["created_at"] as String?)}",
                                if (removedReason.isNotEmpty) "Reason: $removedReason",
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    "Open listing to edit details, reactivate, remove, or delete when it has no inquiries.",
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.tonal(
                                  onPressed: () => _openDetail(listing["id"] as String),
                                  child: const Text("Open"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
