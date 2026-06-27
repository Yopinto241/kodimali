class AppEnv {
  static const String _defaultSupabaseUrl =
      "https://tlhoajedyaeaaqtrjqqh.supabase.co";
  static const String _defaultSupabasePublishableKey =
      "sb_publishable_3Txem_vMHZbvLswFzjR6ng_OGXbur1K";

  static const String supabaseUrl = String.fromEnvironment(
    "SUPABASE_URL",
    defaultValue: _defaultSupabaseUrl,
  );
  static const String supabasePublishableKey = String.fromEnvironment(
    "SUPABASE_PUBLISHABLE_KEY",
    defaultValue: _defaultSupabasePublishableKey,
  );
  static const String admobAndroidAppId = String.fromEnvironment("ADMOB_ANDROID_APP_ID");
  static const String admobIosAppId = String.fromEnvironment("ADMOB_IOS_APP_ID");
  static const String admobNativeUnitId = String.fromEnvironment("ADMOB_NATIVE_UNIT_ID");
  static const String admobInlineBannerUnitId = String.fromEnvironment(
    "ADMOB_INLINE_BANNER_UNIT_ID",
  );

  static void ensureConfigured() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError(
        "Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY.",
      );
    }
  }
}
