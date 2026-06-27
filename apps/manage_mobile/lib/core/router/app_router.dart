import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/admin/presentation/admin_shell_screen.dart';
import '../../features/agent/presentation/agent_shell_screen.dart';
import '../../features/auth/presentation/access_denied_screen.dart';
import '../../features/auth/presentation/agent_account_status_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../state/app_controller.dart';

GoRouter createAppRouter(AppController controller) {
  return GoRouter(
    initialLocation: "/splash",
    refreshListenable: controller,
    redirect: (context, state) {
      final String location = state.matchedLocation;
      if (!controller.initialized) {
        return location == "/splash" ? null : "/splash";
      }

      final bool isAuthPath =
          location == "/login" ||
          location == "/forgot-password" ||
          location == "/register-agent";

      if (!controller.isSignedIn) {
        return isAuthPath ? null : "/login";
      }

      final AppRole? role = controller.highestRole;
      final String target = switch (role) {
        AppRole.admin => "/admin",
        AppRole.agent =>
          controller.isAgentAccessBlocked ? "/agent-account-status" : "/agent",
        _ => "/access-denied",
      };

      if (location == "/splash") {
        return target;
      }
      if (isAuthPath) {
        return target;
      }
      if (location.startsWith("/admin") && role == AppRole.admin) {
        return null;
      }
      if (location.startsWith("/agent") && role == AppRole.agent) {
        return controller.isAgentAccessBlocked ? "/agent-account-status" : null;
      }
      if (location == "/agent-account-status" && role == AppRole.agent) {
        return controller.isAgentAccessBlocked ? null : "/agent";
      }
      if (location == "/access-denied" &&
          role != AppRole.admin &&
          role != AppRole.agent) {
        return null;
      }
      return target;
    },
    routes: <RouteBase>[
      GoRoute(
        path: "/splash",
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: "/login", builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: "/register-agent",
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: "/forgot-password",
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: "/access-denied",
        builder: (context, state) => const AccessDeniedScreen(),
      ),
      GoRoute(
        path: "/agent-account-status",
        builder: (context, state) => const AgentAccountStatusScreen(),
      ),
      GoRoute(
        path: "/agent",
        builder: (context, state) => const AgentShellScreen(),
      ),
      GoRoute(
        path: "/admin",
        builder: (context, state) => const AdminShellScreen(),
      ),
    ],
  );
}
