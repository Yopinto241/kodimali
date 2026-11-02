import 'package:flutter/material.dart';
import 'package:flutter_core/localized_ui.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/utils/user_facing_error.dart';

class SupervisorManagementScreen extends StatefulWidget {
  const SupervisorManagementScreen({super.key});
  @override
  State<SupervisorManagementScreen> createState() =>
      _SupervisorManagementState();
}

class _SupervisorManagementState extends State<SupervisorManagementScreen> {
  final _email = TextEditingController();
  String? _location;
  bool _busy = false;
  String _notice = '';
  Future<List<Map<String, dynamic>>>? _directory;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _directory ??= AppScope.of(context).repository.fetchSupervisorDirectory();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save(String email, String location, bool active) async {
    setState(() {
      _busy = true;
      _notice = '';
    });
    try {
      await AppScope.of(
        context,
      ).repository.configureSupervisorTerritory(email, location, active);
      if (!mounted) return;
      setState(() {
        _notice = 'Supervisor territory saved.';
        _directory = AppScope.of(context).repository.fetchSupervisorDirectory();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = userFacingError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedUiText('Supervisors and territories')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const LocalizedUiText(
          'Only Super Admin assigns locations and transfers agents. Each agent belongs to one supervisor.',
        ),
        const SizedBox(height: 12),
        const LocalizedUiText(
          'Register as an agent first. Super Admin then appoints you as a supervisor and assigns your territory. Sign in again and open Manage > Agents to supervise your team.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          onChanged: (_) {
            setState(() {});
          },
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: mobileUi(context, 'Registered agent email'),
          ),
        ),
        const SizedBox(height: 12),
        SupervisorLocationPicker(
          onChanged: (id) {
            setState(() {
              _location = id;
            });
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy || _location == null || _email.text.trim().isEmpty
              ? null
              : () => _save(_email.text, _location!, true),
          child: const LocalizedUiText('Assign supervisor territory'),
        ),
        if (_notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: LocalizedUiText(_notice),
          ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _directory,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return LocalizedUiText(userFacingError(snapshot.error!));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: snapshot.data!
                  .map(
                    (row) => Card(
                      child: ListTile(
                        title: Text(
                          (row['full_name'] ?? row['account_email']).toString(),
                        ),
                        subtitle: Text(
                          '${row['location_name'] ?? '—'} · ${row['agent_count']}',
                        ),
                        trailing: row['location_id'] == null
                            ? const LocalizedUiText('Unassigned')
                            : TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _save(
                                        row['account_email'].toString(),
                                        row['location_id'].toString(),
                                        row['is_active'] != true,
                                      ),
                                child: LocalizedUiText(
                                  row['is_active'] == true
                                      ? 'Deactivate'
                                      : 'Activate',
                                ),
                              ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}

class SupervisorLocationPicker extends StatefulWidget {
  const SupervisorLocationPicker({super.key, required this.onChanged});
  final ValueChanged<String?> onChanged;
  @override
  State<SupervisorLocationPicker> createState() =>
      _SupervisorLocationPickerState();
}

class _SupervisorLocationPickerState extends State<SupervisorLocationPicker> {
  List<Map<String, dynamic>> _path = [];
  List<Map<String, dynamic>> _children = [];
  bool _initialized = false;
  bool _loading = false;
  String? _error;
  int _offset = 0;
  bool _hasMore = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load(null);
    }
  }

  Future<void> _load(Map<String, dynamic>? parent, {int offset = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AppScope.of(context).repository.fetchLocationChildren(
        parentId: parent?['id'] as String?,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _children = rows.where((row) => row['is_active'] == true).toList();
        _offset = offset;
        _hasMore = rows.length == 20;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = userFacingError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _choose(Map<String, dynamic> row, int? index) {
    setState(() {
      _path = index == null ? [..._path, row] : _path.take(index + 1).toList();
    });
    widget.onChanged(
      row['location_type'] == 'country' ? null : row['id'] as String,
    );
    _load(row);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LocalizedUiText('Supervisor territory'),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () {
              setState(() {
                _path = [];
              });
              widget.onChanged(null);
              _load(null);
            },
            child: const LocalizedUiText('Reset'),
          ),
          ..._path.asMap().entries.map(
            (entry) => TextButton(
              onPressed: () => _choose(entry.value, entry.key),
              child: Text(entry.value['name'].toString()),
            ),
          ),
        ],
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) LocalizedUiText(_error!),
      if (!_loading && _children.isNotEmpty)
        DropdownButtonFormField<String>(
          key: ValueKey('${_path.lastOrNull?['id']}:$_offset'),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: mobileUi(context, 'Choose location'),
          ),
          items: _children
              .map(
                (row) => DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(row['name'].toString()),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id != null) {
              _choose(_children.firstWhere((row) => row['id'] == id), null);
            }
          },
        ),
      Wrap(
        children: [
          if (_offset > 0)
            TextButton(
              onPressed: () => _load(_path.lastOrNull, offset: _offset - 20),
              child: const LocalizedUiText('Previous'),
            ),
          if (_hasMore)
            TextButton(
              onPressed: () => _load(_path.lastOrNull, offset: _offset + 20),
              child: const LocalizedUiText('Next'),
            ),
        ],
      ),
    ],
  );
}

class AgentSupervisorAssignment extends StatelessWidget {
  const AgentSupervisorAssignment({
    super.key,
    required this.agentId,
    required this.onSaved,
  });
  final String agentId;
  final Future<void> Function() onSaved;
  Future<void> _assign(BuildContext context) async {
    final repository = AppScope.of(context).repository;
    try {
      final directory = await repository.fetchSupervisorDirectory();
      final current = await repository.fetchAgentSupervisor(agentId);
      if (!context.mounted) return;
      String selected = current ?? '';
      bool busy = false;
      String? error;
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const LocalizedUiText('Assigned supervisor'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LocalizedUiText(
                  'Transfer this agent? The previous supervisor will lose access immediately.',
                ),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: LocalizedUiText('Unassigned'),
                    ),
                    ...directory
                        .where(
                          (row) =>
                              row['is_active'] == true ||
                              row['supervisor_id'] == current,
                        )
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['supervisor_id'] as String,
                            child: Text(
                              '${row['full_name']} · ${row['location_name']}',
                            ),
                          ),
                        ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          selected = value ?? '';
                        },
                ),
                if (error != null) LocalizedUiText(error!),
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const LocalizedUiText('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        update(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await repository.assignAgentSupervisor(
                            agentId,
                            selected.isEmpty ? null : selected,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (failure) {
                          if (dialogContext.mounted) {
                            update(() {
                              error = userFacingError(failure);
                              busy = false;
                            });
                          }
                        }
                      },
                child: const LocalizedUiText('Save agent team'),
              ),
            ],
          ),
        ),
      );
      if (saved == true) await onSaved();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedUiText(userFacingError(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _assign(context),
    icon: const Icon(Icons.supervisor_account),
    label: const LocalizedUiText('Assigned supervisor'),
  );
}
