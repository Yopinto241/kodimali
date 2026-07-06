import 'package:url_launcher/url_launcher.dart';

class Launchers {
  static Future<void> callPhone(String rawNumber) async {
    final String sanitized = _sanitize(rawNumber);
    if (sanitized.isEmpty) {
      throw StateError("Namba ya simu haipo.");
    }
    final Uri uri = Uri(scheme: "tel", path: sanitized);
    if (!await launchUrl(uri)) {
      throw StateError("Imeshindikana kufungua kupiga simu.");
    }
  }

  static Future<void> openWhatsApp(String rawNumber) async {
    return openWhatsAppMessage(rawNumber, null);
  }

  static Future<void> openWhatsAppMessage(
    String rawNumber,
    String? message,
  ) async {
    final String sanitized = _sanitize(rawNumber);
    if (sanitized.isEmpty) {
      throw StateError("Namba ya WhatsApp haipo.");
    }
    final Uri uri = Uri.https("wa.me", "/$sanitized", {
      if (message != null && message.trim().isNotEmpty) "text": message.trim(),
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError("Imeshindikana kufungua WhatsApp.");
    }
  }

  static Future<void> email(String rawEmail) async {
    final String sanitized = rawEmail.trim();
    if (sanitized.isEmpty) {
      throw StateError("Barua pepe haipo.");
    }
    final Uri uri = Uri(scheme: "mailto", path: sanitized);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError("Imeshindikana kufungua email.");
    }
  }

  static String _sanitize(String raw) {
    return raw.replaceAll(RegExp(r"[^\d+]"), "");
  }
}
