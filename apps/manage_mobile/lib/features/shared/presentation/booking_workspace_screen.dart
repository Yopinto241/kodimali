import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class BookingWorkspaceScreen extends StatefulWidget {
  const BookingWorkspaceScreen({
    super.key,
    required this.booking,
    this.isAdmin = false,
    this.onChanged,
  });

  final Map<String, dynamic> booking;
  final bool isAdmin;
  final Future<void> Function()? onChanged;

  @override
  State<BookingWorkspaceScreen> createState() => _BookingWorkspaceScreenState();
}

class _BookingWorkspaceScreenState extends State<BookingWorkspaceScreen> {
  late Future<Map<String, dynamic>> _future;
  Timer? _chatTimer;
  bool _initialized = false;
  bool _busy = false;

  Map<String, dynamic> get _booking => widget.booking;
  String get _bookingId => _booking["id"] as String;
  bool get _hasCustomerAccount => _booking["customer_id"] != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _future = _load();
    if (_hasCustomerAccount) {
      _chatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted && !_busy) {
          _refresh(quiet: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _chatTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final repository = AppScope.of(context).repository;
    final List<dynamic> primary = await Future.wait<dynamic>(<Future<dynamic>>[
      repository.fetchBookingStatusHistory(_bookingId),
      repository.fetchViewingAppointments(_bookingId),
      repository.fetchBookingReview(_bookingId),
      repository.fetchAcceptedBookingTerms(_bookingId),
      repository.fetchBookingPaymentIntents(_bookingId),
      repository.fetchBookingFulfillmentMilestones(_bookingId),
      repository.fetchBookingIncidents(_bookingId),
      repository.fetchBookingProviderPayables(_bookingId),
      repository.fetchBookingCancellations(_bookingId),
      if (_hasCustomerAccount)
        repository.getOrCreateBookingConversation(_bookingId)
      else
        Future<Map<String, dynamic>?>.value(null),
    ]);
    final Map<String, dynamic>? conversation =
        primary[9] as Map<String, dynamic>?;
    final String? conversationId = conversation?["id"] as String?;
    final List<Map<String, dynamic>> messages = conversationId == null
        ? <Map<String, dynamic>>[]
        : await repository.fetchBookingMessages(conversationId);
    if (conversationId != null) {
      await repository.markBookingConversationRead(conversationId);
    }
    return <String, dynamic>{
      "history": primary[0],
      "appointments": primary[1],
      "review": primary[2],
      "terms": primary[3],
      "paymentIntents": primary[4],
      "milestones": primary[5],
      "incidents": primary[6],
      "payables": primary[7],
      "cancellations": primary[8],
      "conversation": conversation,
      "messages": messages,
    };
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (!mounted) {
      return;
    }
    final Future<Map<String, dynamic>> next = _load();
    setState(() => _future = next);
    if (!quiet) {
      await next;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      await widget.onChanged?.call();
      if (mounted) {
        await _refresh();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _updateStatus(BookingStatus status) async {
    await _run(
      () => AppScope.of(
        context,
      ).repository.updateBookingStatus(bookingId: _bookingId, status: status),
    );
    if (mounted) {
      setState(() => _booking["booking_status"] = status.storageValue);
    }
  }

  Future<void> _sendResponse(String conversationId, String responseCode) async {
    await _run(
      () => AppScope.of(context).repository.sendBookingResponse(
        conversationId: conversationId,
        responseCode: responseCode,
      ),
    );
  }

  Future<void> _proposeViewing() async {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);
    final bool? shouldSave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text("Propose viewing"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: const Text("Date"),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(selectedDate),
                      ),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text("Start time"),
                      subtitle: Text(selectedTime.format(context)),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text("Send proposal"),
                ),
              ],
            );
          },
        );
      },
    );
    if (shouldSave != true || !mounted) {
      return;
    }
    final DateTime startAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    await _run(
      () => AppScope.of(context).repository.proposeViewingAppointment(
        bookingId: _bookingId,
        startAt: startAt,
        endAt: startAt.add(const Duration(hours: 1)),
        locationNote: null,
      ),
    );
  }

  Future<void> _respondToAppointment(String appointmentId, String status) {
    return _run(
      () => AppScope.of(context).repository.respondToViewingAppointment(
        appointmentId: appointmentId,
        status: status,
      ),
    );
  }

  Future<void> _confirmMilestone(String milestoneId) async {
    await _run(
      () => AppScope.of(
        context,
      ).repository.confirmFulfillmentMilestone(milestoneId),
    );
  }

  Future<void> _reviewCancellation(String caseId, bool approve) async {
    final controller = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? "Approve cancellation" : "Decline cancellation"),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: "Review notes"),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Back"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? "Approve" : "Decline"),
          ),
        ],
      ),
    );
    final notes = controller.text;
    controller.dispose();
    if (confirmed != true || !mounted) return;
    await _run(
      () => AppScope.of(context).repository.reviewBookingCancellation(
        caseId: caseId,
        approve: approve,
        notes: notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? listing =
        _booking["listings"] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(
        title: Text(_booking["request_reference"] as String? ?? "Request"),
        actions: <Widget>[
          IconButton(
            tooltip: "Refresh",
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<Map<String, dynamic>> snapshot,
            ) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(userFacingError(snapshot.error!)));
              }
              final Map<String, dynamic> data =
                  snapshot.data ?? <String, dynamic>{};
              final List<Map<String, dynamic>> history =
                  (data["history"] as List<dynamic>? ?? <dynamic>[])
                      .whereType<Map>()
                      .map((Map item) => item.cast<String, dynamic>())
                      .toList(growable: false);
              final List<Map<String, dynamic>> appointments =
                  (data["appointments"] as List<dynamic>? ?? <dynamic>[])
                      .whereType<Map>()
                      .map((Map item) => item.cast<String, dynamic>())
                      .toList(growable: false);
              final List<Map<String, dynamic>> messages =
                  (data["messages"] as List<dynamic>? ?? <dynamic>[])
                      .whereType<Map>()
                      .map((Map item) => item.cast<String, dynamic>())
                      .toList(growable: false);
              return ManagePageScrollView(
                onRefresh: _refresh,
                children: <Widget>[
                  ManageHeroCard(
                    title: listing?["title"] as String? ?? "Listing request",
                    subtitle:
                        "Customer: ${_booking["customer_name"] ?? "-"}. Keep status, viewing, chat, and completion evidence together.",
                    trailing: KodimaliStatusChip(
                      label: _booking["booking_status"] as String? ?? "new",
                      highlight: true,
                    ),
                    bottom: ManageMetaWrap(
                      items: <String>[
                        "Reference ${_booking["request_reference"] ?? "-"}",
                        _hasCustomerAccount
                            ? "Customer account linked"
                            : "Guest request",
                        widget.isAdmin ? "Admin oversight" : "Assigned to you",
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildOwnershipPanel(context),
                  const SizedBox(height: 16),
                  _buildStatusActions(context),
                  const SizedBox(height: 16),
                  _buildFinancialPanel(context, data),
                  const SizedBox(height: 16),
                  _buildFulfillmentPanel(context, data),
                  const SizedBox(height: 16),
                  _buildCancellationPanel(context, data),
                  const SizedBox(height: 16),
                  _buildViewingPanel(context, appointments),
                  const SizedBox(height: 16),
                  _buildChatPanel(context, data["conversation"], messages),
                  const SizedBox(height: 16),
                  _buildCompletionPanel(context, data["review"]),
                  const SizedBox(height: 16),
                  _buildHistoryPanel(context, history),
                ],
              );
            },
      ),
    );
  }

  Widget _buildOwnershipPanel(BuildContext context) {
    final Map<String, dynamic>? agent =
        _booking["assigned_agent"] as Map<String, dynamic>?;
    final String phone = (_booking["customer_phone_number"] as String? ?? "")
        .trim();
    return ManagePanel(
      title: widget.isAdmin ? "Request ownership" : "Your assigned request",
      subtitle: widget.isAdmin
          ? "This shows exactly which agent received and owns the request."
          : "Only you and admins can move this request through the agent workflow.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            agent?["display_name"] as String? ??
                agent?["business_name"] as String? ??
                (widget.isAdmin
                    ? "Unassigned agent record"
                    : "Assigned to you"),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ManageMetaWrap(
            items: <String>[
              "Agent ID ${_booking["agent_id"] ?? "-"}",
              "Customer ${_booking["customer_name"] ?? "-"}",
              if (_booking["agent_response_due_at"] != null)
                "Response due ${DateFormatters.formatDateTime(_booking["agent_response_due_at"] as String?)}",
              if (_booking["first_agent_response_at"] != null)
                "First response ${DateFormatters.formatDateTime(_booking["first_agent_response_at"] as String?)}",
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: phone.isEmpty
                    ? null
                    : () => Launchers.callPhone(phone),
                icon: const Icon(Icons.call_outlined),
                label: const Text("Call customer"),
              ),
              OutlinedButton.icon(
                onPressed: phone.isEmpty
                    ? null
                    : () => Launchers.openWhatsApp(phone),
                icon: const Icon(Icons.chat_outlined),
                label: const Text("WhatsApp"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusActions(BuildContext context) {
    final String currentStatus = _booking["booking_status"] as String? ?? "new";
    final String ownerApproval =
        _booking["owner_approval_status"] as String? ?? "not_required";
    final List<dynamic> payments =
        _booking["booking_payment_transactions"] as List<dynamic>? ??
        <dynamic>[];
    final bool paid = payments.any(
      (dynamic row) => row is Map && row["status"] == "paid",
    );
    final bool terminal = <String>{
      "completed",
      "cancelled",
      "rejected",
      "no_response",
    }.contains(currentStatus);
    final bool instantHold = currentStatus == "reserved" && !paid;
    return ManagePanel(
      title: "Respond and move request",
      subtitle:
          "Verified availability is reserved automatically. Every stage change is retained in booking history.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            paid
                ? "Payment confirmed. The booking is secured and can continue to completion."
                : instantHold
                ? "The period is temporarily held for this customer. No manual acceptance is needed; payment confirmation secures it."
                : ownerApproval == "pending"
                ? "Waiting for the verified owner or manager to approve before payment."
                : _booking["payment_ready_at"] != null
                ? "Customer has been notified to pay and secure this booking."
                : currentStatus == "new"
                ? "Accept this request to unlock the customer's next step."
                : "Availability is being handled; payment becomes available after required approval.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _busy || terminal || instantHold
                    ? null
                    : () => _updateStatus(BookingStatus.checkingAvailability),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Accept request"),
              ),
              OutlinedButton.icon(
                onPressed: _busy || terminal
                    ? null
                    : () => _updateStatus(BookingStatus.contacted),
                icon: const Icon(Icons.mark_chat_read_outlined),
                label: const Text("Mark contacted"),
              ),
              OutlinedButton.icon(
                onPressed: _busy || terminal || !_hasCustomerAccount
                    ? null
                    : _proposeViewing,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text("Schedule viewing"),
              ),
              PopupMenuButton<BookingStatus>(
                enabled: !_busy,
                onSelected: _updateStatus,
                itemBuilder: (BuildContext context) => BookingStatus.values
                    .where(
                      (BookingStatus item) =>
                          item != BookingStatus.agentDelayed,
                    )
                    .map(
                      (BookingStatus item) => PopupMenuItem<BookingStatus>(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(growable: false),
                child: const Chip(
                  avatar: Icon(Icons.account_tree_outlined, size: 18),
                  label: Text("All stages"),
                ),
              ),
              TextButton.icon(
                onPressed: _busy || terminal
                    ? null
                    : () => _updateStatus(BookingStatus.rejected),
                icon: const Icon(Icons.close_rounded),
                label: const Text("Reject"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialPanel(BuildContext context, Map<String, dynamic> data) {
    final Map<String, dynamic>? terms = data["terms"] is Map
        ? (data["terms"] as Map).cast<String, dynamic>()
        : null;
    final List<Map<String, dynamic>> intents =
        (data["paymentIntents"] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map((Map item) => item.cast<String, dynamic>())
            .toList(growable: false);
    final List<Map<String, dynamic>> payables =
        (data["payables"] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map((Map item) => item.cast<String, dynamic>())
            .toList(growable: false);

    if (terms == null && intents.isEmpty && payables.isEmpty) {
      return const ManagePanel(
        title: "Booking payment",
        subtitle: "No confirmed price yet.",
        child: Text(
          "Payment starts only after the customer accepts a clear booking price and terms.",
        ),
      );
    }

    return ManagePanel(
      title: "Booking payment",
      subtitle:
          "See what the customer agreed and paid. Financial records are controlled by the platform.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (terms != null)
            ManageMetaWrap(
              items: <String>[
                "Total ${DateFormatters.formatCurrency(terms["agreed_total_minor"] as num?)}",
                "Deposit ${DateFormatters.formatCurrency(terms["deposit_minor"] as num?)} (${terms["deposit_percent"] ?? 25}%)",
                "Balance ${DateFormatters.formatCurrency(terms["balance_minor"] as num?)}",
                "Agreement ${terms["agreement_version"] ?? "-"}",
                if (terms["balance_due_at"] != null)
                  "Balance due ${DateFormatters.formatDateTime(terms["balance_due_at"] as String?)}",
              ],
            ),
          if (intents.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            ...intents.map(
              (Map<String, dynamic> intent) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  intent["status"] == "verified_paid"
                      ? Icons.verified_rounded
                      : Icons.payments_outlined,
                ),
                title: Text(
                  intent["product"] == "booking_deposit"
                      ? "Booking deposit"
                      : "Booking balance",
                ),
                subtitle: Text(
                  DateFormatters.formatCurrency(intent["amount_minor"] as num?),
                ),
                trailing: KodimaliStatusChip(
                  label: intent["status"] as String? ?? "created",
                  highlight: intent["status"] == "verified_paid",
                ),
              ),
            ),
          ],
          if (payables.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            Text(
              "Provider settlement",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...payables.map(
              (Map<String, dynamic> payable) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  DateFormatters.formatCurrency(
                    payable["amount_minor"] as num?,
                  ),
                ),
                subtitle: const Text(
                  "Released only after fulfillment and protection checks.",
                ),
                trailing: KodimaliStatusChip(
                  label: payable["status"] as String? ?? "pending_fulfillment",
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFulfillmentPanel(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final List<Map<String, dynamic>> milestones =
        (data["milestones"] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map((Map item) => item.cast<String, dynamic>())
            .toList(growable: false);
    final List<Map<String, dynamic>> incidents =
        (data["incidents"] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map((Map item) => item.cast<String, dynamic>())
            .toList(growable: false);
    return ManagePanel(
      title: "Fulfillment",
      subtitle: milestones.isEmpty
          ? "Fulfillment steps appear after booking terms are confirmed."
          : "Confirm only a step you have actually completed. Customer or admin verification remains separate.",
      child: Column(
        children: <Widget>[
          if (milestones.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("No fulfillment step is due yet."),
            )
          else
            ...milestones.map((Map<String, dynamic> milestone) {
              final String status = milestone["status"] as String? ?? "pending";
              final bool canConfirm =
                  !widget.isAdmin &&
                  <String>{"pending", "ready"}.contains(status);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.task_alt_rounded),
                title: Text(
                  (milestone["milestone_kind"] as String? ?? "milestone")
                      .replaceAll("_", " "),
                ),
                subtitle: milestone["due_at"] == null
                    ? null
                    : Text(
                        "Due ${DateFormatters.formatDateTime(milestone["due_at"] as String?)}",
                      ),
                trailing: canConfirm
                    ? FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () =>
                                  _confirmMilestone(milestone["id"] as String),
                        child: const Text("Confirm done"),
                      )
                    : KodimaliStatusChip(
                        label: status,
                        highlight: status == "verified",
                      ),
              );
            }),
          if (incidents.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Protection cases",
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ...incidents.map(
              (Map<String, dynamic> incident) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.report_problem_outlined),
                title: Text(incident["summary"] as String? ?? "Issue reported"),
                subtitle: Text(
                  "${incident["incident_kind"] ?? "issue"} · ${incident["severity"] ?? "-"}",
                ),
                trailing: KodimaliStatusChip(
                  label: incident["status"] as String? ?? "open",
                  highlight: incident["settlement_suspended"] == true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCancellationPanel(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final List<Map<String, dynamic>> cases =
        (data["cancellations"] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map((Map item) => item.cast<String, dynamic>())
            .toList(growable: false);
    if (cases.isEmpty) {
      return const ManagePanel(
        title: "Cancellation and refund",
        subtitle: "No cancellation has been requested.",
        child: Text(
          "Booking, refund and settlement remain active independently.",
        ),
      );
    }
    return ManagePanel(
      title: "Cancellation and refund",
      subtitle:
          "Review the calculated allocation. Approval releases inventory and creates liabilities; it does not send money automatically.",
      child: Column(
        children: cases
            .map((item) {
              final String status =
                  item["booking_status"] as String? ?? "requested";
              final bool reviewable = widget.isAdmin && status == "requested";
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item["reason"] as String? ??
                                "Cancellation requested",
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        KodimaliStatusChip(
                          label: status,
                          highlight: reviewable,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ManageMetaWrap(
                      items: <String>[
                        "Paid ${DateFormatters.formatCurrency(item["paid_minor"] as num?)}",
                        "Customer refund ${DateFormatters.formatCurrency(item["customer_refund_minor"] as num?)}",
                        "Provider ${DateFormatters.formatCurrency(item["provider_compensation_minor"] as num?)}",
                        "KODIMALI ${DateFormatters.formatCurrency(item["platform_fee_minor"] as num?)}",
                        "Refund ${item["refund_status"] ?? "not_started"}",
                        "Inventory ${item["inventory_release_status"] ?? "retained"}",
                        "Settlement ${item["settlement_status"] ?? "not_started"}",
                      ],
                    ),
                    if (reviewable) ...<Widget>[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _reviewCancellation(
                                    item["id"] as String,
                                    true,
                                  ),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text("Approve"),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _reviewCancellation(
                                    item["id"] as String,
                                    false,
                                  ),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text("Decline"),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _buildViewingPanel(
    BuildContext context,
    List<Map<String, dynamic>> appointments,
  ) {
    final Map<String, dynamic>? latest = appointments.isEmpty
        ? null
        : appointments.first;
    return ManagePanel(
      title: "Viewing appointment",
      subtitle: !_hasCustomerAccount
          ? "A signed-in customer must be linked before an in-app viewing can be scheduled."
          : latest == null
          ? "No viewing has been proposed yet."
          : "Latest appointment and response are shown below.",
      action: IconButton(
        tooltip: "Propose another time",
        onPressed: _busy || !_hasCustomerAccount ? null : _proposeViewing,
        icon: const Icon(Icons.add_rounded),
      ),
      child: latest == null
          ? Text(
              _hasCustomerAccount
                  ? "Choose Schedule viewing to send the customer a date and time."
                  : "Use Call or WhatsApp to coordinate this guest request. Once the customer signs in and claims it, in-app appointments become available.",
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        DateFormatters.formatDateTime(
                          latest["scheduled_start_at"] as String?,
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    KodimaliStatusChip(
                      label: latest["status"] as String? ?? "proposed",
                      highlight: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _respondToAppointment(
                              latest["id"] as String,
                              "confirmed",
                            ),
                      child: const Text("Confirm"),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _respondToAppointment(
                              latest["id"] as String,
                              "completed",
                            ),
                      child: const Text("Viewing completed"),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _respondToAppointment(
                              latest["id"] as String,
                              "cancelled",
                            ),
                      child: const Text("Cancel viewing"),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildChatPanel(
    BuildContext context,
    dynamic rawConversation,
    List<Map<String, dynamic>> messages,
  ) {
    final Map<String, dynamic>? conversation = rawConversation is Map
        ? rawConversation.cast<String, dynamic>()
        : null;
    final String? conversationId = conversation?["id"] as String?;
    if (!_hasCustomerAccount) {
      return const ManagePanel(
        title: "Request follow-up",
        subtitle: "Structured responses require a linked customer account.",
        child: Text(
          "This guest request can be followed through status changes and viewing appointments. Free-text messaging is not available.",
        ),
      );
    }
    if (conversationId == null) {
      return const ManagePanel(
        title: "Request follow-up",
        subtitle: "The customer account is linked.",
        child: Text(
          "Structured responses are not available from the server yet.",
        ),
      );
    }
    final String currentUserId =
        AppScope.of(context).controller.currentUser?.id ?? "";
    return ManagePanel(
      title: "Request follow-up",
      subtitle:
          "Only safe predefined responses are allowed. Private conversation remains in paid listing chat.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (messages.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text("No messages yet. Send the first response."),
            )
          else
            ...messages.take(30).map((Map<String, dynamic> message) {
              final bool mine = message["sender_id"] == currentUserId;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: mine
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(message["body"] as String? ?? ""),
                      const SizedBox(height: 4),
                      Text(
                        DateFormatters.formatDateTime(
                          message["created_at"] as String?,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (widget.isAdmin)
            const Text(
              "Administrators can review this follow-up but cannot send responses or contact details.",
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  const <MapEntry<String, String>>[
                        MapEntry('request_received', 'Request received'),
                        MapEntry(
                          'checking_availability',
                          'Checking availability',
                        ),
                        MapEntry('available', 'Available'),
                        MapEntry('unavailable', 'Not available'),
                        MapEntry('will_call', 'I will call you'),
                        MapEntry('viewing_proposed', 'Viewing proposed'),
                        MapEntry('need_more_time', 'Need more time'),
                      ]
                      .map(
                        (response) => ActionChip(
                          label: Text(response.value),
                          onPressed: _busy
                              ? null
                              : () =>
                                    _sendResponse(conversationId, response.key),
                        ),
                      )
                      .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCompletionPanel(BuildContext context, dynamic rawReview) {
    final String status = _booking["booking_status"] as String? ?? "new";
    final Map<String, dynamic>? review = rawReview is Map
        ? rawReview.cast<String, dynamic>()
        : null;
    return ManagePanel(
      title: "Completion and review",
      subtitle:
          "A completed, account-linked request becomes eligible for a verified customer review.",
      child: status != "completed"
          ? const Text(
              "Mark the request completed only after the real rental is finished.",
            )
          : review == null
          ? Text(
              _hasCustomerAccount
                  ? "Rental completed. The customer can now submit a verified review."
                  : "Rental completed, but this guest request has no signed-in customer account for a verified review.",
            )
          : Row(
              children: <Widget>[
                const Icon(Icons.verified_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Verified review received: ${review["rating"] ?? "-"}/5${(review["comment"] as String?)?.isNotEmpty == true ? " — ${review["comment"]}" : ""}",
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHistoryPanel(
    BuildContext context,
    List<Map<String, dynamic>> history,
  ) {
    return ManagePanel(
      title: "Status history",
      subtitle:
          "An audit trail of how this request moved through the workflow.",
      child: history.isEmpty
          ? const Text("No status history is available yet.")
          : Column(
              children: history
                  .map((Map<String, dynamic> item) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(item["status"] as String? ?? "-"),
                      subtitle: Text(
                        <String>[
                          DateFormatters.formatDateTime(
                            item["created_at"] as String?,
                          ),
                          if ((item["reason"] as String?)?.isNotEmpty == true)
                            item["reason"] as String,
                        ].join(" • "),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}
