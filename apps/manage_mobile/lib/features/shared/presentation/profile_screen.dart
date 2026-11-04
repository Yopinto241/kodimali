import 'package:flutter_core/localized_ui.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/models/app_profile.dart';
import '../../../core/models/upload_task.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/widgets/app_scope.dart';
import '../../../core/widgets/manage_ui.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _uploadingPhoto = false;
  XFile? _pendingPhoto;
  UploadTaskController? _photoUploadController;
  UploadProgressSnapshot? _photoProgress;

  Future<void> _openChangePasswordDialog() async {
    final dependencies = AppScope.of(context);
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController =
        TextEditingController();
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                return AlertDialog(
                  scrollable: true,
                  title: const LocalizedUiText("Change password"),
                  content: SizedBox(
                    width: 360,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const LocalizedUiText(
                          "Use a new password with at least 6 characters. After saving, use the new password the next time you sign in.",
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: newPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: mobileUi(context, "New password"),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: mobileUi(
                              context,
                              "Confirm new password",
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const LocalizedUiText("Cancel"),
                    ),
                    FilledButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              final String newPassword =
                                  newPasswordController.text;
                              final String confirmPassword =
                                  confirmPasswordController.text;
                              if (newPassword.length < 6) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: LocalizedUiText(
                                      "Password must be at least 6 characters.",
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (newPassword != confirmPassword) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: LocalizedUiText(
                                      "Password confirmation does not match.",
                                    ),
                                  ),
                                );
                                return;
                              }
                              setModalState(() => submitting = true);
                              try {
                                await dependencies.controller.changePassword(
                                  newPassword,
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: LocalizedUiText(
                                        "Password updated.",
                                      ),
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: LocalizedUiText(
                                        userFacingError(error),
                                      ),
                                    ),
                                  );
                                }
                                setModalState(() => submitting = false);
                              }
                            },
                      child: Text(
                        submitting
                            ? mobileUi(context, "Saving...")
                            : mobileUi(context, "Save password"),
                      ),
                    ),
                  ],
                );
              },
        );
      },
    );

    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _changeProfilePhoto() async {
    final dependencies = AppScope.of(context);
    final profile = dependencies.controller.profile;
    if (profile == null || profile.agentAccountStatus != "active") {
      return;
    }
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (file == null || !mounted) {
      return;
    }

    final UploadTaskController controller = UploadTaskController();
    setState(() {
      _pendingPhoto = file;
      _uploadingPhoto = true;
      _photoUploadController = controller;
      _photoProgress = UploadProgressSnapshot(
        value: 0.05,
        label: mobileUi(context, "Preparing photo..."),
      );
    });
    try {
      await dependencies.repository.uploadAgentProfilePhoto(
        file: file,
        uploadController: controller,
        onProgress: (UploadProgressSnapshot progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _photoProgress = progress;
          });
        },
      );
      await dependencies.controller.refreshProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedUiText("Profile photo updated.")),
        );
      }
    } on UploadCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedUiText("Upload cancelled.")),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedUiText(userFacingError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
          _pendingPhoto = null;
          _photoUploadController = null;
          _photoProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).controller;
    final profile = controller.profile;
    final bool verified = profile?.agentVerificationStatus == "approved";
    final bool activeAgent = profile?.agentAccountStatus == "active";
    final bool isAdmin = profile?.roles.contains(AppRole.admin) ?? false;
    final bool isAgent = profile?.roles.contains(AppRole.agent) ?? false;
    final String heroName =
        profile?.agentDisplayName ?? profile?.fullName ?? "My account";
    final String? pendingPhotoPath = _pendingPhoto?.path;

    return ManagePageScrollView(
      children: <Widget>[
        ManageHeroCard(
          title: heroName,
          subtitle: isAdmin
              ? "Review your admin account details, workspace role, and any public agent profile connected to this account."
              : "Review your role, identity details, and the public agent profile customers will see.",
          trailing: profile == null
              ? null
              : _ManageAgentAvatar(
                  imageUrl: profile.agentProfilePhotoUrl,
                  localFilePath: pendingPhotoPath,
                  fallbackText: heroName,
                  verified: verified,
                ),
          bottom: ManageMetaWrap(
            items: <String>[
              profile?.agentPhoneNumber ??
                  profile?.phoneNumber ??
                  "No phone saved",
              "Language: ${profile?.preferredLanguage ?? "sw"}",
              "Role count: ${(profile?.roles.length ?? 0)}",
            ],
          ),
        ),
        const SizedBox(height: 18),
        ManagePanel(
          title: isAgent ? "Agent profile photo" : "Profile photo",
          subtitle: isAgent
              ? "Active agents can update the photo customers see on listing details."
              : "This account does not have an active public agent photo to update.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _ManageAgentAvatar(
                    imageUrl: profile?.agentProfilePhotoUrl,
                    localFilePath: pendingPhotoPath,
                    fallbackText: heroName,
                    verified: verified,
                    radius: 34,
                  ),
                  SizedBox(
                    width: 260,
                    child: Text(
                      activeAgent
                          ? mobileUi(
                              context,
                              "Rules: JPG, PNG, or WebP only, up to 5MB. Changing the photo does not grant or remove the verification badge.",
                            )
                          : mobileUi(
                              context,
                              "Photo changes are allowed only after the agent account becomes active.",
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_uploadingPhoto && _photoProgress != null) ...<Widget>[
                LinearProgressIndicator(value: _photoProgress!.value),
                const SizedBox(height: 10),
                Text(_photoProgress!.label),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _photoProgress!.canCancel
                      ? () => _photoUploadController?.cancel()
                      : null,
                  icon: const Icon(Icons.close_rounded),
                  label: const LocalizedUiText("Cancel upload"),
                ),
                const SizedBox(height: 14),
              ],
              FilledButton.icon(
                onPressed: activeAgent && !_uploadingPhoto
                    ? _changeProfilePhoto
                    : null,
                icon: const Icon(Icons.photo_camera_back_outlined),
                label: Text(
                  _uploadingPhoto
                      ? mobileUi(context, "Uploading...")
                      : mobileUi(context, "Change photo"),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ManagePanel(
          title: mobileUi(context, "Account details"),
          subtitle: mobileUi(
            context,
            "These details come from your authenticated profile and agent record.",
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ProfileRow(
                label: mobileUi(context, "Full name"),
                value: profile?.fullName ?? "-",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Account email"),
                value:
                    profile?.accountEmail ??
                    controller.currentUser?.email ??
                    "-",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Login username"),
                value: profile?.username ?? "-",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Email status"),
                value: profile?.accountEmailConfirmedAt == null
                    ? "pending"
                    : "confirmed",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Workspace role"),
                value: profile?.highestRole.displayLabel ?? "CUSTOMER",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Public agent name"),
                value: profile?.agentDisplayName ?? profile?.fullName ?? "-",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Agent phone number"),
                value: profile?.agentPhoneNumber ?? profile?.phoneNumber ?? "-",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Agent location"),
                value: profile?.agentLocationLabel ?? "-",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "NIDA number"),
                value: profile?.agentNidaNumber ?? "-",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Preferred language"),
                value: profile?.preferredLanguage ?? "sw",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Agent account status"),
                value: profile?.agentAccountStatus ?? "not-agent",
              ),
              const SizedBox(height: 14),
              _ProfileRow(
                label: mobileUi(context, "Verification status"),
                value: profile?.agentVerificationStatus ?? "pending",
              ),
              if (isAdmin) ...<Widget>[
                const SizedBox(height: 14),
                _ProfileRow(
                  label: mobileUi(context, "Admin access"),
                  value: "Enabled",
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        ManagePanel(
          title: mobileUi(context, "Roles"),
          subtitle: mobileUi(
            context,
            "The app experience changes depending on the highest available role on your account.",
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: (profile?.roles ?? const <dynamic>[])
                .whereType<AppRole>()
                .map((AppRole role) => Chip(label: Text(role.displayLabel)))
                .toList(),
          ),
        ),
        const SizedBox(height: 18),
        ManagePanel(
          title: mobileUi(context, "Security"),
          subtitle: mobileUi(
            context,
            "Forgot password sends a reset link only when this account has a real recovery email. Signed-in agents can still change the password here anytime.",
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _openChangePasswordDialog,
              icon: const Icon(Icons.lock_reset_outlined),
              label: const LocalizedUiText("Change password"),
            ),
          ),
        ),
        const SizedBox(height: 18),
        ManagePanel(
          title: mobileUi(context, "Session"),
          subtitle: mobileUi(
            context,
            "Use sign out when switching device or testing another account.",
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => controller.signOut(),
              child: const LocalizedUiText("Toka kwenye akaunti"),
            ),
          ),
        ),
      ],
    );
  }
}

class _ManageAgentAvatar extends StatelessWidget {
  const _ManageAgentAvatar({
    required this.imageUrl,
    this.localFilePath,
    required this.fallbackText,
    required this.verified,
    this.radius = 28,
  });

  final String? imageUrl;
  final String? localFilePath;
  final String fallbackText;
  final bool verified;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? imageProvider =
        localFilePath != null && localFilePath!.isNotEmpty
        ? FileImage(File(localFilePath!))
        : (imageUrl == null || imageUrl!.isEmpty
              ? null
              : NetworkImage(imageUrl!));
    final Widget avatar = CircleAvatar(
      radius: radius,
      backgroundImage: imageProvider,
      child: imageProvider == null
          ? Text(
              (fallbackText.isEmpty ? mobileUi(context, "K") : fallbackText[0])
                  .toUpperCase(),
            )
          : null,
    );

    if (!verified) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFF1D9BF0),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 14,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
