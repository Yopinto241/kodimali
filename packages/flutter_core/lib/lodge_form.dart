import 'lodge_photos.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'lodge_api.dart';
import 'lodge_forms.dart';
import 'localized_ui.dart';
import 'lodge_errors.dart';

class LodgeFormScreen extends StatefulWidget {
  const LodgeFormScreen({
    super.key,
    required this.api,
    required this.action,
    this.lodgeId,
    this.initial = const {},
    this.uploadPhotos,
  });
  final LodgeApi api;
  final String action;
  final String? lodgeId;
  final LodgeRow initial;
  final Future<List<String>> Function()? uploadPhotos;
  @override
  State<LodgeFormScreen> createState() => _LodgeFormScreenState();
}

class _LodgeFormScreenState extends State<LodgeFormScreen> {
  final _form = GlobalKey<FormState>();
  final String _requestId = const Uuid().v4();
  final Map<String, TextEditingController> _controllers = {};
  final LodgeRow _values = {};
  List<LodgeRow> _rooms = [], _bookings = [];
  List<String> _photos = [];
  bool _busy = false, _loading = false;
  String? _error;
  List<LodgeRow> get _fields =>
      ((lodgeDefinitions['forms'] as Map)[widget.action] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .where(
            (f) =>
                widget.action != 'reservation_update' ||
                widget.initial['accepted_at'] == null ||
                ![
                  'arrival',
                  'departure',
                  'total_amount',
                  'status',
                  'guests',
                ].contains(f['name']),
          )
          .toList();
  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      final name = field['name'] as String;
      final value = widget.initial[name];
      if ([
        'checkbox',
        'rooms',
        'permissions',
        'select',
        'room',
        'reservation',
        'location',
      ].contains(field['type'])) {
        _values[name] =
            value ??
            (field['type'] == 'checkbox'
                ? false
                : field['type'] == 'rooms' || field['type'] == 'permissions'
                ? <String>[]
                : (field['options'] as List?)?.first);
      } else {
        _controllers[name] = TextEditingController(
          text: value is List ? value.join(', ') : value?.toString() ?? '',
        );
      }
    }
    _photos = widget.action == 'save_room_type'
        ? (widget.initial['main_image'] == null
              ? []
              : [widget.initial['main_image'].toString()])
        : (widget.initial['photos'] as List? ?? []).cast<String>().toList();
    if ([
      'reserve',
      'reservation_update',
      'record_payment',
      'save_room',
      'enquire',
    ].contains(widget.action)) {
      _loadOptions();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions({bool more = false}) async {
    setState(() => _loading = true);
    try {
      if (widget.action == 'enquire') {
        final result = await widget.api.discover(id: widget.lodgeId);
        final lodges = result['rows'] as List? ?? [];
        if (mounted) {
          setState(() {
            _rooms = lodges.isEmpty
                ? []
                : List<LodgeRow>.from(
                    (lodges.first as Map)['room_types'] as List? ?? [],
                  );
            _loading = false;
          });
        }
        return;
      }
      final payments = widget.action == 'record_payment';
      final options = await widget.api.workspace(
        lodgeId: widget.lodgeId,
        section: ['save_room', 'enquire'].contains(widget.action)
            ? 'room-types'
            : payments
            ? 'reservations'
            : 'rooms',
        limit: 100,
        offset: more ? (payments ? _bookings.length : _rooms.length) : 0,
        start: payments
            ? DateTime.now()
                  .subtract(const Duration(days: 365))
                  .toIso8601String()
                  .split('T')
                  .first
            : null,
        end: payments
            ? DateTime.now()
                  .add(const Duration(days: 365))
                  .toIso8601String()
                  .split('T')
                  .first
            : null,
      );
      if (!mounted) return;
      final rows = (options['rows'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      setState(() {
        if (payments) {
          _bookings = more ? [..._bookings, ...rows] : rows;
        } else {
          _rooms = more ? [..._rooms, ...rows] : rows;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = lodgeUserMessage(
            e,
            language: Localizations.localeOf(context).languageCode,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{'request_id': _requestId};
      for (final field in _fields) {
        final name = field['name'] as String, type = field['type'];
        if (_controllers.containsKey(name)) {
          final text = _controllers[name]!.text.trim();
          if (text.isNotEmpty || type == 'array') {
            body[name] = type == 'array'
                ? text
                      .split(',')
                      .map((x) => x.trim())
                      .where((x) => x.isNotEmpty)
                      .toList()
                : type == 'number'
                ? num.parse(text)
                : type == 'datetime-local'
                ? DateTime.parse(text).toUtc().toIso8601String()
                : text;
          }
        } else if (_values[name] != null) {
          if (name == 'permissions' && (_values[name] as List).isEmpty) {
            continue;
          }
          body[name] = _values[name];
        }
      }
      if (body['arrival'] != null &&
          body['departure'] != null &&
          !DateTime.parse(
            body['departure'].toString(),
          ).isAfter(DateTime.parse(body['arrival'].toString()))) {
        throw const FormatException('Invalid arrival and departure dates');
      }
      if (widget.initial['id'] != null) body['id'] = widget.initial['id'];
      if (widget.action == 'set_staff') {
        body['profile_id'] = widget.initial['profile_id'];
      }
      if (['settings'].contains(widget.action)) {
        body['photos'] = _photos;
      }
      dynamic result;
      if (widget.action == 'save_room_type') {
        body['main_image'] = _photos.isEmpty ? null : _photos.first;
      }
      if (widget.action == 'register') {
        result = await widget.api.register(body);
      } else if (widget.action == 'enquire') {
        result = await widget.api.enquire(widget.lodgeId!, body);
      } else {
        result = await widget.api.command(widget.lodgeId!, widget.action, body);
      }
      if (mounted) Navigator.of(context).pop(result ?? true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = lodgeUserMessage(
            e,
            language: Localizations.localeOf(context).languageCode,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseRooms(String name, bool multiple) async {
    var selected = multiple
        ? List<String>.from(_values[name] as List? ?? [])
        : <String>[if (_values[name] != null) _values[name].toString()];
    final options = name == 'reservation_id' ? _bookings : _rooms;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: LocalizedUiText(multiple ? 'Rooms' : 'Select'),
          content: SizedBox(
            width: 440,
            height: 360,
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (context, i) {
                final row = options[i];
                final id = row['id'].toString();
                return CheckboxListTile(
                  value: selected.contains(id),
                  title: Text(
                    '${row['code']} / ${row['room_type'] ?? row['full_name'] ?? ''}',
                  ),
                  subtitle: Text(
                    '${row['arrival'] ?? row['currency'] ?? ''} ${row['nightly_rate'] ?? ''}',
                  ),
                  onChanged: (value) => setLocal(() {
                    if (!multiple) selected = [];
                    if (value == true) {
                      selected.add(id);
                    } else {
                      selected.remove(id);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LocalizedUiText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const LocalizedUiText('Select'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _values[name] = multiple ? result : result.firstOrNull);
    }
  }

  String _selectionLabel(String name) {
    final ids = _values[name] is List
        ? List<String>.from(_values[name] as List)
        : <String>[if (_values[name] != null) _values[name].toString()];
    final options = name == 'reservation_id' ? _bookings : _rooms;
    final selected = options
        .where((r) => ids.contains(r['id'].toString()))
        .map((r) => '${r['code']} ${r['full_name'] ?? r['room_type'] ?? ''}')
        .join(', ');
    return selected.isNotEmpty
        ? selected
        : '${mobileUi(context, 'Select')} (${ids.length})';
  }

  Widget _field(LodgeRow f) {
    final name = f['name'] as String, type = f['type'];
    final label = mobileUi(context, f['label'] as String);
    final required = f['required'] == true;
    if (type == 'location') {
      return LodgeLocationSearch(
        api: widget.api,
        initialId: widget.initial['location_id']?.toString(),
        required: required,
        onSelected: (id, label) {
          _values[name] = id;
          _controllers['location_label']?.text = label;
        },
      );
    }
    if (type == 'checkbox') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: _values[name] == true,
        onChanged: _busy ? null : (v) => setState(() => _values[name] = v),
      );
    }
    if (type == 'permissions') {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Wrap(
          spacing: 6,
          children: (lodgeDefinitions['permissions'] as List)
              .map(
                (p) => FilterChip(
                  label: LocalizedUiText(
                    (lodgeDefinitions['permissionLabels'] as Map)[p]
                            ?.toString() ??
                        p.toString(),
                  ),
                  selected: (_values[name] as List? ?? []).contains(p),
                  onSelected: (yes) => setState(() {
                    final a = List<String>.from(_values[name] as List? ?? []);
                    yes ? a.add(p.toString()) : a.remove(p);
                    _values[name] = a;
                  }),
                ),
              )
              .toList(),
        ),
      );
    }
    if (type == 'room_type') {
      return DropdownButtonFormField<String>(
        initialValue: _controllers[name]?.text.isEmpty == false
            ? _controllers[name]!.text
            : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: _rooms
            .map(
              (r) => DropdownMenuItem(
                value: r['id'].toString(),
                child: Text((r['name'] ?? r['room_type']).toString()),
              ),
            )
            .toList(),
        validator: (v) => required && v == null ? 'Select a room type' : null,
        onChanged: (v) {
          _controllers[name]?.text = v ?? '';
        },
      );
    }
    if (['rooms', 'room', 'reservation'].contains(type)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormField<dynamic>(
            validator: (_) =>
                required &&
                    (_values[name] == null ||
                        (_values[name] is List &&
                            (_values[name] as List).isEmpty))
                ? 'Select a room or reservation'
                : null,
            builder: (field) => InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                errorText: field.errorText,
              ),
              child: TextButton(
                onPressed: _loading || _busy
                    ? null
                    : () => _chooseRooms(name, type == 'rooms'),
                child: Text(_selectionLabel(name)),
              ),
            ),
          ),
          TextButton(
            onPressed: _loading ? null : () => _loadOptions(more: true),
            child: const LocalizedUiText('Load more'),
          ),
        ],
      );
    }
    if (type == 'select') {
      return DropdownButtonFormField<String>(
        initialValue: _values[name]?.toString(),
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: (f['options'] as List)
            .map(
              (v) => DropdownMenuItem(
                value: v.toString(),
                child: LocalizedUiText(v.toString().replaceAll('_', ' ')),
              ),
            )
            .toList(),
        onChanged: _busy ? null : (v) => setState(() => _values[name] = v),
      );
    }
    return TextFormField(
      controller: _controllers[name],
      enabled: !_busy,
      readOnly: type == 'date',
      maxLines: type == 'textarea' ? 3 : 1,
      keyboardType: type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : type == 'email'
          ? TextInputType.emailAddress
          : type == 'tel'
          ? TextInputType.phone
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: type == 'array'
            ? mobileUi(context, 'Separate with commas')
            : type == 'datetime-local'
            ? 'YYYY-MM-DDTHH:mm'
            : null,
        suffixIcon: type == 'date'
            ? const Icon(Icons.calendar_month_outlined)
            : null,
      ),
      onTap: type == 'date'
          ? () async {
              final date = await showDatePicker(
                context: context,
                initialDate:
                    DateTime.tryParse(_controllers[name]!.text) ??
                    DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 730)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (date != null && mounted) {
                _controllers[name]!.text = date
                    .toIso8601String()
                    .split('T')
                    .first;
              }
            }
          : null,
      validator: (text) {
        if (required && (text ?? '').trim().isEmpty) {
          return mobileUi(context, 'Required');
        }
        if (type == 'number' &&
            text!.isNotEmpty &&
            (num.tryParse(text) == null || num.parse(text) < 0)) {
          return mobileUi(context, 'Enter a valid amount');
        }
        if (type == 'datetime-local' &&
            text!.isNotEmpty &&
            DateTime.tryParse(text) == null) {
          return mobileUi(context, 'Enter a valid date');
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LocalizedUiText(
        (lodgeDefinitions['titles'] as Map)[widget.action]?.toString() ??
            widget.action.replaceAll('_', ' '),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.initial['lodge_timezone'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${mobileUi(context, 'Dates use the lodge timezone')}: ${widget.initial['lodge_timezone']}. ${mobileUi(context, 'Departure date is not included.')}',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading)
            const SizedBox(height: 90, child: KodimaliLoading(size: 36)),
          for (final field in _fields)
            Padding(
              key: ValueKey(field['name']),
              padding: const EdgeInsets.only(bottom: 18),
              child: _field(field),
            ),
          if (widget.uploadPhotos != null &&
              ['save_room_type', 'settings'].contains(widget.action)) ...[
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        final files = await widget.uploadPhotos!();
                        if (mounted) {
                          setState(
                            () => _photos = widget.action == 'save_room_type'
                                ? files.take(1).toList()
                                : [..._photos, ...files],
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(
                            () => _error = lodgeUserMessage(
                              e,
                              language: Localizations.localeOf(
                                context,
                              ).languageCode,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const LocalizedUiText('Add photos'),
            ),
            LodgePhotoPreview(api: widget.api, paths: _photos),
            Wrap(
              children: [
                for (final path in _photos)
                  InputChip(
                    label: Text(
                      '${mobileUi(context, 'Photo')} ${_photos.indexOf(path) + 1}',
                    ),
                    onDeleted: _busy
                        ? null
                        : () => setState(() => _photos.remove(path)),
                  ),
              ],
            ),
          ],
          FilledButton(
            onPressed: _busy || _loading ? null : _submit,
            child: LocalizedUiText(_busy ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

class LodgeLocationSearch extends StatefulWidget {
  const LodgeLocationSearch({
    super.key,
    required this.api,
    required this.onSelected,
    this.initialId,
    this.required = false,
  });
  final LodgeApi api;
  final String? initialId;
  final bool required;
  final void Function(String? id, String label) onSelected;
  @override
  State<LodgeLocationSearch> createState() => _LodgeLocationSearchState();
}

class _LodgeLocationSearchState extends State<LodgeLocationSearch> {
  String? _selected;
  String _label = '';
  List<LodgeRow> _options = [];
  int _request = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _selected = widget.initialId;
  }

  Future<void> _search(String text) async {
    final request = ++_request;
    _selected = null;
    widget.onSelected(null, '');
    if (text.trim().length < 2) {
      setState(() => _options = []);
      return;
    }
    try {
      final options = await widget.api.locations(text);
      if (mounted && request == _request) {
        setState(() {
          _options = options;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(
          () => _error = lodgeUserMessage(
            e,
            language: Localizations.localeOf(context).languageCode,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        decoration: InputDecoration(
          labelText: mobileUi(context, 'Search location'),
          helperText: _selected != null
              ? (_label.isEmpty
                    ? mobileUi(context, 'Saved location selected')
                    : _label)
              : mobileUi(context, 'Type at least two letters'),
          errorText: _error,
        ),
        onChanged: _search,
        validator: (_) => widget.required && _selected == null
            ? mobileUi(context, 'Select a location')
            : null,
      ),
      for (final option in _options)
        ListTile(
          title: Text(option['label'].toString()),
          subtitle: LocalizedUiText(option['location_type'].toString()),
          onTap: () {
            setState(() {
              _selected = option['location_id'].toString();
              _label = option['label'].toString();
              _options = [];
            });
            widget.onSelected(_selected, _label);
          },
        ),
      if (!widget.required && _selected != null)
        TextButton(
          onPressed: () {
            setState(() => _selected = null);
            widget.onSelected(null, '');
          },
          child: const LocalizedUiText('Clear location'),
        ),
    ],
  );
}
