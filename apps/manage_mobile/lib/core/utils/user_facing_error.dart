import 'package:flutter_core/user_messages.dart';

String userFacingError(
  Object error, {
  String fallback = 'We could not complete the request. Please try again.',
}) => safeUserMessage(error);
