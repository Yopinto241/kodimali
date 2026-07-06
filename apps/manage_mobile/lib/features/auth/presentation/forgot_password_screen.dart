import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/launchers.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const String _adminPhoneNumber = "0628621737";
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  bool _submitting = false;
  bool _openingWhatsApp = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _openAdminWhatsApp() async {
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();
    final String username = _usernameController.text.trim();

    if (name.isEmpty || phone.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Enter your name, phone number, and username before opening WhatsApp help.",
          ),
        ),
      );
      return;
    }

    final String identifier = _identifierController.text.trim();
    final String message = [
      "Habari admin,",
      "Naomba msaada wa forgot password kwenye manage app.",
      "Jina: $name",
      "Namba ya simu: $phone",
      "Username: $username",
      if (identifier.isNotEmpty) "Identifier niliyojaribu: $identifier",
    ].join("\n");

    setState(() => _openingWhatsApp = true);
    try {
      await Launchers.openWhatsAppMessage(_adminPhoneNumber, message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
    } finally {
      if (mounted) {
        setState(() => _openingWhatsApp = false);
      }
    }
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
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  KodimaliSpacing.screenPadding.left,
                  KodimaliSpacing.screenPadding.top,
                  KodimaliSpacing.screenPadding.right,
                  KodimaliSpacing.screenPadding.bottom +
                      MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    minHeight:
                        constraints.maxHeight -
                        KodimaliSpacing.screenPadding.vertical,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                            borderRadius: BorderRadius.circular(
                              KodimaliRadii.hero,
                            ),
                            boxShadow: KodimaliShadows.lifted(
                              KodimaliColors.navy,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const KodimaliStatusBadge(
                                label: "Password help",
                                tone: KodimaliStatusTone.pending,
                              ),
                              const SizedBox(height: KodimaliSpacing.sm),
                              Text(
                                "Umesahau nenosiri?",
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: KodimaliSpacing.xs),
                              Text(
                                "Tuma reset link kwenye recovery email yako, au muombe admin msaada wa WhatsApp kama akaunti yako haina recovery email.",
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  "Tuma reset link",
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.sm),
                                Text(
                                  "Weka username, simu, au email. Ikiwa akaunti ina recovery email, Supabase itatuma link ya kubadili nenosiri huko.",
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: KodimaliSpacing.lg),
                                TextFormField(
                                  controller: _identifierController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: "Username, simu, au barua pepe",
                                    helperText:
                                        "Unaweza kuanza na username, phone, au email.",
                                  ),
                                  validator: (String? value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return "Weka username, simu, au email.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.sm),
                                Text(
                                  "Kama akaunti iliundwa bila recovery email, reset ya email haitatumika. Ukiwa umeingia unaweza kutumia change password, au tumia msaada wa admin hapa chini.",
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: KodimaliSpacing.lg),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _submitting ? null : _submit,
                                    child: Text(
                                      _submitting ? "Inatuma..." : "Tuma link",
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: KodimaliSpacing.md),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(KodimaliSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  "Msaada wa admin kwa WhatsApp",
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.sm),
                                Text(
                                  "Jaza taarifa hizi ili ujumbe wa WhatsApp uwe tayari na admin akusaidie haraka.",
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: KodimaliSpacing.lg),
                                TextFormField(
                                  controller: _nameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: "Jina lako",
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: "Namba yako ya simu",
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _usernameController,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: "Username yako",
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.lg),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _openingWhatsApp
                                        ? null
                                        : _openAdminWhatsApp,
                                    icon: const Icon(Icons.chat_outlined),
                                    label: Text(
                                      _openingWhatsApp
                                          ? "Inafungua WhatsApp..."
                                          : "Pata msaada wa admin kwa WhatsApp",
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: KodimaliSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => context.go("/login"),
                            child: const Text("Back to login"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
