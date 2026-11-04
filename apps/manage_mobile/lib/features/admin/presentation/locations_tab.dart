import 'package:flutter/material.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:shared_models/shared_models.dart';
import '../../../core/data/manage_repository.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/utils/user_facing_error.dart';

class LocationsTab extends StatefulWidget {
  const LocationsTab({super.key, this.ancestors = const [], this.repository});
  final List<Map<String, dynamic>> ancestors;
  final ManageRepository? repository;
  @override
  State<LocationsTab> createState() => _LocationsTabState();
}

class _LocationsTabState extends State<LocationsTab> {
  final _search = TextEditingController();
  Future<List<Map<String, dynamic>>>? _future;
  int _page = 0;
  Map<String, dynamic>? _country;
  List<Map<String, dynamic>> get _trail => widget.ancestors.isNotEmpty
      ? widget.ancestors
      : _country == null
      ? []
      : [_country!];
  bool _busy = false;
  ManageRepository get _repository =>
      widget.repository ?? AppScope.of(context).repository;
  Map<String, dynamic>? get _parent => _trail.lastOrNull;
  static const _children = {
    'country': 'region',
    'region': 'district',
    'district': 'ward',
    'ward': 'area',
    'area': 'street',
  };
  String? get _childType =>
      _parent == null ? null : _children[_parent!['location_type']];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _bootstrap() async {
    if (widget.ancestors.isEmpty) {
      _country = await _repository.fetchLocationCountryForAdmin();
    }
    return _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      _repository.fetchLocationChildren(
        parentId: _parent?['id']?.toString(),
        search: _search.text,
        offset: _page * 20,
      );
  Future<void> _refresh() async {
    setState(() {
      _future = _country == null && widget.ancestors.isEmpty
          ? _bootstrap()
          : _load();
    });
    await _future;
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    String name = row?['name']?.toString() ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedUiText(row == null ? 'Add location' : 'Edit location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${mobileUi(context, 'Parent')}: ${_parent?['name'] ?? mobileUi(context, 'No parent')}',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: name,
                onChanged: (value) => name = value,
                autofocus: true,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Location name'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name.trim());
            },
            child: const LocalizedUiText('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      if (row == null) {
        await _repository.addLocation(
          name: value,
          type: LocationType.values.firstWhere(
            (type) => type.name == _childType,
          ),
          parentId: _parent?['id']?.toString(),
        );
      } else {
        await _repository.renameLocation(id: row['id'].toString(), name: value);
      }
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: LocalizedUiText(userFacingError(error))));
  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedUiText('Delete location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row['name'].toString()),
            const SizedBox(height: 12),
            const LocalizedUiText('Referenced locations cannot be deleted.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedUiText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedUiText('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await _repository.deleteLocation(row['id'].toString());
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  const LocalizedUiText('Locations'),
                  ..._trail.map(
                    (row) => TextButton(
                      onPressed: row == _parent
                          ? null
                          : () => Navigator.of(context).popUntil(
                              (route) =>
                                  route.settings.name ==
                                      'manage-location:${row['id']}' ||
                                  route.isFirst,
                            ),
                      child: Text(row['name'].toString()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _parent?['name']?.toString() ?? mobileUi(context, 'Locations'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  _page = 0;
                  _refresh();
                },
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Search locations'),
                  suffixIcon: IconButton(
                    tooltip: mobileUi(context, 'Search'),
                    onPressed: () {
                      _page = 0;
                      _refresh();
                    },
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_childType != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.add),
                    label: Text(
                      '${mobileUi(context, 'Add')} ${mobileUi(context, _childType!)}',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                KodimaliLoading(label: mobileUi(context, 'Loading...'))
              else if (snapshot.hasError)
                Column(
                  children: [
                    Text(userFacingError(snapshot.error!)),
                    TextButton(
                      onPressed: _refresh,
                      child: const LocalizedUiText('Retry'),
                    ),
                  ],
                )
              else if (rows.isEmpty)
                const LocalizedUiText('No locations found.')
              else
                ...rows.map(
                  (row) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(row['name'].toString()),
                            subtitle: Text(
                              '${mobileUi(context, row['location_type'].toString())} · ${mobileUi(context, row['is_active'] == true ? 'Active' : 'Inactive')}',
                            ),
                            trailing:
                                _children.containsKey(row['location_type'])
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: !_children.containsKey(row['location_type'])
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      settings: RouteSettings(
                                        name: 'manage-location:${row['id']}',
                                      ),
                                      builder: (_) => LocationsTab(
                                        ancestors: [..._trail, row],
                                        repository: _repository,
                                      ),
                                    ),
                                  ),
                          ),
                          Wrap(
                            spacing: 12,
                            children: [
                              OutlinedButton(
                                onPressed: _busy ? null : () => _edit(row),
                                child: const LocalizedUiText('Edit'),
                              ),
                              TextButton(
                                onPressed: _busy ? null : () => _delete(row),
                                child: const LocalizedUiText('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!snapshot.hasError &&
                  snapshot.connectionState == ConnectionState.done)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _page == 0
                          ? null
                          : () {
                              _page--;
                              _refresh();
                            },
                      child: const LocalizedUiText('Previous'),
                    ),
                    TextButton(
                      onPressed: rows.length < 20
                          ? null
                          : () {
                              _page++;
                              _refresh();
                            },
                      child: const LocalizedUiText('Next'),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
    return widget.ancestors.isEmpty
        ? body
        : Scaffold(
            appBar: AppBar(title: Text(_parent!['name'].toString())),
            body: SafeArea(child: body),
          );
  }
}
