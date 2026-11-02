import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/data/manage_repository.dart';
import '../../../core/widgets/kodimali_empty_state.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key, this.repository});
  final ManageRepository? repository;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final TextEditingController _search = TextEditingController();
  Future<List<Map<String, dynamic>>>? _users;
  int _page = 0;
  String? _confirmation;
  Future<List<Map<String, dynamic>>> _load() =>
      (widget.repository ?? AppScope.of(context).repository)
          .fetchAdminCustomerUsers(
            limit: 20,
            offset: _page * 20,
            search: _search.text,
            confirmation: _confirmation,
          );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _users ??= _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() {
      _users = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return KodimaliLoading(label: mobileUi(context, 'Loading...'));
          }
          if (snapshot.hasError) {
            return ListView(
              children: <Widget>[
                KodimaliEmptyState(
                  title: mobileUi(context, 'Users could not load'),
                  message: userFacingError(snapshot.error!),
                  action: FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const LocalizedUiText('Retry'),
                  ),
                ),
              ],
            );
          }
          final users = snapshot.data ?? <Map<String, dynamic>>[];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: KodimaliSpacing.screenPadding,
            children: <Widget>[
              LocalizedUiText(
                'Registered users',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: KodimaliSpacing.xs),
              LocalizedUiText(
                'Customer accounts registered through KODIMALI. Agent and admin accounts are listed separately.',
              ),
              const SizedBox(height: KodimaliSpacing.md),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  _page = 0;
                  _reload();
                },
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Search users'),
                  hintText: mobileUi(context, 'Name, email, or phone number'),
                  suffixIcon: IconButton(
                    tooltip: mobileUi(context, 'Search'),
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () {
                      _page = 0;
                      _reload();
                    },
                  ),
                ),
              ),
              const SizedBox(height: KodimaliSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _confirmation ?? '',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: mobileUi(context, 'Email confirmation'),
                ),
                items: ['', 'confirmed', 'pending']
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(
                          mobileUi(
                            context,
                            value.isEmpty
                                ? 'All statuses'
                                : value == 'confirmed'
                                ? 'Email confirmed'
                                : 'Confirmation pending',
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _confirmation = value == '' ? null : value;
                  _page = 0;
                  _reload();
                },
              ),
              const SizedBox(height: 16),
              if (users.isEmpty)
                KodimaliEmptyState(
                  title: mobileUi(context, 'No users found'),
                  message: mobileUi(
                    context,
                    'Registered customer accounts will appear here.',
                  ),
                )
              else
                ...users.map(
                  (user) => Card(
                    margin: const EdgeInsets.only(bottom: KodimaliSpacing.sm),
                    child: ListTile(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => Scaffold(
                            appBar: AppBar(
                              title: const LocalizedUiText('User details'),
                            ),
                            body: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                Text(
                                  user['full_name']?.toString() ??
                                      mobileUi(context, 'KODIMALI user'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 16),
                                ...[
                                  'account_email',
                                  'phone_number',
                                  'preferred_language',
                                  'created_at',
                                ].map(
                                  (key) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      mobileUi(
                                        context,
                                        {
                                          'account_email': 'Email',
                                          'phone_number': 'Phone',
                                          'preferred_language':
                                              'Preferred language',
                                          'created_at': 'Registered',
                                        }[key]!,
                                      ),
                                    ),
                                    subtitle: Text(
                                      user[key]?.toString() ?? '-',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      leading: CircleAvatar(
                        child: Text(
                          (user['full_name']?.toString().trim().isNotEmpty ==
                                      true
                                  ? user['full_name'].toString().trim()[0]
                                  : mobileUi(context, 'U'))
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(
                        user['full_name']?.toString() ??
                            mobileUi(context, 'KODIMALI user'),
                      ),
                      subtitle: Text(
                        <String>[
                          user['account_email']?.toString() ??
                              mobileUi(context, 'No email'),
                          user['phone_number']?.toString() ??
                              mobileUi(context, 'No phone number'),
                          '${mobileUi(context, 'Registered')}: ${DateFormatters.formatDateTime(user['created_at']?.toString())}',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        user['email_confirmed_at'] == null
                            ? Icons.mark_email_unread_outlined
                            : Icons.verified_outlined,
                        color: user['email_confirmed_at'] == null
                            ? KodimaliColors.warning
                            : KodimaliColors.green,
                      ),
                    ),
                  ),
                ),
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
                    child: const LocalizedUiText('Previous'),
                  ),
                  TextButton(
                    onPressed: users.length < 20
                        ? null
                        : () {
                            _page++;
                            _reload();
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
  }
}
