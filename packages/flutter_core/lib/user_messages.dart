import 'dart:async';
import 'package:flutter/material.dart';

/// Only controlled application copy reaches the UI. Never interpolate raw SQL,
/// provider responses, table names, paths, tokens or exception descriptions.
String safeUserMessage(Object? error, {String language = 'en'}) {
  final text = error.toString().toLowerCase();
  final sw = language == 'sw';
  if (text.contains('user already registered')) {
    return sw ? 'Mtumiaji huyu amesajiliwa tayari' : 'User already registered';
  }
  if (error is TimeoutException ||
      text.contains('timed out') ||
      text.contains('timeout')) {
    return sw
        ? 'Hatukuweza kuthibitisha matokeo. Angalia akaunti yako kabla ya kujaribu tena.'
        : 'We could not confirm the result. Check your account before trying again.';
  }
  if (text.contains('socketexception') ||
      text.contains('failed to fetch') ||
      text.contains('connection') ||
      text.contains('network')) {
    return sw
        ? 'Muunganisho haupatikani. Angalia intaneti kisha ujaribu tena.'
        : 'Connection unavailable. Check your internet and try again.';
  }
  if (text.contains('invalid login') || text.contains('invalid credentials')) {
    return sw
        ? 'Barua pepe au nenosiri si sahihi.'
        : 'The email or password is incorrect.';
  }
  if (text.contains('session') ||
      text.contains('jwt') ||
      text.contains('401')) {
    return sw
        ? 'Kipindi chako kimeisha. Ingia tena.'
        : 'Your session expired. Please sign in again.';
  }
  if (text.contains('permission') ||
      text.contains('forbidden') ||
      text.contains('42501')) {
    return sw
        ? 'Huna ruhusa ya kufanya hili.'
        : 'You do not have permission to do this.';
  }
  if (text.contains('payment') || text.contains('verification pending')) {
    return sw
        ? 'Uhakiki wa malipo unasubiri. Angalia hali kabla ya kulipa tena.'
        : 'Payment verification is pending. Check the status before paying again.';
  }
  if (text.contains('not available') || text.contains('no longer available')) {
    return sw
        ? 'Chaguo hili halipatikani tena. Tafadhali chagua jingine.'
        : 'This option is no longer available. Please choose another.';
  }
  return sw
      ? 'Hatukuweza kukamilisha ombi. Tafadhali jaribu tena.'
      : 'We could not complete the request. Please try again.';
}

String userMessage(BuildContext context, Object? error) => safeUserMessage(
  error,
  language: Localizations.maybeLocaleOf(context)?.languageCode ?? 'sw',
);

class RecoverableError extends StatelessWidget {
  const RecoverableError({
    super.key,
    required this.error,
    required this.onRetry,
  });
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(userMessage(context, error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'sw'
                  ? 'Jaribu tena'
                  : 'Retry',
            ),
          ),
        ],
      ),
    ),
  );
}
