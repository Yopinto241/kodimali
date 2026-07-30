import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/ads/admob_support.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/manage_ui.dart';
import '../../shared/presentation/platform_promotions_panel.dart';
import '../../shared/presentation/business_growth_panels.dart';

class AgentDashboardTab extends StatefulWidget {
  const AgentDashboardTab({
    super.key,
    this.onOpenRequests,
    this.onOpenListings,
    this.onOpenNotifications,
  });

  final VoidCallback? onOpenRequests;
  final VoidCallback? onOpenListings;
  final VoidCallback? onOpenNotifications;

  @override
  State<AgentDashboardTab> createState() => _AgentDashboardTabState();
}

class _AgentDashboardTabState extends State<AgentDashboardTab> {
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
    ).repository.fetchAgentDashboardCounts(controller.currentUser!.id);
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
            title: "Hakuna dashboard bado",
            message:
                "Ukithibitishwa kama agent, data za listings na maombi zitaonekana hapa.",
          );
        }

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Agent dashboard",
              subtitle:
                  "Fuata hali ya akaunti, listings zako, na maombi mapya bila kupoteza muda.",
              trailing: profile == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Chip(
                          label: Text(profile.agentAccountStatus ?? "inactive"),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          profile.fullName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
              bottom: ManageMetaWrap(
                items: <String>[
                  "Verification: ${profile?.agentVerificationStatus ?? "pending"}",
                  "Language: ${profile?.preferredLanguage ?? "sw"}",
                  "Refresh any time to pull new requests",
                ],
              ),
            ),
            const SizedBox(height: 18),
            const AgentBusinessPanel(),
            const SizedBox(height: 18),
            ManageMetricGrid(
              children: <Widget>[
                ManageMetricCard(
                  label: "Live listings",
                  value: "${counts["activeListings"] ?? 0}",
                  icon: Icons.storefront_outlined,
                  caption: "Assets currently visible to customers.",
                  onTap: widget.onOpenListings,
                ),
                ManageMetricCard(
                  label: "Inactive listings",
                  value: "${counts["inactiveListings"] ?? 0}",
                  icon: Icons.pause_circle_outline,
                  caption: "Items waiting for activation or return.",
                  tint: Theme.of(context).colorScheme.secondary,
                  onTap: widget.onOpenListings,
                ),
                ManageMetricCard(
                  label: "All inquiries",
                  value: "${counts["totalInquiries"] ?? 0}",
                  icon: Icons.forum_outlined,
                  caption: "Total customer requests sent to you.",
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: "New requests",
                  value: "${counts["newRequests"] ?? 0}",
                  icon: Icons.notifications_active_outlined,
                  caption: "New items needing your response.",
                  tint: KodimaliColors.warning,
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: "Viewing appointments",
                  value: "${counts["scheduledViewings"] ?? 0}",
                  icon: Icons.event_available_outlined,
                  caption: "Customer viewings currently scheduled.",
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: "Completed rentals",
                  value: "${counts["completedRequests"] ?? 0}",
                  icon: Icons.task_alt_outlined,
                  caption: "Requests recorded as completed.",
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: "Unread notifications",
                  value: "${counts["unreadNotifications"] ?? 0}",
                  icon: Icons.mark_chat_unread_outlined,
                  caption: "Platform and customer updates still unread.",
                  onTap: widget.onOpenNotifications,
                ),
              ],
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: "Action queue",
              subtitle:
                  "Start with customer work that is most likely to become a completed rental.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.priority_high_rounded),
                    title: Text(
                      "${counts["newRequests"] ?? 0} new requests need a response",
                    ),
                    subtitle: const Text(
                      "Accept, reject, call, chat, or schedule a viewing.",
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenRequests,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home_work_outlined),
                    title: Text(
                      "${counts["inactiveListings"] ?? 0} inactive listings to review",
                    ),
                    subtitle: const Text(
                      "Confirm details and availability before reactivation.",
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenListings,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const ManageInlineBannerAdCard(),
            const SizedBox(height: 12),
            const ManageAdPrivacyButton(),
            const SizedBox(height: 18),
            const PlatformPromotionsPanel(
              surface: "manage_agent",
              placement: "global",
              title: "Platform promotions",
            ),
          ],
        );
      },
    );
  }
}
