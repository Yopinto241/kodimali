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
    final String sanitized = _sanitize(rawNumber);
    if (sanitized.isEmpty) {
      throw StateError("Namba ya WhatsApp haipo.");
    }
    final Uri uri = Uri.parse("https://wa.me/$sanitized");
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError("Imeshindikana kufungua WhatsApp.");
    }
  }

  static String _sanitize(String raw) {
    return raw.replaceAll(RegExp(r"[^\d+]"), "");
  }
}
