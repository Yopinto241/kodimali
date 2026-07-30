import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/customer_account_repository.dart';

class CustomerListingChatsScreen extends StatefulWidget {
  const CustomerListingChatsScreen({super.key, required this.repository});
  final CustomerAccountRepository repository;
  @override
  State<CustomerListingChatsScreen> createState() =>
      _CustomerListingChatsScreenState();
}

class _CustomerListingChatsScreenState
    extends State<CustomerListingChatsScreen> {
  late Future<List<Map<String, dynamic>>> _future = widget.repository
      .fetchListingChats();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() => _future = widget.repository.fetchListingChats());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My chats')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const Center(
            child: Text('Your agent chats will appear here.'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => _future = widget.repository.fetchListingChats()),
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final expiry = DateTime.tryParse(
                row['expires_at']?.toString() ?? '',
              );
              final active = expiry?.isAfter(DateTime.now()) ?? false;
              final unread = (row['unread_count'] as num?)?.toInt() ?? 0;
              final lastMessage = row['last_message']?.toString().trim();
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.chat_bubble_outline),
                ),
                title: Text(row['agent_name']?.toString() ?? 'Agent'),
                subtitle: Text(
                  '${row['listing_title'] ?? 'Listing'}\n${lastMessage?.isNotEmpty == true
                      ? lastMessage
                      : active
                      ? 'Chat ready'
                      : 'Access expired'}',
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
                    builder: (_) => CustomerListingChatScreen(
                      repository: widget.repository,
                      conversationId: row['id'].toString(),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class CustomerListingChatGate extends StatefulWidget {
  const CustomerListingChatGate({
    super.key,
    required this.repository,
    required this.listingId,
    required this.listingTitle,
    required this.onAuthenticate,
  });
  final CustomerAccountRepository repository;
  final String listingId;
  final String listingTitle;
  final Future<void> Function(bool createAccount) onAuthenticate;
  @override
  State<CustomerListingChatGate> createState() =>
      _CustomerListingChatGateState();
}

class _CustomerListingChatGateState extends State<CustomerListingChatGate> {
  final _phone = TextEditingController();
  bool _busy = false;
  String? _message;
  bool? _paymentsEnabled;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPaymentMode());
  }

  Future<void> _loadPaymentMode() async {
    try {
      final enabled = await widget.repository.fetchChatPaymentsEnabled();
      if (mounted) setState(() => _paymentsEnabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _paymentsEnabled = true);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy) return;
    if (!widget.repository.isSignedIn) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      Map<String, dynamic> result = await widget.repository
          .createListingChatPayment(
            listingId: widget.listingId,
            phoneNumber: _phone.text,
          );
      String status = result['paymentStatus']?.toString() ?? 'pending';
      final required = result['paymentRequired'] as bool? ?? true;
      final id = result['paymentId']?.toString();
      if (required && id != null && status != 'paid') {
        setState(
          () =>
              _message = 'Payment prompt sent. Confirm TSh 500 on your phone.',
        );
        for (var i = 0; i < 30 && status != 'paid'; i++) {
          await Future<void>.delayed(const Duration(seconds: 3));
          result = await widget.repository.checkListingChatPayment(id);
          status = result['paymentStatus']?.toString() ?? status;
          if ({'failed', 'expired', 'cancelled'}.contains(status)) break;
        }
      }
      if (required && status != 'paid') {
        throw StateError('Payment is not confirmed. Your chat remains locked.');
      }
      final conversation = await widget.repository.openListingConversation(
        widget.listingId,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CustomerListingChatScreen(
            repository: widget.repository,
            conversationId: conversation['id'].toString(),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chat with agent')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          Icons.lock_open_rounded,
          size: 52,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          widget.listingTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _paymentsEnabled == false
              ? 'Private chat with this listing’s assigned agent is currently free and stays active for 7 days. Each participant may send 10 messages per Tanzania day.'
              : 'Private chat with this listing’s assigned agent costs TSh 500 and stays active for 7 days. Each participant may send 10 messages per Tanzania day.',
        ),
        const SizedBox(height: 20),
        if (!widget.repository.isSignedIn)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Sign in or register to message this agent.'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => widget.onAuthenticate(true),
                          child: const Text('Register'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => widget.onAuthenticate(false),
                          child: const Text('Sign in'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else if (_paymentsEnabled != false)
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile-money phone number',
              prefixText: '+255 ',
            ),
          ),
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
        const SizedBox(height: 20),
        if (widget.repository.isSignedIn)
          FilledButton.icon(
            onPressed: _busy || _paymentsEnabled == null ? null : _continue,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chat),
            label: Text(
              _busy
                  ? 'Checking access…'
                  : _paymentsEnabled == false
                  ? 'Open free private chat'
                  : 'Pay TSh 500 and open chat',
            ),
          ),
      ],
    ),
  );
}

class CustomerListingChatScreen extends StatefulWidget {
  const CustomerListingChatScreen({
    super.key,
    required this.repository,
    required this.conversationId,
  });
  final CustomerAccountRepository repository;
  final String conversationId;
  @override
  State<CustomerListingChatScreen> createState() =>
      _CustomerListingChatScreenState();
}

class _CustomerListingChatScreenState extends State<CustomerListingChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late Future<Map<String, dynamic>> _details = widget.repository
      .fetchListingConversation(widget.conversationId);
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
      await widget.repository.sendListingChatMessage(
        conversationId: widget.conversationId,
        body: body,
      );
      _text.clear();
      setState(
        () => _details = widget.repository.fetchListingConversation(
          widget.conversationId,
        ),
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
          title: Text(d['agent_name']?.toString() ?? 'Agent chat'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$sent/10 sent today • ${active ? 'Access until ${expiry!.toLocal()}' : 'Access expired'}',
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: widget.repository.watchListingChatMessages(
                  widget.conversationId,
                ),
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
                  if (rows.isEmpty) {
                    return const Center(child: Text('Start the conversation.'));
                  }
                  unawaited(
                    widget.repository.markListingChatRead(
                      widget.conversationId,
                    ),
                  );
                  _scrollToLatest();
                  return ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[rows.length - 1 - i];
                      final mine =
                          row['sender_id'] == widget.repository.currentUser?.id;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(row['body'].toString()),
                                const SizedBox(height: 4),
                                Text(
                                  _customerChatTime(row['created_at']),
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
                      child: TextField(
                        controller: _text,
                        maxLength: 1000,
                        maxLines: 3,
                        minLines: 1,
                        enabled: active && sent < 10,
                        decoration: InputDecoration(
                          hintText: active
                              ? (sent < 10
                                    ? 'Message agent…'
                                    : 'Daily limit reached')
                              : 'Chat access expired',
                        ),
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

String _customerChatTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
