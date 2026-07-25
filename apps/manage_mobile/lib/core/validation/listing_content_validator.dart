class ListingContentValidator {
  const ListingContentValidator._();

  static const int minimumTitleCharacters = 3;
  static const int maximumTitleCharacters = 180;
  static const int minimumDescriptionCharacters = 10;

  static String? titleError(String? value) {
    final String normalized = value?.trim() ?? '';
    final int characterCount = normalized.runes.length;
    if (characterCount < minimumTitleCharacters) {
      return 'Title must have at least $minimumTitleCharacters characters.';
    }
    if (characterCount > maximumTitleCharacters) {
      return 'Title must have no more than $maximumTitleCharacters characters.';
    }
    return null;
  }

  static String? descriptionError(String? value) {
    final String normalized = value?.trim() ?? '';
    if (normalized.runes.length < minimumDescriptionCharacters) {
      return 'Description must have at least '
          '$minimumDescriptionCharacters characters.';
    }
    return null;
  }

  static String requireValidTitle(String value) {
    final String normalized = value.trim();
    final String? error = titleError(normalized);
    if (error != null) {
      throw StateError(error);
    }
    return normalized;
  }

  static String requireValidDescription(String value) {
    final String normalized = value.trim();
    final String? error = descriptionError(normalized);
    if (error != null) {
      throw StateError(error);
    }
    return normalized;
  }
}
