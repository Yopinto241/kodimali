import 'package:supabase_flutter/supabase_flutter.dart';

const registrationUnavailable =
    'Sorry, we could not complete your registration just now. Please try again shortly, or contact KODIMALI support for help.';

String agentRegistrationError(Object error) {
  final message =
      (error is AuthException
              ? error.message
              : error is PostgrestException
              ? error.message
              : error is StateError
              ? error.message.toString()
              : error.toString())
          .toLowerCase();
  final status = error is AuthException
      ? int.tryParse(error.statusCode ?? '') ?? 0
      : 0;
  final code = error is AuthException ? error.code ?? '' : '';
  bool has(String pattern) => RegExp(pattern).hasMatch(message);
  if (status >= 500 ||
      has(
        r'database|sqlstate|internal server|column reference|relation .*exist',
      )) {
    return registrationUnavailable;
  }
  if (RegExp('email_exists|user_already_exists').hasMatch(code) ||
      has(
        r'user already registered|email.*already|account with those details already',
      )) {
    return 'An account may already exist with these details. Please sign in or reset your password instead of registering again.';
  }
  if (has(r'username.*(use|taken)|username.*unavailable')) {
    return 'That username is already in use. Please choose another username.';
  }
  if (has(r'phone.*(linked|use|registered)')) {
    return 'That phone number is already linked to an account. Please sign in or use another number.';
  }
  if (code == 'weak_password' || has(r'password.*(least|short|weak)')) {
    return 'Please choose a stronger password with at least 6 characters.';
  }
  if (code == 'email_address_invalid' ||
      has(r'invalid.*email|email.*invalid')) {
    return 'Please check your email address and try again.';
  }
  if (code.contains('rate_limit') || has(r'too many requests|rate limit')) {
    return 'Please wait a few minutes before trying again.';
  }
  if (has(r'location|operating area|ward|choose.*area|area.*required')) {
    return 'Please choose your region, district, ward and operating area before continuing.';
  }
  if (has(r'category')) {
    return 'Please choose an available service category before continuing.';
  }
  if (has(r'nida')) {
    return 'Please check your NIDA number and try again. Contact KODIMALI support if you need help.';
  }
  if (has(r'network|failed to fetch|fetch failed|socketexception')) {
    return 'Please check your internet connection and try again.';
  }
  return registrationUnavailable;
}
