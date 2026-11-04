import 'package:flutter_core/localized_ui.dart';
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
  String? _message;
  final _messageKey = GlobalKey();

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
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      await dependencies.controller.signIn(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = userFacingError(error);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final messageContext = _messageKey.currentContext;
        if (mounted && messageContext != null) {
          Scrollable.ensureVisible(messageContext, alignment: .3);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final messageBackground = Color(dark ? 0xFF402427 : 0xFFFFF1EE);
    final messageForeground = Color(dark ? 0xFFFFE3E0 : 0xFF722B24);
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
                          context.isSwahili
                              ? mobileUi(context, "Karibu tena")
                              : mobileUi(context, "Welcome back"),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: KodimaliSpacing.xs),
                        Text(
                          context.isSwahili
                              ? mobileUi(
                                  context,
                                  "Ingia kwenye KODIMALI Manage App ya wakala, mmiliki au admin.",
                                )
                              : mobileUi(
                                  context,
                                  "Sign in to the KODIMALI Manage App as an agent, owner, or administrator.",
                                ),
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
                            if (_message != null) ...[
                              Semantics(
                                key: _messageKey,
                                liveRegion: true,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: messageBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Color(
                                        dark ? 0xFFE49A91 : 0xFF963D32,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: messageForeground,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: LocalizedUiText(
                                          _message!,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                color: messageForeground,
                                                fontSize: 16,
                                                height: 1.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                            Text(
                              context.isSwahili
                                  ? mobileUi(
                                      context,
                                      "Tumia jina la mtumiaji, namba ya simu au barua pepe pamoja na nenosiri lako. Mfumo utafungua sehemu sahihi ya kazi.",
                                    )
                                  : mobileUi(
                                      context,
                                      "Use your username, phone number, or email with your password. The correct workspace will open automatically.",
                                    ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: KodimaliSpacing.lg),
                            TextFormField(
                              controller: _identifierController,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                helperMaxLines: 3,
                                errorMaxLines: 4,
                                labelText: context.isSwahili
                                    ? mobileUi(
                                        context,
                                        "Jina la mtumiaji, simu au barua pepe",
                                      )
                                    : mobileUi(
                                        context,
                                        "Username, phone, or email",
                                      ),
                                helperText: context.isSwahili
                                    ? mobileUi(
                                        context,
                                        "Tumia njia yoyote kati ya hizo.",
                                      )
                                    : mobileUi(
                                        context,
                                        "Use any one of these identifiers.",
                                      ),
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return context.isSwahili
                                      ? mobileUi(
                                          context,
                                          "Weka jina la mtumiaji, simu au barua pepe.",
                                        )
                                      : mobileUi(
                                          context,
                                          "Enter your username, phone, or email.",
                                        );
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: KodimaliSpacing.md),
                            TextFormField(
                              controller: _passwordController,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              obscureText: true,
                              decoration: InputDecoration(
                                helperMaxLines: 3,
                                errorMaxLines: 4,
                                labelText: context.isSwahili
                                    ? mobileUi(context, "Nenosiri")
                                    : mobileUi(context, "Password"),
                                helperText: context.isSwahili
                                    ? mobileUi(context, "Angalau herufi 6.")
                                    : mobileUi(
                                        context,
                                        "At least 6 characters.",
                                      ),
                              ),
                              validator: (String? value) {
                                if (value == null || value.length < 6) {
                                  return context.isSwahili
                                      ? mobileUi(
                                          context,
                                          "Nenosiri liwe angalau herufi 6.",
                                        )
                                      : mobileUi(
                                          context,
                                          "Password must have at least 6 characters.",
                                        );
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
                                      ? mobileUi(context, "Umesahau nenosiri?")
                                      : mobileUi(context, "Forgot password?"),
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
                                            ? mobileUi(context, "Inaingia...")
                                            : mobileUi(
                                                context,
                                                "Signing in...",
                                              ))
                                      : (context.isSwahili
                                            ? mobileUi(context, "Ingia")
                                            : mobileUi(context, "Sign in")),
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
                                      ? mobileUi(
                                          context,
                                          'Jisajili kama mmiliki au meneja',
                                        )
                                      : mobileUi(
                                          context,
                                          'Register as an owner or manager',
                                        ),
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
                                      ? mobileUi(
                                          context,
                                          "Jisajili kama wakala",
                                        )
                                      : mobileUi(
                                          context,
                                          "Register as an agent",
                                        ),
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
