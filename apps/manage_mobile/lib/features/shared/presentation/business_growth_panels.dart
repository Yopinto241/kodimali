import 'package:flutter/material.dart';

import '../../../core/widgets/app_scope.dart';

String _money(dynamic value) {
  final num amount = value is num ? value : num.tryParse('$value') ?? 0;
  return '${amount.toStringAsFixed(0)} TZS';
}

class AdminBusinessAnalyticsPanel extends StatefulWidget {
  const AdminBusinessAnalyticsPanel({super.key});

  @override
  State<AdminBusinessAnalyticsPanel> createState() =>
      _AdminBusinessAnalyticsPanelState();
}

class _AdminBusinessAnalyticsPanelState
    extends State<AdminBusinessAnalyticsPanel> {
  Future<Map<String, dynamic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).repository.fetchAdminBusinessAnalytics();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snapshot.data!;
          final paid = (d['payments_paid'] as num?) ?? 0;
          final failed = (d['payments_failed'] as num?) ?? 0;
          final success = paid + failed == 0 ? 0 : paid * 100 / (paid + failed);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Business analytics · last 30 days',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Revenue, conversion, response speed and delivery health in one place.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _Metric(
                    'Revenue',
                    _money(d['revenue_tzs']),
                    Icons.payments_outlined,
                  ),
                  _Metric(
                    'Listing views',
                    '${d['listing_views'] ?? 0}',
                    Icons.visibility_outlined,
                  ),
                  _Metric(
                    'Contact unlocks',
                    '${d['contact_unlocks'] ?? 0}',
                    Icons.lock_open_outlined,
                  ),
                  _Metric(
                    'Chat conversions',
                    '${d['chat_conversions'] ?? 0}',
                    Icons.chat_outlined,
                  ),
                  _Metric(
                    'Payment success',
                    '${success.toStringAsFixed(1)}%',
                    Icons.verified_outlined,
                  ),
                  _Metric(
                    'Avg. response',
                    '${d['average_response_minutes'] ?? '-'} min',
                    Icons.speed_outlined,
                  ),
                  _Metric(
                    'Delivery issues',
                    '${d['notification_pending'] ?? 0}',
                    Icons.notification_important_outlined,
                  ),
                  _Metric(
                    'Risk flags',
                    '${d['open_risk_flags'] ?? 0}',
                    Icons.shield_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Most profitable categories',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final dynamic item
                  in (d['categories'] as List? ?? const <dynamic>[]).take(5))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.category_outlined),
                  title: Text((item as Map)['name']?.toString() ?? '-'),
                  subtitle: Text('${item['conversions'] ?? 0} conversions'),
                  trailing: Text(_money(item['revenue_tzs'])),
                ),
              Text(
                'Most profitable locations',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final dynamic item
                  in (d['locations'] as List? ?? const <dynamic>[]).take(5))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text((item as Map)['location']?.toString() ?? '-'),
                  subtitle: Text('${item['conversions'] ?? 0} conversions'),
                  trailing: Text(_money(item['revenue_tzs'])),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class AgentBusinessPanel extends StatefulWidget {
  const AgentBusinessPanel({super.key});
  @override
  State<AgentBusinessPanel> createState() => _AgentBusinessPanelState();
}

class _AgentBusinessPanelState extends State<AgentBusinessPanel> {
  Future<Map<String, dynamic>>? _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).repository.fetchAgentBusinessDashboard();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snapshot.data!;
          final plan =
              (d['plan'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final ratings =
              (d['ratings'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final performance =
              (d['performance'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final wallet =
              (d['wallet'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.workspace_premium_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${plan['name'] ?? 'Free'} business plan',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (plan['verification_badge'] == true)
                    const Chip(label: Text('Verified')),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Publication fee: ${_money(plan['publication_fee_tzs'])} · Listing limit: ${plan['listing_limit'] ?? 'Unlimited'}',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _Metric(
                    'Rating',
                    '${ratings['rating'] ?? '-'} (${ratings['reviews'] ?? 0})',
                    Icons.star_outline,
                  ),
                  _Metric(
                    'Completed',
                    '${performance['completed'] ?? 0}',
                    Icons.task_alt_outlined,
                  ),
                  _Metric(
                    'Response',
                    '${performance['response_minutes'] ?? '-'} min',
                    Icons.speed_outlined,
                  ),
                  _Metric(
                    'Follow-ups',
                    '${d['follow_ups'] ?? 0}',
                    Icons.event_outlined,
                  ),
                  _Metric(
                    'Wallet',
                    _money(wallet['available_balance_tzs']),
                    Icons.account_balance_wallet_outlined,
                  ),
                  _Metric(
                    'Promo credit',
                    _money(wallet['promotional_credits_tzs']),
                    Icons.redeem_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Lead pipeline: New → Contacted → Viewing scheduled → Negotiating → Completed/Lost',
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 148,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: .42),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(label),
      ],
    ),
  );
}
