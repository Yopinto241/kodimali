import 'package:flutter/material.dart';

import '../../core/data/customer_account_repository.dart';
import '../../core/localization/customer_localization.dart';

class CustomerTenancyScreen extends StatefulWidget {
  const CustomerTenancyScreen({super.key, required this.repository});

  final CustomerAccountRepository repository;

  @override
  State<CustomerTenancyScreen> createState() => _CustomerTenancyScreenState();
}

class _CustomerTenancyScreenState extends State<CustomerTenancyScreen> {
  late Future<List<CustomerJson>> _agreements;
  final TextEditingController _token = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _agreements = widget.repository.fetchMyRentalAgreements();
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = widget.repository.fetchMyRentalAgreements();
    setState(() => _agreements = next);
    await next;
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _acceptInvite() async {
    final value = _token.text.trim();
    if (value.isEmpty) return;
    final sw = context.isSwahili;
    setState(() => _busy = true);
    try {
      await widget.repository.acceptTenantInvitation(value);
      if (!mounted) return;
      _token.clear();
      _message(
        sw
            ? 'Mwaliko umekubaliwa. Mwenye mali sasa anaweza kuandaa mkataba.'
            : 'Invitation accepted. The owner can now prepare the agreement.',
      );
      await _reload();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptAgreement(String id) async {
    final sw = context.isSwahili;
    setState(() => _busy = true);
    try {
      await widget.repository.acceptRentalAgreement(id);
      if (!mounted) return;
      _message(sw ? 'Mkataba umekubaliwa.' : 'Agreement accepted.');
      await _reload();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveOut(String id) async {
    final sw = context.isSwahili;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final reason = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(sw ? 'Taarifa ya kuhama' : 'Move-out notice'),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: sw ? 'Sababu (si lazima)' : 'Reason (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(sw ? 'Ghairi' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(sw ? 'Tuma' : 'Send'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) {
      reason.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.submitMoveOutNotice(
        agreementId: id,
        date: date,
        reason: reason.text,
      );
      if (!mounted) return;
      _message(
        sw
            ? 'Taarifa ya kuhama imetumwa kwa mwenye mali.'
            : 'Move-out notice sent to the owner.',
      );
      await _reload();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      reason.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Upangaji wangu' : 'My tenancy')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sw ? 'Unganisha na mwenye mali' : 'Connect with an owner',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sw
                          ? 'Weka namba ya mwaliko uliyotumiwa na mwenye mali.'
                          : 'Enter the private invitation token sent by the owner.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _token,
                      decoration: InputDecoration(
                        labelText: sw ? 'Namba ya mwaliko' : 'Invitation token',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _acceptInvite,
                      child: Text(sw ? 'Kubali mwaliko' : 'Accept invitation'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<CustomerJson>>(
              future: _agreements,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) return Text(snapshot.error.toString());
                final rows = snapshot.data ?? const <CustomerJson>[];
                if (rows.isEmpty) {
                  return Text(
                    sw
                        ? 'Bado huna mkataba wa upangaji.'
                        : 'No rental agreements yet.',
                  );
                }
                return Column(
                  children: rows.map((row) {
                    final rawAsset = row['rental_assets'];
                    final asset = rawAsset is Map
                        ? rawAsset.cast<String, dynamic>()
                        : null;
                    final status = row['status'].toString();
                    return Card(
                      child: ListTile(
                        title: Text(
                          asset?['display_name']?.toString() ??
                              (sw ? 'Mkataba wa upangaji' : 'Rental agreement'),
                        ),
                        subtitle: Text(
                          '${row['starts_on']} · TZS ${row['rent_amount_tzs']} / ${row['rent_period']}\n'
                          '${status.replaceAll('_', ' ')}',
                        ),
                        isThreeLine: true,
                        trailing: status == 'pending_tenant'
                            ? FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _acceptAgreement(
                                        row['id'].toString(),
                                      ),
                                child: Text(sw ? 'Kubali' : 'Accept'),
                              )
                            : status == 'active'
                            ? TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _moveOut(row['id'].toString()),
                                child: Text(
                                  sw ? 'Taarifa ya kuhama' : 'Move out',
                                ),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
