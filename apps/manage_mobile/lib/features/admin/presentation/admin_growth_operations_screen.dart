import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/manage_ui.dart';

class AdminGrowthOperationsScreen extends StatefulWidget {
  const AdminGrowthOperationsScreen({super.key});
  @override
  State<AdminGrowthOperationsScreen> createState() =>
      _AdminGrowthOperationsScreenState();
}

class _AdminGrowthOperationsScreenState
    extends State<AdminGrowthOperationsScreen> {
  late Future<List<dynamic>> future;
  final bookingFilter = TextEditingController();
  final providerFilter = TextEditingController();
  DateTimeRange? reportDates;
  String? reportProduct;
  String? reportStatus;
  String? reportCategory;
  String? reportPaymentProvider;
  final Set<String> selectedPayableIds = <String>{};

  @override
  void dispose() {
    bookingFilter.dispose();
    providerFilter.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future = load();
  }

  Future<List<dynamic>> load() {
    final r = AppScope.of(context).repository;
    return Future.wait<dynamic>([
      r.fetchAdminGrowthOperations(),
      r.fetchRiskFlags(),
      r.fetchRefunds(),
      r.fetchPendingBoosts(),
      r.fetchCommercialPayments(),
      r.fetchAdminRoleDefinitions(),
      r.fetchAdminRoleDirectory(),
      r.fetchAdminAgentWallets(),
      r.fetchAdminFinancialOverview(),
      r.fetchAdminExternalDeals(),
      r.fetchAdminFinancialActivity(
        from: reportDates?.start,
        until: reportDates?.end.add(const Duration(days: 1)),
        product: reportProduct,
        status: reportStatus,
        bookingId: bookingFilter.text,
        providerProfileId: providerFilter.text,
        category: reportCategory,
        paymentProvider: reportPaymentProvider,
      ),
      r.fetchKodimaliRolloutFlags(),
      r.fetchRefundObligations(),
      r.fetchProviderPayables(),
      r.fetchSettlementBatches(),
      r.fetchFinancialReconciliationCases(),
    ]);
  }

  Future<void> refresh() async {
    setState(() => future = load());
    await future;
  }

  Future<void> risk(String id, String status) async {
    await AppScope.of(context).repository.updateRiskFlag(id, status);
    await refresh();
  }

  Future<void> refund(String id, String status) async {
    await AppScope.of(context).repository.updateRefund(id, status);
    await refresh();
  }

  Future<void> boost(String id, String status) async {
    await AppScope.of(context).repository.updateBoost(id, status);
    await refresh();
  }

  Future<void> externalDeal(String id, String status) async {
    try {
      await AppScope.of(
        context,
      ).repository.reviewExternalDeal(dealId: id, status: status);
      await refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> chooseReportDates() async {
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: reportDates,
    );
    if (value == null || !mounted) return;
    setState(() {
      reportDates = value;
      future = load();
    });
  }

  void clearFinancialFilters() {
    bookingFilter.clear();
    providerFilter.clear();
    setState(() {
      reportDates = null;
      reportProduct = null;
      reportStatus = null;
      reportCategory = null;
      reportPaymentProvider = null;
      future = load();
    });
  }

  String csvCell(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';

  Future<void> exportFinancialActivity(List<Map<String, dynamic>> rows) async {
    const columns = <String>[
      'payment_intent_id',
      'created_at',
      'verified_at',
      'product',
      'status',
      'amount_minor',
      'currency',
      'booking_id',
      'provider_profile_id',
      'category',
      'payment_provider',
      'provider_order_id',
      'provider_transaction_id',
    ];
    final csv = <String>[
      columns.map(csvCell).join(','),
      ...rows.map((row) => columns.map((key) => csvCell(row[key])).join(',')),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${rows.length} rows copied as CSV.')),
      );
    }
  }

  Future<String?> financialOperationNote(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason / approval note',
            hintText: 'At least 10 characters',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().length < 10) return null;
    return result.trim();
  }

  Future<void> runFinancialOperation(Future<void> Function() operation) async {
    try {
      await operation();
      await refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> prepareRefund(String refundId) async {
    final note = await financialOperationNote('Prepare refund execution');
    if (note == null || !mounted) return;
    await runFinancialOperation(
      () => AppScope.of(
        context,
      ).repository.prepareRefundExecution(refundId: refundId, note: note),
    );
  }

  Future<void> createSettlementBatch() async {
    if (selectedPayableIds.isEmpty) return;
    final note = await financialOperationNote('Create settlement batch');
    if (note == null || !mounted) return;
    final ids = selectedPayableIds.toList(growable: false);
    await runFinancialOperation(
      () => AppScope.of(
        context,
      ).repository.createProviderSettlementBatch(payableIds: ids, note: note),
    );
    if (mounted) setState(selectedPayableIds.clear);
  }

  Future<void> approveSettlementBatch(String batchId) async {
    final note = await financialOperationNote('Approve settlement batch');
    if (note == null || !mounted) return;
    await runFinancialOperation(
      () => AppScope.of(
        context,
      ).repository.approveProviderSettlementBatch(batchId: batchId, note: note),
    );
  }

  Future<void> releaseFailedPayable(String payableId) async {
    final note = await financialOperationNote('Release failed settlement');
    if (note == null || !mounted) return;
    await runFinancialOperation(
      () => AppScope.of(context).repository.releaseFailedSettlementPayable(
        payableId: payableId,
        note: note,
      ),
    );
  }

  Future<void> reviewReconciliation(String caseId, String status) async {
    final note = await financialOperationNote(
      status == 'investigating'
          ? 'Start reconciliation investigation'
          : status == 'resolved'
          ? 'Resolve reconciliation case'
          : 'Write off reconciliation case',
    );
    if (note == null || !mounted) return;
    await runFinancialOperation(
      () => AppScope.of(context).repository.reviewFinancialReconciliation(
        caseId: caseId,
        status: status,
        resolution: note,
      ),
    );
  }

  Future<void> _editRoles(
    Map<String, dynamic> user,
    List<Map<String, dynamic>> definitions,
  ) async {
    final Set<String> selected = ((user['roles'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((r) => r['id'].toString())
        .toSet();
    final Set<String>? result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Roles · ${user['full_name'] ?? user['account_email']}'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: definitions
                  .map(
                    (role) => CheckboxListTile(
                      value: selected.contains(role['id']),
                      title: Text(role['name'].toString()),
                      subtitle: Text(role['description'].toString()),
                      onChanged: (value) => setDialog(() {
                        if (value == true) {
                          selected.add(role['id'].toString());
                        } else {
                          selected.remove(role['id'].toString());
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Save roles'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final repo = AppScope.of(context).repository;
    final Set<String> original = ((user['roles'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((r) => r['id'].toString())
        .toSet();
    for (final role in definitions) {
      final id = role['id'].toString();
      if (result.contains(id) != original.contains(id)) {
        await repo.assignAdminRole(
          user['user_id'].toString(),
          id,
          result.contains(id),
        );
      }
    }
    await refresh();
  }

  Future<void> _adjustWallet(Map<String, dynamic> wallet) async {
    final amount = TextEditingController();
    final description = TextEditingController(text: 'Promotional credit');
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Wallet · ${wallet['business_name'] ?? wallet['display_name'] ?? 'Agent'}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: 'Amount (positive credit, negative debit)',
              ),
            ),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apply adjustment'),
          ),
        ],
      ),
    );
    final num? value = num.tryParse(amount.text);
    if (save != true || value == null || !mounted) return;
    await AppScope.of(context).repository.adjustAgentWallet(
      agentId: wallet['agent_id'].toString(),
      balanceKind: 'promotional',
      amountTzs: value,
      description: description.text.trim(),
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: future,
    builder: (context, s) {
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      if (s.hasError) return Center(child: Text('${s.error}'));
      final d = s.data!,
          summary = (d[0] as Map).cast<String, dynamic>(),
          risks = (d[1] as List).cast<Map<String, dynamic>>(),
          refunds = (d[2] as List).cast<Map<String, dynamic>>(),
          boosts = (d[3] as List).cast<Map<String, dynamic>>(),
          payments = (d[4] as List).cast<Map<String, dynamic>>();
      final definitions = (d[5] as List).cast<Map<String, dynamic>>();
      final admins = (d[6] as List).cast<Map<String, dynamic>>();
      final wallets = (d[7] as List).cast<Map<String, dynamic>>();
      final finance = (d[8] as Map).cast<String, dynamic>();
      final externalDeals = (d[9] as List).cast<Map<String, dynamic>>();
      final financialActivity = (d[10] as List).cast<Map<String, dynamic>>();
      final rolloutFlags = (d[11] as List).cast<Map<String, dynamic>>();
      final refundObligations = (d[12] as List).cast<Map<String, dynamic>>();
      final providerPayables = (d[13] as List).cast<Map<String, dynamic>>();
      final settlementBatches = (d[14] as List).cast<Map<String, dynamic>>();
      final reconciliationCases = (d[15] as List).cast<Map<String, dynamic>>();
      return ManagePageScrollView(
        onRefresh: refresh,
        children: [
          ManageHeroCard(
            title: 'Growth operations',
            subtitle:
                'Control subscriptions, campaigns, refunds, fraud signals and payment reliability.',
            bottom: Wrap(
              spacing: 12,
              children: [
                Text(
                  '${summary['subscriptions'] ?? 0} subscriptions',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  '${summary['active_boosts'] ?? 0} active campaigns',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  '${summary['open_risks'] ?? 0} risks',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _financialPanel(finance),
          const SizedBox(height: 16),
          _financialActivityPanel(financialActivity),
          const SizedBox(height: 16),
          _refundSettlementPanel(
            rolloutFlags: rolloutFlags,
            refunds: refundObligations,
            payables: providerPayables,
            batches: settlementBatches,
            reconciliationCases: reconciliationCases,
          ),
          const SizedBox(height: 16),
          _panel(
            'External deal declarations',
            'These values were reported outside KODIMALI and are not platform collections.',
            externalDeals.map(
              (deal) => ListTile(
                leading: const Icon(Icons.handshake_outlined),
                title: Text(
                  '${DateFormatters.formatCurrency(deal['claimed_value_minor'] as num?)} · ${deal['status']}',
                ),
                subtitle: Text(
                  '${deal['listing_id'] != null ? 'Listing ${deal['listing_id']}' : 'Referral ${deal['referral_submission_id']}'} · ${deal['transaction_date']}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) =>
                      externalDeal(deal['id'].toString(), value),
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'verified', child: Text('Verify')),
                    PopupMenuItem(
                      value: 'commission_assessed',
                      child: Text('Commission assessed'),
                    ),
                    PopupMenuItem(value: 'disputed', child: Text('Dispute')),
                    PopupMenuItem(value: 'rejected', child: Text('Reject')),
                    PopupMenuItem(value: 'settled', child: Text('Settled')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            'Promotion approvals',
            'Review paid and pending featured-listing campaigns.',
            boosts.map(
              (b) => ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(
                  ((b['listings'] as Map?)?['title'] ?? 'Listing').toString(),
                ),
                subtitle: Text(
                  '${b['placement']} · ${b['duration_days']} days · ${b['amount_tzs']} TZS',
                ),
                trailing: b['status'] == 'pending'
                    ? Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Approve',
                            onPressed: () =>
                                boost(b['id'].toString(), 'active'),
                            icon: const Icon(Icons.check_circle_outline),
                          ),
                          IconButton(
                            tooltip: 'Reject',
                            onPressed: () =>
                                boost(b['id'].toString(), 'cancelled'),
                            icon: const Icon(Icons.cancel_outlined),
                          ),
                        ],
                      )
                    : Chip(label: Text(b['status'].toString())),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            'Fraud and duplicate review',
            'Resolve or dismiss automatically detected risks.',
            risks.map(
              (r) => ListTile(
                leading: Icon(
                  Icons.shield_outlined,
                  color: r['severity'] == 'critical' ? Colors.red : null,
                ),
                title: Text(r['risk_type'].toString().replaceAll('_', ' ')),
                subtitle: Text(r['reason'].toString()),
                trailing: r['status'] == 'open'
                    ? PopupMenuButton<String>(
                        onSelected: (v) => risk(r['id'].toString(), v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'reviewing',
                            child: Text('Reviewing'),
                          ),
                          PopupMenuItem(
                            value: 'resolved',
                            child: Text('Resolve'),
                          ),
                          PopupMenuItem(
                            value: 'dismissed',
                            child: Text('Dismiss'),
                          ),
                        ],
                      )
                    : Chip(label: Text(r['status'].toString())),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            'Refund queue',
            'Approve or reject customer and agent refund requests.',
            refunds.map(
              (r) => ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text('${r['amount_tzs']} TZS · ${r['payment_kind']}'),
                subtitle: Text(r['reason'].toString()),
                trailing: r['status'] == 'requested'
                    ? Wrap(
                        children: [
                          IconButton(
                            onPressed: () =>
                                refund(r['id'].toString(), 'approved'),
                            icon: const Icon(Icons.check),
                          ),
                          IconButton(
                            onPressed: () =>
                                refund(r['id'].toString(), 'rejected'),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      )
                    : Chip(label: Text(r['status'].toString())),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            'Administrative roles',
            'Only Super Admins can assign roles. The final Super Admin cannot remove their own access.',
            admins.map(
              (admin) => ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text(admin['full_name']?.toString() ?? 'Administrator'),
                subtitle: Text(
                  ((admin['roles'] as List?) ?? const <dynamic>[])
                      .whereType<Map>()
                      .map((r) => r['name'])
                      .join(' · '),
                ),
                trailing: const Icon(Icons.manage_accounts_outlined),
                onTap: () => _editRoles(admin, definitions),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            'Agent promotional wallets',
            'Finance Admins can grant or remove platform credits with a permanent ledger entry.',
            wallets.map(
              (wallet) => ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(
                  wallet['business_name']?.toString() ??
                      wallet['display_name']?.toString() ??
                      'Agent',
                ),
                subtitle: Text(
                  'Available: ${wallet['available_balance_tzs']} TZS · Promotional: ${wallet['promotional_credits_tzs']} TZS',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _adjustWallet(wallet),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            'Payment monitoring',
            'Latest subscription and promotion transactions.',
            payments
                .take(50)
                .map(
                  (p) => ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(
                      '${p['requested_amount']} TZS · ${p['product_type']}',
                    ),
                    subtitle: Text(
                      '${p['order_reference']} · ${p['created_at'].toString().split('T').first}',
                    ),
                    trailing: Chip(label: Text(p['payment_status'].toString())),
                  ),
                ),
          ),
          const SizedBox(height: 90),
        ],
      );
    },
  );
  Widget _panel(String title, String subtitle, Iterable<Widget> children) =>
      ManagePanel(
        title: title,
        subtitle: subtitle,
        child: children.isEmpty
            ? const Text('Nothing needs attention.')
            : Column(children: children.toList()),
      );

  Widget _financialPanel(Map<String, dynamic> finance) {
    if (finance.isEmpty) {
      return const ManagePanel(
        title: 'Financial control center',
        subtitle:
            'Requires the KODIMALI 3.0 financial migration and permission.',
        child: Text('Financial totals are not available on this server yet.'),
      );
    }
    String money(String key) => DateFormatters.formatCurrency(
      finance[key] is num ? finance[key] as num : 0,
    );
    return ManagePanel(
      title: 'Financial control center',
      subtitle:
          'Collections, liabilities, KODIMALI revenue and external deals are shown separately.',
      child: Column(
        children: <Widget>[
          ManageMetaWrap(
            items: <String>[
              'Booking collections ${money('verified_booking_collections_minor')}',
              'Outstanding balances ${money('outstanding_booking_balances_minor')}',
              'Events collections ${money('verified_event_collections_minor')}',
              'Events outstanding ${money('outstanding_event_balances_minor')}',
              'Provider payables ${money('provider_payables_minor')}',
              'Refund liabilities ${money('refund_liabilities_minor')}',
              'Refunded ${money('refunded_minor')}',
            ],
          ),
          const Divider(height: 28),
          ManageMetaWrap(
            items: <String>[
              'Booking fees ${money('booking_service_fee_revenue_minor')}',
              'Chat revenue ${money('paid_chat_revenue_minor')}',
              'Contact revenue ${money('contact_unlock_revenue_minor')}',
              'Agent commissions ${money('commission_obligations_minor')}',
              'Referral rewards ${money('referral_reward_obligations_minor')}',
              'External verified value ${money('verified_external_deal_value_minor')}',
              '${finance['open_reconciliation_cases'] ?? 0} reconciliation cases',
              '${finance['pending_settlements'] ?? 0} pending settlement batches',
            ],
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Read-only summary. Posted ledger balances cannot be edited here.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _financialActivityPanel(List<Map<String, dynamic>> rows) {
    Widget filterDropdown({
      required String label,
      required String? value,
      required List<String> values,
      required ValueChanged<String?> onChanged,
    }) => SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(value: null, child: Text('All')),
          ...values.map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item.replaceAll('_', ' ')),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );

    void updateFilter(VoidCallback change) {
      setState(() {
        change();
        future = load();
      });
    }

    return ManagePanel(
      title: 'Financial activity',
      subtitle:
          'Read-only payment-intent report. Filters and exports are permission checked and audited.',
      action: OutlinedButton.icon(
        onPressed: rows.isEmpty ? null : () => exportFinancialActivity(rows),
        icon: const Icon(Icons.content_copy_outlined),
        label: const Text('Copy CSV'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              filterDropdown(
                label: 'Product',
                value: reportProduct,
                values: const <String>[
                  'booking_deposit',
                  'booking_balance',
                  'event_deposit',
                  'event_balance',
                  'contact_unlock',
                  'paid_chat_unlock',
                  'booking_service_fee',
                  'customer_refund',
                ],
                onChanged: (value) => updateFilter(() => reportProduct = value),
              ),
              filterDropdown(
                label: 'Status',
                value: reportStatus,
                values: const <String>[
                  'created',
                  'awaiting_payment',
                  'processing',
                  'verified_paid',
                  'failed',
                  'expired',
                  'refund_pending',
                  'refunded',
                  'partially_refunded',
                  'reconciliation_required',
                ],
                onChanged: (value) => updateFilter(() => reportStatus = value),
              ),
              filterDropdown(
                label: 'Category',
                value: reportCategory,
                values: const <String>[
                  'house',
                  'apartment',
                  'car',
                  'motorcycle',
                  'office',
                  'meeting-hall',
                  'ceremony-hall',
                ],
                onChanged: (value) =>
                    updateFilter(() => reportCategory = value),
              ),
              filterDropdown(
                label: 'Payment provider',
                value: reportPaymentProvider,
                values: const <String>['sonicpesa', 'clickpesa'],
                onChanged: (value) =>
                    updateFilter(() => reportPaymentProvider = value),
              ),
              OutlinedButton.icon(
                onPressed: chooseReportDates,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  reportDates == null
                      ? 'Date range'
                      : '${reportDates!.start.toIso8601String().split('T').first} – ${reportDates!.end.toIso8601String().split('T').first}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 300,
                child: TextField(
                  controller: bookingFilter,
                  decoration: const InputDecoration(
                    labelText: 'Booking ID',
                    hintText: 'Optional UUID',
                  ),
                ),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: providerFilter,
                  decoration: const InputDecoration(
                    labelText: 'Provider profile ID',
                    hintText: 'Optional UUID',
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => setState(() => future = load()),
                child: const Text('Apply'),
              ),
              TextButton(
                onPressed: clearFinancialFilters,
                child: const Text('Clear'),
              ),
            ],
          ),
          const Divider(height: 28),
          if (rows.isEmpty)
            const Text('No payment activity matches these filters.')
          else ...<Widget>[
            Text('${rows.length} row(s) · newest first'),
            const SizedBox(height: 8),
            ...rows
                .take(50)
                .map(
                  (row) => ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      '${DateFormatters.formatCurrency(row['amount_minor'] as num?)} · ${row['product']}',
                    ),
                    subtitle: Text(
                      '${row['status']} · ${row['category'] ?? row['resource_type']} · ${row['created_at'].toString().replaceFirst('T', ' ').split('.').first}',
                    ),
                    trailing: Text(row['payment_provider']?.toString() ?? '—'),
                  ),
                ),
            if (rows.length > 50)
              Text('${rows.length - 50} additional rows are included in CSV.'),
          ],
        ],
      ),
    );
  }

  Widget _refundSettlementPanel({
    required List<Map<String, dynamic>> rolloutFlags,
    required List<Map<String, dynamic>> refunds,
    required List<Map<String, dynamic>> payables,
    required List<Map<String, dynamic>> batches,
    required List<Map<String, dynamic>> reconciliationCases,
  }) {
    bool flagEnabled(String key) => rolloutFlags.any(
      (flag) => flag['key'] == key && flag['enabled'] == true,
    );
    final refundsEnabled = flagEnabled('automated_refunds');
    final payoutsEnabled = flagEnabled('automated_provider_payouts');
    final eligiblePayables = payables
        .where((payable) => payable['status'] == 'eligible')
        .toList(growable: false);
    final heldPayables = payables
        .where(
          (payable) =>
              payable['status'] == 'on_hold' &&
              ((payable['settlement_batch_items'] as List?) ??
                      const <dynamic>[])
                  .whereType<Map>()
                  .any((item) => item['status'] == 'failed'),
        )
        .toList(growable: false);

    return ManagePanel(
      title: 'Refunds and provider settlements',
      subtitle:
          'Approvals are separated from payment-provider execution. Provider results can only be recorded by the server.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ManageMetaWrap(
            items: <String>[
              'Automated refunds: ${refundsEnabled ? 'enabled' : 'disabled'}',
              'Automated payouts: ${payoutsEnabled ? 'enabled' : 'disabled'}',
              '${refunds.where((item) => item['status'] == 'approved').length} approved refunds',
              '${eligiblePayables.length} eligible payables',
            ],
          ),
          if (!refundsEnabled || !payoutsEnabled) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              'Disabled automation cannot move money. A Super Admin must separately approve a rollout flag before execution can begin.',
            ),
          ],
          const Divider(height: 28),
          const Text(
            'Refund obligations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (refunds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No refund obligations.'),
            )
          else
            ...refunds
                .take(30)
                .map(
                  (refund) => ListTile(
                    leading: const Icon(Icons.currency_exchange_outlined),
                    title: Text(
                      '${DateFormatters.formatCurrency(refund['amount_minor'] as num?)} · ${refund['status']}',
                    ),
                    subtitle: Text(
                      '${refund['reason']} · Booking ${refund['booking_request_id']}',
                    ),
                    trailing: refund['status'] == 'approved'
                        ? FilledButton.tonal(
                            onPressed: refundsEnabled
                                ? () => prepareRefund(refund['id'].toString())
                                : null,
                            child: const Text('Prepare'),
                          )
                        : null,
                  ),
                ),
          const Divider(height: 28),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Eligible provider payables',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: selectedPayableIds.isEmpty
                    ? null
                    : createSettlementBatch,
                icon: const Icon(Icons.playlist_add_check_outlined),
                label: Text('Create batch (${selectedPayableIds.length})'),
              ),
            ],
          ),
          if (eligiblePayables.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No provider payables are eligible.'),
            )
          else
            ...eligiblePayables
                .take(50)
                .map(
                  (payable) => CheckboxListTile(
                    value: selectedPayableIds.contains(
                      payable['id'].toString(),
                    ),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        selectedPayableIds.add(payable['id'].toString());
                      } else {
                        selectedPayableIds.remove(payable['id'].toString());
                      }
                    }),
                    title: Text(
                      DateFormatters.formatCurrency(
                        payable['amount_minor'] as num?,
                      ),
                    ),
                    subtitle: Text(
                      'Provider ${payable['provider_profile_id']} · Booking ${payable['booking_request_id']}',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
          if (heldPayables.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'Settlement recovery',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            ...heldPayables
                .take(30)
                .map(
                  (payable) => ListTile(
                    leading: const Icon(Icons.pause_circle_outline),
                    title: Text(
                      '${DateFormatters.formatCurrency(payable['amount_minor'] as num?)} · on hold',
                    ),
                    subtitle: Text('Booking ${payable['booking_request_id']}'),
                    trailing: OutlinedButton(
                      onPressed: () =>
                          releaseFailedPayable(payable['id'].toString()),
                      child: const Text('Review and release'),
                    ),
                  ),
                ),
          ],
          const Divider(height: 28),
          const Text(
            'Settlement batches',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (batches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No settlement batches.'),
            )
          else
            ...batches.take(30).map((batch) {
              final items =
                  (batch['settlement_batch_items'] as List?) ??
                  const <dynamic>[];
              final amount = items.fold<num>(
                0,
                (total, item) =>
                    total + ((item as Map)['amount_minor'] as num? ?? 0),
              );
              return ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(
                  '${batch['reference']} · ${DateFormatters.formatCurrency(amount)}',
                ),
                subtitle: Text('${batch['status']} · ${items.length} item(s)'),
                trailing: batch['status'] == 'draft'
                    ? OutlinedButton(
                        onPressed: () =>
                            approveSettlementBatch(batch['id'].toString()),
                        child: const Text('Approve'),
                      )
                    : Chip(label: Text(batch['status'].toString())),
              );
            }),
          const Divider(height: 28),
          const Text(
            'Reconciliation cases',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (reconciliationCases.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No financial discrepancies.'),
            )
          else
            ...reconciliationCases.take(50).map((item) {
              final expected = item['expected_amount_minor'] as num?;
              final reported = item['reported_amount_minor'] as num?;
              final difference = expected == null || reported == null
                  ? null
                  : expected - reported;
              final isOpen =
                  item['status'] == 'open' || item['status'] == 'investigating';
              return ListTile(
                leading: const Icon(Icons.balance_outlined),
                title: Text('${item['provider']} · ${item['status']}'),
                subtitle: Text(
                  '${item['reason']}\nExpected ${DateFormatters.formatCurrency(expected)} · Reported ${DateFormatters.formatCurrency(reported)}${difference == null ? '' : ' · Difference ${DateFormatters.formatCurrency(difference)}'}',
                ),
                isThreeLine: true,
                trailing: isOpen
                    ? PopupMenuButton<String>(
                        onSelected: (status) =>
                            reviewReconciliation(item['id'].toString(), status),
                        itemBuilder: (_) => const <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'investigating',
                            child: Text('Investigate'),
                          ),
                          PopupMenuItem<String>(
                            value: 'resolved',
                            child: Text('Resolve'),
                          ),
                          PopupMenuItem<String>(
                            value: 'written_off',
                            child: Text('Record write-off decision'),
                          ),
                        ],
                      )
                    : Chip(label: Text(item['status'].toString())),
              );
            }),
        ],
      ),
    );
  }
}
