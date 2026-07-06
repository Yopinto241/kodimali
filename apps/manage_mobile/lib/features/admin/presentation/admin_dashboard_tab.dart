import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/models/app_profile.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/manage_ui.dart';
import '../../shared/presentation/platform_promotions_panel.dart';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key});

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
            ManageMetricGrid(
              children: <Widget>[
                ManageMetricCard(
                  label: "Inactive or suspended agents",
                  value: "${counts["inactiveAgents"] ?? 0}",
                  icon: Icons.person_off_outlined,
                  caption: "Accounts waiting for activation or admin review.",
                ),
                ManageMetricCard(
                  label: "Live listings",
                  value: "${counts["liveListings"] ?? 0}",
                  icon: Icons.approval_outlined,
                  caption: "Assets currently active in the marketplace.",
                  tint: Theme.of(context).colorScheme.secondary,
                ),
                ManageMetricCard(
                  label: "Inquiry volume",
                  value: "${counts["totalInquiries"] ?? 0}",
                  icon: Icons.insights_outlined,
                  caption: "Combined booking and inquiry demand.",
                ),
                ManageMetricCard(
                  label: "Reports",
                  value: "${counts["reports"] ?? 0}",
                  icon: Icons.flag_outlined,
                  caption: "Reported content or complaints needing review.",
                  tint: KodimaliColors.warning,
                ),
                ManageMetricCard(
                  label: "Unread notifications",
                  value: "${counts["unreadNotifications"] ?? 0}",
                  icon: Icons.notifications_none_outlined,
                  caption: "System updates still waiting for attention.",
                ),
              ],
            ),
            const SizedBox(height: 18),
            const ManagePanel(
              title: "Admin focus",
              subtitle:
                  "Best order: verify agent category access, confirm activation status, then moderate listings and promotion placements.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Keep inactive and suspended agents unable to handle booking workflows.",
                  ),
                  SizedBox(height: 8),
                  Text(
                    "New categories should flow through category_id and field_schema only.",
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Promotion placement must respect actual user role, not client-provided surface values.",
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

  @override
  void initState() {
    super.initState();
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
        return ManagePanel(
          title: "Agent number payment",
          subtitle: enabled
              ? "Payments are on. Customer app and website hide agent numbers until contact payment is confirmed."
              : "Payments are off. Customer app and website can show agent numbers for free.",
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            title: Text(enabled ? "Payment required" : "Free contact"),
            subtitle: Text(
              _saving
                  ? "Saving..."
                  : "Turn this off when you want customers to see agent numbers without payment.",
            ),
            onChanged:
                snapshot.connectionState == ConnectionState.waiting || _saving
                ? null
                : _setEnabled,
          ),
        );
      },
    );
  }
}
