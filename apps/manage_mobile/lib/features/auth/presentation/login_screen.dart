import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/localization/manage_localization.dart';

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
                  const Align(
                    alignment: Alignment.centerRight,
                    child: ManageLanguageButton(),
                  ),
                  const SizedBox(height: KodimaliSpacing.sm),
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
                        KodimaliStatusBadge(
                          label: context.isSwahili
                              ? "Ufikiaji salama"
                              : "Secure access",
                          tone: KodimaliStatusTone.active,
                        ),
                        const SizedBox(height: KodimaliSpacing.sm),
                        Text(
                          context.isSwahili ? "Karibu tena" : "Welcome back",
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: KodimaliSpacing.xs),
                        Text(
                          context.isSwahili
                              ? "Ingia kwenye KODIMALI Manage App ya wakala, mmiliki au admin."
                              : "Sign in to the KODIMALI Manage App as an agent, owner, or administrator.",
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
                              context.isSwahili
                                  ? "Tumia jina la mtumiaji, namba ya simu au barua pepe pamoja na nenosiri lako. Mfumo utafungua sehemu sahihi ya kazi."
                                  : "Use your username, phone number, or email with your password. The correct workspace will open automatically.",
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: KodimaliSpacing.lg),
                            TextFormField(
                              controller: _identifierController,
                              decoration: InputDecoration(
                                labelText: context.isSwahili
                                    ? "Jina la mtumiaji, simu au barua pepe"
                                    : "Username, phone, or email",
                                helperText: context.isSwahili
                                    ? "Tumia njia yoyote kati ya hizo."
                                    : "Use any one of these identifiers.",
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return context.isSwahili
                                      ? "Weka jina la mtumiaji, simu au barua pepe."
                                      : "Enter your username, phone, or email.";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: KodimaliSpacing.md),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: context.isSwahili
                                    ? "Nenosiri"
                                    : "Password",
                                helperText: context.isSwahili
                                    ? "Angalau herufi 6."
                                    : "At least 6 characters.",
                              ),
                              validator: (String? value) {
                                if (value == null || value.length < 6) {
                                  return context.isSwahili
                                      ? "Nenosiri liwe angalau herufi 6."
                                      : "Password must have at least 6 characters.";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: KodimaliSpacing.sm),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => context.go("/forgot-password"),
                                child: Text(
                                  context.isSwahili
                                      ? "Umesahau nenosiri?"
                                      : "Forgot password?",
                                ),
                              ),
                            ),
                            const SizedBox(height: KodimaliSpacing.sm),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _submitting ? null : _submit,
                                child: Text(
                                  _submitting
                                      ? (context.isSwahili
                                            ? "Inaingia..."
                                            : "Signing in...")
                                      : (context.isSwahili
                                            ? "Ingia"
                                            : "Sign in"),
                                ),
                              ),
                            ),
                            const SizedBox(height: KodimaliSpacing.sm),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _submitting
                                    ? null
                                    : () => context.go('/register-owner'),
                                child: Text(
                                  context.isSwahili
                                      ? 'Jisajili kama mmiliki au meneja'
                                      : 'Register as an owner or manager',
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
                                child: Text(
                                  context.isSwahili
                                      ? "Jisajili kama wakala"
                                      : "Register as an agent",
                                ),
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
