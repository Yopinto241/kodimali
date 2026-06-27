import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/manage_repository.dart';
import '../router/app_router.dart';
import '../state/app_controller.dart';

class AppDependencies {
  AppDependencies({
    required this.repository,
    required this.controller,
    required this.router,
  });

  final ManageRepository repository;
  final AppController controller;
  final GoRouter router;

  factory AppDependencies.create() {
    final ManageRepository repository = ManageRepository(Supabase.instance.client);
    final AppController controller = AppController(repository);
    final GoRouter router = createAppRouter(controller);
    return AppDependencies(
      repository: repository,
      controller: controller,
      router: router,
    );
  }
}
