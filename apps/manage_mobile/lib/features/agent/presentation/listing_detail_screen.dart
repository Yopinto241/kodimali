import 'package:flutter/material.dart';

import '../../../core/utils/date_formatters.dart';
import '../../../core/validation/listing_content_validator.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

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
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Listing imehifadhiwa.")));
    await _refresh();
  }

  Future<void> _markAsRented() async {
    await AppScope.of(context).repository.markListingAsRented(widget.listingId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Listing imeondolewa sokoni kama rented.")),
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
      const SnackBar(content: Text("Listing imeondolewa sokoni.")),
    );
    await _refresh();
  }

  Future<void> _reactivateListing() async {
    await AppScope.of(context).repository.reactivateListing(widget.listingId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Listing imerudi sokoni.")));
    await _refresh();
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Delete permanently?"),
        content: const Text(
          "This wrong listing has zero inquiries and will be removed completely together with its media files.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete"),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Listing detail")),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
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
                  subtitle:
                      "Update the public summary, price, availability, and marketplace status from one place.",
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
                  title: "Public details",
                  subtitle:
                      "These are the main fields that shape how the asset appears in the marketplace.",
                  child: Column(
                    children: <Widget>[
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(labelText: "Title"),
                        validator: ListingContentValidator.titleError,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: "Description *",
                          helperText: "At least 10 characters",
                        ),
                        validator: ListingContentValidator.descriptionError,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Public location label",
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
                  title: "Category listing fields",
                  subtitle:
                      "These fields are configured by the administrator for this listing category.",
                  child: _attributeSchema.isEmpty
                      ? const Text(
                          "No extra fields configured for this category.",
                        )
                      : Column(children: _buildAttributeFields()),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  title: "Pricing and rules",
                  subtitle:
                      "Keep the commercial terms clear so requests are more qualified when they arrive.",
                  child: Column(
                    children: <Widget>[
                      TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Price amount",
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _pricePeriod,
                        decoration: const InputDecoration(
                          labelText: "Price period",
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: "hour", child: Text("Hour")),
                          DropdownMenuItem(value: "day", child: Text("Day")),
                          DropdownMenuItem(value: "week", child: Text("Week")),
                          DropdownMenuItem(
                            value: "month",
                            child: Text("Month"),
                          ),
                          DropdownMenuItem(value: "year", child: Text("Year")),
                          DropdownMenuItem(value: "trip", child: Text("Trip")),
                          DropdownMenuItem(
                            value: "event",
                            child: Text("Event"),
                          ),
                          DropdownMenuItem(
                            value: "piece",
                            child: Text("Piece"),
                          ),
                          DropdownMenuItem(
                            value: "custom",
                            child: Text("Custom"),
                          ),
                        ],
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() => _pricePeriod = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _depositController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Deposit amount",
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _availability,
                        decoration: const InputDecoration(
                          labelText: "Availability",
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                            value: "available",
                            child: Text("Available"),
                          ),
                          DropdownMenuItem(
                            value: "reserved",
                            child: Text("Reserved"),
                          ),
                          DropdownMenuItem(
                            value: "rented",
                            child: Text("Rented"),
                          ),
                          DropdownMenuItem(
                            value: "unavailable",
                            child: Text("Unavailable"),
                          ),
                        ],
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() => _availability = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _rulesController,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: "Rules"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  title: "Media records",
                  subtitle:
                      "Current media already attached to this listing. Cover assets stay easy to audit here.",
                  child: media.isEmpty
                      ? const Text("No media found for this listing yet.")
                      : Column(
                          children: media.map((dynamic item) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  item["media_type"] == "video"
                                      ? Icons.videocam_outlined
                                      : Icons.image_outlined,
                                ),
                                title: Text(
                                  item["storage_path"] as String? ?? "-",
                                ),
                                subtitle: Text(
                                  item["is_cover"] == true
                                      ? "Cover media"
                                      : "Standard media",
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 16),
                ManagePanel(
                  title: "Listing actions",
                  subtitle:
                      "Save changes first, then use lifecycle actions depending on whether the listing should stay public.",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text("Save changes"),
                      ),
                      const SizedBox(height: 12),
                      if (_status == "active")
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            OutlinedButton(
                              onPressed: _markAsRented,
                              child: const Text("Mark as rented"),
                            ),
                            OutlinedButton(
                              onPressed: _removeFromMarketplace,
                              child: const Text("Remove from marketplace"),
                            ),
                          ],
                        ),
                      if (_status == "inactive")
                        OutlinedButton(
                          onPressed: _reactivateListing,
                          child: const Text("Reactivate listing"),
                        ),
                      const SizedBox(height: 14),
                      if (inquiryCount == 0)
                        TextButton(
                          onPressed: _delete,
                          child: const Text("Delete permanently"),
                        )
                      else
                        const Text(
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
      final String label = field['label']?.toString() ?? key;
      final String type = field['type']?.toString() ?? 'text';
      final bool required = field['required'] == true;
      final String? helpText = field['help_text']?.toString().trim();
      if (type == 'boolean') {
        return CheckboxListTile(
          value: _attributeBooleans[key] ?? false,
          title: Text(label),
          subtitle: helpText?.isNotEmpty == true ? Text(helpText!) : null,
          contentPadding: EdgeInsets.zero,
          onChanged: (bool? value) =>
              setState(() => _attributeBooleans[key] = value ?? false),
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
                    child: Text(option),
                  ),
                )
                .toList(),
            validator: required
                ? (String? value) =>
                      value?.isNotEmpty == true ? null : '$label is required'
                : null,
            onChanged: (String? value) =>
                setState(() => _attributeSelections[key] = value),
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
