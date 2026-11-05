import 'package:flutter/material.dart';
import 'package:flutter_core/localized_ui.dart';
import 'app_scope.dart';
import '../utils/user_facing_error.dart';

/// Browses geography independently of result pagination. Selecting a folder
/// never guesses a location from a public label.
class LocationDirectory extends StatefulWidget {
  const LocationDirectory({
    super.key,
    required this.onView,
    this.label = 'View listings here',
    this.allowAllLocations = true,
  });
  final ValueChanged<Map<String, dynamic>?> onView;
  final String label;
  final bool allowAllLocations;
  @override
  State<LocationDirectory> createState() => _LocationDirectoryState();
}

class _LocationDirectoryState extends State<LocationDirectory> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _path = [];
  List<Map<String, dynamic>> _children = [];
  bool _ready = false, _busy = false, _more = false;
  int _offset = 0, _request = 0;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      _ready = true;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int offset = 0}) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = AppScope.of(context).repository;
      if (_path.isEmpty) _path = [await repo.fetchLocationCountryForAdmin()];
      final rows = await repo.fetchLocationChildren(
        parentId: _path.last['id'] as String,
        search: _search.text.trim(),
        offset: offset,
        limit: 30,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _children = rows;
        _offset = offset;
        _more = rows.length == 30;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = userFacingError(error);
        });
      }
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _open(Map<String, dynamic> row) {
    _path = [..._path, row];
    _search.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalizedUiText(
            'Browse by location',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: _path
                .asMap()
                .entries
                .map(
                  (entry) => TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _path = _path.take(entry.key + 1).toList();
                            _search.clear();
                            _load();
                          },
                    child: Text(entry.value['name'].toString()),
                  ),
                )
                .toList(),
          ),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: mobileUi(context, 'Find a location'),
              suffixIcon: IconButton(
                onPressed: _busy ? null : () => _load(),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          FilledButton.icon(
            onPressed:
                _busy ||
                    _path.isEmpty ||
                    (!widget.allowAllLocations &&
                        _path.last['location_type'] == 'country')
                ? null
                : () => widget.onView(
                    _path.last['location_type'] == 'country'
                        ? null
                        : Map.of(_path.last),
                  ),
            icon: const Icon(Icons.manage_search),
            label: LocalizedUiText(widget.label),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: () => _load(),
              child: const LocalizedUiText('Retry'),
            ),
          ],
          if (!_busy && _error == null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                primary: false,
                shrinkWrap: true,
                children: [
                  ..._children.map(
                    (row) => ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(row['name'].toString()),
                      subtitle: LocalizedUiText(
                        row['location_type'].toString(),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(row),
                    ),
                  ),
                ],
              ),
            ),
            if (_children.isEmpty)
              const LocalizedUiText(
                'No smaller locations found. View results at this level.',
              ),
            Row(
              children: [
                if (_offset > 0)
                  TextButton(
                    onPressed: () => _load(offset: _offset - 30),
                    child: const LocalizedUiText('Previous'),
                  ),
                if (_more)
                  TextButton(
                    onPressed: () => _load(offset: _offset + 30),
                    child: const LocalizedUiText('Next'),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
