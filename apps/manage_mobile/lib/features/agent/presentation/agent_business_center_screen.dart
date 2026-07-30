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
    ]);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  String _money(dynamic n) =>
      '${num.tryParse('$n')?.toStringAsFixed(0) ?? '0'} TZS';
  Future<String?> _phone() async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Mobile-money payment'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Payment phone number',
            hintText: '2557...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, c.text.trim()),
            child: const Text('Send payment request'),
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
            content: Text(
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
          title: const Text('Promote a listing'),
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
                    child: Text('Featured badge'),
                  ),
                  DropdownMenuItem(
                    value: 'search_top',
                    child: Text('Top of search'),
                  ),
                  DropdownMenuItem(value: 'homepage', child: Text('Homepage')),
                ],
                onChanged: (v) => set(() => placement = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: days,
                items: const [
                  DropdownMenuItem(value: 3, child: Text('3 days · 3,000 TZS')),
                  DropdownMenuItem(value: 7, child: Text('7 days · 6,000 TZS')),
                  DropdownMenuItem(
                    value: 30,
                    child: Text('30 days · 20,000 TZS'),
                  ),
                ],
                onChanged: (v) => set(() => days = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(x, true),
              child: const Text('Continue'),
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
            content: Text(
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
            'Lead · ${booking['customer_name'] ?? booking['request_reference'] ?? 'Customer'}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: stage,
                decoration: const InputDecoration(labelText: 'Pipeline stage'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'new', child: Text('New lead')),
                  DropdownMenuItem(
                    value: 'contacted',
                    child: Text('Contacted'),
                  ),
                  DropdownMenuItem(
                    value: 'viewing_scheduled',
                    child: Text('Viewing scheduled'),
                  ),
                  DropdownMenuItem(
                    value: 'negotiating',
                    child: Text('Negotiating'),
                  ),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(value: 'lost', child: Text('Lost')),
                ],
                onChanged: (v) => setDialog(() => stage = v!),
              ),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Customer note'),
              ),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Expected transaction value (TZS)',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
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
                    ? 'Set follow-up date'
                    : 'Follow up: ${followUpAt!.toIso8601String().split('T').first}',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save lead'),
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
      final current = (dash['plan'] as Map?)?.cast<String, dynamic>() ?? {};
      return ManagePageScrollView(
        onRefresh: _refresh,
        children: [
          ManageHeroCard(
            title: 'Business center',
            subtitle:
                'Grow your sales with plans, featured listings, CRM follow-ups, wallet and receipts.',
            bottom: Text(
              'Current plan: ${current['name'] ?? 'Free'}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: 'Subscription packages',
            subtitle:
                'Paid plans activate for 30 days after ClickPesa confirms payment.',
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
                        '${p['name']} · ${_money(p['monthly_price_tzs'])}/month',
                      ),
                      subtitle: Text(
                        'Listings: ${p['listing_limit'] ?? 'Unlimited'} · Publication fee: ${_money(p['publication_fee_tzs'])}',
                      ),
                      trailing: p['id'] == current['plan_id']
                          ? const Chip(label: Text('Current'))
                          : FilledButton(
                              onPressed: (p['monthly_price_tzs'] as num) == 0
                                  ? null
                                  : () => _buyPlan(p),
                              child: const Text('Choose'),
                            ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: 'Featured listings',
            subtitle:
                'Target homepage or search placement for 3, 7 or 30 days.',
            action: FilledButton.icon(
              onPressed: () => _boost(listings),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Promote'),
            ),
            child: boosts.isEmpty
                ? const Text('No promotion campaigns yet.')
                : Column(
                    children: boosts
                        .map(
                          (b) => ListTile(
                            title: Text(
                              ((b['listings'] as Map?)?['title'] ?? 'Listing')
                                  .toString(),
                            ),
                            subtitle: Text(
                              '${b['placement']} · ${b['duration_days']} days · ${_money(b['amount_tzs'])}',
                            ),
                            trailing: Chip(label: Text(b['status'].toString())),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 16),
          ManagePanel(
            title: 'Sales pipeline',
            subtitle:
                'New → Contacted → Viewing → Negotiating → Completed/Lost',
            child: Column(
              children: <Widget>[
                if (leads.isEmpty)
                  const Text(
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
            title: 'Wallet and receipts',
            subtitle:
                'Available balance: ${_money(((dash['wallet'] as Map?)?['available_balance_tzs']))} · Promotional credits: ${_money(((dash['wallet'] as Map?)?['promotional_credits_tzs']))}',
            child: receipts.isEmpty
                ? const Text(
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
              title: 'Wallet activity',
              subtitle:
                  'Wallet balances are administrative credits and adjustments, not customer rental payments.',
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
    title: const Text('Confirm on your phone'),
    content: Text(
      'Payment status: $status\nAfter approving the mobile-money prompt, tap Check status.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        onPressed: busy ? null : check,
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(),
              )
            : const Icon(Icons.refresh),
        label: const Text('Check status'),
      ),
    ],
  );
}
