import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/agent_location_fields.dart';
import '../../../core/widgets/app_scope.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _activationEmailController =
      TextEditingController();
  final TextEditingController _nidaController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessDescriptionController =
      TextEditingController();

  bool _submitting = false;
  bool _initialized = false;
  bool _loadingOptions = true;
  String? _optionsError;
  List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[];
  AgentLocationSelection _locationSelection = const AgentLocationSelection();
  String? _selectedCategoryId;
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  String? _usernameStatusText;
  int _usernameLookupToken = 0;
  Timer? _usernameDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    unawaited(_loadOptions());
  }

  Future<void> _loadOptions() async {
    final repository = AppScope.of(context).repository;
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final List<Map<String, dynamic>> categories =
          await repository.fetchCategoriesForAgentAssignment();
      if (!mounted) {
        return;
      }
      setState(() {
        _categories = categories;
        _selectedCategoryId ??= categories.isNotEmpty
            ? categories.first["id"] as String?
            : null;
        _loadingOptions = false;
        _optionsError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingOptions = false;
        _optionsError = userFacingError(error);
      });
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _fullNameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _activationEmailController.dispose();
    _nidaController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _businessNameController.dispose();
    _businessDescriptionController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    final String normalized = value.trim().toLowerCase();
    final int lookupToken = ++_usernameLookupToken;
    if (normalized.isEmpty) {
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = null;
        _usernameStatusText = null;
      });
      return;
    }
    if (!RegExp(r"^[a-z0-9_]{3,32}$").hasMatch(normalized)) {
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = false;
        _usernameStatusText =
            "Use 3-32 lowercase letters, numbers, or underscores.";
      });
      return;
    }

    _usernameDebounce?.cancel();
    setState(() {
      _checkingUsername = true;
      _usernameAvailable = null;
      _usernameStatusText = "Checking username...";
    });
    _usernameDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || lookupToken != _usernameLookupToken) {
        return;
      }
      unawaited(_checkUsernameAvailability(normalized, lookupToken));
    });
  }

  Future<void> _checkUsernameAvailability(
    String normalized,
    int lookupToken,
  ) async {
    try {
      final bool available = await AppScope.of(
        context,
      ).repository.isUsernameAvailable(normalized);
      if (!mounted || lookupToken != _usernameLookupToken) {
        return;
      }
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = available;
        _usernameStatusText = available
            ? "Username is available."
            : "Username is already taken.";
      });
    } catch (error) {
      if (!mounted || lookupToken != _usernameLookupToken) {
        return;
      }
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = null;
        _usernameStatusText = userFacingError(error);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Choose the base category first.")),
      );
      return;
    }
    if (_locationSelection.regionId == null ||
        _locationSelection.districtId == null ||
        _locationSelection.wardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Choose region, district, ward, and area first."),
        ),
      );
      return;
    }

    final dependencies = AppScope.of(context);
    final String normalizedUsername = _usernameController.text
        .trim()
        .toLowerCase();
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match yet.")),
      );
      return;
    }
    if (_usernameAvailable == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Choose another username first.")),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final String locationId = await dependencies.repository
          .resolveWardAreaLocation(
            selectedAreaId: _locationSelection.savedAreaId,
            wardId: _locationSelection.wardId,
            manualAreaName: _locationSelection.manualAreaName,
          );
      await dependencies.controller.registerAgentAccount(
        fullName: _fullNameController.text.trim(),
        username: normalizedUsername,
        phoneNumber: _phoneController.text.trim(),
        activationEmail: _activationEmailController.text.trim().toLowerCase(),
        password: _passwordController.text,
        locationId: locationId,
        nidaNumber: _nidaController.text.trim(),
        primaryCategoryId: _selectedCategoryId!,
        businessName: _businessNameController.text.trim(),
        businessDescription: _businessDescriptionController.text.trim().isEmpty
            ? null
            : _businessDescriptionController.text.trim(),
        preferredLanguage: "sw",
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Registration saved. Wait for admin approval before signing in as an agent.",
          ),
        ),
      );
      context.go("/login");
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

  String _selectedCategoryLabel() {
    for (final Map<String, dynamic> category in _categories) {
      if (category["id"] == _selectedCategoryId) {
        return category["name"] as String? ?? "-";
      }
    }
    return "Choose base category";
  }

  bool _matchesSearch(String label, String query) {
    final String normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(normalizedQuery);
  }

  Future<String?> _pickCategory() async {
    final TextEditingController searchController = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final String query = searchController.text;
            final List<Map<String, dynamic>> filteredCategories = _categories
                .where((Map<String, dynamic> category) {
                  final String label = category["name"] as String? ?? "";
                  return _matchesSearch(label, query);
                })
                .toList(growable: false);
            return FractionallySizedBox(
              heightFactor: 0.92,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            "Choose base category",
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        labelText: "Search category",
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filteredCategories.isEmpty
                        ? const Center(
                            child: Text("No category matches your search."),
                          )
                        : ListView(
                            children: filteredCategories.map((
                              Map<String, dynamic> category,
                            ) {
                              final String value =
                                  category["id"] as String? ?? "";
                              final String label =
                                  category["name"] as String? ?? "-";
                              return ListTile(
                                title: Text(label),
                                trailing: _selectedCategoryId == value
                                    ? const Icon(Icons.check_rounded)
                                    : null,
                                onTap: () =>
                                    Navigator.of(context).pop(value),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(searchController.dispose);
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
                    maxWidth: 520,
                    minHeight:
                        constraints.maxHeight -
                        KodimaliSpacing.screenPadding.vertical,
                  ),
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
                              label: "Agent registration",
                              tone: KodimaliStatusTone.pending,
                            ),
                            const SizedBox(height: KodimaliSpacing.sm),
                            Text(
                              "Jisajili kama agent",
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: KodimaliSpacing.xs),
                            Text(
                              "Chagua region, district, ward, kisha tumia area iliyopo au andika area mpya. Area mpya itaunganishwa moja kwa moja chini ya ward husika.",
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: KodimaliSpacing.md),
                      if (_optionsError != null) ...<Widget>[
                        Card(
                          color: theme.colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(KodimaliSpacing.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Icon(Icons.error_outline),
                                const SizedBox(width: KodimaliSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _optionsError!,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: KodimaliSpacing.sm),
                                TextButton(
                                  onPressed: _loadOptions,
                                  child: const Text("Retry"),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: KodimaliSpacing.md),
                      ],
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(KodimaliSpacing.lg),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (_loadingOptions) ...<Widget>[
                                  const LinearProgressIndicator(),
                                  const SizedBox(height: KodimaliSpacing.sm),
                                  Text(
                                    "Loading registration options...",
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: KodimaliSpacing.md),
                                ],
                                TextFormField(
                                  controller: _fullNameController,
                                  decoration: const InputDecoration(
                                    labelText: "Full name",
                                  ),
                                  validator: (String? value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return "Enter your full name.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _usernameController,
                                  onChanged: _onUsernameChanged,
                                  decoration: const InputDecoration(
                                    labelText: "Username",
                                    helperText:
                                        "Use 3-32 lowercase letters, numbers, or underscores.",
                                  ),
                                  validator: (String? value) {
                                    final String normalized =
                                        value?.trim().toLowerCase() ?? "";
                                    if (!RegExp(
                                      r"^[a-z0-9_]{3,32}$",
                                    ).hasMatch(normalized)) {
                                      return "Use 3-32 lowercase letters, numbers, or underscores.";
                                    }
                                    return null;
                                  },
                                ),
                                if (_usernameStatusText != null) ...<Widget>[
                                  const SizedBox(height: KodimaliSpacing.xs),
                                  Row(
                                    children: <Widget>[
                                      if (_checkingUsername)
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else if (_usernameAvailable == true)
                                        const Icon(
                                          Icons.check_circle_outline,
                                          size: 16,
                                          color: Colors.green,
                                        )
                                      else if (_usernameAvailable == false)
                                        const Icon(
                                          Icons.error_outline,
                                          size: 16,
                                          color: Colors.redAccent,
                                        ),
                                      if (_checkingUsername ||
                                          _usernameAvailable != null)
                                        const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _usernameStatusText!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    _usernameAvailable == true
                                                    ? Colors.green
                                                    : _usernameAvailable ==
                                                          false
                                                    ? Colors.redAccent
                                                    : null,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    labelText: "Mobile number (optional)",
                                  ),
                                  validator: (String? value) {
                                    final String normalized =
                                        value?.trim() ?? "";
                                    if (normalized.isNotEmpty &&
                                        normalized.length < 8) {
                                      return "Enter a valid phone number.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _activationEmailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText: "Account email",
                                    helperText:
                                        "Used for password recovery and email login. It is not used as the public agent contact email.",
                                  ),
                                  validator: (String? value) {
                                    if (value == null ||
                                        value.trim().isEmpty ||
                                        !value.contains("@")) {
                                      return "Enter a valid email address.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                AgentLocationFields(
                                  onChanged: (AgentLocationSelection value) {
                                    _locationSelection = value;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _nidaController,
                                  decoration: const InputDecoration(
                                    labelText: "NIDA number",
                                  ),
                                  validator: (String? value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return "Enter the NIDA number.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: "Password",
                                    helperText: "At least 6 characters.",
                                  ),
                                  validator: (String? value) {
                                    if (value == null || value.length < 6) {
                                      return "Password must be at least 6 characters.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: "Re-enter password",
                                    helperText:
                                        "Type the same password again to confirm it.",
                                  ),
                                  validator: (String? value) {
                                    if (value == null || value.isEmpty) {
                                      return "Re-enter the password.";
                                    }
                                    if (value != _passwordController.text) {
                                      return "Passwords do not match.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _businessNameController,
                                  decoration: const InputDecoration(
                                    labelText: "Business name",
                                  ),
                                  validator: (String? value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return "Enter the business name.";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                InkWell(
                                  onTap: _categories.isEmpty
                                      ? null
                                      : () async {
                                          final String? value =
                                              await _pickCategory();
                                          if (!mounted || value == null) {
                                            return;
                                          }
                                          setState(
                                            () => _selectedCategoryId = value,
                                          );
                                        },
                                  borderRadius: BorderRadius.circular(16),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: "Base category",
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(_selectedCategoryLabel()),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                TextFormField(
                                  controller: _businessDescriptionController,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText: "Business description",
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.md),
                                Text(
                                  "After registration, admin still needs to approve your agent account before you can use the agent workspace.",
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: KodimaliSpacing.lg),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed:
                                        _submitting ||
                                            _loadingOptions ||
                                            _categories.isEmpty
                                        ? null
                                        : _submit,
                                    child: Text(
                                      _submitting
                                          ? "Inahifadhi..."
                                          : "Submit registration",
                                    ),
                                  ),
                                ),
                                const SizedBox(height: KodimaliSpacing.sm),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: _submitting
                                        ? null
                                        : () => context.go("/login"),
                                    child: const Text("Back to login"),
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
            );
          },
        ),
      ),
    );
  }
}
