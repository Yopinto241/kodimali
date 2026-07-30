import 'package:flutter/material.dart';
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
}
