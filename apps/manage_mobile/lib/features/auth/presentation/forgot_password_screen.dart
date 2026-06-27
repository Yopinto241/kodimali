import 'package:flutter/material.dart';

import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final dependencies = AppScope.of(context);
    setState(() => _submitting = true);
    try {
      await dependencies.controller.sendPasswordReset(
        _identifierController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset instructions have been sent."),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Umesahau nenosiri")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                "Weka username, simu, au email. Ikiwa akaunti ina recovery email ya kweli, Supabase itatuma link ya kubadili nenosiri huko.",
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _identifierController,
                decoration: const InputDecoration(
                  labelText: "Username, simu, au barua pepe",
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Weka username, simu, au email.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Text(
                "Kama akaunti iliundwa na admin bila recovery email, forgot password ya email haitatumika. Tumia Change password ukiwa umeingia, au muombe admin akusaidie.",
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting ? "Inatuma..." : "Tuma link"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
