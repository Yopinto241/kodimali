import 'package:flutter/material.dart';

import '../../core/data/customer_public_repository.dart';
import '../../core/localization/customer_localization.dart';
import 'event_location_picker.dart';

class EventsMarketplaceScreen extends StatefulWidget {
  const EventsMarketplaceScreen({
    super.key,
    required this.repository,
    this.initialRegionId,
    this.initialDistrictId,
    this.initialWardId,
    this.initialAreaId,
  });
  final CustomerPublicRepository repository;
  final String? initialRegionId;
  final String? initialDistrictId;
  final String? initialWardId;
  final String? initialAreaId;

  @override
  State<EventsMarketplaceScreen> createState() =>
      _EventsMarketplaceScreenState();
}

class _EventsMarketplaceScreenState extends State<EventsMarketplaceScreen> {
  late Future<JsonMap> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchEventsMarketplace();
  }

  Future<void> _reload() async {
    final next = widget.repository.fetchEventsMarketplace();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(sw ? 'Sherehe na Matukio' : 'Events'),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _EventAdvisorScreen(
                  repository: widget.repository,
                  initialRegionId: widget.initialRegionId,
                  initialDistrictId: widget.initialDistrictId,
                  initialWardId: widget.initialWardId,
                  initialAreaId: widget.initialAreaId,
                ),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Event Advisor',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _IndividualBookingsHistoryScreen(
                  repository: widget.repository,
                ),
              ),
            ),
            icon: const Icon(Icons.event_note_outlined),
            tooltip: sw ? 'Booking za vifaa na huduma' : 'Individual bookings',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    _MyEventPlansScreen(repository: widget.repository),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: sw ? 'Mipango yangu' : 'My event plans',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPlanner(sw),
        icon: const Icon(Icons.event_available_outlined),
        label: Text(sw ? 'Panga tukio' : 'Plan event'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<JsonMap>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: <Widget>[Text(snapshot.error.toString())],
              );
            }
            final data = snapshot.data ?? <String, dynamic>{};
            final types = (data['types'] as List? ?? const <dynamic>[])
                .cast<JsonMap>();
            final equipment = (data['equipment'] as List? ?? const <dynamic>[])
                .cast<JsonMap>();
            final services = (data['services'] as List? ?? const <dynamic>[])
                .cast<JsonMap>();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF102438), Color(0xFF147D8C)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'KODIMALI EVENTS',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFD6A75B),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        sw
                            ? 'Panga sherehe yako, sehemu moja.'
                            : 'Plan your event in one place.',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        sw
                            ? 'Vifaa, wataalamu na quotation moja iliyo wazi.'
                            : 'Equipment, professionals and one clear quotation.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                _title(sw ? 'Aina ya tukio' : 'Event types'),
                SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: types.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (_, i) => SizedBox(
                      width: 190,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            (sw ? types[i]['name_sw'] : types[i]['name_en'])
                                .toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _title(sw ? 'Vifaa vya kukodisha' : 'Equipment for rent'),
                if (equipment.isEmpty)
                  Text(
                    sw
                        ? 'Hakuna vifaa vilivyothibitishwa kwa sasa.'
                        : 'No verified equipment yet.',
                  )
                else
                  ...equipment.map(
                    (item) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.chair_alt_outlined),
                        title: Text(item['name'].toString()),
                        subtitle: Text(
                          '${sw ? 'Vilivyopo' : 'Stock'}: ${item['total_quantity']}',
                        ),
                        trailing: Text('TZS ${item['price_amount_tzs']}'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _IndividualEventDetailScreen(
                              repository: widget.repository,
                              kind: 'equipment',
                              id: item['id'].toString(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                _title(sw ? 'Wataalamu wa matukio' : 'Event professionals'),
                if (services.isEmpty)
                  Text(
                    sw
                        ? 'Hakuna wataalamu waliothibitishwa kwa sasa.'
                        : 'No verified professionals yet.',
                  )
                else
                  ...services.map((item) {
                    final offerings =
                        (item['event_service_offerings'] as List? ??
                                const <dynamic>[])
                            .cast<JsonMap>();
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(item['display_name'].toString()),
                        subtitle: Text(
                          item['provider_kind'].toString().replaceAll('_', ' '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: offerings.isEmpty
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _IndividualEventDetailScreen(
                                    repository: widget.repository,
                                    kind: 'service',
                                    id: offerings.first['id'].toString(),
                                  ),
                                ),
                              ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _title(String value) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      value,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  Future<void> _openPlanner(bool sw) async {
    JsonMap marketplace;
    try {
      marketplace = await _future;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final types = (marketplace['types'] as List? ?? const <dynamic>[])
        .cast<JsonMap>();
    if (types.isEmpty) return;
    String typeId = types.first['id'].toString();
    final title = TextEditingController();
    final location = TextEditingController();
    final attendance = TextEditingController();
    final budget = TextEditingController();
    EventLocationSelection? selectedLocation;
    DateTime start = DateTime.now().add(const Duration(days: 7));
    DateTime end = start.add(const Duration(hours: 5));
    final save = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (plannerContext) => StatefulBuilder(
          builder: (context, setPlannerState) => Scaffold(
            appBar: AppBar(title: Text(sw ? 'Panga tukio' : 'Plan an event')),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      sw
                          ? 'Weka taarifa za tukio lako kwa utaratibu. Unaweza kuchagua vifaa na huduma baada ya kuhifadhi.'
                          : 'Add your event details clearly. You can choose equipment and services after saving.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: typeId,
                      items: types
                          .map(
                            (type) => DropdownMenuItem(
                              value: type['id'].toString(),
                              child: Text(
                                (sw ? type['name_sw'] : type['name_en'])
                                    .toString(),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) typeId = value;
                      },
                    ),
                    TextField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: sw ? 'Jina la tukio' : 'Event name',
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text(
                          selectedLocation?.label ??
                              (sw
                                  ? 'Chagua eneo la tukio'
                                  : 'Choose event location'),
                        ),
                        subtitle: Text(
                          sw
                              ? 'Mkoa, wilaya, kata na eneo'
                              : 'Region, district, ward and area',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final value = await Navigator.of(context)
                              .push<EventLocationSelection>(
                                MaterialPageRoute(
                                  builder: (_) => EventLocationPicker(
                                    repository: widget.repository,
                                    swahili: sw,
                                    initialRegionId:
                                        selectedLocation?.regionId ??
                                        widget.initialRegionId,
                                    initialDistrictId:
                                        selectedLocation?.districtId ??
                                        widget.initialDistrictId,
                                    initialWardId:
                                        selectedLocation?.wardId ??
                                        widget.initialWardId,
                                    initialAreaId:
                                        selectedLocation?.areaId ??
                                        widget.initialAreaId,
                                  ),
                                ),
                              );
                          if (value != null) {
                            setPlannerState(() => selectedLocation = value);
                          }
                        },
                      ),
                    ),
                    TextField(
                      controller: attendance,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: sw ? 'Idadi ya wageni' : 'Attendance',
                      ),
                    ),
                    TextField(
                      controller: budget,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: sw ? 'Bajeti (TZS)' : 'Budget (TZS)',
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(sw ? 'Mwanzo' : 'Starts'),
                      subtitle: Text(start.toString()),
                      onTap: () async {
                        final value = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 1095),
                          ),
                          initialDate: start,
                        );
                        if (value != null) {
                          setPlannerState(() {
                            start = DateTime(
                              value.year,
                              value.month,
                              value.day,
                              10,
                            );
                            end = start.add(const Duration(hours: 5));
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(plannerContext, true),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        sw
                            ? 'Hifadhi na uchague huduma'
                            : 'Save and choose services',
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(plannerContext, false),
                      child: Text(sw ? 'Ghairi' : 'Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (save != true || !mounted) {
      title.dispose();
      location.dispose();
      attendance.dispose();
      budget.dispose();
      return;
    }
    if (selectedLocation?.locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sw
                ? 'Chagua eneo la tukio kwanza.'
                : 'Choose the event location first.',
          ),
        ),
      );
      title.dispose();
      location.dispose();
      attendance.dispose();
      budget.dispose();
      return;
    }
    try {
      final result = await widget.repository.createEventPlan(
        eventTypeId: typeId,
        startsAt: start,
        endsAt: end,
        locationId: selectedLocation!.locationId,
        locationDetails: null,
        attendance: int.parse(attendance.text),
        budgetTzs: double.tryParse(budget.text),
        title: title.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${sw ? 'Mpango umeanzishwa' : 'Event plan created'}: ${result['reference']}',
            ),
          ),
        );
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ChooseEventComponentsScreen(
              repository: widget.repository,
              planId: result['id'].toString(),
              marketplace: marketplace,
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    title.dispose();
    location.dispose();
    attendance.dispose();
    budget.dispose();
  }
}

class _ChooseEventComponentsScreen extends StatefulWidget {
  const _ChooseEventComponentsScreen({
    required this.repository,
    required this.planId,
    required this.marketplace,
  });
  final CustomerPublicRepository repository;
  final String planId;
  final JsonMap marketplace;
  @override
  State<_ChooseEventComponentsScreen> createState() =>
      _ChooseEventComponentsScreenState();
}

class _ChooseEventComponentsScreenState
    extends State<_ChooseEventComponentsScreen> {
  final Map<String, int> quantities = <String, int>{};
  final Set<String> providers = <String>{};
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    final equipment = (widget.marketplace['equipment'] as List? ?? <dynamic>[])
        .cast<JsonMap>();
    final services = (widget.marketplace['services'] as List? ?? <dynamic>[])
        .cast<JsonMap>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          sw ? 'Chagua mahitaji ya tukio' : 'Choose event components',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: <Widget>[
          Text(
            sw ? 'Vifaa na idadi' : 'Equipment and quantities',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          ...equipment.map((item) {
            final id = item['id'].toString();
            final quantity = quantities[id] ?? 0;
            final maximum = ((item['total_quantity'] as num?)?.toInt() ?? 1)
                .clamp(1, 999);
            return Card(
              child: ListTile(
                title: Text(item['name'].toString()),
                subtitle: Text(
                  'TZS ${item['price_amount_tzs']} · ${sw ? 'vilivyopo' : 'stock'} $maximum',
                ),
                trailing: quantity == 0
                    ? IconButton(
                        onPressed: () => setState(() => quantities[id] = 1),
                        icon: const Icon(Icons.add_circle_outline),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            onPressed: () => setState(() {
                              if (quantity <= 1) {
                                quantities.remove(id);
                              } else {
                                quantities[id] = quantity - 1;
                              }
                            }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$quantity',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            onPressed: quantity >= maximum
                                ? null
                                : () => setState(
                                    () => quantities[id] = quantity + 1,
                                  ),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
              ),
            );
          }),
          const SizedBox(height: 20),
          Text(
            sw ? 'Wataalamu' : 'Professionals',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          ...services.map((provider) {
            final id = provider['id'].toString();
            return CheckboxListTile(
              value: providers.contains(id),
              onChanged: (selected) => setState(() {
                if (selected == true) {
                  providers.add(id);
                } else {
                  providers.remove(id);
                }
              }),
              title: Text(provider['display_name'].toString()),
              subtitle: Text(
                provider['provider_kind'].toString().replaceAll('_', ' '),
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy ? null : _submit,
            child: Text(sw ? 'Tuma ombi la quotation' : 'Request quotation'),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final sw = context.isSwahili;
    if (quantities.isEmpty && providers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sw
                ? 'Chagua angalau kifaa au mtaalamu.'
                : 'Choose at least one item or professional.',
          ),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      for (final entry in quantities.entries) {
        await widget.repository.addEventPlanItem(
          planId: widget.planId,
          kind: 'equipment',
          equipmentId: entry.key,
          quantity: entry.value,
        );
      }
      final services = (widget.marketplace['services'] as List? ?? <dynamic>[])
          .cast<JsonMap>();
      for (final providerId in providers) {
        final provider = services.firstWhere(
          (row) => row['id'].toString() == providerId,
        );
        final offerings =
            (provider['event_service_offerings'] as List? ?? <dynamic>[])
                .cast<Map<String, dynamic>>();
        if (offerings.isNotEmpty) {
          await widget.repository.addEventPlanItem(
            planId: widget.planId,
            kind: 'service',
            offeringId: offerings.first['id'].toString(),
          );
        }
      }
      await widget.repository.requestEventQuote(widget.planId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sw ? 'Ombi la quotation limetumwa.' : 'Quotation request sent.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _MyEventPlansScreen extends StatefulWidget {
  const _MyEventPlansScreen({required this.repository});
  final CustomerPublicRepository repository;
  @override
  State<_MyEventPlansScreen> createState() => _MyEventPlansScreenState();
}

class _MyEventPlansScreenState extends State<_MyEventPlansScreen> {
  late Future<List<JsonMap>> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = widget.repository.fetchMyEventPlans();
  }

  void reload() =>
      setState(() => future = widget.repository.fetchMyEventPlans());
  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(sw ? 'Mipango yangu ya matukio' : 'My event plans'),
      ),
      body: FutureBuilder<List<JsonMap>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? <JsonMap>[];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                sw ? 'Bado huna mpango wa tukio.' : 'No event plans yet.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              reload();
              await future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: rows.map((plan) {
                final quotes =
                    (plan['event_quote_revisions'] as List? ?? <dynamic>[])
                        .cast<Map<String, dynamic>>();
                final sent = quotes
                    .where((quote) => quote['status'] == 'sent')
                    .firstOrNull;
                final agreements =
                    (plan['event_agreements'] as List? ?? <dynamic>[])
                        .cast<Map<String, dynamic>>();
                final agreement = agreements
                    .where((row) => row['status'] == 'sent')
                    .firstOrNull;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                (plan['title'] ?? plan['reference']).toString(),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Chip(
                              label: Text(
                                plan['status'].toString().replaceAll('_', ' '),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${plan['reference']} · ${sw ? 'Wageni' : 'Guests'} ${plan['attendance']}',
                        ),
                        if (sent != null) ...<Widget>[
                          const Divider(height: 28),
                          Text(
                            '${sw ? 'Quotation' : 'Quotation'} #${sent['revision']} · TZS ${sent['total_tzs']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => accept(sent['id'].toString()),
                            child: Text(
                              sw ? 'Kubali quotation' : 'Accept quotation',
                            ),
                          ),
                        ],
                        if (agreement != null) ...<Widget>[
                          const Divider(height: 28),
                          Text(
                            '${sw ? 'Makubaliano ya mwisho' : 'Final agreement'} · v${agreement['version']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(agreement['terms'].toString()),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => acceptAgreement(
                                    agreement['id'].toString(),
                                  ),
                            child: Text(
                              sw ? 'Kubali makubaliano' : 'Accept agreement',
                            ),
                          ),
                        ],
                        if (sent == null &&
                            agreement == null &&
                            plan['status'] != 'confirmed')
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              sw
                                  ? 'Quotation bado inaandaliwa.'
                                  : 'Quotation is being prepared.',
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Future<void> accept(String id) async {
    setState(() => busy = true);
    try {
      await widget.repository.acceptEventQuote(id);
      reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> acceptAgreement(String id) async {
    setState(() => busy = true);
    try {
      await widget.repository.acceptEventAgreement(id);
      reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _IndividualEventDetailScreen extends StatefulWidget {
  const _IndividualEventDetailScreen({
    required this.repository,
    required this.kind,
    required this.id,
  });
  final CustomerPublicRepository repository;
  final String kind;
  final String id;
  @override
  State<_IndividualEventDetailScreen> createState() =>
      _IndividualEventDetailScreenState();
}

class _IndividualBookingsHistoryScreen extends StatelessWidget {
  const _IndividualBookingsHistoryScreen({required this.repository});
  final CustomerPublicRepository repository;
  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Booking zangu' : 'My bookings')),
      body: FutureBuilder<List<JsonMap>>(
        future: repository.fetchMyIndividualEventBookings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? <JsonMap>[];
          if (rows.isEmpty) {
            return Center(
              child: Text(sw ? 'Bado huna booking.' : 'No bookings yet.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final item = row['event_plan_items'] as Map?;
              final equipment = item?['event_equipment_items'] as Map?;
              final offering = item?['event_service_offerings'] as Map?;
              final title =
                  equipment?['name'] ?? offering?['title'] ?? 'Event booking';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              row['status'].toString().replaceAll('_', ' '),
                            ),
                          ),
                        ],
                      ),
                      Text(row['reference'].toString()),
                      if (row['requested_quantity'] != null)
                        Text(
                          '${sw ? 'Idadi' : 'Quantity'}: ${row['requested_quantity']}',
                        ),
                      if (row['quoted_amount_tzs'] != null)
                        Text(
                          'TZS ${row['quoted_amount_tzs']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      Text(
                        '${sw ? 'Malipo' : 'Payment'}: ${row['payment_status'].toString().replaceAll('_', ' ')}',
                      ),
                      if (row['provider_response'] != null)
                        Text(row['provider_response'].toString()),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EventAdvisorScreen extends StatefulWidget {
  const _EventAdvisorScreen({
    required this.repository,
    this.initialRegionId,
    this.initialDistrictId,
    this.initialWardId,
    this.initialAreaId,
  });
  final CustomerPublicRepository repository;
  final String? initialRegionId,
      initialDistrictId,
      initialWardId,
      initialAreaId;
  @override
  State<_EventAdvisorScreen> createState() => _EventAdvisorScreenState();
}

class _EventAdvisorScreenState extends State<_EventAdvisorScreen> {
  late Future<List<JsonMap>> templatesFuture;
  final guests = TextEditingController();
  final budget = TextEditingController();
  final location = TextEditingController();
  final accessibility = TextEditingController();
  String? templateId;
  String setting = 'indoor';
  String venueStatus = 'needed';
  DateTime date = DateTime.now().add(const Duration(days: 30));
  bool busy = false;
  List<JsonMap> recommendations = <JsonMap>[];
  EventLocationSelection? selectedLocation;
  @override
  void initState() {
    super.initState();
    templatesFuture = widget.repository.fetchEventTemplates();
  }

  @override
  void dispose() {
    guests.dispose();
    budget.dispose();
    location.dispose();
    accessibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(title: const Text('Event Advisor')),
      body: FutureBuilder<List<JsonMap>>(
        future: templatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final templates = snapshot.data ?? <JsonMap>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                sw ? 'Tukusaidie kupanga' : 'Let us help you plan',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                sw
                    ? 'Mapendekezo yanatokana na template iliyothibitishwa. Bei na availability hazitabuniwa.'
                    : 'Recommendations come from approved templates. Prices and availability are never invented.',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: templateId,
                decoration: InputDecoration(
                  labelText: sw ? 'Aina ya mpango' : 'Planning template',
                ),
                items: templates
                    .map(
                      (row) => DropdownMenuItem(
                        value: row['id'].toString(),
                        child: Text(
                          (sw ? row['name_sw'] : row['name_en']).toString(),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => templateId = value),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(
                    selectedLocation?.label ??
                        (sw ? 'Chagua eneo la tukio' : 'Choose event location'),
                  ),
                  subtitle: Text(
                    sw
                        ? 'Mkoa, wilaya, kata na eneo'
                        : 'Region, district, ward and area',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final value = await Navigator.of(context)
                        .push<EventLocationSelection>(
                          MaterialPageRoute(
                            builder: (_) => EventLocationPicker(
                              repository: widget.repository,
                              swahili: sw,
                              initialRegionId:
                                  selectedLocation?.regionId ??
                                  widget.initialRegionId,
                              initialDistrictId:
                                  selectedLocation?.districtId ??
                                  widget.initialDistrictId,
                              initialWardId:
                                  selectedLocation?.wardId ??
                                  widget.initialWardId,
                              initialAreaId:
                                  selectedLocation?.areaId ??
                                  widget.initialAreaId,
                            ),
                          ),
                        );
                    if (value != null) setState(() => selectedLocation = value);
                  },
                ),
              ),
              TextField(
                controller: guests,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: sw ? 'Wageni' : 'Guests',
                ),
              ),
              TextField(
                controller: budget,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: sw ? 'Bajeti (TZS)' : 'Budget (TZS)',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: setting,
                decoration: InputDecoration(
                  labelText: sw ? 'Mpangilio' : 'Setting',
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                  DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => setting = value);
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: venueStatus,
                decoration: InputDecoration(
                  labelText: sw ? 'Hali ya venue' : 'Venue status',
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'needed',
                    child: Text('Need a venue'),
                  ),
                  DropdownMenuItem(
                    value: 'shortlisted',
                    child: Text('Shortlisted'),
                  ),
                  DropdownMenuItem(
                    value: 'booked_elsewhere',
                    child: Text('Already booked'),
                  ),
                  DropdownMenuItem(
                    value: 'booked_kodimali',
                    child: Text('Booked on KODIMALI'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => venueStatus = value);
                },
              ),
              TextField(
                controller: accessibility,
                decoration: InputDecoration(
                  labelText: sw
                      ? 'Accessibility na usalama'
                      : 'Accessibility and safety',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(sw ? 'Tarehe ya tukio' : 'Event date'),
                subtitle: Text(date.toString()),
                onTap: () async {
                  final next = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 1095)),
                    initialDate: date,
                  );
                  if (next != null) {
                    setState(
                      () =>
                          date = DateTime(next.year, next.month, next.day, 10),
                    );
                  }
                },
              ),
              FilledButton(
                onPressed: busy ? null : () => _run(templates),
                child: Text(
                  busy
                      ? (sw ? 'Inaandaa…' : 'Preparing…')
                      : (sw
                            ? 'Tengeneza mapendekezo'
                            : 'Create recommendations'),
                ),
              ),
              if (recommendations.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                Text(
                  sw ? 'Mapendekezo yako' : 'Your recommendations',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                ...recommendations.map(
                  (row) => Card(
                    child: ListTile(
                      title: Text(
                        (sw ? row['title_sw'] : row['title_en'])
                            .toString()
                            .replaceAll('_', ' '),
                      ),
                      subtitle: Text(
                        (sw ? row['reason_sw'] : row['reason_en']).toString(),
                      ),
                      trailing: row['suggested_quantity'] == null
                          ? null
                          : Chip(
                              label: Text(row['suggested_quantity'].toString()),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _run(List<JsonMap> templates) async {
    if (templateId == null ||
        int.tryParse(guests.text) == null ||
        selectedLocation?.locationId == null) {
      return;
    }
    setState(() => busy = true);
    try {
      final template = templates.firstWhere(
        (row) => row['id'].toString() == templateId,
      );
      final plan = await widget.repository.createEventPlan(
        eventTypeId: template['event_type_id']?.toString() ?? '',
        startsAt: date,
        endsAt: date.add(const Duration(hours: 6)),
        locationId: selectedLocation!.locationId,
        locationDetails: null,
        attendance: int.parse(guests.text),
        budgetTzs: double.tryParse(budget.text),
        title: 'Event Advisor plan',
      );
      final rows = await widget.repository.runEventAdvisor(
        planId: plan['id'].toString(),
        templateId: templateId!,
        setting: setting,
        venueStatus: venueStatus,
        accessibility: accessibility.text,
      );
      if (mounted) {
        setState(() => recommendations = rows);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
}

class _IndividualEventDetailScreenState
    extends State<_IndividualEventDetailScreen> {
  late Future<JsonMap> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = widget.repository.fetchIndividualEventDetail(
      kind: widget.kind,
      id: widget.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(sw ? 'Maelezo ya booking' : 'Booking details'),
      ),
      body: FutureBuilder<JsonMap>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final row = snapshot.data!;
          final provider = row['event_service_profiles'] as Map?;
          final title = (row['name'] ?? row['title']).toString();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: <Widget>[
              Container(
                height: 220,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFDDECE6), Color(0xFFB7D7CF)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  widget.kind == 'equipment'
                      ? Icons.chair_alt_outlined
                      : Icons.person_outline,
                  size: 72,
                  color: const Color(0xFF147D8C),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (provider != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${provider['display_name']} · ${provider['provider_kind'].toString().replaceAll('_', ' ')}',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                (row['description'] ?? provider?['biography'] ?? '').toString(),
              ),
              const SizedBox(height: 16),
              Text(
                row['price_amount_tzs'] == null
                    ? (sw ? 'Omba quotation' : 'Request quote')
                    : 'TZS ${row['price_amount_tzs']}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (widget.kind == 'equipment') ...<Widget>[
                _detail(
                  sw ? 'Idadi iliyopo' : 'Total stock',
                  row['total_quantity'],
                ),
                _detail(sw ? 'Eneo' : 'Location', row['public_location_label']),
                _detail(
                  sw ? 'Dhamana' : 'Security deposit',
                  row['security_deposit_tzs'],
                ),
                _detail(
                  sw ? 'Uharibifu na urejeshaji' : 'Damage and return',
                  row['damage_rules'] ?? row['return_procedure'],
                ),
              ] else ...<Widget>[
                _detail(
                  sw ? 'Muda wa huduma' : 'Duration',
                  row['duration_minutes'],
                ),
                _detail(
                  sw ? 'Vifaa vinavyojumuishwa' : 'Included equipment',
                  row['included_equipment'],
                ),
                _detail(
                  sw ? 'Mahitaji maalum' : 'Special requirements',
                  row['requirements'],
                ),
              ],
              _detail(
                sw ? 'Kughairi' : 'Cancellation',
                row['cancellation_policy'],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : () => _request(row),
                icon: const Icon(Icons.event_available_outlined),
                label: Text(sw ? 'Tuma ombi la booking' : 'Request booking'),
              ),
              const SizedBox(height: 10),
              Text(
                sw
                    ? 'Mtoa huduma atathibitisha upatikanaji. Malipo ya mtandaoni hayajawashwa.'
                    : 'The provider will confirm availability. Online collection is not enabled.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detail(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value?.toString() ?? '—'),
      ],
    ),
  );

  Future<void> _request(JsonMap row) async {
    final sw = context.isSwahili;
    DateTime start = DateTime.now().add(const Duration(days: 7));
    DateTime end = start.add(
      Duration(hours: widget.kind == 'equipment' ? 8 : 3),
    );
    final quantity = TextEditingController(text: '1');
    final notes = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(sw ? 'Ombi la booking' : 'Booking request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(sw ? 'Tarehe ya kuanza' : 'Start date'),
                  subtitle: Text(start.toString()),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 1095)),
                      initialDate: start,
                    );
                    if (value != null) {
                      setDialogState(() {
                        start = DateTime(value.year, value.month, value.day, 9);
                        end = start.add(
                          Duration(hours: widget.kind == 'equipment' ? 8 : 3),
                        );
                      });
                    }
                  },
                ),
                if (widget.kind == 'equipment')
                  TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: sw ? 'Idadi' : 'Quantity',
                    ),
                  ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: sw ? 'Maelezo ya ombi' : 'Request notes',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
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
      ),
    );
    if (accepted == true) {
      setState(() => busy = true);
      try {
        final booking = await widget.repository.createIndividualEventBooking(
          kind: widget.kind,
          id: widget.id,
          startsAt: start,
          endsAt: end,
          quantity: widget.kind == 'equipment'
              ? int.parse(quantity.text)
              : null,
          message: notes.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${sw ? 'Ombi limetumwa' : 'Request sent'}: ${booking['reference']}',
              ),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      } finally {
        if (mounted) {
          setState(() => busy = false);
        }
      }
    }
    quantity.dispose();
    notes.dispose();
  }
}
