import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
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
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _lastRows = [];
  Timer? _refreshTimer;
  bool _refreshInFlight = false;
  Object? _refreshError;
  Future<List<Map<String, dynamic>>> _fetch() async {
    _refreshInFlight = true;
    try {
      final rows = await widget.repository.fetchListingChats().timeout(
        const Duration(seconds: 20),
      );
      _refreshError = null;
      _lastRows = rows;
      return rows;
    } catch (error) {
      _refreshError = error;
      if (_lastRows.isNotEmpty) return _lastRows;
      rethrow;
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _reload() async {
    if (!mounted || _refreshInFlight) return;
    final next = _fetch();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_reload());
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
    appBar: AppBar(
      title: const LocalizedUiText('My chats'),
      actions: [
        IconButton(
          onPressed: _reload,
          tooltip: mobileUi(context, 'Retry'),
          icon: Icon(_refreshError == null ? Icons.refresh : Icons.cloud_off),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            _lastRows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return RecoverableError(error: snapshot.error, onRetry: _reload);
        }
        final rows = snapshot.data ?? _lastRows;
        if (rows.isEmpty) {
          return const Center(
            child: LocalizedUiText('Your agent chats will appear here.'),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
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
                      ? mobileUi(context, 'Chat ready')
                      : mobileUi(context, 'Access expired')}',
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
  int? _chatPrice;
  bool _hasAccess = false;
  bool _modeFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPaymentMode());
  }

  Future<void> _loadPaymentMode() async {
    try {
      final hasAccess = await widget.repository
          .hasListingChatAccess(widget.listingId)
          .timeout(const Duration(seconds: 20));
      final enabled = hasAccess
          ? true
          : await widget.repository.fetchChatPaymentsEnabled().timeout(
              const Duration(seconds: 20),
            );
      final price = enabled && !hasAccess
          ? await widget.repository.fetchPaidChatUnlockPrice().timeout(
              const Duration(seconds: 20),
            )
          : 0;
      if (mounted) {
        setState(() {
          _paymentsEnabled = enabled;
          _chatPrice = price;
          _hasAccess = hasAccess;
          _modeFailed = false;
        });
        if ((_paymentsEnabled == false || _hasAccess) &&
            widget.repository.isSignedIn) {
          await _continue();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _modeFailed = true;
          _paymentsEnabled = null;
        });
      }
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
            expectedAmount: _paymentsEnabled == true && !_hasAccess
                ? _chatPrice
                : null,
          );
      String status = result['paymentStatus']?.toString() ?? 'pending';
      final required = result['paymentRequired'] as bool? ?? true;
      final id = result['paymentId']?.toString();
      if (required && id != null && status != 'paid') {
        setState(() {
          _message =
              'Payment prompt sent. Confirm TSh ${result['amount'] ?? _chatPrice} on your phone.';
        });
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
        setState(() {
          _message = userMessage(context, error);
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
    appBar: AppBar(title: const LocalizedUiText('Chat with agent')),
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
          _paymentsEnabled == null
              ? (Localizations.localeOf(context).languageCode == 'sw'
                    ? 'Inaangalia ruhusa...'
                    : 'Checking access...')
              : _paymentsEnabled == false || _hasAccess
              ? (Localizations.localeOf(context).languageCode == 'sw'
                    ? 'Zungumza moja kwa moja na wakala kuhusu mali hii.'
                    : 'Chat directly with the agent about this listing.')
              : (Localizations.localeOf(context).languageCode == 'sw'
                    ? 'TZS $_chatPrice kwa siku 7. Thibitisha malipo ili kuendelea.'
                    : 'TZS $_chatPrice for 7 days. Confirm payment to continue.'),
        ),
        if (_modeFailed)
          TextButton(
            onPressed: _loadPaymentMode,
            child: const LocalizedUiText('Retry'),
          ),
        const SizedBox(height: 20),
        if (!widget.repository.isSignedIn)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const LocalizedUiText(
                    'Sign in or register to message this agent.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await widget.onAuthenticate(true);
                            await _loadPaymentMode();
                          },
                          child: const LocalizedUiText('Register'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            await widget.onAuthenticate(false);
                            await _loadPaymentMode();
                          },
                          child: const LocalizedUiText('Sign in'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else if (_paymentsEnabled == true && !_hasAccess)
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: mobileUi(context, 'Mobile-money phone number'),
              prefixText: '+255 ',
            ),
          ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          LocalizedUiText(_message!),
        ],
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
                  ? mobileUi(context, 'Checking access…')
                  : _paymentsEnabled == false || _hasAccess
                  ? (Localizations.localeOf(context).languageCode == 'sw'
                        ? 'Zungumza hapa'
                        : 'Chat here')
                  : mobileUiFormat(context, "Pay TSh {0} and open chat", [
                      _chatPrice ?? '-',
                    ]),
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
  late Future<Map<String, dynamic>> _details = _loadDetails();
  late Stream<List<Map<String, dynamic>>> _messages = widget.repository
      .watchListingChatMessages(widget.conversationId);
  Map<String, dynamic>? _lastDetails;
  List<Map<String, dynamic>> _lastMessages = [];
  void _retryMessages() => setState(() {
    _messages = widget.repository.watchListingChatMessages(
      widget.conversationId,
    );
  });
  bool _refreshingDetails = false;
  bool _sending = false;
  int _messageCount = 0;
  bool _newMessages = false;
  Timer? _accessTimer;
  Future<Map<String, dynamic>> _loadDetails() async {
    final details = await widget.repository
        .fetchListingConversation(widget.conversationId)
        .timeout(const Duration(seconds: 20));
    _lastDetails = details;
    return details;
  }

  Future<void> _retryDetails() async {
    if (_refreshingDetails || !mounted) return;
    _refreshingDetails = true;
    final next = _loadDetails();
    setState(() {
      _details = next;
    });
    try {
      await next;
    } catch (_) {
    } finally {
      _refreshingDetails = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _accessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_retryDetails());
      }
    });
  }

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
    _accessTimer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
    });
    try {
      await widget.repository.sendListingChatMessage(
        conversationId: widget.conversationId,
        body: body,
      );
      if (!mounted) return;
      _text.clear();
      _scrollToLatest();
      await _retryDetails();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, e))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _details,
    builder: (context, s) {
      final d = s.data ?? _lastDetails;
      if (d == null) {
        return Scaffold(
          appBar: AppBar(title: const LocalizedUiText('Agent chat')),
          body: s.hasError
              ? RecoverableError(error: s.error, onRetry: _retryDetails)
              : const Center(child: CircularProgressIndicator()),
        );
      }
      final sent = (d['messages_sent_today'] as num?)?.toInt() ?? 0;
      final expiry = DateTime.tryParse(d['expires_at']?.toString() ?? '');
      final revoked =
          d['revoked_at'] != null || d['access_status'] == 'revoked';
      final active =
          !revoked && (expiry?.isAfter(DateTime.now()) ?? false) && !s.hasError;
      return Scaffold(
        appBar: AppBar(
          title: Text(d['agent_name']?.toString() ?? 'Agent chat'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                mobileUiFormat(context, "{0}/10 sent today • {1}", [
                  sent,
                  s.hasError
                      ? mobileUi(context, 'Unable to check chat access')
                      : revoked
                      ? mobileUi(context, 'Chat access revoked')
                      : active
                      ? mobileUiFormat(context, 'Access until {0}', [
                          expiry!.toLocal(),
                        ])
                      : mobileUi(context, 'Access expired'),
                ]),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            if (s.hasError)
              MaterialBanner(
                content: Text(userMessage(context, s.error)),
                actions: [
                  TextButton(
                    onPressed: _retryDetails,
                    child: const LocalizedUiText('Retry'),
                  ),
                ],
              ),
            if (revoked)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LocalizedUiText(
                  'Chat access was revoked. Contact support.',
                ),
              ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _messages,
                builder: (context, m) {
                  final rows = m.data ?? _lastMessages;
                  if (m.data != null) _lastMessages = m.data!;
                  if (m.hasError && rows.isEmpty) {
                    return RecoverableError(
                      error: m.error,
                      onRetry: _retryMessages,
                    );
                  }
                  if (rows.isEmpty) {
                    return const Center(
                      child: LocalizedUiText('Start the conversation.'),
                    );
                  }
                  unawaited(
                    widget.repository.markListingChatRead(
                      widget.conversationId,
                    ),
                  );
                  if (rows.length != _messageCount) {
                    final nearLatest =
                        !_scroll.hasClients || _scroll.offset < 100;
                    final first = _messageCount == 0;
                    _messageCount = rows.length;
                    if (nearLatest || first) {
                      _scrollToLatest();
                    } else {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _newMessages = true;
                          });
                        }
                      });
                    }
                  }
                  final messages = ListView.builder(
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
                  return Column(
                    children: [
                      if (m.hasError)
                        MaterialBanner(
                          content: Text(userMessage(context, m.error)),
                          actions: [
                            TextButton(
                              onPressed: _retryMessages,
                              child: const LocalizedUiText('Retry'),
                            ),
                          ],
                        ),
                      Expanded(child: messages),
                    ],
                  );
                },
              ),
            ),
            if (_newMessages)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _newMessages = false;
                  });
                  _scrollToLatest();
                },
                icon: const Icon(Icons.arrow_downward),
                label: const LocalizedUiText('New messages'),
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
                                    ? mobileUi(context, 'Message agent…')
                                    : mobileUi(context, 'Daily limit reached'))
                              : mobileUi(
                                  context,
                                  s.hasError
                                      ? 'Unable to check chat access. Retry.'
                                      : revoked
                                      ? 'Chat access was revoked. Contact support.'
                                      : 'Chat access expired',
                                ),
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
