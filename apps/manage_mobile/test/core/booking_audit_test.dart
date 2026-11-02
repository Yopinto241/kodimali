import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manage_mobile/core/config/app_dependencies.dart';
import 'package:manage_mobile/core/data/manage_repository.dart';
import 'package:manage_mobile/core/localization/manage_localization.dart';
import 'package:manage_mobile/core/state/app_controller.dart';
import 'package:manage_mobile/core/widgets/app_scope.dart';
import 'package:manage_mobile/features/shared/presentation/booking_workspace_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const bookingId = '11111111-1111-4111-8111-111111111111';
const conversationId = '22222222-2222-4222-8222-222222222222';

void main() {
  test(
    'optional workflow reads catch asynchronous schema errors but preserve access denials',
    () async {
      var denied = false;
      final client = SupabaseClient(
        'https://fixture.invalid',
        'fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': denied ? '42501' : '42703',
              'message': denied ? 'permission denied' : 'column does not exist',
            }),
            denied ? 403 : 400,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      final repo = ManageRepository(client);
      final reads = <Future<List<JsonMap>> Function()>[
        () => repo.fetchBookingMessages(conversationId),
        () => repo.fetchViewingAppointments(bookingId),
        () => repo.fetchBookingPaymentIntents(bookingId),
        () => repo.fetchBookingFulfillmentMilestones(bookingId),
        () => repo.fetchBookingIncidents(bookingId),
        () => repo.fetchBookingCancellations(bookingId),
        () => repo.fetchBookingProviderPayables(bookingId),
      ];
      for (final read in reads) {
        expect(await read(), isEmpty);
      }
      denied = true;
      for (final read in reads) {
        await expectLater(
          read(),
          throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
          ),
        );
      }
    },
  );

  for (final admin in [true, false]) {
    testWidgets(
      '${admin ? 'Admin audit' : 'Assigned agent'} opens with preserved booking and conversation',
      (tester) async {
        final calls = <String>[];
        final client = (await tester.runAsync(
          () async => SupabaseClient(
            'https://fixture.invalid',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((request) async {
              calls.add(request.url.path);
              final Object result;
              if (request.url.path.endsWith(
                '/get_or_create_booking_conversation',
              )) {
                result = [
                  {'id': conversationId},
                ];
              } else if (request.url.path.endsWith('/mark_conversation_read')) {
                result = 0;
              } else {
                result = <Object>[];
              }
              return http.Response(
                jsonEncode(result),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }),
          ),
        ))!;
        final repo = ManageRepository(client);
        final controller = AppController(repo);
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
        );
        addTearDown(() => tester.runAsync(client.dispose));
        addTearDown(controller.dispose);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ManageLanguageScope(
            languageCode: 'en',
            onChanged: (_) async {},
            child: AppScope(
              dependencies: AppDependencies(
                repository: repo,
                controller: controller,
                router: router,
              ),
              child: MaterialApp(
                home: BookingWorkspaceScreen(
                  isAdmin: admin,
                  booking: {
                    'id': bookingId,
                    'customer_id': '33333333-3333-4333-8333-333333333333',
                    'booking_status': 'new', 'request_reference': 'AUDIT-001',
                    // A permanently removed listing has a null relationship.
                    'listing_id': null, 'listings': null,
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('AUDIT-001'), findsOneWidget);
        expect(
          find.text('Request ownership'),
          admin ? findsOneWidget : findsNothing,
        );
        expect(
          calls.where((p) => p.endsWith('/mark_conversation_read')).length,
          admin ? 0 : 1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
