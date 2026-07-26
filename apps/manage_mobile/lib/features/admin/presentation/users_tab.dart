import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final TextEditingController _search = TextEditingController();
  Future<List<Map<String, dynamic>>>? _users;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _users ??= AppScope.of(context).repository.fetchAdminCustomerUsers();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = AppScope.of(context).repository.fetchAdminCustomerUsers();
    setState(() => _users = future);
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: <Widget>[
                KodimaliEmptyState(
                  title: 'Users could not load',
                  message: userFacingError(snapshot.error!),
                  action: FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            );
          }
          final query = _search.text.trim().toLowerCase();
          final users = (snapshot.data ?? <Map<String, dynamic>>[]).where((
            user,
          ) {
            if (query.isEmpty) return true;
            return <dynamic>[
              user['full_name'],
              user['account_email'],
              user['phone_number'],
            ].any(
              (value) =>
                  value?.toString().toLowerCase().contains(query) ?? false,
            );
          }).toList();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: KodimaliSpacing.screenPadding,
            children: <Widget>[
              Text(
                'Registered users',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: KodimaliSpacing.xs),
              Text(
                'Customer accounts registered through KODIMALI. Agent and admin accounts are listed separately.',
              ),
              const SizedBox(height: KodimaliSpacing.md),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search users',
                  hintText: 'Name, email, or phone number',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: KodimaliSpacing.md),
              if (users.isEmpty)
                const KodimaliEmptyState(
                  title: 'No users found',
                  message: 'Registered customer accounts will appear here.',
                )
              else
                ...users.map(
                  (user) => Card(
                    margin: const EdgeInsets.only(bottom: KodimaliSpacing.sm),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (user['full_name']?.toString().trim().isNotEmpty ==
                                      true
                                  ? user['full_name'].toString().trim()[0]
                                  : 'U')
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(
                        user['full_name']?.toString() ?? 'KODIMALI user',
                      ),
                      subtitle: Text(
                        <String>[
                          user['account_email']?.toString() ?? 'No email',
                          user['phone_number']?.toString() ?? 'No phone',
                          'Registered ${DateFormatters.formatDateTime(user['created_at']?.toString())}',
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
            ],
          );
        },
      ),
    );
  }
}
