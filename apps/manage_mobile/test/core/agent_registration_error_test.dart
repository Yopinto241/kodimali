import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:manage_mobile/core/utils/agent_registration_error.dart';
import 'package:flutter_core/localized_ui.dart';

void main() {
  test('technical registration details stay out of user messages', () {
    final errors = <Object>[
      const AuthException('Database error saving new user', statusCode: '500'),
      const PostgrestException(
        message: 'column reference id is ambiguous',
        code: '42702',
      ),
      StateError('Internal Server Error'),
      StateError(
        'Agent self-registration needs the latest Supabase migration before it can be used.',
      ),
      Exception('unexpected implementation detail'),
    ];
    for (final error in errors) {
      expect(agentRegistrationError(error), registrationUnavailable);
      expect(
        translateMobileUi('sw', agentRegistrationError(error)),
        startsWith('Samahani,'),
      );
    }
  });
  test('actionable validation stays clear in both languages', () {
    expect(
      agentRegistrationError(const AuthException('User already registered')),
      contains('sign in or reset'),
    );
    expect(
      agentRegistrationError(StateError('That username is already in use.')),
      contains('choose another username'),
    );
    expect(
      agentRegistrationError(
        StateError('Agent location must be an active area'),
      ),
      contains('ward and operating area'),
    );
    expect(
      agentRegistrationError(
        const AuthException('Please wait', code: 'over_email_send_rate_limit'),
      ),
      contains('wait a few minutes'),
    );
  });
}
