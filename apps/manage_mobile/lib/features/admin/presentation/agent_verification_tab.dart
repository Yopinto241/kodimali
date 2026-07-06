import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/agent_location_fields.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/kodimali_empty_state.dart';
import '../../../core/widgets/kodimali_status_chip.dart';
import '../../../core/widgets/manage_ui.dart';

class AgentVerificationTab extends StatefulWidget {
  const AgentVerificationTab({super.key});

  @override
  State<AgentVerificationTab> createState() => _AgentVerificationTabState();
}

class _AgentVerificationTabState extends State<AgentVerificationTab> {
  static const int _pageSize = 24;
  static const double _menuMaxHeight = 360;

  bool _initialized = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _agents = <Map<String, dynamic>>[];
  int _totalCount = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _loadError;
  String _searchText = "";
  String? _accountStatusFilter;
  String? _verificationStatusFilter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    unawaited(_loadAgents(reset: true));
  }

  Future<void> _refresh() async {
    await _loadAgents(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAgents({required bool reset}) async {
    if (_loading || _loadingMore) {
      return;
    }
    final bool append = !reset && _agents.isNotEmpty;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadError = null;
      }
    });
    try {
      final Map<String, dynamic> payload = await AppScope.of(context).repository
          .fetchAdminAgents(
            searchText: _searchText,
            accountStatus: _accountStatusFilter,
            verificationStatus: _verificationStatusFilter,
            limit: _pageSize,
            offset: append ? _agents.length : 0,
          );
      if (!mounted) {
        return;
      }
      final List<Map<String, dynamic>> items =
          (payload["items"] as List<dynamic>? ?? <dynamic>[])
              .cast<Map<String, dynamic>>();
      setState(() {
        if (append) {
          _agents = <Map<String, dynamic>>[..._agents, ...items];
        } else {
          _agents = items;
        }
        _totalCount = (payload["total_count"] as num?)?.toInt() ?? items.length;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = userFacingError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      setState(() => _searchText = value.trim());
      unawaited(_loadAgents(reset: true));
    });
  }

  Future<void> _setAccountStatusFilter(String? value) async {
    setState(() => _accountStatusFilter = value);
    await _loadAgents(reset: true);
  }

  Future<void> _setVerificationStatusFilter(String? value) async {
    setState(() => _verificationStatusFilter = value);
    await _loadAgents(reset: true);
  }

  Future<void> _clearFilters() async {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchText = "";
      _accountStatusFilter = null;
      _verificationStatusFilter = null;
    });
    await _loadAgents(reset: true);
  }

  int _countAccountStatus(String value) {
    return _agents
        .where(
          (Map<String, dynamic> agent) =>
              (agent["account_status"] as String? ?? "") == value,
        )
        .length;
  }

  int _countVerificationStatus(String value) {
    return _agents
        .where(
          (Map<String, dynamic> agent) =>
              (agent["verification_status"] as String? ?? "") == value,
        )
        .length;
  }

  bool get _hasFiltersApplied =>
      _searchText.isNotEmpty ||
      _accountStatusFilter != null ||
      _verificationStatusFilter != null;

  bool get _hasMoreResults => _agents.length < _totalCount;

  String _formatDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "-";
    }
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final String month = parsed.month.toString().padLeft(2, "0");
    final String day = parsed.day.toString().padLeft(2, "0");
    return "${parsed.year}-$month-$day";
  }

  List<Map<String, dynamic>> _agentCategories(Map<String, dynamic> agent) {
    final List<dynamic> raw =
        agent["agent_service_categories"] as List<dynamic>? ?? <dynamic>[];
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (final dynamic entry in raw) {
      final Map<String, dynamic> row = (entry as Map).cast<String, dynamic>();
      final Map<String, dynamic>? category = (row["asset_categories"] as Map?)
          ?.cast<String, dynamic>();
      if (category == null) {
        continue;
      }
      items.add(<String, dynamic>{
        ...category,
        "assignment_category_id": row["category_id"],
        "is_primary": row["is_primary"] == true,
      });
    }
    items.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int primaryCompare = ((b["is_primary"] == true) ? 1 : 0).compareTo(
        (a["is_primary"] == true) ? 1 : 0,
      );
      if (primaryCompare != 0) {
        return primaryCompare;
      }
      return (a["name"] as String? ?? "").compareTo(b["name"] as String? ?? "");
    });
    return items;
  }

  Future<void> _setStatus(
    String agentId,
    String accountStatus, {
    String? verificationStatus,
    String? note,
  }) async {
    await AppScope.of(context).repository.updateAgentVerification(
      agentId: agentId,
      accountStatus: accountStatus,
      verificationStatus: verificationStatus,
      note: note,
    );
    await _refresh();
  }

  String _emailStatusLabel(Map<String, dynamic>? profile) {
    final String? confirmedAt =
        profile?["account_email_confirmed_at"] as String?;
    if (confirmedAt == null || confirmedAt.isEmpty) {
      return "pending";
    }
    return "confirmed";
  }

  Future<void> _openAddAgentDialog() async {
    final repository = AppScope.of(context).repository;
    final List<Map<String, dynamic>> profiles = await repository
        .fetchProfilesAvailableForAgentCreation();
    final List<Map<String, dynamic>> categories = await repository
        .fetchCategoriesForAgentAssignment();
    if (!mounted) {
      return;
    }
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No free user profiles are available to convert into agents.",
          ),
        ),
      );
      return;
    }
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Create at least one active category first."),
        ),
      );
      return;
    }
    String? selectedProfileId = profiles.first["id"] as String?;
    String? selectedPrimaryCategoryId = categories.first["id"] as String?;
    AgentLocationSelection selectedLocation = const AgentLocationSelection();
    final TextEditingController displayNameController = TextEditingController(
      text: profiles.first["full_name"] as String? ?? "",
    );
    final TextEditingController phoneController = TextEditingController(
      text: profiles.first["phone_number"] as String? ?? "",
    );
    final TextEditingController nidaController = TextEditingController();
    final TextEditingController businessNameController = TextEditingController(
      text: profiles.first["full_name"] as String? ?? "",
    );
    final TextEditingController businessDescriptionController =
        TextEditingController();
    bool submitting = false;

    final bool? created = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                return AlertDialog(
                  title: const Text("Add agent"),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          menuMaxHeight: _menuMaxHeight,
                          initialValue: selectedProfileId,
                          decoration: const InputDecoration(
                            labelText: "Existing user",
                          ),
                          items: profiles.map((Map<String, dynamic> profile) {
                            final String fullName =
                                profile["full_name"] as String? ?? "-";
                            final String username =
                                profile["username"] as String? ?? "-";
                            final String phone =
                                profile["phone_number"] as String? ?? "";
                            final String label = "$fullName - @$username";
                            return DropdownMenuItem<String>(
                              value: profile["id"] as String,
                              child: Text(
                                phone.isEmpty ? label : "$label - $phone",
                              ),
                            );
                          }).toList(),
                          onChanged: (String? value) {
                            setModalState(() {
                              selectedProfileId = value;
                              final Map<String, dynamic>? selected = profiles
                                  .cast<Map<String, dynamic>?>()
                                  .firstWhere(
                                    (Map<String, dynamic>? profile) =>
                                        profile?["id"] == value,
                                    orElse: () => null,
                                  );
                              if (selected != null) {
                                displayNameController.text =
                                    selected["full_name"] as String? ?? "";
                                phoneController.text =
                                    selected["phone_number"] as String? ?? "";
                                if (businessNameController.text
                                    .trim()
                                    .isEmpty) {
                                  businessNameController.text =
                                      selected["full_name"] as String? ?? "";
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: displayNameController,
                          decoration: const InputDecoration(
                            labelText: "Agent name",
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: "Mobile number",
                          ),
                        ),
                        const SizedBox(height: 16),
                        AgentLocationFields(
                          onChanged: (AgentLocationSelection value) {
                            setModalState(() => selectedLocation = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nidaController,
                          decoration: const InputDecoration(
                            labelText: "NIDA number",
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          menuMaxHeight: _menuMaxHeight,
                          initialValue: selectedPrimaryCategoryId,
                          decoration: const InputDecoration(
                            labelText: "Base category",
                          ),
                          items: categories.map((
                            Map<String, dynamic> category,
                          ) {
                            return DropdownMenuItem<String>(
                              value: category["id"] as String,
                              child: Text(category["name"] as String? ?? "-"),
                            );
                          }).toList(),
                          onChanged: (String? value) {
                            setModalState(
                              () => selectedPrimaryCategoryId = value,
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: businessNameController,
                          decoration: const InputDecoration(
                            labelText: "Business name",
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: businessDescriptionController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: "Business description",
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "New agents start inactive. Their base category becomes the default category they can work in while active.",
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text("Cancel"),
                    ),
                    FilledButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              if (selectedProfileId == null ||
                                  selectedPrimaryCategoryId == null ||
                                  selectedLocation.regionId == null ||
                                  selectedLocation.districtId == null ||
                                  selectedLocation.wardId == null ||
                                  displayNameController.text.trim().isEmpty ||
                                  phoneController.text.trim().isEmpty ||
                                  nidaController.text.trim().isEmpty) {
                                return;
                              }
                              setModalState(() => submitting = true);
                              try {
                                final String locationId = await repository
                                    .resolveWardAreaLocation(
                                      selectedAreaId:
                                          selectedLocation.savedAreaId,
                                      wardId: selectedLocation.wardId,
                                      manualAreaName:
                                          selectedLocation.manualAreaName,
                                    );
                                await repository.createAgentFromProfile(
                                  profileId: selectedProfileId!,
                                  displayName: displayNameController.text
                                      .trim(),
                                  phoneNumber: phoneController.text.trim(),
                                  locationId: locationId,
                                  nidaNumber: nidaController.text.trim(),
                                  primaryCategoryId: selectedPrimaryCategoryId!,
                                  businessName: businessNameController.text
                                      .trim(),
                                  businessDescription:
                                      businessDescriptionController.text
                                          .trim()
                                          .isEmpty
                                      ? null
                                      : businessDescriptionController.text
                                            .trim(),
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(userFacingError(error)),
                                    ),
                                  );
                                }
                                setModalState(() => submitting = false);
                              }
                            },
                      child: Text(submitting ? "Saving..." : "Create agent"),
                    ),
                  ],
                );
              },
        );
      },
    );

    businessNameController.dispose();
    businessDescriptionController.dispose();
    displayNameController.dispose();
    phoneController.dispose();
    nidaController.dispose();

    if (created == true) {
      await _refresh();
    }
  }

  Future<void> _openCreateAgentAccountDialog() async {
    final repository = AppScope.of(context).repository;
    final List<Map<String, dynamic>> categories = await repository
        .fetchCategoriesForAgentAssignment();
    if (!mounted) {
      return;
    }
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Create at least one active category first."),
        ),
      );
      return;
    }
    final TextEditingController fullNameController = TextEditingController();
    final TextEditingController usernameController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController nidaController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmPasswordController =
        TextEditingController();
    final TextEditingController businessNameController =
        TextEditingController();
    final TextEditingController businessDescriptionController =
        TextEditingController();
    String? selectedPrimaryCategoryId = categories.first["id"] as String?;
    AgentLocationSelection selectedLocation = const AgentLocationSelection();
    bool submitting = false;
    bool checkingUsername = false;
    bool? usernameAvailable;
    String? usernameStatusText;
    int usernameLookupToken = 0;
    String latestUsernameQuery = "";
    bool dialogActive = true;

    Future<void> scheduleUsernameCheck(
      String value,
      void Function(void Function()) setModalState,
    ) async {
      final String normalized = value.trim().toLowerCase();
      latestUsernameQuery = normalized;
      if (normalized.isEmpty) {
        setModalState(() {
          checkingUsername = false;
          usernameAvailable = null;
          usernameStatusText = null;
        });
        return;
      }
      if (!RegExp(r"^[a-z0-9_]{3,32}$").hasMatch(normalized)) {
        setModalState(() {
          checkingUsername = false;
          usernameAvailable = false;
          usernameStatusText =
              "Use 3-32 lowercase letters, numbers, or underscores.";
        });
        return;
      }
      setModalState(() {
        checkingUsername = true;
        usernameAvailable = null;
        usernameStatusText = "Checking username...";
      });
      final int lookupToken = ++usernameLookupToken;
      try {
        final bool available = await repository.isUsernameAvailable(normalized);
        if (!dialogActive ||
            !context.mounted ||
            lookupToken != usernameLookupToken ||
            latestUsernameQuery != normalized) {
          return;
        }
        setModalState(() {
          checkingUsername = false;
          usernameAvailable = available;
          usernameStatusText = available
              ? "Username is available."
              : "Username is already taken.";
        });
      } catch (error) {
        if (!dialogActive ||
            !context.mounted ||
            lookupToken != usernameLookupToken ||
            latestUsernameQuery != normalized) {
          return;
        }
        setModalState(() {
          checkingUsername = false;
          usernameAvailable = null;
          usernameStatusText = userFacingError(error);
        });
      }
    }

    final bool? created = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                return AlertDialog(
                  title: const Text("Create agent account"),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextField(
                          controller: fullNameController,
                          decoration: const InputDecoration(
                            labelText: "Full name",
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: "Mobile number",
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: usernameController,
                          onChanged: (String value) {
                            scheduleUsernameCheck(value, setModalState);
                          },
                          decoration: const InputDecoration(
                            labelText: "Username",
                            helperText:
                                "3-32 lowercase letters, numbers, or underscores.",
                          ),
                        ),
                        if (usernameStatusText != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              if (checkingUsername)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else if (usernameAvailable == true)
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                  color: Colors.green,
                                )
                              else if (usernameAvailable == false)
                                const Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: Colors.redAccent,
                                ),
                              if (checkingUsername || usernameAvailable != null)
                                const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  usernameStatusText!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: usernameAvailable == true
                                            ? Colors.green
                                            : usernameAvailable == false
                                            ? Colors.redAccent
                                            : null,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        AgentLocationFields(
                          onChanged: (AgentLocationSelection value) {
                            setModalState(() => selectedLocation = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nidaController,
                          decoration: const InputDecoration(
                            labelText: "NIDA number",
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "Password",
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "Re-enter password",
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: businessNameController,
                          decoration: const InputDecoration(
                            labelText: "Business name",
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          menuMaxHeight: _menuMaxHeight,
                          initialValue: selectedPrimaryCategoryId,
                          decoration: const InputDecoration(
                            labelText: "Base category",
                          ),
                          items: categories.map((
                            Map<String, dynamic> category,
                          ) {
                            return DropdownMenuItem<String>(
                              value: category["id"] as String,
                              child: Text(category["name"] as String? ?? "-"),
                            );
                          }).toList(),
                          onChanged: (String? value) {
                            setModalState(
                              () => selectedPrimaryCategoryId = value,
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: businessDescriptionController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: "Business description",
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "The system generates the internal account email automatically. The new account starts inactive until admin activation.",
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text("Cancel"),
                    ),
                    FilledButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              if (passwordController.text !=
                                  confirmPasswordController.text) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Passwords do not match yet.",
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (fullNameController.text.trim().isEmpty ||
                                  !RegExp(r"^[a-z0-9_]{3,32}$").hasMatch(
                                    usernameController.text
                                        .trim()
                                        .toLowerCase(),
                                  ) ||
                                  phoneController.text.trim().isEmpty ||
                                  nidaController.text.trim().isEmpty ||
                                  selectedLocation.regionId == null ||
                                  selectedLocation.districtId == null ||
                                  selectedLocation.wardId == null ||
                                  usernameAvailable == false ||
                                  passwordController.text.length < 6 ||
                                  selectedPrimaryCategoryId == null) {
                                return;
                              }
                              setModalState(() => submitting = true);
                              try {
                                final String locationId = await repository
                                    .resolveWardAreaLocation(
                                      selectedAreaId:
                                          selectedLocation.savedAreaId,
                                      wardId: selectedLocation.wardId,
                                      manualAreaName:
                                          selectedLocation.manualAreaName,
                                    );
                                await repository.createAgentAccount(
                                  username: usernameController.text
                                      .trim()
                                      .toLowerCase(),
                                  password: passwordController.text,
                                  fullName: fullNameController.text.trim(),
                                  phoneNumber: phoneController.text.trim(),
                                  locationId: locationId,
                                  nidaNumber: nidaController.text.trim(),
                                  businessName:
                                      businessNameController.text.trim().isEmpty
                                      ? null
                                      : businessNameController.text.trim(),
                                  primaryCategoryId: selectedPrimaryCategoryId!,
                                  businessDescription:
                                      businessDescriptionController.text
                                          .trim()
                                          .isEmpty
                                      ? null
                                      : businessDescriptionController.text
                                            .trim(),
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(userFacingError(error)),
                                    ),
                                  );
                                }
                                setModalState(() => submitting = false);
                              }
                            },
                      child: Text(
                        submitting ? "Creating..." : "Create account",
                      ),
                    ),
                  ],
                );
              },
        );
      },
    );

    dialogActive = false;
    fullNameController.dispose();
    usernameController.dispose();
    phoneController.dispose();
    nidaController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    businessNameController.dispose();
    businessDescriptionController.dispose();

    if (created == true) {
      await _refresh();
    }
  }

  Future<void> _openCategoryAssignmentDialog(Map<String, dynamic> agent) async {
    final repository = AppScope.of(context).repository;
    final List<Map<String, dynamic>> categories = await repository
        .fetchCategoriesForAgentAssignment();
    if (!mounted) {
      return;
    }
    final List<Map<String, dynamic>> currentAssignments = _agentCategories(
      agent,
    );
    final Set<String> selectedIds = currentAssignments
        .map((Map<String, dynamic> item) => item["id"] as String? ?? "")
        .where((String value) => value.isNotEmpty)
        .toSet();
    String? primaryCategoryId;
    for (final Map<String, dynamic> item in currentAssignments) {
      if (item["is_primary"] == true) {
        primaryCategoryId = item["id"] as String?;
        break;
      }
    }
    primaryCategoryId ??= categories.isEmpty
        ? null
        : categories.first["id"] as String?;
    bool submitting = false;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                return AlertDialog(
                  title: const Text("Agent categories"),
                  content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            "Assign the categories this agent can post in. Keep one base category selected while the agent is active.",
                          ),
                          const SizedBox(height: 16),
                          ...categories.map((Map<String, dynamic> category) {
                            final String categoryId = category["id"] as String;
                            final bool selected = selectedIds.contains(
                              categoryId,
                            );
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: <Widget>[
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: selected,
                                      title: Text(
                                        category["name"] as String? ?? "-",
                                      ),
                                      subtitle: Text(
                                        category["slug"] as String? ?? "",
                                      ),
                                      onChanged: (bool? value) {
                                        setModalState(() {
                                          if (value == true) {
                                            selectedIds.add(categoryId);
                                            primaryCategoryId ??= categoryId;
                                          } else {
                                            selectedIds.remove(categoryId);
                                            if (primaryCategoryId ==
                                                categoryId) {
                                              primaryCategoryId =
                                                  selectedIds.isEmpty
                                                  ? null
                                                  : selectedIds.first;
                                            }
                                          }
                                        });
                                      },
                                    ),
                                    if (selected)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: ChoiceChip(
                                          label: const Text(
                                            "Use as base category",
                                          ),
                                          selected:
                                              primaryCategoryId == categoryId,
                                          onSelected: (bool value) {
                                            if (!value) {
                                              return;
                                            }
                                            setModalState(() {
                                              primaryCategoryId = categoryId;
                                            });
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text("Cancel"),
                    ),
                    FilledButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              if (selectedIds.isEmpty ||
                                  primaryCategoryId == null) {
                                return;
                              }
                              setModalState(() => submitting = true);
                              try {
                                await repository.saveAgentCategoryAssignments(
                                  agentId: agent["id"] as String,
                                  categoryIds: selectedIds.toList(),
                                  primaryCategoryId: primaryCategoryId!,
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(userFacingError(error)),
                                    ),
                                  );
                                }
                                setModalState(() => submitting = false);
                              }
                            },
                      child: Text(submitting ? "Saving..." : "Save categories"),
                    ),
                  ],
                );
              },
        );
      },
    );

    if (saved == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _agents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _agents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => unawaited(_loadAgents(reset: true)),
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    final List<Map<String, dynamic>> agents = _agents;
    final int activeCount = _countAccountStatus("active");
    final int pendingVerificationCount = _countVerificationStatus("pending");
    final int suspendedCount = _countAccountStatus("suspended");

    return ManagePageScrollView(
      onRefresh: _refresh,
      children: <Widget>[
        ManageHeroCard(
          title: "Agent management",
          subtitle:
              "Search agents quickly, review their account health, and keep verification separate from activation.",
          bottom: ManageMetaWrap(
            items: <String>[
              "$_totalCount matching agent${_totalCount == 1 ? "" : "s"}",
              "Showing ${agents.length} loaded result${agents.length == 1 ? "" : "s"}",
              "Verification and activation stay separate",
            ],
          ),
        ),
        const SizedBox(height: 18),
        ManageMetricGrid(
          children: <Widget>[
            ManageMetricCard(
              label: "Matching agents",
              value: _totalCount.toString(),
              icon: Icons.groups_rounded,
            ),
            ManageMetricCard(
              label: "Active on screen",
              value: activeCount.toString(),
              icon: Icons.verified_user_outlined,
            ),
            ManageMetricCard(
              label: "Pending badge",
              value: pendingVerificationCount.toString(),
              icon: Icons.pending_actions_outlined,
            ),
            ManageMetricCard(
              label: "Suspended on screen",
              value: suspendedCount.toString(),
              icon: Icons.block_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        ManagePanel(
          title: "Search and filters",
          subtitle:
              "Search by public name, username, phone number, NIDA, business, email, or location.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _searchController,
                onChanged: (String value) {
                  setState(() {});
                  _handleSearchChanged(value);
                },
                decoration: InputDecoration(
                  labelText: "Search agents",
                  hintText: "Name, username, phone, NIDA, business, location",
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              _FilterSection(
                label: "Account status",
                children: <Widget>[
                  _FilterChip(
                    label: "All",
                    selected: _accountStatusFilter == null,
                    onSelected: () => _setAccountStatusFilter(null),
                  ),
                  _FilterChip(
                    label: "Active",
                    selected: _accountStatusFilter == "active",
                    onSelected: () => _setAccountStatusFilter("active"),
                  ),
                  _FilterChip(
                    label: "Inactive",
                    selected: _accountStatusFilter == "inactive",
                    onSelected: () => _setAccountStatusFilter("inactive"),
                  ),
                  _FilterChip(
                    label: "Suspended",
                    selected: _accountStatusFilter == "suspended",
                    onSelected: () => _setAccountStatusFilter("suspended"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FilterSection(
                label: "Badge status",
                children: <Widget>[
                  _FilterChip(
                    label: "All",
                    selected: _verificationStatusFilter == null,
                    onSelected: () => _setVerificationStatusFilter(null),
                  ),
                  _FilterChip(
                    label: "Approved",
                    selected: _verificationStatusFilter == "approved",
                    onSelected: () => _setVerificationStatusFilter("approved"),
                  ),
                  _FilterChip(
                    label: "Pending",
                    selected: _verificationStatusFilter == "pending",
                    onSelected: () => _setVerificationStatusFilter("pending"),
                  ),
                  _FilterChip(
                    label: "Rejected",
                    selected: _verificationStatusFilter == "rejected",
                    onSelected: () => _setVerificationStatusFilter("rejected"),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _openAddAgentDialog,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text("Add agent"),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openCreateAgentAccountDialog,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text("Create account"),
                  ),
                  if (_hasFiltersApplied)
                    OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text("Clear filters"),
                    ),
                ],
              ),
              if (_loadError != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _loadError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (agents.isEmpty)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                KodimaliEmptyState(
                  title: _hasFiltersApplied
                      ? "No matching agents"
                      : "Hakuna agents",
                  message: _hasFiltersApplied
                      ? "Try a different name, username, phone number, or status filter."
                      : "Agent accounts will appear here for activation, category assignment, and suspension.",
                ),
              ],
            ),
          )
        else
          ...agents.map((Map<String, dynamic> agent) {
            final Map<String, dynamic>? profile =
                agent["profiles"] as Map<String, dynamic>?;
            final List<dynamic> documents =
                agent["agent_documents"] as List<dynamic>? ?? <dynamic>[];
            final List<Map<String, dynamic>> assignedCategories =
                _agentCategories(agent);
            final String accountStatus =
                agent["account_status"] as String? ?? "inactive";
            final String verificationStatus =
                agent["verification_status"] as String? ?? "pending";
            final bool verified = verificationStatus == "approved";
            final String displayName =
                agent["display_name"] as String? ??
                profile?["full_name"] as String? ??
                "-";
            final String phone =
                agent["phone_number"] as String? ??
                profile?["phone_number"] as String? ??
                "-";
            final String location =
                agent["public_location_label"] as String? ?? "-";
            final String username = profile?["username"] as String? ?? "-";
            final String accountEmail =
                profile?["account_email"] as String? ?? "-";
            final String emailStatus = _emailStatusLabel(profile);
            final String preferredLanguage =
                profile?["preferred_language"] as String? ?? "sw";
            final String nida = agent["nida_number"] as String? ?? "-";
            final String? photoUrl = agent["profile_photo_url"] as String?;
            final String businessName =
                agent["business_name"] as String? ?? "-";
            final String businessDescription =
                agent["business_description"] as String? ?? "";
            final String profileName = profile?["full_name"] as String? ?? "-";
            final String createdAt = _formatDate(
              agent["created_at"] as String?,
            );
            final String verifiedAt = _formatDate(
              agent["verified_at"] as String?,
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ManagePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _AgentCardAvatar(
                          imageUrl: photoUrl,
                          fallbackText: displayName,
                          verified: verified,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                displayName,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                businessName,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  KodimaliStatusChip(
                                    label: accountStatus,
                                    highlight: accountStatus == "active",
                                  ),
                                  KodimaliStatusChip(
                                    label: verificationStatus,
                                    highlight: verificationStatus == "approved",
                                  ),
                                  if (verifiedAt != "-")
                                    Chip(label: Text("Verified $verifiedAt")),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 18,
                      runSpacing: 10,
                      children: <Widget>[
                        _AgentInfoLine(
                          icon: Icons.alternate_email_rounded,
                          label: "Username",
                          value: username,
                        ),
                        _AgentInfoLine(
                          icon: Icons.phone_outlined,
                          label: "Phone",
                          value: phone,
                        ),
                        _AgentInfoLine(
                          icon: Icons.email_outlined,
                          label: "Account email",
                          value: accountEmail,
                        ),
                        _AgentInfoLine(
                          icon: Icons.mark_email_read_outlined,
                          label: "Email status",
                          value: emailStatus,
                        ),
                        _AgentInfoLine(
                          icon: Icons.badge_outlined,
                          label: "Login profile",
                          value: profileName,
                        ),
                        _AgentInfoLine(
                          icon: Icons.language_outlined,
                          label: "Language",
                          value: preferredLanguage,
                        ),
                        _AgentInfoLine(
                          icon: Icons.place_outlined,
                          label: "Location",
                          value: location,
                        ),
                        _AgentInfoLine(
                          icon: Icons.perm_identity_outlined,
                          label: "NIDA",
                          value: nida,
                        ),
                        _AgentInfoLine(
                          icon: Icons.event_available_outlined,
                          label: "Created",
                          value: createdAt,
                        ),
                      ],
                    ),
                    if (businessDescription.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _AgentDetailBlock(
                        title: "Business details",
                        child: Text(businessDescription),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _AgentDetailBlock(
                      title: "Assigned categories",
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: assignedCategories.isEmpty
                            ? const <Widget>[
                                Chip(label: Text("No category assigned")),
                              ]
                            : assignedCategories.map((
                                Map<String, dynamic> category,
                              ) {
                                final String label =
                                    category["is_primary"] == true
                                    ? "${category["name"]} - base"
                                    : category["name"] as String? ?? "-";
                                return Chip(label: Text(label));
                              }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AgentDetailBlock(
                      title: "Documents",
                      child: documents.isEmpty
                          ? const Text("No documents uploaded yet.")
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: documents.map((dynamic doc) {
                                return Chip(
                                  label: Text(
                                    doc["document_type"] as String? ??
                                        "Document",
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    if (agent["deactivation_reason"] != null &&
                        (agent["deactivation_reason"] as String)
                            .trim()
                            .isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _AgentDetailBlock(
                        title: "Status note",
                        child: Text(agent["deactivation_reason"] as String),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton(
                          onPressed: accountStatus == "active"
                              ? null
                              : () =>
                                    _setStatus(agent["id"] as String, "active"),
                          child: const Text("Activate"),
                        ),
                        OutlinedButton(
                          onPressed: verified
                              ? null
                              : () => _setStatus(
                                  agent["id"] as String,
                                  accountStatus,
                                  verificationStatus: "approved",
                                  note: "Verified by admin",
                                ),
                          child: const Text("Verify badge"),
                        ),
                        OutlinedButton(
                          onPressed: verificationStatus == "pending"
                              ? null
                              : () => _setStatus(
                                  agent["id"] as String,
                                  accountStatus,
                                  verificationStatus: "pending",
                                  note: "Verification reset by admin",
                                ),
                          child: const Text("Mark pending"),
                        ),
                        OutlinedButton(
                          onPressed: () => _openCategoryAssignmentDialog(agent),
                          child: const Text("Categories"),
                        ),
                        OutlinedButton(
                          onPressed: accountStatus == "inactive"
                              ? null
                              : () => _setStatus(
                                  agent["id"] as String,
                                  "inactive",
                                  note: "Offline activation pending",
                                ),
                          child: const Text("Deactivate"),
                        ),
                        OutlinedButton(
                          onPressed: verificationStatus == "rejected"
                              ? null
                              : () => _setStatus(
                                  agent["id"] as String,
                                  accountStatus,
                                  verificationStatus: "rejected",
                                  note: "Verification rejected by admin",
                                ),
                          child: const Text("Reject badge"),
                        ),
                        OutlinedButton(
                          onPressed: accountStatus == "suspended"
                              ? null
                              : () => _setStatus(
                                  agent["id"] as String,
                                  "suspended",
                                  note: "Suspended by admin",
                                ),
                          child: const Text("Suspend"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        if (_loadingMore) ...<Widget>[
          const SizedBox(height: 12),
          const Center(child: CircularProgressIndicator()),
        ] else if (_hasMoreResults) ...<Widget>[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_loadAgents(reset: false)),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text("Load more agents"),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _AgentInfoLine extends StatelessWidget {
  const _AgentInfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: <TextSpan>[
                  TextSpan(
                    text: "$label: ",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentDetailBlock extends StatelessWidget {
  const _AgentDetailBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _AgentCardAvatar extends StatelessWidget {
  const _AgentCardAvatar({
    required this.imageUrl,
    required this.fallbackText,
    required this.verified,
  });

  final String? imageUrl;
  final String fallbackText;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final Widget avatar = CircleAvatar(
      radius: 24,
      backgroundImage: imageUrl == null || imageUrl!.isEmpty
          ? null
          : NetworkImage(imageUrl!),
      child: imageUrl == null || imageUrl!.isEmpty
          ? Text((fallbackText.isEmpty ? "A" : fallbackText[0]).toUpperCase())
          : null,
    );

    if (!verified) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        avatar,
        const Positioned(right: -2, bottom: -2, child: _VerifiedBadge()),
      ],
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: const Color(0xFF1D9BF0),
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
      child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
    );
  }
}
