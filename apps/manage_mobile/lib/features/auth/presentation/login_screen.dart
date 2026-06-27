import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final dependencies = AppScope.of(context);
    setState(() => _submitting = true);
    try {
      await dependencies.controller.signIn(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
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
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: KodimaliSpacing.screenPadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(KodimaliSpacing.lg),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[
                          KodimaliColors.navy,
                          KodimaliColors.blueSurface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(KodimaliRadii.hero),
                      boxShadow: KodimaliShadows.lifted(KodimaliColors.navy),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const KodimaliStatusBadge(
                          label: "Secure access",
                          tone: KodimaliStatusTone.active,
                        ),
                        const SizedBox(height: KodimaliSpacing.sm),
                        Text(
                          "Karibu tena",
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: KodimaliSpacing.xs),
                        Text(
                          "Ingia kwenye KODIMALI Manage App ya agent au admin.",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: KodimaliSpacing.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(KodimaliSpacing.lg),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              "Tumia username, namba ya simu, au barua pepe pamoja na nenosiri lako. Baada ya kuingia, mfumo utafungua workspace sahihi kwa role yako.",
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: KodimaliSpacing.lg),
                            TextFormField(
                              controller: _identifierController,
                              decoration: const InputDecoration(
                                labelText: "Username, simu, au barua pepe",
                                helperText:
                                    "Unaweza kuingia kwa username, phone, au email.",
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Weka username, simu, au email.";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: KodimaliSpacing.md),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: "Nenosiri",
                                helperText: "Angalau herufi 6.",
                              ),
                              validator: (String? value) {
                                if (value == null || value.length < 6) {
                                  return "Nenosiri liwe angalau herufi 6.";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: KodimaliSpacing.sm),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => context.go("/forgot-password"),
                                child: const Text("Umesahau nenosiri?"),
                              ),
                            ),
                            const SizedBox(height: KodimaliSpacing.sm),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _submitting ? null : _submit,
                                child: Text(
                                  _submitting ? "Inaingia..." : "Ingia",
                                ),
                              ),
                            ),
                            const SizedBox(height: KodimaliSpacing.sm),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _submitting
                                    ? null
                                    : () => context.go("/register-agent"),
                                child: const Text("Jisajili kama agent"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
