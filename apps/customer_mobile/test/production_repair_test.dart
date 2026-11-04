import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:customer_mobile/core/data/customer_account_repository.dart';
import 'package:customer_mobile/features/chat/listing_chat_screens.dart';
import 'package:customer_mobile/features/account/customer_account_screens.dart';
import 'mobile_ui_test.dart' show host;

// Regression tests: all network access is replaced by an in-memory repository.
class AuditRepository extends CustomerAccountRepository {
  AuditRepository(super.client);
  String mode = '';
  final login = Completer<AuthResponse>();
  final messages = StreamController<List<Map<String, dynamic>>>.broadcast();
  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => login.future;
  @override
  Future<List<Map<String, dynamic>>> fetchListingChats() async {
    if (mode == 'raw') {
      throw const PostgrestException(
        message: 'permission denied for table listing_conversations',
        code: '42501',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    return [
      {
        'id': 'chat',
        'agent_name': 'Fixture Agent',
        'listing_title': 'Fixture listing',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> fetchListingConversation(String id) async {
    if (mode == 'offline') {
      throw StateError('Connection temporarily unavailable');
    }
    return {
      if (mode == 'revoked') 'revoked_at': DateTime.now().toIso8601String(),
      'agent_name': 'Fixture Agent',
      'expires_at': DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'messages_sent_today': 0,
    };
  }

  @override
  Stream<List<Map<String, dynamic>>> watchListingChatMessages(String id) =>
      messages.stream;
  @override
  Future<void> markListingChatRead(String id) async {}
}

void main() {
  late SupabaseClient client;
  late AuditRepository repo;
  setUp(() {
    client = SupabaseClient(
      'https://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repo = AuditRepository(client);
  });
  tearDown(() async {
    await repo.messages.close();
    await client.dispose();
  });
  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(host(screen, 'en', KodimaliTheme.mobileLight(), 1));
    await tester.pump();
  }

  testWidgets('chat refresh retains rows without a setState Future', (
    tester,
  ) async {
    await open(tester, CustomerListingChatsScreen(repository: repo));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
      find.text('Fixture listing', findRichText: true),
      findsNothing,
    ); // text is combined in subtitle
    expect(find.textContaining('Fixture listing'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('chat errors hide backend details and offer retry', (
    tester,
  ) async {
    repo.mode = 'raw';
    await open(tester, CustomerListingChatsScreen(repository: repo));
    await tester.pump();
    expect(
      find.textContaining('permission denied for table listing_conversations'),
      findsNothing,
    );
    expect(find.text('Retry'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed access lookup offers retry without claiming expiration', (
    tester,
  ) async {
    repo.mode = 'offline';
    await open(
      tester,
      CustomerListingChatScreen(repository: repo, conversationId: 'chat'),
    );
    await tester.pump();
    expect(find.text('Chat access expired'), findsNothing);
    expect(find.text('Retry'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('Connection temporarily unavailable'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'incoming message preserves reading position and shows new-message control',
    (tester) async {
      await open(
        tester,
        CustomerListingChatScreen(repository: repo, conversationId: 'chat'),
      );
      await tester.pump();
      final rows = List.generate(
        40,
        (i) => <String, dynamic>{
          'id': '$i',
          'sender_id': 'agent',
          'body': 'Message $i: ${'Long conversation text. ' * 8}',
          'created_at': DateTime.now().toIso8601String(),
        },
      );
      repo.messages.add(rows);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(800));
      scroll.jumpTo(800);
      await tester.pump();
      expect(scroll.offset, 800);
      repo.messages.add([
        ...rows,
        {'id': 'new', 'sender_id': 'agent', 'body': 'New message'},
      ]);
      await tester.pumpAndSettle();
      expect(scroll.offset, 800);
      expect(find.text('New messages'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('revoked chat is distinct from failed lookup or expiration', (
    tester,
  ) async {
    repo.mode = 'revoked';
    await open(
      tester,
      CustomerListingChatScreen(repository: repo, conversationId: 'chat'),
    );
    await tester.pump();
    expect(find.textContaining('Chat access revoked'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('Chat access expired'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('message network failure retains history and draft with retry', (
    tester,
  ) async {
    await open(
      tester,
      CustomerListingChatScreen(repository: repo, conversationId: 'chat'),
    );
    await tester.pump();
    repo.messages.add([
      {'id': 'one', 'sender_id': 'agent', 'body': 'Retained conversation'},
    ]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsent draft');
    repo.messages.addError(StateError('network offline'));
    await tester.pump();
    expect(find.text('Retained conversation'), findsOneWidget);
    expect(find.text('Unsent draft'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Chat access expired'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('slow login releases controls after deadline', (tester) async {
    await open(tester, CustomerAuthScreen(repository: repo));
    await tester.enterText(
      find.byType(TextFormField).first,
      'fixture@example.invalid',
    );
    await tester.enterText(find.byType(TextFormField).last, 'test-password');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.pumpWidget(const SizedBox());
    repo.login.complete(AuthResponse());
    await tester.pump();
  });
}
