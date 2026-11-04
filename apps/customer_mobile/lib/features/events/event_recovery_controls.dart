import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/customer_public_repository.dart';
import '../../core/localization/customer_localization.dart';

class EventRecoveryControls extends StatefulWidget {
  const EventRecoveryControls({
    super.key,
    required this.repository,
    required this.planId,
    required this.status,
    required this.onChanged,
  });
  final CustomerPublicRepository repository;
  final String planId;
  final String status;
  final VoidCallback onChanged;

  @override
  State<EventRecoveryControls> createState() => _EventRecoveryControlsState();
}

class _EventRecoveryControlsState extends State<EventRecoveryControls> {
  late Future<List<Map<String, dynamic>>> future;
  late Future<List<Map<String, dynamic>>> reviews;
  bool busy = false;
  final reason = TextEditingController();
  @override
  void initState() {
    super.initState();
    future = _load();
    reviews = _loadReviews();
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      (await Supabase.instance.client
              .from('event_substitution_proposals')
              .select(
                'id,reason,price_change_tzs,status,expires_at,equipment:event_equipment_items!proposed_equipment_id(name),service:event_service_offerings!proposed_offering_id(title)',
              )
              .eq('plan_id', widget.planId)
              .order('created_at', ascending: false))
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> _loadReviews() async =>
      (await Supabase.instance.client
              .from('event_cancellations')
              .select('id,status,reason,resolution,refundable_amount_tzs')
              .eq('plan_id', widget.planId)
              .order('created_at', ascending: false))
          .cast<Map<String, dynamic>>();

  Future<void> _act(String function, Map<String, dynamic> params) async {
    setState(() {
      busy = true;
    });
    try {
      await Supabase.instance.client.rpc(function, params: params);
      if (!mounted) return;
      setState(() {
        future = _load();
        reviews = _loadReviews();
      });
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, e))));
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() {
                  future = _load();
                }),
                child: Text(
                  sw
                      ? mobileUi(
                          context,
                          'Imeshindwa kupakia mbadala. Jaribu tena.',
                        )
                      : mobileUi(
                          context,
                          'Could not load replacements. Retry.',
                        ),
                ),
              );
            }
            return Column(
              children: (snapshot.data ?? []).map((proposal) {
                final canRespond =
                    proposal['status'] == 'proposed' &&
                    DateTime.parse(
                      proposal['expires_at'].toString(),
                    ).isAfter(DateTime.now());
                final equipment = proposal['equipment'] as Map?;
                final service = proposal['service'] as Map?;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${sw ? mobileUi(context, 'Mbadala') : mobileUi(context, 'Replacement')}: ${equipment?['name'] ?? service?['title'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(proposal['reason'].toString()),
                        Text(
                          '${sw ? mobileUi(context, 'Tofauti ya bei') : mobileUi(context, 'Price change')}: TZS ${proposal['price_change_tzs']}',
                        ),
                        Text(
                          sw
                              ? mobileUi(
                                  context,
                                  'Mtoa huduma lazima athibitishe. Utakagua quotation mpya kabla ya malipo.',
                                )
                              : mobileUi(
                                  context,
                                  'Provider confirmation and a revised quotation are required before any new payment.',
                                ),
                        ),
                        if (canRespond)
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _act('respond_event_replacement', {
                                        'p_proposal_id': proposal['id'],
                                        'p_accept': false,
                                      }),
                                child: Text(
                                  sw
                                      ? mobileUi(context, 'Kataa')
                                      : mobileUi(context, 'Decline'),
                                ),
                              ),
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => _act('respond_event_replacement', {
                                        'p_proposal_id': proposal['id'],
                                        'p_accept': true,
                                      }),
                                child: Text(
                                  sw
                                      ? mobileUi(context, 'Kubali mbadala')
                                      : mobileUi(context, 'Accept replacement'),
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            proposal['status'] == 'proposed'
                                ? (sw
                                      ? mobileUi(context, 'Imeisha muda')
                                      : mobileUi(context, 'Expired'))
                                : proposal['status'].toString(),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: reviews,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() {
                  reviews = _loadReviews();
                }),
                child: Text(
                  sw
                      ? mobileUi(context, 'Jaribu kupakia suluhu tena')
                      : mobileUi(context, 'Retry cancellation reviews'),
                ),
              );
            }
            return Column(
              children: (snapshot.data ?? [])
                  .map(
                    (row) => ListTile(
                      title: Text(
                        '${sw ? mobileUi(context, 'Ukaguzi wa cancellation') : mobileUi(context, 'Cancellation review')}: ${row['status']}',
                      ),
                      subtitle: Text(
                        '${row['reason']} / ${row['resolution'] ?? (sw ? mobileUi(context, 'Inasubiri uhakiki') : mobileUi(context, 'Awaiting review'))} / TZS ${row['refundable_amount_tzs'] ?? 0}',
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        if (!['cancelled', 'completed'].contains(widget.status))
          ExpansionTile(
            title: Text(
              sw
                  ? mobileUi(context, 'Ghairi tukio')
                  : mobileUi(context, 'Cancel event'),
            ),
            children: [
              Text(
                sw
                    ? mobileUi(
                        context,
                        'Vifaa na muda vitaachiwa. Marejesho ya fedha yanahitaji uhakiki.',
                      )
                    : mobileUi(
                        context,
                        'Stock and provider time will be released. Refunds require review.',
                      ),
              ),
              TextField(
                controller: reason,
                onChanged: (_) => setState(() {}),
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: sw
                      ? mobileUi(context, 'Sababu')
                      : mobileUi(context, 'Reason'),
                ),
              ),
              OutlinedButton(
                onPressed: busy || reason.text.trim().isEmpty
                    ? null
                    : () => _act('cancel_customer_event', {
                        'p_plan_id': widget.planId,
                        'p_reason': reason.text.trim(),
                      }),
                child: Text(
                  sw
                      ? mobileUi(context, 'Thibitisha kughairi')
                      : mobileUi(context, 'Confirm cancellation'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
