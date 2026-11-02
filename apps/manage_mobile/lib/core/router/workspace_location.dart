import 'package:shared_models/shared_models.dart';

String workspaceLocation(
  AppRole? role, {
  required bool agentBlocked,
  required bool eventsAgent,
}) => switch (role) {
  AppRole.admin => '/admin',
  AppRole.owner => '/owner',
  AppRole.agent =>
    agentBlocked
        ? '/agent-account-status'
        : eventsAgent
        ? '/events-provider'
        : '/agent',
  _ => '/access-denied',
};
