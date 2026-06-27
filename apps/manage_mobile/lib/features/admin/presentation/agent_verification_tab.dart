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
  late Future<List<Map<String, dynamic>>> _future;
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

  Future<List<Map<String, dynamic>>> _load() {
    return AppScope.of(context).repository.fetchPendingAgents();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
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
                          controller: businessNameController,
                          decoration: const InputDecoration(
                            labelText: "Business name",
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(userFacingError(snapshot.error ?? "Unknown error")),
          );
        }
        final List<Map<String, dynamic>> agents =
            snapshot.data ?? <Map<String, dynamic>>[];
        if (agents.isEmpty) {
          return ManagePageScrollView(
            children: <Widget>[
              const ManageHeroCard(
                title: "Agent management",
                subtitle:
                    "Create agents, assign their categories, and activate them only after your offline checks are complete.",
              ),
              const SizedBox(height: 18),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const KodimaliEmptyState(
                      title: "Hakuna agents",
                      message:
                          "Agent accounts zitaonekana hapa kwa activation, category assignment, au suspension.",
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openAddAgentDialog,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text("Add agent"),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return ManagePageScrollView(
          onRefresh: _refresh,
          children: <Widget>[
            ManageHeroCard(
              title: "Agent management",
              subtitle:
                  "Create agents, assign their base category, then activate them after offline checks.",
              bottom: ManageMetaWrap(
                items: <String>[
                  "${agents.length} agent${agents.length == 1 ? "" : "s"}",
                  "Verification and activation stay separate",
                ],
              ),
            ),
            const SizedBox(height: 18),
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
                  icon: const Icon(Icons.mail_outline),
                  label: const Text("Create account"),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ),
                                    if (verified)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: _VerifiedBadge(),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  businessName,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          KodimaliStatusChip(
                            label: accountStatus,
                            highlight: accountStatus == "active",
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text("Public name: $displayName"),
                      Text("Business: $businessName"),
                      Text("Login profile: ${profile?["full_name"] ?? "-"}"),
                      Text("Username: $username"),
                      Text("Account email: $accountEmail"),
                      Text("Email status: $emailStatus"),
                      Text("Phone: $phone"),
                      Text("Preferred language: $preferredLanguage"),
                      Text("Location: $location"),
                      Text("NIDA: $nida"),
                      Text("Verification: $verificationStatus"),
                      if (businessDescription.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text("Business details: $businessDescription"),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
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
                      if (agent["deactivation_reason"] != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Text("Reason: ${agent["deactivation_reason"]}"),
                      ],
                      const SizedBox(height: 10),
                      Text("Documents: ${documents.length}"),
                      ...documents.map(
                        (dynamic doc) => Text(
                          "${doc["document_type"]} | ${doc["storage_path"]}",
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          FilledButton(
                            onPressed: accountStatus == "active"
                                ? null
                                : () => _setStatus(
                                    agent["id"] as String,
                                    "active",
                                  ),
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
                            onPressed: () =>
                                _openCategoryAssignmentDialog(agent),
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
          ],
        );
      },
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
