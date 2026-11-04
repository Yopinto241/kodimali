import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import '../../agent/presentation/listing_detail_screen.dart';

import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class ListingApprovalTab extends StatefulWidget {
  const ListingApprovalTab({super.key});

  @override
  State<ListingApprovalTab> createState() => _ListingApprovalTabState();
}

class _ListingApprovalTabState extends State<ListingApprovalTab> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;
  final _search = TextEditingController();
  String? _status;
  String? _category;
  List<Map<String, dynamic>> _categories = [];
  Future<List<Map<String, dynamic>>> _bootstrap() async {
    _categories = await AppScope.of(context).repository.fetchActiveCategories();
    return _load();
  }

  int _page = 0;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  final Set<String> _updatingListingIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _future = _bootstrap();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return AppScope.of(context).repository.fetchListingsForModeration(
      search: _search.text,
      status: _status,
      categoryId: _category,
      offset: _page * 20,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _moderate({
    required String listingId,
    required String status,
    String? removedReason,
  }) async {
    if (_updatingListingIds.contains(listingId)) return;
    setState(() {
      _updatingListingIds.add(listingId);
    });
    try {
      final Map<String, dynamic> result = await AppScope.of(context).repository
          .moderateListing(
            listingId: listingId,
            status: status,
            removedReason: removedReason,
          );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result["message"]?.toString() ??
                  "Listing marketplace status updated.",
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mobileUiFormat(context, "Could not update listing: {0}", [
                userMessage(context, error),
              ]),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingListingIds.remove(listingId);
        });
      }
    }
  }

  Future<void> _deletePermanently(Map<String, dynamic> listing) async {
    final int inquiryCount = (listing["inquiry_count"] as num?)?.toInt() ?? 0;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const LocalizedUiText("Delete listing permanently?"),
        content: Text(
          inquiryCount > 0
              ? mobileUiFormat(
                  context,
                  "This listing has {0} inquiries. Permanent deletion will also remove customer inquiry history.",
                  [inquiryCount],
                )
              : mobileUi(
                  context,
                  "This listing has zero inquiries. Permanent deletion will remove the listing and its media files.",
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const LocalizedUiText("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const LocalizedUiText("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    try {
      await AppScope.of(context).repository.adminDeleteListing(
        listing["id"] as String,
        confirmDeleteWithInquiries: inquiryCount > 0,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedUiText('Listing deleted permanently.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mobileUiFormat(context, "Permanent deletion failed: {0}", [
                error,
              ]),
            ),
          ),
        );
      }
    }
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
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return KodimaliLoading(label: mobileUi(context, 'Loading...'));
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(userMessage(context, snapshot.error)),
                    TextButton(
                      onPressed: _refresh,
                      child: const LocalizedUiText('Retry'),
                    ),
                  ],
                ),
              );
            }
            final List<Map<String, dynamic>> listings =
                snapshot.data ?? <Map<String, dynamic>>[];
            return ManagePageScrollView(
              onRefresh: _refresh,
              children: <Widget>[
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _page = 0;
                    _refresh();
                  },
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Search listings'),
                    suffixIcon: IconButton(
                      tooltip: mobileUi(context, 'Search'),
                      onPressed: () {
                        _page = 0;
                        _refresh();
                      },
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Status'),
                  ),
                  items:
                      [
                            '',
                            'draft',
                            'active',
                            'inactive',
                            'expired',
                            'suspended',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                mobileUi(
                                  context,
                                  value.isEmpty ? 'All statuses' : value,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    _status = value;
                    _page = 0;
                    _refresh();
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _category ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Category'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: LocalizedUiText('All categories'),
                    ),
                    ..._categories.map(
                      (row) => DropdownMenuItem(
                        value: row['id'].toString(),
                        child: Text(
                          row['name'].toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    _category = value;
                    _page = 0;
                    _refresh();
                  },
                ),
                const SizedBox(height: 16),
                if (listings.isEmpty)
                  KodimaliEmptyState(
                    title: mobileUi(context, 'No listings available.'),
                    message: mobileUi(context, 'Try another search.'),
                  ),
                ...listings.map((Map<String, dynamic> listing) {
                  final String status = listing["status"] as String? ?? "-";
                  final String reviewStatus =
                      listing["publication_review_status"] as String? ??
                      "pending";
                  final Map<String, dynamic>? agent =
                      listing["agents"] as Map<String, dynamic>?;
                  final bool verifiedAgent =
                      agent?["verification_status"] == "approved" &&
                      agent?["account_status"] == "active";
                  final bool updating = _updatingListingIds.contains(
                    listing["id"],
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ManagePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (listing['preview_url'] != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  listing['preview_url'].toString(),
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  semanticLabel: listing['title']?.toString(),
                                  errorBuilder: (_, error, stack) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      listing["title"] as String? ?? "-",
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(_categoryLabel(listing)),
                                    const SizedBox(height: 6),
                                    Text(
                                      listing["public_location_label"]
                                              as String? ??
                                          "-",
                                    ),
                                  ],
                                ),
                              ),
                              KodimaliStatusChip(
                                label: status,
                                highlight: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'TZS ${listing['price_amount'] ?? 0} / ${mobileUi(context, listing['price_period']?.toString() ?? '')}',
                          ),
                          const SizedBox(height: 8),
                          ManageMetaWrap(
                            items: <String>[
                              mobileUiFormat(context, 'Inquiries: {0}', [
                                listing['inquiry_count'] ?? 0,
                              ]),
                              verifiedAgent
                                  ? "Verified agent · direct publication"
                                  : "Unverified agent · admin approval required",
                              '${mobileUi(context, 'Review')}: ${mobileUi(context, reviewStatus.replaceAll('_', ' '))}',
                              if (listing["publication_requested"] == true)
                                "Waiting for publication requirement",
                              if (listing["removed_reason"] != null)
                                "Reason: ${listing["removed_reason"]}",
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: () => Navigator.of(context)
                                    .push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ListingDetailScreen(
                                          listingId: listing['id'].toString(),
                                          adminMode: true,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted) _refresh();
                                    }),
                                child: const LocalizedUiText('View details'),
                              ),
                              FilledButton(
                                onPressed: status == "active" || updating
                                    ? null
                                    : () => _moderate(
                                        listingId: listing["id"] as String,
                                        status: "active",
                                      ),
                                child: Text(
                                  updating
                                      ? mobileUi(context, "Updating...")
                                      : reviewStatus == "pending"
                                      ? mobileUi(
                                          context,
                                          "Approve and activate",
                                        )
                                      : mobileUi(context, "Reactivate"),
                                ),
                              ),
                              OutlinedButton(
                                onPressed: status == "inactive"
                                    ? null
                                    : () => _moderate(
                                        listingId: listing["id"] as String,
                                        status: "inactive",
                                        removedReason: "admin_removed",
                                      ),
                                child: const LocalizedUiText("Remove"),
                              ),
                              OutlinedButton(
                                onPressed: () => _moderate(
                                  listingId: listing["id"] as String,
                                  status: "inactive",
                                  removedReason: "rented",
                                ),
                                child: const LocalizedUiText("Mark rented"),
                              ),
                              TextButton(
                                onPressed: () => _deletePermanently(listing),
                                child: const LocalizedUiText(
                                  "Delete permanently",
                                ),
                              ),
                            ],
                          ),
                        ],
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
