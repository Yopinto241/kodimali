import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/models/app_profile.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';
import '../../shared/presentation/platform_promotions_panel.dart';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({
    super.key,
    this.onOpenAgents,
    this.onOpenListings,
    this.onOpenRequests,
    this.onOpenReports,
    this.onOpenNotifications,
  });

  final VoidCallback? onOpenAgents;
  final VoidCallback? onOpenListings;
  final VoidCallback? onOpenRequests;
  final VoidCallback? onOpenReports;
  final VoidCallback? onOpenNotifications;

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  late Future<Map<String, int>> _future;
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

  Future<Map<String, int>> _load() {
    final controller = AppScope.of(context).controller;
    return AppScope.of(
      context,
    ).repository.fetchAdminDashboardCounts(controller.currentUser!.id);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).controller.profile;
    return FutureBuilder<Map<String, int>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Map<String, int>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final Map<String, int> counts = snapshot.data ?? <String, int>{};
        if (counts.isEmpty) {
          return const KodimaliEmptyState(
            title: "Hakuna dashboard data",
            message: "Admin metrics zitaonekana hapa.",
          );
        }

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Admin control center",
              subtitle:
                  "Manage activation, moderation, promotions, categories, and the health of the full marketplace.",
              trailing: profile == null
                  ? null
                  : Chip(
                      label: Text(
                        profile.highestRole.displayLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
              bottom: const ManageMetaWrap(
                items: <String>[
                  "Activate agents only after offline payment confirmation",
                  "Moderation changes hide listings immediately",
                  "Use category assignment to limit what each agent can post",
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _ContactPaymentSettingsPanel(),
            const SizedBox(height: 18),
            const _ContactPaymentOperationsPanel(),
            const SizedBox(height: 18),
            ManageMetricGrid(
              children: <Widget>[
                ManageMetricCard(
                  label: "Inactive or suspended agents",
                  value: "${counts["inactiveAgents"] ?? 0}",
                  icon: Icons.person_off_outlined,
                  caption: "Accounts waiting for activation or admin review.",
                  onTap: widget.onOpenAgents,
                ),
                ManageMetricCard(
                  label: "Live listings",
                  value: "${counts["liveListings"] ?? 0}",
                  icon: Icons.approval_outlined,
                  caption: "Assets currently active in the marketplace.",
                  tint: Theme.of(context).colorScheme.secondary,
                  onTap: widget.onOpenListings,
                ),
                ManageMetricCard(
                  label: "Inquiry volume",
                  value: "${counts["totalInquiries"] ?? 0}",
                  icon: Icons.insights_outlined,
                  caption: "Combined booking and inquiry demand.",
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: "New requests",
                  value: "${counts["newRequests"] ?? 0}",
                  icon: Icons.priority_high_rounded,
                  caption: "Requests still waiting for an agent response.",
                  tint: KodimaliColors.warning,
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: "Completed rentals",
                  value: "${counts["completedRequests"] ?? 0}",
                  icon: Icons.task_alt_outlined,
                  caption: "Request workflows marked completed.",
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: "Reports",
                  value: "${counts["reports"] ?? 0}",
                  icon: Icons.flag_outlined,
                  caption: "Reported content or complaints needing review.",
                  tint: KodimaliColors.warning,
                  onTap: widget.onOpenReports,
                ),
                ManageMetricCard(
                  label: "Unread notifications",
                  value: "${counts["unreadNotifications"] ?? 0}",
                  icon: Icons.notifications_none_outlined,
                  caption: "System updates still waiting for attention.",
                  onTap: widget.onOpenNotifications,
                ),
              ],
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Needs attention",
              subtitle:
                  "Open the exact queue instead of searching across the workspace.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_search_outlined),
                    title: Text(
                      "${counts["inactiveAgents"] ?? 0} agent accounts need review",
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenAgents,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.pending_actions_outlined),
                    title: Text(
                      "${counts["newRequests"] ?? 0} requests await agent action",
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenRequests,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(
                      "${counts["reports"] ?? 0} reports need moderation",
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenReports,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const PlatformPromotionsPanel(
              surface: "manage_admin",
              placement: "global",
              title: "Global promotions",
            ),
          ],
        );
      },
    );
  }
}

class _ContactPaymentSettingsPanel extends StatefulWidget {
  const _ContactPaymentSettingsPanel();

  @override
  State<_ContactPaymentSettingsPanel> createState() =>
      _ContactPaymentSettingsPanelState();
}

class _ContactPaymentSettingsPanelState
    extends State<_ContactPaymentSettingsPanel> {
  late Future<Map<String, dynamic>> _future;
  bool _saving = false;
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

  Future<Map<String, dynamic>> _load() {
    return AppScope.of(context).repository.fetchMarketplaceSettings();
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await AppScope.of(
        context,
      ).repository.updateContactPaymentsEnabled(enabled);
      if (!mounted) {
        return;
      }
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        final bool enabled =
            snapshot.data?["contact_payments_enabled"] as bool? ?? true;
        final String? updatedAt = snapshot.data?["updated_at"] as String?;
        final String? updatedBy = snapshot.data?["updated_by"] as String?;
        return ManagePanel(
          title: "Agent number payment",
          subtitle: enabled
              ? "Payments are on. Customer app and website hide agent numbers until contact payment is confirmed."
              : "Payments are off. Customer app and website can show agent numbers for free.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: Text(enabled ? "Payment required" : "Free contact"),
                subtitle: Text(
                  _saving
                      ? "Saving..."
                      : "Turn this off when you want customers to see agent numbers without payment.",
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setEnabled,
              ),
              const SizedBox(height: 8),
              ManageMetaWrap(
                items: <String>[
                  "Last changed ${DateFormatters.formatDateTime(updatedAt)}",
                  if (updatedBy != null) "Changed by $updatedBy",
                  "Every change is saved with admin identity",
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContactPaymentOperationsPanel extends StatefulWidget {
  const _ContactPaymentOperationsPanel();

  @override
  State<_ContactPaymentOperationsPanel> createState() =>
      _ContactPaymentOperationsPanelState();
}

class _ContactPaymentOperationsPanelState
    extends State<_ContactPaymentOperationsPanel> {
  String? _status;
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
    return AppScope.of(
      context,
    ).repository.fetchAdminPaymentOperations(paymentStatus: _status);
  }

  Future<void> _refresh() async {
    final Future<List<Map<String, dynamic>>> next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: "Contact payment operations",
      subtitle:
          "Monitor provider status, reconciliation, webhook delivery, and whether contact access was revealed.",
      action: IconButton(
        tooltip: "Refresh payments",
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButton<String?>(
            value: _status,
            hint: const Text("All payment statuses"),
            items: const <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(value: null, child: Text("All")),
              DropdownMenuItem<String?>(
                value: "pending",
                child: Text("Pending"),
              ),
              DropdownMenuItem<String?>(
                value: "processing",
                child: Text("Processing"),
              ),
              DropdownMenuItem<String?>(value: "paid", child: Text("Paid")),
              DropdownMenuItem<String?>(value: "failed", child: Text("Failed")),
              DropdownMenuItem<String?>(
                value: "expired",
                child: Text("Expired"),
              ),
              DropdownMenuItem<String?>(
                value: "cancelled",
                child: Text("Cancelled"),
              ),
            ],
            onChanged: (String? value) {
              setState(() {
                _status = value;
                _future = _load();
              });
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
                ) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Text(userFacingError(snapshot.error!));
                  }
                  final List<Map<String, dynamic>> rows =
                      snapshot.data ?? <Map<String, dynamic>>[];
                  if (rows.isEmpty) {
                    return const Text(
                      "No contact-payment operations match this filter yet.",
                    );
                  }
                  final int paid = rows.where((Map<String, dynamic> row) {
                    return row["payment_status"] == "paid";
                  }).length;
                  final int failed = rows.where((Map<String, dynamic> row) {
                    return row["payment_status"] == "failed";
                  }).length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Chip(label: Text("${rows.length} loaded")),
                          Chip(label: Text("$paid paid")),
                          Chip(label: Text("$failed failed")),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...rows.take(10).map((Map<String, dynamic> row) {
                        final num? amount =
                            row["requested_amount"] as num? ??
                            row["amount"] as num?;
                        final String title =
                            row["listing_title"] as String? ??
                            row["customer_name"] as String? ??
                            "Contact payment";
                        final String status =
                            row["payment_status"] as String? ?? "pending";
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            status == "paid"
                                ? Icons.check_circle_outline
                                : status == "failed"
                                ? Icons.error_outline_rounded
                                : Icons.hourglass_top_rounded,
                          ),
                          title: Text(title),
                          subtitle: Text(
                            <String>[
                              row["order_reference"] as String? ??
                                  "No reference",
                              DateFormatters.formatCurrency(amount),
                              DateFormatters.formatDateTime(
                                row["initiated_at"] as String?,
                              ),
                              if (row["reconciliation_status"] != null)
                                "Reconciliation ${row["reconciliation_status"]}",
                              if (row["reconciliation_attempts"] != null)
                                "Attempts ${row["reconciliation_attempts"]}",
                              if (row["last_event_status"] != null)
                                "Webhook ${row["last_event_status"]}",
                            ].join(" • "),
                          ),
                          trailing: KodimaliStatusChip(
                            label: status,
                            highlight:
                                status == "failed" || status == "pending",
                          ),
                        );
                      }),
                    ],
                  );
                },
          ),
        ],
      ),
    );
  }
}
