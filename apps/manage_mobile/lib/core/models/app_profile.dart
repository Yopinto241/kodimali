import 'package:shared_models/shared_models.dart';

class AppProfile {
  const AppProfile({
    required this.id,
    required this.fullName,
    required this.username,
    required this.accountEmail,
    required this.accountEmailConfirmedAt,
    required this.phoneNumber,
    required this.preferredLanguage,
    required this.roles,
    this.agentDisplayName,
    this.agentPhoneNumber,
    this.agentContactEmail,
    this.agentNidaNumber,
    this.agentLocationLabel,
    this.agentProfilePhotoUrl,
    this.agentBusinessName,
    this.agentVerifiedAt,
    this.agentAccountStatus,
    this.agentVerificationStatus,
  });

  final String id;
  final String fullName;
  final String? username;
  final String? accountEmail;
  final DateTime? accountEmailConfirmedAt;
  final String? phoneNumber;
  final String preferredLanguage;
  final List<AppRole> roles;
  final String? agentDisplayName;
  final String? agentPhoneNumber;
  final String? agentContactEmail;
  final String? agentNidaNumber;
  final String? agentLocationLabel;
  final String? agentProfilePhotoUrl;
  final String? agentBusinessName;
  final DateTime? agentVerifiedAt;
  final String? agentAccountStatus;
  final String? agentVerificationStatus;

  AppRole get highestRole {
    if (roles.contains(AppRole.admin)) {
      return AppRole.admin;
    }
    if (roles.contains(AppRole.agent)) {
      return AppRole.agent;
    }
    return AppRole.customer;
  }

  bool get isCustomerOnly =>
      !roles.contains(AppRole.admin) && !roles.contains(AppRole.agent);

  bool get isAgentActive =>
      agentAccountStatus == null || agentAccountStatus == "active";
}

extension AppRolePresentation on AppRole {
  String get displayLabel => switch (this) {
    AppRole.admin => "ADMIN",
    AppRole.agent => "AGENT",
    AppRole.customer => "CUSTOMER",
  };
}
