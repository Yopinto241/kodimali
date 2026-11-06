import 'package:flutter_core/listing_media.dart';
import '../../../core/widgets/location_directory.dart';
import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

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
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedStatus;
  String _sort = "newest";
  List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[];
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;
  int _page = 0;
  Map<String, dynamic>? _directoryLocation;
  bool _viewListings = false;

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
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() {
    if (!_viewListings) return Future.value(<Map<String, dynamic>>[]);
    return AppScope.of(context).repository.fetchMyListings(
      directoryLocationId: _directoryLocation?["id"] as String?,
      directoryLocationType: _directoryLocation?["location_type"] as String?,
      search: _searchController.text.trim(),
      category: _selectedCategoryId,
      status: _selectedStatus,
      minPrice: double.tryParse(_minPriceController.text.trim()),
      maxPrice: double.tryParse(_maxPriceController.text.trim()),
      sort: _sort,
      offset: _page * 20,
      limit: 20,
    );
  }

  Future<void> _applyFilters() {
    _page = 0;
    return _refresh();
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
    return category?["name"] as String? ??
        listing["category"] as String? ??
        "-";
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return KodimaliLoading(label: mobileUi(context, 'Loading...'));
        }
        if (snapshot.hasError) {
          return Center(child: Text(userMessage(context, snapshot.error)));
        }
        final List<Map<String, dynamic>> listings =
            snapshot.data ?? <Map<String, dynamic>>[];

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            LocationDirectory(
              onView: (location) {
                _directoryLocation = location;
                _viewListings = true;
                _page = 0;
                _refresh();
              },
            ),
            if (_viewListings)
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in const {
                    '': 'All statuses',
                    'active': 'Active',
                    'parked': 'Parked / not on market',
                  }.entries)
                    ChoiceChip(
                      label: LocalizedUiText(entry.value),
                      selected: (_selectedStatus ?? '') == entry.key,
                      onSelected: (_) {
                        _selectedStatus = entry.key.isEmpty ? null : entry.key;
                        _page = 0;
                        _refresh();
                      },
                    ),
                ],
              ),
            if (_viewListings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _directoryLocation == null
                      ? mobileUi(context, 'All locations')
                      : '${_directoryLocation!["name"]}',
                ),
              ),
            if (!_viewListings)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LocalizedUiText(
                  'Choose a region, district or ward, then view listings at that level.',
                ),
              ),

            ManageHeroCard(
              title: mobileUi(context, "My listings"),
              subtitle: mobileUi(
                context,
                "Search quickly, filter by category or status, and open any asset to update price, availability, or marketplace visibility.",
              ),
              bottom: ManageMetaWrap(
                items: <String>[
                  "${listings.length} listing${listings.length == 1 ? "" : "s"} loaded",
                  _selectedStatus == null
                      ? "All statuses"
                      : "Status: $_selectedStatus",
                  _selectedCategoryId == null
                      ? "All categories"
                      : "Category filter active",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ManagePanel(
              collapsible: true,
              title: mobileUi(context, "Filter listings"),
              subtitle: mobileUi(
                context,
                "Use narrow filters when you need to update one category or find inactive assets fast.",
              ),
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _applyFilters(),
                    decoration: InputDecoration(
                      labelText: mobileUi(context, "Search title"),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: _applyFilters,
                        icon: const Icon(Icons.tune),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _minPriceController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: mobileUi(context, "Minimum price"),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: mobileUi(context, "Maximum price"),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _sort,
                    decoration: InputDecoration(
                      labelText: mobileUi(context, "Sort listings"),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: "newest",
                        child: LocalizedUiText("Newest first"),
                      ),
                      DropdownMenuItem(
                        value: "price_low",
                        child: LocalizedUiText("Lowest price"),
                      ),
                      DropdownMenuItem(
                        value: "price_high",
                        child: LocalizedUiText("Highest price"),
                      ),
                    ],
                    onChanged: (String? value) => setState(() {
                      _sort = value ?? "newest";
                    }),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final bool stacked = constraints.maxWidth < 680;
                          final Widget categoryField =
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                menuMaxHeight: _menuMaxHeight,
                                initialValue: _selectedCategoryId,
                                decoration: InputDecoration(
                                  labelText: mobileUi(context, "Category"),
                                ),
                                items: <DropdownMenuItem<String>>[
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: LocalizedUiText("All categories"),
                                  ),
                                  ..._categories.map(
                                    (Map<String, dynamic> category) =>
                                        DropdownMenuItem<String>(
                                          value: category["id"] as String,
                                          child: Text(
                                            category["name"] as String? ?? "-",
                                          ),
                                        ),
                                  ),
                                ],
                                onChanged: (String? value) {
                                  setState(() {
                                    _selectedCategoryId = value;
                                  });
                                },
                              );
                          final Widget statusField =
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                menuMaxHeight: _menuMaxHeight,
                                key: ValueKey(_selectedStatus),
                                initialValue: _selectedStatus,
                                decoration: InputDecoration(
                                  labelText: mobileUi(context, "Status"),
                                ),
                                items: const <DropdownMenuItem<String>>[
                                  DropdownMenuItem<String>(
                                    value: null,
                                    child: LocalizedUiText("All statuses"),
                                  ),
                                  DropdownMenuItem(
                                    value: "active",
                                    child: LocalizedUiText("Active"),
                                  ),
                                  DropdownMenuItem(
                                    value: "parked",
                                    child: LocalizedUiText(
                                      "Parked / not on market",
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: "inactive",
                                    child: LocalizedUiText("Inactive"),
                                  ),
                                  DropdownMenuItem(
                                    value: "suspended",
                                    child: LocalizedUiText("Suspended"),
                                  ),
                                ],
                                onChanged: (String? value) {
                                  setState(() {
                                    _selectedStatus = value;
                                  });
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
                          onPressed: _applyFilters,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const LocalizedUiText("Apply filters"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          _page = 0;
                          _searchController.clear();
                          _minPriceController.clear();
                          _maxPriceController.clear();
                          setState(() {
                            _selectedCategoryId = null;
                            _selectedStatus = null;
                            _sort = "newest";
                            _future = _load();
                          });
                        },
                        child: const LocalizedUiText("Reset"),
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
              title: mobileUi(context, "Listing overview"),
              subtitle: listings.isEmpty
                  ? "No assets match the current filters."
                  : "Tap any card to open the full listing editor.",
            ),
            const SizedBox(height: 12),
            if (listings.isEmpty)
              KodimaliEmptyState(
                title: mobileUi(context, "Hakuna listings"),
                message: mobileUi(
                  context,
                  "Listings zako zitaonekana hapa baada ya kuongeza asset ya kwanza.",
                ),
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
                            if (listing['preview_url'] != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AspectRatio(
                                    aspectRatio: 4 / 5,
                                    child:
                                        listing['preview_media_type'] == 'video'
                                        ? AbsorbPointer(
                                            child: ListingVideo(
                                              autoPlay: true,
                                              showControls: false,
                                              url: listing['preview_url']
                                                  .toString(),
                                            ),
                                          )
                                        : ListingImage(
                                            url: listing['preview_url']
                                                .toString(),
                                            cacheKey:
                                                (listing['listing_media']
                                                        as List?)
                                                    ?.firstOrNull?['storage_path']
                                                    ?.toString(),
                                          ),
                                  ),
                                ),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        listing["title"] as String? ?? "-",
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _categoryLabel(listing),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        listing["public_location_label"]
                                                as String? ??
                                            "-",
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
                                if (removedReason.isNotEmpty)
                                  "Reason: $removedReason",
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: LocalizedUiText(
                                    "Open listing to edit details, reactivate, remove, or delete when it has no inquiries.",
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.tonal(
                                  onPressed: () =>
                                      _openDetail(listing["id"] as String),
                                  child: const LocalizedUiText("Open"),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _page == 0
                      ? null
                      : () {
                          _page--;
                          _refresh();
                        },
                  child: const LocalizedUiText('Previous'),
                ),
                TextButton(
                  onPressed: listings.length < 20
                      ? null
                      : () {
                          _page++;
                          _refresh();
                        },
                  child: const LocalizedUiText('Next'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
