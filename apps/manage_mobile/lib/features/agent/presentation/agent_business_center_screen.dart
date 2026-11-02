import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/manage_ui.dart';

class AgentBusinessCenterScreen extends StatefulWidget {
  const AgentBusinessCenterScreen({super.key});
  @override
  State<AgentBusinessCenterScreen> createState() =>
      _AgentBusinessCenterScreenState();
}

class _AgentBusinessCenterScreenState extends State<AgentBusinessCenterScreen> {
  late Future<List<dynamic>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load();
  }

  Future<List<dynamic>> _load() {
    final r = AppScope.of(context).repository;
    return Future.wait<dynamic>([
      r.fetchAgentBusinessDashboard(),
      r.fetchSubscriptionPlans(),
      r.fetchMyListings(),
      r.fetchMyListingBoosts(),
      r.fetchMyLeadPipeline(),
      r.fetchMyReceipts(),
      r.fetchAgentBookings(),
      r.fetchMyWalletTransactions(),
      r.fetchMyExternalDeals(),
    ]);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _declareExternalDeal(List<Map<String, dynamic>> listings) async {
    if (listings.isEmpty) return;
    String listingId = listings.first['id'].toString();
    final amount = TextEditingController();
    final notes = TextEditingController();
    DateTime transactionDate = DateTime.now();
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedUiText('Report an external deal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const LocalizedUiText(
                  'Use this only for a deal completed outside KODIMALI. It is not recorded as money collected by KODIMALI.',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: listingId,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Listing'),
                  ),
                  items: listings
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row['id'].toString(),
                          child: Text(row['title']?.toString() ?? 'Listing'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setDialog(() => listingId = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Declared value (TZS)'),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedUiText('Transaction date'),
                  subtitle: Text(
                    transactionDate.toIso8601String().split('T').first,
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: transactionDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialog(() => transactionDate = picked);
                    }
                  },
                ),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Notes'),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const LocalizedUiText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedUiText('Submit declaration'),
            ),
          ],
        ),
      ),
    );
    final value = int.tryParse(amount.text.trim());
    final note = notes.text;
    amount.dispose();
    notes.dispose();
    if (save != true || value == null || value < 0 || !mounted) return;
    try {
      await AppScope.of(context).repository.declareExternalListingDeal(
        listingId: listingId,
        claimedValueTzs: value,
        transactionDate: transactionDate,
        notes: note,
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  String _money(dynamic n) =>
      '${num.tryParse('$n')?.toStringAsFixed(0) ?? '0'} TZS';
  Future<String?> _phone() async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (x) => AlertDialog(
        title: const LocalizedUiText('Mobile-money payment'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: mobileUi(context, 'Payment phone number'),
            hintText: '2557...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, c.text.trim()),
            child: const LocalizedUiText('Send payment request'),
          ),
        ],
      ),
    );
  }

  Future<void> _buyPlan(Map<String, dynamic> plan) async {
    try {
      final r = AppScope.of(context).repository;
      final bool paidMode = await r.commercialPaymentEnabled('subscription');
      if (!mounted) return;
      final String? phone = paidMode ? await _phone() : '';
      if (phone == null || (paidMode && phone.isEmpty) || !mounted) return;
      final p = await r.createCommercialPayment(
        productType: 'subscription',
        planId: plan['id'].toString(),
        phoneNumber: phone,
      );
      if (!mounted) return;
      if (p['paymentRequired'] != false) {
        await showDialog<void>(
          context: context,
          builder: (x) => _PaymentStatusDialog(
            paymentId: p['paymentId'].toString(),
            repository: r,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedUiText(
              'The administrator has made subscriptions free. Your plan is active.',
            ),
          ),
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _boost(List<Map<String, dynamic>> listings) async {
    if (listings.isEmpty) return;
    String listing = listings.first['id'].toString(), placement = 'featured';
    int days = 7;
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (x, set) => AlertDialog(
          title: const LocalizedUiText('Promote a listing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: listing,
                items: listings
                    .map(
                      (l) => DropdownMenuItem(
                        value: l['id'].toString(),
                        child: Text(l['title'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => set(() => listing = v!),
              ),
              DropdownButtonFormField<String>(
                initialValue: placement,
                items: const [
                  DropdownMenuItem(
                    value: 'featured',
                    child: LocalizedUiText('Featured badge'),
                  ),
                  DropdownMenuItem(
                    value: 'search_top',
                    child: LocalizedUiText('Top of search'),
                  ),
                  DropdownMenuItem(
                    value: 'homepage',
                    child: LocalizedUiText('Homepage'),
                  ),
                ],
                onChanged: (v) => set(() => placement = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: days,
                items: const [
                  DropdownMenuItem(
                    value: 3,
                    child: LocalizedUiText('3 days · 3,000 TZS'),
                  ),
                  DropdownMenuItem(
                    value: 7,
                    child: LocalizedUiText('7 days · 6,000 TZS'),
                  ),
                  DropdownMenuItem(
                    value: 30,
                    child: LocalizedUiText('30 days · 20,000 TZS'),
                  ),
                ],
                onChanged: (v) => set(() => days = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const LocalizedUiText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(x, true),
              child: const LocalizedUiText('Continue'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final repo = AppScope.of(context).repository;
    final boost = await repo.requestListingBoost(
      listingId: listing,
      placement: placement,
      durationDays: days,
      amountTzs: days == 3
          ? 3000
          : days == 7
          ? 6000
          : 20000,
    );
    if (!mounted) return;
    final bool paidMode = await repo.commercialPaymentEnabled('listing_boost');
    if (!mounted) return;
    final String? phone = paidMode ? await _phone() : '';
    if (phone != null && (!paidMode || phone.isNotEmpty) && mounted) {
      final payment = await repo.createCommercialPayment(
        productType: 'listing_boost',
        boostId: boost['id'].toString(),
        phoneNumber: phone,
      );
      if (!mounted) return;
      if (payment['paymentRequired'] != false) {
        await showDialog<void>(
          context: context,
          builder: (context) => _PaymentStatusDialog(
            paymentId: payment['paymentId'].toString(),
            repository: repo,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedUiText(
              'The administrator has made featured campaigns free. Campaign activated.',
            ),
          ),
        );
      }
    }
    await _refresh();
  }

  Future<void> _editLead(Map<String, dynamic> booking) async {
    String stage = 'new';
    DateTime? followUpAt;
    final note = TextEditingController();
    final value = TextEditingController();
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            mobileUiFormat(context, "Lead · {0}", [
              booking['customer_name'] ??
                  booking['request_reference'] ??
                  'Customer',
            ]),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: stage,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Pipeline stage'),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'new',
                    child: LocalizedUiText('New lead'),
                  ),
                  DropdownMenuItem(
                    value: 'contacted',
                    child: LocalizedUiText('Contacted'),
                  ),
                  DropdownMenuItem(
                    value: 'viewing_scheduled',
                    child: LocalizedUiText('Viewing scheduled'),
                  ),
                  DropdownMenuItem(
                    value: 'negotiating',
                    child: LocalizedUiText('Negotiating'),
                  ),
                  DropdownMenuItem(
                    value: 'completed',
                    child: LocalizedUiText('Completed'),
                  ),
                  DropdownMenuItem(
                    value: 'lost',
                    child: LocalizedUiText('Lost'),
                  ),
                ],
                onChanged: (v) => setDialog(() => stage = v!),
              ),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Customer note'),
                ),
              ),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: mobileUi(
                    context,
                    'Expected transaction value (TZS)',
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedUiText('Cancel'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final DateTime? chosen = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: followUpAt ?? DateTime.now(),
                );
                if (chosen != null) setDialog(() => followUpAt = chosen);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                followUpAt == null
                    ? mobileUi(context, 'Set follow-up date')
                    : mobileUiFormat(context, "Follow up: {0}", [
                        followUpAt!.toIso8601String().split('T').first,
                      ]),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedUiText('Save lead'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    await AppScope.of(context).repository.saveLeadPipeline(
      bookingRequestId: booking['id'].toString(),
      stage: stage,
      note: note.text.trim(),
      transactionValueTzs: num.tryParse(value.text),
      followUpAt: followUpAt,
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _future,
    builder: (context, s) {
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      if (s.hasError) return Center(child: Text('${s.error}'));
      final d = s.data!;
      final dash = (d[0] as Map).cast<String, dynamic>(),
          plans = (d[1] as List).cast<Map<String, dynamic>>(),
          listings = (d[2] as List).cast<Map<String, dynamic>>(),
          boosts = (d[3] as List).cast<Map<String, dynamic>>(),
          leads = (d[4] as List).cast<Map<String, dynamic>>(),
          receipts = (d[5] as List).cast<Map<String, dynamic>>(),
          bookings = (d[6] as List).cast<Map<String, dynamic>>(),
          walletTransactions = (d[7] as List).cast<Map<String, dynamic>>();
      final externalDeals = (d[8] as List).cast<Map<String, dynamic>>();
      final current = (dash['plan'] as Map?)?.cast<String, dynamic>() ?? {};
      return ManagePageScrollView(
        onRefresh: _refresh,
        children: [
          ManageHeroCard(
            title: mobileUi(context, 'Business center'),
            subtitle: mobileUi(
              context,
              'Grow your sales with plans, featured listings, CRM follow-ups, wallet and receipts.',
            ),
            bottom: Text(
              mobileUiFormat(context, "Current plan: {0}", [
                current['name'] ?? 'Free',
              ]),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: mobileUi(context, 'Subscription packages'),
            subtitle: mobileUi(
              context,
              'Paid plans activate for 30 days after ClickPesa confirms payment.',
            ),
            child: Column(
              children: plans
                  .map(
                    (p) => ListTile(
                      leading: Icon(
                        p['verification_badge'] == true
                            ? Icons.verified
                            : Icons.workspace_premium_outlined,
                      ),
                      title: Text(
                        mobileUiFormat(context, "{0} · {1}/month", [
                          p['name'],
                          _money(p['monthly_price_tzs']),
                        ]),
                      ),
                      subtitle: Text(
                        mobileUiFormat(
                          context,
                          "Listings: {0} · Publication fee: {1}",
                          [
                            p['listing_limit'] ?? 'Unlimited',
                            _money(p['publication_fee_tzs']),
                          ],
                        ),
                      ),
                      trailing: p['id'] == current['plan_id']
                          ? const Chip(label: LocalizedUiText('Current'))
                          : FilledButton(
                              onPressed: (p['monthly_price_tzs'] as num) == 0
                                  ? null
                                  : () => _buyPlan(p),
                              child: const LocalizedUiText('Choose'),
                            ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: mobileUi(context, 'Featured listings'),
            subtitle: mobileUi(
              context,
              'Target homepage or search placement for 3, 7 or 30 days.',
            ),
            action: FilledButton.icon(
              onPressed: () => _boost(listings),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const LocalizedUiText('Promote'),
            ),
            child: boosts.isEmpty
                ? const LocalizedUiText('No promotion campaigns yet.')
                : Column(
                    children: boosts
                        .map(
                          (b) => ListTile(
                            title: Text(
                              ((b['listings'] as Map?)?['title'] ?? 'Listing')
                                  .toString(),
                            ),
                            subtitle: Text(
                              mobileUiFormat(context, "{0} · {1} days · {2}", [
                                b['placement'],
                                b['duration_days'],
                                _money(b['amount_tzs']),
                              ]),
                            ),
                            trailing: Chip(label: Text(b['status'].toString())),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: mobileUi(context, 'Sales pipeline'),
            subtitle: mobileUi(
              context,
              'New → Contacted → Viewing → Negotiating → Completed/Lost',
            ),
            child: Column(
              children: <Widget>[
                if (leads.isEmpty)
                  const LocalizedUiText(
                    'Choose any customer request below to organize it as a lead.',
                  ),
                ...bookings
                    .take(30)
                    .map(
                      (b) => ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(
                          b['customer_name']?.toString() ??
                              b['request_reference']?.toString() ??
                              'Customer request',
                        ),
                        subtitle: Text(
                          '${b['booking_status'] ?? 'new'} · ${b['listing_title'] ?? ''}',
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editLead(b),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: mobileUi(context, 'Wallet and receipts'),
            subtitle:
                'Available balance: ${_money(((dash['wallet'] as Map?)?['available_balance_tzs']))} · Promotional credits: ${_money(((dash['wallet'] as Map?)?['promotional_credits_tzs']))}',
            child: receipts.isEmpty
                ? const LocalizedUiText(
                    'Receipts appear automatically after successful payments.',
                  )
                : Column(
                    children: receipts
                        .take(20)
                        .map(
                          (r) => ListTile(
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(
                              '${r['receipt_number']} · ${_money(r['amount_tzs'])}',
                            ),
                            subtitle: Text(
                              '${r['payment_kind']} · ${r['issued_at'].toString().split('T').first}',
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (walletTransactions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            ManagePanel(
              title: mobileUi(context, 'Wallet activity'),
              subtitle: mobileUi(
                context,
                'Wallet balances are administrative credits and adjustments, not customer rental payments.',
              ),
              child: Column(
                children: walletTransactions
                    .map(
                      (t) => ListTile(
                        leading: Icon(
                          t['transaction_type'] == 'credit'
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                        ),
                        title: Text(
                          '${t['transaction_type']} · ${_money(t['amount_tzs'])}',
                        ),
                        subtitle: Text(
                          '${t['description']} · ${t['balance_kind']}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ManagePanel(
            title: mobileUi(context, 'Deals completed outside KODIMALI'),
            subtitle: mobileUi(
              context,
              'Declare an authorized deal for verification. The value remains separate from KODIMALI collections.',
            ),
            action: FilledButton.icon(
              onPressed: listings.isEmpty
                  ? null
                  : () => _declareExternalDeal(listings),
              icon: const Icon(Icons.add_business_outlined),
              label: const LocalizedUiText('Report deal'),
            ),
            child: externalDeals.isEmpty
                ? const LocalizedUiText('No external deals declared.')
                : Column(
                    children: externalDeals
                        .map(
                          (deal) => ListTile(
                            leading: const Icon(Icons.handshake_outlined),
                            title: Text(
                              '${_money(deal['claimed_value_minor'])} · ${deal['status']}',
                            ),
                            subtitle: Text(
                              mobileUiFormat(context, "{0} · Listing {1}", [
                                deal['transaction_date'],
                                deal['listing_id'] ?? '-',
                              ]),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 90),
        ],
      );
    },
  );
}

class _PaymentStatusDialog extends StatefulWidget {
  const _PaymentStatusDialog({
    required this.paymentId,
    required this.repository,
  });
  final String paymentId;
  final dynamic repository;
  @override
  State<_PaymentStatusDialog> createState() => _PaymentStatusDialogState();
}

class _PaymentStatusDialogState extends State<_PaymentStatusDialog> {
  bool busy = false;
  String status = 'pending';
  Future<void> check() async {
    setState(() => busy = true);
    try {
      final d = await widget.repository.checkCommercialPayment(
        widget.paymentId,
      );
      setState(() => status = d['paymentStatus'].toString());
      if (status == 'paid' && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const LocalizedUiText('Confirm on your phone'),
    content: Text(
      mobileUiFormat(
        context,
        "Payment status: {0}\nAfter approving the mobile-money prompt, tap Check status.",
        [status],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const LocalizedUiText('Close'),
      ),
      FilledButton.icon(
        onPressed: busy ? null : check,
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(),
              )
            : const Icon(Icons.refresh),
        label: const LocalizedUiText('Check status'),
      ),
    ],
  );
}
