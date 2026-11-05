import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_core/user_messages.dart';
import 'package:flutter_core/localized_ui.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/validation/listing_content_validator.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listingId,
    this.adminMode = false,
  });

  final String listingId;
  final bool adminMode;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
  final _ownerName = TextEditingController(),
      _ownerPhone = TextEditingController(),
      _ownerNotes = TextEditingController();
  bool _saving = false;
  final TextEditingController _rulesController = TextEditingController();
  final Map<String, TextEditingController> _attributeControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _attributeBooleans = <String, bool>{};
  final Map<String, String?> _attributeSelections = <String, String?>{};
  final Map<String, dynamic> _retiredAttributes = <String, dynamic>{};
  List<Map<String, dynamic>> _attributeSchema = <Map<String, dynamic>>[];
  String _availability = "available";
  String _pricePeriod = "day";
  String? _status;
  String _publicLocationLabel = "";
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _future = _load();
  }

  @override
  void dispose() {
    _ownerName.dispose();
    _ownerPhone.dispose();
    _ownerNotes.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    _rulesController.dispose();
    for (final TextEditingController controller
        in _attributeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final Map<String, dynamic> detail = await AppScope.of(
      context,
    ).repository.fetchListingDetail(widget.listingId);
    final owner = (detail['owners'] as Map?) ?? {};
    _ownerName.text = owner['full_name']?.toString() ?? '';
    _ownerPhone.text = owner['phone_number']?.toString() ?? '';
    _ownerNotes.text = owner['notes']?.toString() ?? '';
    _titleController.text = detail["title"] as String? ?? "";
    _descriptionController.text = detail["description"] as String? ?? "";
    _publicLocationLabel = detail["public_location_label"] as String? ?? "";
    _priceController.text = (detail["price_amount"] ?? "").toString();
    _depositController.text = (detail["deposit_required_amount"] ?? "")
        .toString();
    _rulesController.text = detail["listing_rules"] as String? ?? "";
    _availability = detail["availability_status"] as String? ?? "available";
    _pricePeriod = detail["price_period"] as String? ?? "day";
    _status = detail["status"] as String?;
    _initializeAttributes(detail);
    return detail;
  }

  void _initializeAttributes(Map<String, dynamic> detail) {
    for (final TextEditingController controller
        in _attributeControllers.values) {
      controller.dispose();
    }
    _attributeControllers.clear();
    _attributeBooleans.clear();
    _attributeSelections.clear();
    _retiredAttributes.clear();
    final Map<String, dynamic> category =
        (detail['asset_categories'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final dynamic rawSchema = category['field_schema'];
    _attributeSchema = rawSchema is List
        ? rawSchema
              .whereType<Map>()
              .map((Map item) => item.cast<String, dynamic>())
              .where(
                (Map<String, dynamic> field) =>
                    field['key']?.toString().trim().isNotEmpty == true &&
                    field['active'] != false,
              )
              .toList()
        : <Map<String, dynamic>>[];
    final Map<String, dynamic> values =
        (detail['listing_attributes'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final Set<String> activeKeys = _attributeSchema
        .map((Map<String, dynamic> field) => field['key'].toString())
        .toSet();
    _retiredAttributes.addAll(
      Map<String, dynamic>.fromEntries(
        values.entries.where(
          (MapEntry<String, dynamic> entry) => !activeKeys.contains(entry.key),
        ),
      ),
    );
    for (final Map<String, dynamic> field in _attributeSchema) {
      final String key = field['key'].toString();
      final String type = field['type']?.toString() ?? 'text';
      if (type == 'boolean') {
        _attributeBooleans[key] = values[key] == true;
      } else if (type == 'select') {
        _attributeSelections[key] = values[key]?.toString();
      } else {
        _attributeControllers[key] = TextEditingController(
          text: values[key]?.toString() ?? '',
        );
      }
    }
  }

  Map<String, dynamic> _listingAttributes() {
    final Map<String, dynamic> result = Map<String, dynamic>.from(
      _retiredAttributes,
    );
    for (final MapEntry<String, TextEditingController> entry
        in _attributeControllers.entries) {
      final String value = entry.value.text.trim();
      if (value.isNotEmpty) result[entry.key] = num.tryParse(value) ?? value;
    }
    result.addAll(_attributeBooleans);
    for (final MapEntry<String, String?> entry
        in _attributeSelections.entries) {
      if (entry.value?.isNotEmpty == true) result[entry.key] = entry.value;
    }
    return result;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(context).repository.updateListingBasic(
        listingId: widget.listingId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priceAmount: double.tryParse(_priceController.text.trim()) ?? 0,
        pricePeriod: _pricePeriod,
        depositAmount: double.tryParse(_depositController.text.trim()) ?? 0,
        rules: _rulesController.text.trim(),
        availabilityStatus: _availability,
        listingAttributes: _listingAttributes(),
        ownerName: _ownerName.text,
        ownerPhone: _ownerPhone.text,
        ownerNotes: _ownerNotes.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedUiText("Listing imehifadhiwa.")),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _moderateAsAdmin(String status, [String? reason]) async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    try {
      await AppScope.of(context).repository.moderateListing(
        listingId: widget.listingId,
        status: status,
        removedReason: reason,
      );
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _markAsRented() async {
    await AppScope.of(context).repository.markListingAsRented(widget.listingId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: LocalizedUiText("Listing imeondolewa sokoni kama rented."),
      ),
    );
    await _refresh();
  }

  Future<void> _removeFromMarketplace() async {
    await AppScope.of(
      context,
    ).repository.removeListingFromMarketplace(widget.listingId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: LocalizedUiText("Listing imeondolewa sokoni.")),
    );
    await _refresh();
  }

  Future<void> _payAndPublish() async {
    final repository = AppScope.of(context).repository;
    final Map<String, dynamic> payment = await repository
        .createAgentListingPayment(widget.listingId);
    String status = payment["paymentStatus"]?.toString() ?? "pending";
    final bool paymentRequired = payment["paymentRequired"] as bool? ?? true;
    final bool published = payment["published"] as bool? ?? false;
    final String? paymentId = payment["paymentId"]?.toString();
    if (paymentRequired && paymentId != null && status != "paid") {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedUiText(
              "TSh 1,000 payment request sent to your agent phone.",
            ),
          ),
        );
      }
      for (int attempt = 0; attempt < 20 && status != "paid"; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final Map<String, dynamic> checked = await repository
            .checkAgentListingPayment(paymentId);
        status = checked["paymentStatus"]?.toString() ?? status;
        if (<String>{"failed", "expired", "cancelled"}.contains(status)) break;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !paymentRequired && published
              ? mobileUi(
                  context,
                  "Listing published free. It is now live on the marketplace.",
                )
              : status == "paid"
              ? mobileUi(context, "Payment confirmed. Listing is now live.")
              : !paymentRequired
              ? mobileUi(
                  context,
                  "Free publication is enabled, but this listing needs a valid cover image before it can go live.",
                )
              : mobileUi(
                  context,
                  "Payment is not confirmed yet; the listing remains private.",
                ),
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const LocalizedUiText("Delete permanently?"),
        content: const LocalizedUiText(
          "This wrong listing has zero inquiries and will be removed completely together with its media files.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const LocalizedUiText("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const LocalizedUiText("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    await AppScope.of(context).repository.deleteListing(widget.listingId);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _contactOwner({bool whatsapp = false}) async {
    final phone = _ownerPhone.text.trim();
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length == 10 && digits.startsWith('0')) {
      digits = '255${digits.substring(1)}';
    }
    final uri = whatsapp
        ? Uri.https('wa.me', '/$digits')
        : Uri(scheme: 'tel', path: '+$digits');
    try {
      if (digits.length < 8 ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Contact app unavailable');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mobileUi(
                context,
                'Could not open contact app. Copy the phone number and try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const LocalizedUiText("Listing detail")),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(userMessage(context, snapshot.error)));
          }
          final Map<String, dynamic> detail =
              snapshot.data ?? <String, dynamic>{};
          final int inquiryCount =
              (detail["inquiry_count"] as num?)?.toInt() ?? 0;
          final List<dynamic> media =
              detail["media"] as List<dynamic>? ?? <dynamic>[];

          return Form(
            key: _formKey,
            child: ManagePageScrollView(
              children: <Widget>[
                ManageHeroCard(
                  title: _titleController.text.isEmpty
                      ? "Listing detail"
                      : _titleController.text,
                  subtitle: mobileUi(
                    context,
                    "Update the public summary, price, availability, and marketplace status from one place.",
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      KodimaliStatusChip(
                        label: _status ?? "-",
                        highlight: _status == "active",
                      ),
                      const SizedBox(height: 8),
                      KodimaliStatusChip(label: _availability),
                    ],
                  ),
                  bottom: ManageMetaWrap(
                    items: <String>[
                      "Inquiries: $inquiryCount",
                      if ((detail["removed_reason"] as String?)?.isNotEmpty ??
                          false)
                        "Reason: ${detail["removed_reason"]}",
                      "Created ${DateFormatters.formatDateTime(detail["created_at"] as String?)}",
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ManagePanel(
                  title: mobileUi(context, "Public details"),
                  subtitle: mobileUi(
                    context,
                    "These are the main fields that shape how the asset appears in the marketplace.",
                  ),
                  child: Column(
                    children: <Widget>[
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Title"),
                        ),
                        validator: ListingContentValidator.titleError,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Description *"),
                          helperText: mobileUi(
                            context,
                            "At least 10 characters",
                          ),
                        ),
                        validator: ListingContentValidator.descriptionError,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Public location label"),
                        ),
                        child: Text(
                          _publicLocationLabel.isEmpty
                              ? "-"
                              : _publicLocationLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  collapsible: true,
                  initiallyExpanded: true,
                  title: mobileUi(context, "Pricing and rules"),
                  subtitle: mobileUi(
                    context,
                    "Keep the commercial terms clear so requests are more qualified when they arrive.",
                  ),
                  child: Column(
                    children: <Widget>[
                      TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Price amount"),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _pricePeriod,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Price period"),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                            value: "hour",
                            child: LocalizedUiText("Hour"),
                          ),
                          DropdownMenuItem(
                            value: "day",
                            child: LocalizedUiText("Day"),
                          ),
                          DropdownMenuItem(
                            value: "week",
                            child: LocalizedUiText("Week"),
                          ),
                          DropdownMenuItem(
                            value: "month",
                            child: LocalizedUiText("Month"),
                          ),
                          DropdownMenuItem(
                            value: "year",
                            child: LocalizedUiText("Year"),
                          ),
                          DropdownMenuItem(
                            value: "trip",
                            child: LocalizedUiText("Trip"),
                          ),
                          DropdownMenuItem(
                            value: "event",
                            child: LocalizedUiText("Event"),
                          ),
                          DropdownMenuItem(
                            value: "piece",
                            child: LocalizedUiText("Piece"),
                          ),
                          DropdownMenuItem(
                            value: "custom",
                            child: LocalizedUiText("Custom"),
                          ),
                        ],
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _pricePeriod = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _depositController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Deposit amount"),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _availability,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Availability"),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                            value: "available",
                            child: LocalizedUiText("Available"),
                          ),
                          DropdownMenuItem(
                            value: "reserved",
                            child: LocalizedUiText("Reserved"),
                          ),
                          DropdownMenuItem(
                            value: "rented",
                            child: LocalizedUiText("Rented"),
                          ),
                          DropdownMenuItem(
                            value: "unavailable",
                            child: LocalizedUiText("Unavailable"),
                          ),
                        ],
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _availability = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _rulesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, "Rules"),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  collapsible: true,
                  initiallyExpanded: false,
                  title: mobileUi(context, "Category listing fields"),
                  subtitle: mobileUi(
                    context,
                    "These fields are configured by the administrator for this listing category.",
                  ),
                  child: _attributeSchema.isEmpty
                      ? const LocalizedUiText(
                          "No extra fields configured for this category.",
                        )
                      : Column(children: _buildAttributeFields()),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  collapsible: true,
                  initiallyExpanded: false,
                  title: mobileUi(context, 'Private owner contact (optional)'),
                  subtitle: mobileUi(
                    context,
                    'Leave all fields empty to publish without an owner contact. This does not create or verify an owner account.',
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _ownerName,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Owner name'),
                        ),
                        validator: (value) =>
                            (_ownerPhone.text.trim().isNotEmpty ||
                                    _ownerNotes.text.trim().isNotEmpty) &&
                                (value?.trim().isEmpty ?? true)
                            ? mobileUi(
                                context,
                                'Enter the owner name or clear all owner fields.',
                              )
                            : null,
                      ),
                      TextFormField(
                        controller: _ownerPhone,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Owner phone'),
                        ),
                        validator: (value) =>
                            (_ownerName.text.trim().isNotEmpty ||
                                    _ownerNotes.text.trim().isNotEmpty) &&
                                (value?.trim().isEmpty ?? true)
                            ? mobileUi(
                                context,
                                'Enter the owner phone or clear all owner fields.',
                              )
                            : null,
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _ownerPhone,
                        builder: (context, value, _) =>
                            value.text.trim().isEmpty
                            ? const SizedBox.shrink()
                            : Wrap(
                                spacing: 12,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _contactOwner(),
                                    icon: const Icon(Icons.call_outlined),
                                    label: const LocalizedUiText('Call owner'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _contactOwner(whatsapp: true),
                                    icon: const Icon(Icons.open_in_new),
                                    label: const LocalizedUiText('WhatsApp'),
                                  ),
                                ],
                              ),
                      ),
                      TextFormField(
                        controller: _ownerNotes,
                        decoration: InputDecoration(
                          labelText: mobileUi(context, 'Owner notes'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  collapsible: true,
                  initiallyExpanded: false,
                  title: mobileUi(context, "Media records"),
                  subtitle: mobileUi(
                    context,
                    "Current media already attached to this listing. Cover assets stay easy to audit here.",
                  ),
                  child: media.isEmpty
                      ? const LocalizedUiText(
                          "No media found for this listing yet.",
                        )
                      : Column(
                          children: media.map((dynamic item) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                onTap:
                                    item['media_type'] == 'image' &&
                                        item['preview_url'] != null
                                    ? () => showDialog<void>(
                                        context: context,
                                        builder: (context) => Dialog(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: InteractiveViewer(
                                                  child: Image.network(
                                                    item['preview_url']
                                                        .toString(),
                                                    errorBuilder:
                                                        (
                                                          _,
                                                          error,
                                                          stack,
                                                        ) => const LocalizedUiText(
                                                          'Image could not load',
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const LocalizedUiText(
                                                  'Close',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : null,
                                leading:
                                    item['media_type'] == 'image' &&
                                        item['preview_url'] != null
                                    ? Image.network(
                                        item['preview_url'].toString(),
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, error, stack) =>
                                            const Icon(
                                              Icons
                                                  .image_not_supported_outlined,
                                            ),
                                      )
                                    : Icon(
                                        item["media_type"] == "video"
                                            ? Icons.videocam_outlined
                                            : Icons.image_outlined,
                                      ),
                                title: Text(
                                  mobileUi(
                                    context,
                                    item['media_type'] == 'video'
                                        ? 'Video'
                                        : 'Image',
                                  ),
                                ),
                                subtitle: Text(
                                  item["is_cover"] == true
                                      ? mobileUi(context, "Cover media")
                                      : mobileUi(context, "Standard media"),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  title: mobileUi(context, "Listing actions"),
                  subtitle: mobileUi(
                    context,
                    "Save changes first, then use lifecycle actions depending on whether the listing should stay public.",
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const LocalizedUiText("Save changes"),
                      ),
                      const SizedBox(height: 12),
                      if (widget.adminMode)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => _moderateAsAdmin('active'),
                              child: const LocalizedUiText(
                                'Approve and activate',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => _moderateAsAdmin(
                                      'inactive',
                                      'admin_removed',
                                    ),
                              child: const LocalizedUiText('Remove'),
                            ),
                            OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () =>
                                        _moderateAsAdmin('inactive', 'rented'),
                              child: const LocalizedUiText('Mark rented'),
                            ),
                          ],
                        ),
                      if (!widget.adminMode && _status == "active")
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            OutlinedButton(
                              onPressed: _markAsRented,
                              child: const LocalizedUiText("Mark as rented"),
                            ),
                            OutlinedButton(
                              onPressed: _removeFromMarketplace,
                              child: const LocalizedUiText(
                                "Remove from marketplace",
                              ),
                            ),
                          ],
                        ),
                      if (!widget.adminMode && _status == "inactive")
                        OutlinedButton(
                          onPressed: _payAndPublish,
                          child: const LocalizedUiText("Publish listing"),
                        ),
                      const SizedBox(height: 14),
                      if (!widget.adminMode && inquiryCount == 0)
                        TextButton(
                          onPressed: _delete,
                          child: const LocalizedUiText("Delete permanently"),
                        )
                      else if (!widget.adminMode)
                        const LocalizedUiText(
                          "Listing yenye maombi haiwezi kufutwa kabisa. Tumia Remove from marketplace.",
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildAttributeFields() {
    return _attributeSchema.map((Map<String, dynamic> field) {
      final String key = field['key'].toString();
      final String label = mobileUi(context, field['label']?.toString() ?? key);
      final String type = field['type']?.toString() ?? 'text';
      final bool required = field['required'] == true;
      final String? rawHelpText = field['help_text']?.toString().trim();
      final String? helpText = rawHelpText == null
          ? null
          : mobileUi(context, rawHelpText);
      if (type == 'boolean') {
        return CheckboxListTile(
          value: _attributeBooleans[key] ?? false,
          title: Text(label),
          subtitle: helpText?.isNotEmpty == true ? Text(helpText!) : null,
          contentPadding: EdgeInsets.zero,
          onChanged: (bool? value) => setState(() {
            _attributeBooleans[key] = value ?? false;
          }),
        );
      }
      if (type == 'select') {
        final List<String> options =
            (field['options'] as List<dynamic>? ?? <dynamic>[])
                .map((dynamic value) => value.toString())
                .toList();
        final String? current = _attributeSelections[key];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: options.contains(current) ? current : null,
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              helperText: helpText,
            ),
            items: options
                .map(
                  (String option) => DropdownMenuItem<String>(
                    value: option,
                    child: LocalizedUiText(option),
                  ),
                )
                .toList(),
            validator: required
                ? (String? value) =>
                      value?.isNotEmpty == true ? null : '$label is required'
                : null,
            onChanged: (String? value) => setState(() {
              _attributeSelections[key] = value;
            }),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _attributeControllers[key],
          maxLines: type == 'textarea' ? 3 : 1,
          keyboardType: type == 'number'
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            helperText: helpText,
          ),
          validator: required
              ? (String? value) => value?.trim().isNotEmpty == true
                    ? null
                    : '$label is required'
              : null,
        ),
      );
    }).toList();
  }
}
