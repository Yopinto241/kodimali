import 'package:flutter/material.dart';

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
    return AppScope.of(context).repository.fetchListingsForModeration();
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
    await AppScope.of(context).repository.moderateListing(
      listingId: listingId,
      status: status,
      removedReason: removedReason,
    );
    await _refresh();
  }

  Future<void> _deletePermanently(Map<String, dynamic> listing) async {
    final int inquiryCount = (listing["inquiry_count"] as num?)?.toInt() ?? 0;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Delete listing permanently?"),
        content: Text(
          inquiryCount > 0
              ? "This listing has $inquiryCount inquiries. Permanent deletion will also remove customer inquiry history."
              : "This listing has zero inquiries. Permanent deletion will remove the listing and its media files.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete"),
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
    await AppScope.of(context).repository.adminDeleteListing(
      listing["id"] as String,
      confirmDeleteWithInquiries: inquiryCount > 0,
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final List<Map<String, dynamic>> listings =
            snapshot.data ?? <Map<String, dynamic>>[];
        if (listings.isEmpty) {
          return const KodimaliEmptyState(
            title: "Hakuna listings",
            message: "Listings zote zitaonekana hapa kwa admin management.",
          );
        }
        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Listing moderation",
              subtitle:
                  "Reactivate, remove, or permanently delete listings while keeping inquiry history rules intact.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${listings.length} listing${listings.length == 1 ? "" : "s"} in queue",
                  "Public visibility depends on listing state and agent state",
                ],
              ),
            ),
            const SizedBox(height: 18),
            ...listings.map((Map<String, dynamic> listing) {
              final String status = listing["status"] as String? ?? "-";
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: ManagePanel(
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
                                Text(_categoryLabel(listing)),
                                const SizedBox(height: 6),
                                Text(
                                  listing["public_location_label"] as String? ??
                                      "-",
                                ),
                              ],
                            ),
                          ),
                          KodimaliStatusChip(label: status, highlight: true),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ManageMetaWrap(
                        items: <String>[
                          "Inquiries: ${listing["inquiry_count"] ?? 0}",
                          if (listing["removed_reason"] != null)
                            "Reason: ${listing["removed_reason"]}",
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          FilledButton(
                            onPressed: status == "active"
                                ? null
                                : () => _moderate(
                                    listingId: listing["id"] as String,
                                    status: "active",
                                  ),
                            child: const Text("Reactivate"),
                          ),
                          OutlinedButton(
                            onPressed: status == "inactive"
                                ? null
                                : () => _moderate(
                                    listingId: listing["id"] as String,
                                    status: "inactive",
                                    removedReason: "admin_removed",
                                  ),
                            child: const Text("Remove"),
                          ),
                          OutlinedButton(
                            onPressed: () => _moderate(
                              listingId: listing["id"] as String,
                              status: "inactive",
                              removedReason: "rented",
                            ),
                            child: const Text("Mark rented"),
                          ),
                          TextButton(
                            onPressed: () => _deletePermanently(listing),
                            child: const Text("Delete permanently"),
                          ),
                        ],
                      ),
                    ],
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
