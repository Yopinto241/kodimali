String userFacingError(
  Object error, {
  String fallback = "Something went wrong. Please try again.",
}) {
  if (error is StateError) {
    final String text = error.message.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  final String text = error.toString().trim();
  if (text.isEmpty) {
    return fallback;
  }
  if (text.startsWith("Bad state: ")) {
    return text.substring("Bad state: ".length).trim();
  }
  if (text.startsWith("StateError: ")) {
    return text.substring("StateError: ".length).trim();
  }
  if (text.startsWith("PostgrestException(") ||
      text.startsWith("AuthException(")) {
    return fallback;
  }
  return text;
}
