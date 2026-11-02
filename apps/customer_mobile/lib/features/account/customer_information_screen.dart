import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data/customer_account_repository.dart';

Map<String, dynamic> _relation(dynamic value) {
  if (value is List) return value.isEmpty ? {} : _relation(value.first);
  return value is Map ? value.cast<String, dynamic>() : {};
}

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((row) => row.cast<String, dynamic>()).toList()
    : [];
String _error(Object error) => error is StateError
    ? error.message.toString()
    : error is PostgrestException
    ? error.message
    : 'Haikuweza kukamilika. Angalia mtandao na ujaribu tena.';

class CustomerInformationScreen extends StatefulWidget {
  const CustomerInformationScreen({super.key, required this.repository});
  final CustomerAccountRepository repository;
  @override
  State<CustomerInformationScreen> createState() =>
      _CustomerInformationScreenState();
}

class _CustomerInformationScreenState extends State<CustomerInformationScreen> {
  late Future<List<CustomerJson>> _future;
  int _page = 0;
  final Set<String> _accepting = {};
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CustomerJson>> _load() =>
      widget.repository.fetchMyRentalInformation(offset: _page * 20);
  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _submit() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _InformationForm(repository: widget.repository),
    );
    if (saved == true && mounted) {
      _page = 0;
      await _reload();
    }
  }

  Future<void> _accept(CustomerJson agreement) async {
    final id = agreement['id'].toString();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedUiText('Masharti ya zawadi'),
        content: SingleChildScrollView(
          child: Text(agreement['terms'].toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedUiText('Ghairi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedUiText('Nimesoma na kukubali'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _accepting.add(id));
    try {
      await widget.repository.acceptInformationReferralTerms(
        id,
        (agreement['terms_version'] as num).toInt(),
      );
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedUiText(_error(error))));
      }
    } finally {
      if (mounted) setState(() => _accepting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedUiText('Taarifa Zangu')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _submit,
      icon: const Icon(Icons.add),
      label: const LocalizedUiText('Toa Taarifa'),
    ),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<CustomerJson>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      LocalizedUiText(_error(snapshot.error!)),
                      FilledButton(
                        onPressed: _reload,
                        child: const LocalizedUiText('Jaribu tena'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          final leads = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: LocalizedUiText(
                    'Taarifa zako ni za faragha. Fuata uhakiki, soma masharti ya zawadi na uone malipo yako hapa. Kutuma taarifa pekee hakuhakikishi zawadi.',
                  ),
                ),
              ),
              if (leads.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: LocalizedUiText('Bado hujatuma taarifa yoyote.'),
                ),
              ...leads.map((lead) {
                final agreement = _relation(lead['referral_agreements']);
                return Card(
                  child: ExpansionTile(
                    title: Text(lead['reference'].toString()),
                    subtitle: Text(
                      mobileUiFormat(context, "{0}\n{1} · Zawadi: {2}", [
                        lead['location_description'],
                        lead['status'],
                        lead['eligibility_status'],
                      ]),
                    ),
                    childrenPadding: const EdgeInsets.all(16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(lead['description'].toString()),
                      const SizedBox(height: 12),
                      if (agreement.isEmpty)
                        const LocalizedUiText(
                          'Masharti na kiasi cha zawadi vitaonekana baada ya uhakiki.',
                        )
                      else ...[
                        Text(
                          agreement['reward_type'] == 'fixed'
                              ? mobileUiFormat(context, "Zawadi: {0} TZS", [
                                  agreement['fixed_amount_tzs'],
                                ])
                              : mobileUiFormat(
                                  context,
                                  "Zawadi: {0}% ya ada ya huduma iliyothibitishwa",
                                  [agreement['percentage_rate']],
                                ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(agreement['terms'].toString()),
                        const SizedBox(height: 8),
                        const LocalizedUiText(
                          'Zawadi inahitaji booking iliyokamilika, ada ya huduma iliyothibitishwa na idhini ya Finance. Amana haihesabiwi kama ada ya huduma.',
                        ),
                        if (agreement['contributor_accepted_at'] == null)
                          FilledButton(
                            onPressed: _accepting.contains(agreement['id'])
                                ? null
                                : () => _accept(agreement),
                            child: const LocalizedUiText(
                              'Soma na ukubali masharti',
                            ),
                          )
                        else
                          const LocalizedUiText('Umekubali masharti haya.'),
                        ..._rows(agreement['referral_rewards']).map((reward) {
                          final payout = _relation(reward['referral_payouts']);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${reward['reward_amount_tzs']} TZS · ${reward['status']}',
                            ),
                            subtitle: payout.isEmpty
                                ? null
                                : Text(
                                    mobileUiFormat(
                                      context,
                                      "Malipo: {0} · {1}",
                                      [
                                        payout['transaction_reference'],
                                        payout['payment_method'],
                                      ],
                                    ),
                                  ),
                          );
                        }),
                      ],
                    ],
                  ),
                );
              }),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _page == 0
                        ? null
                        : () {
                            _page--;
                            _reload();
                          },
                    child: const LocalizedUiText('Nyuma'),
                  ),
                  TextButton(
                    onPressed: leads.length < 20
                        ? null
                        : () {
                            _page++;
                            _reload();
                          },
                    child: const LocalizedUiText('Mbele'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _InformationForm extends StatefulWidget {
  const _InformationForm({required this.repository});
  final CustomerAccountRepository repository;
  @override
  State<_InformationForm> createState() => _InformationFormState();
}

class _InformationFormState extends State<_InformationForm> {
  final _form = GlobalKey<FormState>();
  final _location = TextEditingController(),
      _description = TextEditingController(),
      _rent = TextEditingController(),
      _ownerName = TextEditingController(),
      _ownerPhone = TextEditingController();
  String _category = 'house', _source = 'moving_out', _period = 'month';
  bool _authorized = false, _busy = false;
  DateTime? _available;
  String? _message;
  @override
  void dispose() {
    for (final controller in [
      _location,
      _description,
      _rent,
      _ownerName,
      _ownerPhone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if ((_ownerName.text.trim().isNotEmpty ||
            _ownerPhone.text.trim().isNotEmpty) &&
        !_authorized) {
      setState(
        () =>
            _message = 'Thibitisha ruhusa ya kushiriki mawasiliano ya mmiliki.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.repository.submitRentalInformation(
        category: _category,
        locationDescription: _location.text,
        description: _description.text,
        informationSource: _source,
        approximateRent: _rent.text.trim().isEmpty
            ? null
            : double.parse(_rent.text.trim()),
        availableFrom: _available,
        ownerName: _ownerName.text.trim().isEmpty
            ? null
            : _ownerName.text.trim(),
        ownerPhone: _ownerPhone.text.trim().isEmpty
            ? null
            : _ownerPhone.text.trim(),
        ownerContactAuthorized: _authorized,
        pricePeriod: _period,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const LocalizedUiText('Toa Taarifa kwa faragha'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Aina ya mali'),
                  ),
                  items:
                      const {
                            'house': 'Nyumba',
                            'apartment': 'Apartment',
                            'office': 'Ofisi',
                            'car': 'Gari',
                            'motorcycle': 'Pikipiki',
                            'meeting_hall': 'Ukumbi wa mikutano',
                            'ceremony_hall': 'Ukumbi wa sherehe',
                            'equipment': 'Vifaa',
                            'farms': 'Shamba',
                            'other_asset': 'Mali nyingine',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: LocalizedUiText(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _category = value!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _source,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Chanzo cha taarifa'),
                  ),
                  items:
                      const {
                            'moving_out': 'Ninahama',
                            'owner': 'Nimepewa na mmiliki',
                            'manager': 'Nimepewa na msimamizi',
                            'community': 'Nimeiona eneo langu',
                            'other': 'Chanzo kingine',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: LocalizedUiText(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _source = value!),
                ),
                TextFormField(
                  controller: _location,
                  decoration: InputDecoration(
                    labelText: mobileUi(
                      context,
                      'Eneo kamili kwa timu ya uhakiki',
                    ),
                  ),
                  maxLength: 500,
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? mobileUi(context, 'Weka eneo kamili.')
                      : null,
                ),
                TextFormField(
                  controller: _description,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Maelezo ya mali'),
                  ),
                  maxLines: 3,
                  maxLength: 4000,
                  validator: (value) => (value?.trim().length ?? 0) < 10
                      ? mobileUi(
                          context,
                          'Weka maelezo ya kutosha (herufi 10 au zaidi).',
                        )
                      : null,
                ),
                TextFormField(
                  controller: _rent,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: mobileUi(
                      context,
                      'Bei/kodi ya makadirio TZS (si lazima)',
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final amount = double.tryParse(value.trim());
                    return amount == null || !amount.isFinite || amount < 0
                        ? mobileUi(context, 'Weka kiasi sahihi.')
                        : null;
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _period,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Kipindi cha bei'),
                  ),
                  items:
                      const {
                            'hour': 'Kwa saa',
                            'day': 'Kwa siku',
                            'week': 'Kwa wiki',
                            'month': 'Kwa mwezi',
                            'year': 'Kwa mwaka',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: LocalizedUiText(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _period = value!),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _available == null
                        ? mobileUi(
                            context,
                            'Inapatikana lini / tarehe ya kuhama?',
                          )
                        : _available!.toIso8601String().substring(0, 10),
                  ),
                  onPressed: _busy
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                            context: context,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1825),
                            ),
                          );
                          if (selected != null && mounted) {
                            setState(() => _available = selected);
                          }
                        },
                ),
                TextFormField(
                  controller: _ownerName,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Jina la mmiliki (si lazima)'),
                  ),
                ),
                TextFormField(
                  controller: _ownerPhone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: mobileUi(context, 'Simu ya mmiliki (si lazima)'),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _authorized,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _authorized = value ?? false),
                  title: const LocalizedUiText(
                    'Nina ruhusa ya kushiriki mawasiliano haya kwa uhakiki.',
                  ),
                ),
                const LocalizedUiText(
                  'Taarifa haitachapishwa moja kwa moja. Kutuma pekee hakuhakikishi zawadi.',
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: LocalizedUiText(_message!),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const LocalizedUiText('Ghairi'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? mobileUi(context, 'Inatuma…')
                : mobileUi(context, 'Tuma taarifa'),
          ),
        ),
      ],
    ),
  );
}
