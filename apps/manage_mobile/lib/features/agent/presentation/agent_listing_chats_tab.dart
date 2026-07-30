import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/widgets/app_scope.dart';

class AgentListingChatsTab extends StatefulWidget {
  const AgentListingChatsTab({super.key});
  @override
  State<AgentListingChatsTab> createState() => _AgentListingChatsTabState();
}

class _AgentListingChatsTabState extends State<AgentListingChatsTab> {
  late Future<List<Map<String, dynamic>>> _future;
  Timer? _refreshTimer;
  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(),
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = AppScope.of(context).repository.fetchListingChats();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, s) {
      if (s.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (s.hasError) {
        return Center(child: Text(s.error.toString()));
      }
      final rows = s.data ?? const <Map<String, dynamic>>[];
      if (rows.isEmpty) {
        return const Center(child: Text('Customer chats will appear here.'));
      }
      return RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            final unread = (row['unread_count'] as num?)?.toInt() ?? 0;
            final lastMessage = row['last_message']?.toString().trim();
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(row['customer_name']?.toString() ?? 'Customer'),
              subtitle: Text(
                '${row['listing_title'] ?? 'Listing'}\n${lastMessage?.isNotEmpty == true ? lastMessage : 'No messages yet'}',
              ),
              isThreeLine: true,
              trailing: unread > 0
                  ? Badge(
                      label: Text('$unread'),
                      child: const Icon(Icons.chevron_right),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AgentListingChatScreen(
                    conversationId: row['id'].toString(),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class AgentListingChatScreen extends StatefulWidget {
  const AgentListingChatScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<AgentListingChatScreen> createState() => _AgentListingChatScreenState();
}

class _AgentListingChatScreenState extends State<AgentListingChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late Future<Map<String, dynamic>> _details;
  bool _sending = false;

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.minScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _details = AppScope.of(
      context,
    ).repository.fetchListingChatConversation(widget.conversationId);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await AppScope.of(context).repository.sendListingChatMessage(
        conversationId: widget.conversationId,
        body: body,
      );
      _text.clear();
      setState(
        () => _details = AppScope.of(
          context,
        ).repository.fetchListingChatConversation(widget.conversationId),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _details,
    builder: (context, s) {
      final d = s.data ?? <String, dynamic>{};
      final sent = (d['messages_sent_today'] as num?)?.toInt() ?? 0;
      final expiry = DateTime.tryParse(d['expires_at']?.toString() ?? '');
      final active = expiry?.isAfter(DateTime.now()) ?? false;
      return Scaffold(
        appBar: AppBar(
          title: Text(d['customer_name']?.toString() ?? 'Customer chat'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(d['listing_title']?.toString() ?? 'Listing'),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: AppScope.of(
                  context,
                ).repository.watchListingChatMessages(widget.conversationId),
                builder: (context, m) {
                  if (m.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('Messages could not load: ${m.error}'),
                      ),
                    );
                  }
                  final rows = m.data ?? const <Map<String, dynamic>>[];
                  if (rows.isNotEmpty) {
                    unawaited(
                      AppScope.of(
                        context,
                      ).repository.markListingChatRead(widget.conversationId),
                    );
                    _scrollToLatest();
                  }
                  return ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[rows.length - 1 - i];
                      final mine =
                          row['sender_id'] ==
                          AppScope.of(context).repository.currentUserId;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(row['body'].toString()),
                                const SizedBox(height: 4),
                                Text(
                                  _chatTime(row['created_at']),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${10 - sent} messages left today • ${active ? 'Chat active' : 'Chat expired'}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          TextField(
                            controller: _text,
                            enabled: active && sent < 10,
                            maxLength: 1000,
                            maxLines: 3,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: active
                                  ? (sent < 10
                                        ? 'Message customer…'
                                        : 'Daily limit reached')
                                  : 'Access expired',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: active && sent < 10 && !_sending
                          ? _send
                          : null,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _chatTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
