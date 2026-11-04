import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
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
import '../../shared/presentation/business_growth_panels.dart';
import 'admin_workspace_access.dart';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({
    super.key,
    required this.access,
    this.onOpenAgents,
    this.onOpenListings,
    this.onOpenRequests,
    this.onOpenReports,
    this.onOpenNotifications,
  });

  final AdminWorkspaceAccess access;
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
          return Center(child: Text(userMessage(context, snapshot.error)));
        }
        final Map<String, int> counts = snapshot.data ?? <String, int>{};
        if (counts.isEmpty) {
          return KodimaliEmptyState(
            title: mobileUi(context, "Hakuna dashboard data"),
            message: mobileUi(context, "Admin metrics zitaonekana hapa."),
          );
        }

        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: mobileUi(context, "Admin control center"),
              subtitle: mobileUi(
                context,
                "Manage activation, moderation, promotions, categories, and the health of the full marketplace.",
              ),
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
            if (widget.access.analytics) const AdminBusinessAnalyticsPanel(),
            const SizedBox(height: 18),
            if (widget.access.roles) const _ContactPaymentSettingsPanel(),
            const SizedBox(height: 18),
            if (widget.access.payments) const _ContactPaymentOperationsPanel(),
            const SizedBox(height: 18),
            ManageMetricGrid(
              children: <Widget>[
                ManageMetricCard(
                  label: mobileUi(context, "Inactive or suspended agents"),
                  value: "${counts["inactiveAgents"] ?? 0}",
                  icon: Icons.person_off_outlined,
                  caption: "Accounts waiting for activation or admin review.",
                  onTap: widget.onOpenAgents,
                ),
                ManageMetricCard(
                  label: mobileUi(context, "Live listings"),
                  value: "${counts["liveListings"] ?? 0}",
                  icon: Icons.approval_outlined,
                  caption: "Assets currently active in the marketplace.",
                  tint: Theme.of(context).colorScheme.secondary,
                  onTap: widget.onOpenListings,
                ),
                ManageMetricCard(
                  label: mobileUi(context, "Inquiry volume"),
                  value: "${counts["totalInquiries"] ?? 0}",
                  icon: Icons.insights_outlined,
                  caption: "Combined booking and inquiry demand.",
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: mobileUi(context, "New requests"),
                  value: "${counts["newRequests"] ?? 0}",
                  icon: Icons.priority_high_rounded,
                  caption: "Requests still waiting for an agent response.",
                  tint: KodimaliColors.warning,
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: mobileUi(context, "Completed rentals"),
                  value: "${counts["completedRequests"] ?? 0}",
                  icon: Icons.task_alt_outlined,
                  caption: "Request workflows marked completed.",
                  onTap: widget.onOpenRequests,
                ),
                ManageMetricCard(
                  label: mobileUi(context, "Reports"),
                  value: "${counts["reports"] ?? 0}",
                  icon: Icons.flag_outlined,
                  caption: "Reported content or complaints needing review.",
                  tint: KodimaliColors.warning,
                  onTap: widget.onOpenReports,
                ),
                ManageMetricCard(
                  label: mobileUi(context, "Unread notifications"),
                  value: "${counts["unreadNotifications"] ?? 0}",
                  icon: Icons.notifications_none_outlined,
                  caption: "System updates still waiting for attention.",
                  onTap: widget.onOpenNotifications,
                ),
              ],
            ),
            const SizedBox(height: 18),
            ManagePanel(
              title: mobileUi(context, "Needs attention"),
              subtitle: mobileUi(
                context,
                "Open the exact queue instead of searching across the workspace.",
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_search_outlined),
                    title: Text(
                      mobileUiFormat(
                        context,
                        "{0} agent accounts need review",
                        [counts["inactiveAgents"] ?? 0],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenAgents,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.pending_actions_outlined),
                    title: Text(
                      mobileUiFormat(
                        context,
                        "{0} requests await agent action",
                        [counts["newRequests"] ?? 0],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenRequests,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(
                      mobileUiFormat(context, "{0} reports need moderation", [
                        counts["reports"] ?? 0,
                      ]),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenReports,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            PlatformPromotionsPanel(
              surface: "manage_admin",
              placement: "global",
              title: mobileUi(context, "Global promotions"),
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

  Future<Map<String, dynamic>> _load() async {
    final repository = AppScope.of(context).repository;
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      repository.fetchMarketplaceSettings(),
      repository.fetchKodimaliRolloutFlags(),
    ]);
    return <String, dynamic>{
      ...(results[0] as Map<String, dynamic>),
      "kodimali_rollout_flags": results[1],
    };
  }

  Future<void> _setRolloutFlag(String key, bool enabled) async {
    final controller = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.admin_panel_settings_outlined),
        title: Text(
          enabled
              ? mobileUiFormat(context, "Activate {0}?", [key])
              : mobileUiFormat(context, "Pause {0}?", [key]),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              enabled
                  ? mobileUi(
                      context,
                      'Activation requires completed payment-provider, policy and operational approval. It does not change historical records.',
                    )
                  : mobileUi(
                      context,
                      'New operations will stop. Existing paid bookings and obligations remain valid.',
                    ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: enabled
                    ? mobileUi(context, 'Approval note (required)')
                    : mobileUi(context, 'Reason'),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              enabled
                  ? mobileUi(context, 'Activate')
                  : mobileUi(context, 'Pause'),
            ),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(context).repository.updateKodimaliRolloutFlag(
        key: key,
        enabled: enabled,
        approvalNote: note,
      );
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedUiText(userFacingError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<bool> _confirmToggle({
    required String feature,
    required bool enablePayment,
    required String paidWarning,
    required String freeWarning,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(
          enablePayment
              ? mobileUiFormat(context, "Enable payment for {0}?", [feature])
              : mobileUiFormat(context, "Make {0} free?", [feature]),
        ),
        content: Text(enablePayment ? paidWarning : freeWarning),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              enablePayment
                  ? mobileUi(context, 'Enable payment')
                  : mobileUi(context, 'Make free'),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _confirmPaymentAvailability({
    required String feature,
    required bool enabled,
    required String enabledWarning,
    required String pausedWarning,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(
          enabled
              ? mobileUiFormat(context, "Enable {0} payments?", [feature])
              : mobileUiFormat(context, "Pause {0} payments?", [feature]),
        ),
        content: Text(enabled ? enabledWarning : pausedWarning),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              enabled
                  ? mobileUi(context, 'Enable payments')
                  : mobileUi(context, 'Pause payments'),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _setEnabled(bool enabled) async {
    final bool confirmed = await _confirmToggle(
      feature: 'agent contact numbers',
      enablePayment: enabled,
      paidWarning:
          'Customers will have to complete the configured contact payment before seeing an agent number. This can reduce contact conversions.',
      freeWarning:
          'Agent phone numbers will be available without payment. KODIMALI will receive no contact-unlock revenue.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(
        context,
      ).repository.updateContactPaymentsEnabled(enabled);
      if (!mounted) {
        return;
      }
      setState(() {
        _future = _load();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setAgentListingEnabled(bool enabled) async {
    final bool confirmed = await _confirmToggle(
      feature: 'listing publication',
      enablePayment: enabled,
      paidWarning:
          'Verified agents will pay their plan publication fee before direct publication. Unverified agents must both pay and receive admin approval.',
      freeWarning:
          'Verified agents will publish directly without payment. Unverified agents will still require admin approval.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(
        context,
      ).repository.updateAgentListingPaymentsEnabled(enabled);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setChatEnabled(bool enabled) async {
    final settings = await _future;
    final int chatPrice =
        (settings["paid_chat_unlock_amount_tzs"] as num?)?.toInt() ?? 500;
    final bool confirmed = await _confirmToggle(
      feature: 'private listing chat',
      enablePayment: enabled,
      paidWarning:
          'Customers will be charged TSh $chatPrice to open seven-day chat access.',
      freeWarning:
          'Customers will open private listing chats without payment. KODIMALI will receive no chat-access revenue.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(context).repository.updateChatPaymentsEnabled(enabled);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _editChatPrice(int currentPrice) async {
    final controller = TextEditingController(text: currentPrice.toString());
    final int? amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedUiText('Paid chat price'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: mobileUi(context, 'Amount (TZS)'),
            helperText: mobileUi(
              context,
              'Confirm the provider minimum before enabling payments.',
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.trim()),
            ),
            child: const LocalizedUiText('Save price'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0 || !mounted) return;
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(context).repository.updatePaidChatUnlockPrice(amount);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedUiText(userFacingError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setSubscriptionEnabled(bool enabled) async {
    final bool confirmed = await _confirmPaymentAvailability(
      feature: 'agent subscriptions',
      enabled: enabled,
      enabledWarning:
          'Agents can purchase Basic, Pro and Business packages through SonicPesa. A package activates only after confirmed payment.',
      pausedWarning:
          'Agents cannot purchase paid packages while payments are paused. Existing subscriptions remain active; no paid package is granted for free.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(
        context,
      ).repository.updateSubscriptionPaymentsEnabled(enabled);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setBookingEnabled(bool enabled) async {
    final bool confirmed = await _confirmPaymentAvailability(
      feature: 'customer booking',
      enabled: enabled,
      enabledWarning:
          'Customers can pay through SonicPesa to confirm eligible bookings after approval and availability checks.',
      pausedWarning:
          'New booking checkout will be unavailable. Existing paid reservations remain valid and unpaid requests are not confirmed for free.',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(
        context,
      ).repository.updateBookingPaymentsEnabled(enabled);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setEventPaymentsEnabled(bool enabled) async {
    final bool confirmed = await _confirmPaymentAvailability(
      feature: 'Events',
      enabled: enabled,
      enabledWarning:
          'Customers can pay event deposits and balances through SonicPesa after accepting a quotation and agreement.',
      pausedWarning:
          'New event deposit and balance checkout will be unavailable. Existing paid obligations remain recorded and inventory is not reserved for free.',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(context).repository.updateEventPaymentsEnabled(enabled);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setBoostEnabled(bool enabled) async {
    final bool confirmed = await _confirmToggle(
      feature: 'featured listing campaigns',
      enablePayment: enabled,
      paidWarning:
          'Agents must complete ClickPesa payment before a featured, homepage or search campaign activates.',
      freeWarning:
          'Agents may activate featured campaigns without payment. KODIMALI will receive no campaign revenue.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(
        context,
      ).repository.updateListingBoostPaymentsEnabled(enabled);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        final bool enabled =
            snapshot.data?["contact_payments_enabled"] as bool? ?? false;
        final bool agentListingEnabled =
            snapshot.data?["agent_listing_payments_enabled"] as bool? ?? false;
        final bool chatEnabled =
            snapshot.data?["chat_payments_enabled"] as bool? ?? false;
        final int chatPrice =
            (snapshot.data?["paid_chat_unlock_amount_tzs"] as num?)?.toInt() ??
            500;
        final bool subscriptionEnabled =
            snapshot.data?["subscription_payments_enabled"] as bool? ?? false;
        final bool boostEnabled =
            snapshot.data?["listing_boost_payments_enabled"] as bool? ?? false;
        final bool bookingEnabled =
            snapshot.data?["booking_payments_enabled"] as bool? ?? false;
        final bool eventPaymentsEnabled =
            snapshot.data?["event_payments_enabled"] as bool? ?? false;
        final List<Map<String, dynamic>> rolloutFlags =
            (snapshot.data?["kodimali_rollout_flags"] as List<dynamic>? ??
                    <dynamic>[])
                .whereType<Map>()
                .map((row) => row.cast<String, dynamic>())
                .where(
                  (row) => <String>{
                    "booking_deposit_payments",
                    "booking_balance_payments",
                    "event_deposit_payments",
                    "event_balance_payments",
                    "automated_refunds",
                    "automated_provider_payouts",
                  }.contains(row["key"]),
                )
                .toList(growable: false);
        final String? updatedAt = snapshot.data?["updated_at"] as String?;
        final String? updatedBy = snapshot.data?["updated_by"] as String?;
        return ManagePanel(
          title: mobileUi(context, "Marketplace payment controls"),
          subtitle: mobileUi(
            context,
            "Admin-only controls shared by the website and mobile apps. Pausing checkout never grants a paid product for free.",
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: Text(
                  enabled
                      ? mobileUi(context, "Payment required")
                      : mobileUi(context, "Free contact"),
                ),
                subtitle: Text(
                  _saving
                      ? mobileUi(context, "Saving...")
                      : mobileUi(
                          context,
                          "Turn this off when you want customers to see agent numbers without payment.",
                        ),
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setEnabled,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: agentListingEnabled,
                title: Text(
                  agentListingEnabled
                      ? mobileUi(context, "Agent listing payment required")
                      : mobileUi(context, "Agent listings are free"),
                ),
                subtitle: Text(
                  agentListingEnabled
                      ? mobileUi(
                          context,
                          "Verified agents publish after paying their plan fee. Unverified agents also require admin approval.",
                        )
                      : mobileUi(
                          context,
                          "Verified agents publish free. Unverified agents remain private until admin approval.",
                        ),
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setAgentListingEnabled,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: chatEnabled,
                title: Text(
                  chatEnabled
                      ? mobileUi(context, "Customer chat payment required")
                      : mobileUi(context, "Customer chat is free"),
                ),
                subtitle: Text(
                  mobileUiFormat(
                    context,
                    "Paid mode charges TSh {0} for 7 days of private listing chat. Each participant can send 10 messages per day.",
                    [chatPrice],
                  ),
                ),
                secondary: IconButton(
                  tooltip: mobileUi(context, 'Change chat price'),
                  onPressed: _saving ? null : () => _editChatPrice(chatPrice),
                  icon: const Icon(Icons.edit_outlined),
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setChatEnabled,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: subscriptionEnabled,
                title: Text(
                  subscriptionEnabled
                      ? mobileUi(context, 'Subscription payments enabled')
                      : mobileUi(context, 'Subscription purchasing paused'),
                ),
                subtitle: const LocalizedUiText(
                  'Controls SonicPesa purchasing for Basic, Pro and Business packages. Existing subscriptions are not changed.',
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setSubscriptionEnabled,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: bookingEnabled,
                title: Text(
                  bookingEnabled
                      ? mobileUi(context, 'Customer pay and book enabled')
                      : mobileUi(context, 'Customer booking checkout paused'),
                ),
                subtitle: const LocalizedUiText(
                  'Controls SonicPesa checkout for ordinary booking reservations. Pausing does not confirm requests for free.',
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setBookingEnabled,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: eventPaymentsEnabled,
                title: Text(
                  eventPaymentsEnabled
                      ? mobileUi(context, 'Events payments enabled')
                      : mobileUi(context, 'Events checkout paused'),
                ),
                subtitle: const LocalizedUiText(
                  'Controls SonicPesa deposits and balances after an event quotation and agreement are accepted.',
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setEventPaymentsEnabled,
              ),
              const Divider(height: 24),
              LocalizedUiText(
                'KODIMALI 3.0 controlled rollout',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const LocalizedUiText(
                'These audited Super Admin flags are separate from marketplace availability. Both controls must be approved before new financial automation can run.',
              ),
              const SizedBox(height: 8),
              if (rolloutFlags.isEmpty)
                const LocalizedUiText(
                  'KODIMALI 3.0 rollout flags are not installed yet.',
                )
              else
                ...rolloutFlags.map((row) {
                  final key = row["key"].toString();
                  final enabled = row["enabled"] == true;
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: enabled,
                    title: Text(key.replaceAll("_", " ")),
                    subtitle: Text(
                      enabled
                          ? mobileUiFormat(context, "Active · approved {0}", [
                              DateFormatters.formatDateTime(
                                row["approved_at"] as String?,
                              ),
                            ])
                          : mobileUi(context, 'Inactive'),
                    ),
                    onChanged: _saving
                        ? null
                        : (value) => _setRolloutFlag(key, value),
                  );
                }),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: boostEnabled,
                title: Text(
                  boostEnabled
                      ? mobileUi(context, 'Featured campaign payment required')
                      : mobileUi(context, 'Featured campaigns are free'),
                ),
                subtitle: const LocalizedUiText(
                  'Controls payment for featured, homepage and top-of-search campaigns.',
                ),
                onChanged:
                    snapshot.connectionState == ConnectionState.waiting ||
                        _saving
                    ? null
                    : _setBoostEnabled,
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
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: mobileUi(context, "Contact payment operations"),
      subtitle: mobileUi(
        context,
        "Monitor provider status, reconciliation, webhook delivery, and whether contact access was revealed.",
      ),
      action: IconButton(
        tooltip: mobileUi(context, "Refresh payments"),
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButton<String?>(
            value: _status,
            hint: const LocalizedUiText("All payment statuses"),
            items: const <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                value: null,
                child: LocalizedUiText("All"),
              ),
              DropdownMenuItem<String?>(
                value: "pending",
                child: LocalizedUiText("Pending"),
              ),
              DropdownMenuItem<String?>(
                value: "processing",
                child: LocalizedUiText("Processing"),
              ),
              DropdownMenuItem<String?>(
                value: "paid",
                child: LocalizedUiText("Paid"),
              ),
              DropdownMenuItem<String?>(
                value: "failed",
                child: LocalizedUiText("Failed"),
              ),
              DropdownMenuItem<String?>(
                value: "expired",
                child: LocalizedUiText("Expired"),
              ),
              DropdownMenuItem<String?>(
                value: "cancelled",
                child: LocalizedUiText("Cancelled"),
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
                    return LocalizedUiText(userFacingError(snapshot.error!));
                  }
                  final List<Map<String, dynamic>> rows =
                      snapshot.data ?? <Map<String, dynamic>>[];
                  if (rows.isEmpty) {
                    return const LocalizedUiText(
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
                          Chip(
                            label: Text(
                              mobileUiFormat(context, "{0} loaded", [
                                rows.length,
                              ]),
                            ),
                          ),
                          Chip(
                            label: Text(
                              mobileUiFormat(context, "{0} paid", [paid]),
                            ),
                          ),
                          Chip(
                            label: Text(
                              mobileUiFormat(context, "{0} failed", [failed]),
                            ),
                          ),
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
