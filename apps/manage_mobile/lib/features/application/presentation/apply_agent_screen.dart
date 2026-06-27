import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_scope.dart';

class ApplyAgentScreen extends StatefulWidget {
  const ApplyAgentScreen({super.key});

  @override
  State<ApplyAgentScreen> createState() => _ApplyAgentScreenState();
}

class _ApplyAgentScreenState extends State<ApplyAgentScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  PlatformFile? _document;
  bool _submitting = false;
  bool _prefilledPhone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilledPhone) {
      return;
    }
    final profile = AppScope.of(context).controller.profile;
    _phoneController.text = profile?.phoneNumber ?? "";
    _prefilledPhone = true;
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>["pdf", "png", "jpg", "jpeg"],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _document = result.files.single;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_document == null || _document!.bytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Pakia kitambulisho au hati.")));
      return;
    }
    final appScope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    try {
      await appScope.repository.submitAgentApplication(
        businessName: _businessNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        businessDescription: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        document: _document!,
      );
      await appScope.controller.refreshProfile();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Application submitted. Awaiting admin verification."),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).controller.profile;
    return Scaffold(
      appBar: AppBar(title: const Text("Apply to become an agent")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Karibu ${profile?.fullName ?? ''}",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  "Ukishaomba kuwa wakala, admin atahakiki taarifa zako kabla ya kukupa dashboard ya uendeshaji.",
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _businessNameController,
                  decoration: const InputDecoration(labelText: "Business name"),
                  validator: (String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Weka jina la biashara.";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "Phone number"),
                  validator: (String? value) {
                    if (value == null || value.trim().length < 8) {
                      return "Weka namba sahihi.";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: "Business description (optional)",
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickDocument,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    _document == null ? "Upload ID or verification document" : _document!.name,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                      _submitting ? "Inatuma ombi..." : "Submit application",
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
