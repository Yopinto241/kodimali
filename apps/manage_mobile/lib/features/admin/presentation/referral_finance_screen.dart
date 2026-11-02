import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReferralFinanceScreen extends StatefulWidget {
  const ReferralFinanceScreen({super.key});
  @override
  State<ReferralFinanceScreen> createState() => _ReferralFinanceScreenState();
}

class _ReferralFinanceScreenState extends State<ReferralFinanceScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      (await Supabase.instance.client.rpc('get_information_finance_rewards')
              as List)
          .cast<Map<String, dynamic>>();
  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _review(Map<String, dynamic> reward, String action) async {
    final note = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(mobileUiFormat(context, "Reward: {0}", [action])),
        content: TextField(
          controller: note,
          decoration: InputDecoration(
            labelText: mobileUi(context, 'Reason for finance decision'),
          ),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const LocalizedUiText('Save decision'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _perform(
        () => Supabase.instance.client.rpc(
          'review_information_referral_reward',
          params: {
            'p_reward_id': reward['id'],
            'p_action': action,
            'p_note': note.text.trim(),
          },
        ),
      );
    }
    note.dispose();
  }

  Future<void> _payout(Map<String, dynamic> reward) async {
    final reference = TextEditingController(),
        method = TextEditingController(),
        note = TextEditingController();
    final form = GlobalKey<FormState>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const LocalizedUiText('Record completed contributor payout'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${reward['contributor_name']} · ${reward['reward_amount_tzs']} TZS',
                  ),
                  const SizedBox(height: 12),
                  const LocalizedUiText(
                    'Record a payment already completed through your payment provider. This does not send money.',
                  ),
                  TextFormField(
                    controller: reference,
                    decoration: InputDecoration(
                      labelText: mobileUi(
                        context,
                        'Completed transaction reference',
                      ),
                    ),
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? mobileUi(
                            context,
                            'Enter the real transaction reference.',
                          )
                        : null,
                  ),
                  TextFormField(
                    controller: method,
                    decoration: InputDecoration(
                      labelText: mobileUi(context, 'Payment method'),
                    ),
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? mobileUi(context, 'Enter the payment method.')
                        : null,
                  ),
                  TextFormField(
                    controller: note,
                    decoration: InputDecoration(
                      labelText: mobileUi(context, 'Payment note'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const LocalizedUiText('Record completed payout'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _perform(
        () => Supabase.instance.client.rpc(
          'record_referral_payout',
          params: {
            'p_reward_id': reward['id'],
            'p_transaction_reference': reference.text.trim(),
            'p_payment_method': method.text.trim(),
            'p_notes': note.text.trim(),
          },
        ),
      );
    }
    reference.dispose();
    method.dispose();
    note.dispose();
  }

  Future<void> _perform(Future<dynamic> Function() action) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PostgrestException
                  ? error.message
                  : mobileUi(
                      context,
                      'Could not save the finance action. Please retry.',
                    ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _reload,
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(24),
                child: LocalizedUiText('Could not load contributor rewards.'),
              ),
              TextButton(
                onPressed: _reload,
                child: const LocalizedUiText('Retry'),
              ),
            ],
          );
        }
        final rewards = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: LocalizedUiText(
                  'Contributor reward payments\nReview calculated rewards, approve valid obligations and record completed external payouts. No money is transferred by this screen.',
                ),
              ),
            ),
            if (rewards.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: LocalizedUiText(
                  'No calculated contributor rewards yet.',
                ),
              ),
            ...rewards.map((reward) {
              final payout = reward['payout'] as Map?;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${reward['submission_reference']} · ${reward['reward_amount_tzs']} TZS',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${reward['contributor_name']}\n${reward['contributor_phone'] ?? reward['contributor_email'] ?? ''}',
                      ),
                      Text(
                        mobileUiFormat(
                          context,
                          "Verified service fee: {0} TZS · {1}",
                          [
                            reward['eligible_fee_collected_tzs'],
                            reward['status'],
                          ],
                        ),
                      ),
                      if (!['paid', 'rejected'].contains(reward['status']))
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final action in [
                              'approved',
                              'on_hold',
                              'rejected',
                            ])
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _review(reward, action),
                                child: Text(action.replaceAll('_', ' ')),
                              ),
                          ],
                        ),
                      if (reward['status'] == 'approved')
                        FilledButton(
                          onPressed: _busy ? null : () => _payout(reward),
                          child: const LocalizedUiText(
                            'Record completed payout',
                          ),
                        ),
                      if (payout != null)
                        Text(
                          mobileUiFormat(
                            context,
                            "Payment reference: {0} · {1}",
                            [
                              payout['transaction_reference'],
                              payout['payment_method'],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    ),
  );
}
