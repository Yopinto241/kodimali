import 'localized_ui.dart';
import 'user_messages.dart';

/// Translate controlled messages, never arbitrary database errors or guest data.
String lodgeUserMessage(Object error, {String language = 'en'}) {
  final text = error.toString().toLowerCase();
  String? message;
  if (text.contains('23p01') || text.contains('exclusion constraint')) {
    message =
        'This room is already reserved for those dates. Choose another room or change the dates.';
  } else if (text.contains('23505')) {
    message =
        'This room identifier, receipt reference or invitation already exists.';
  } else if (text.contains('42501') || text.contains('permission denied')) {
    message =
        'You do not have permission for this lodge. Sign in with an authorized account.';
  } else if (text.contains('check-in requires')) {
    message = 'Check-in needs a confirmed stay today and a ready, active room.';
  } else if (text.contains('same-day turnover')) {
    message = 'Same-day checkout and check-in are disabled in lodge settings.';
  } else if (text.contains('capacity') || text.contains('guest count')) {
    message = 'The guest count exceeds the selected room capacity.';
  } else if (text.contains('dates') ||
      text.contains('departure') ||
      text.contains('arrival')) {
    message =
        'Choose valid arrival and departure dates. Departure must be after arrival.';
  } else if (text.contains('invitation unavailable')) {
    message = 'This invitation has expired or belongs to a different account.';
  }
  return message == null
      ? safeUserMessage(error, language: language)
      : translateMobileUi(language, message);
}
