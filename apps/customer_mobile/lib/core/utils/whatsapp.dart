String? normalizeWhatsAppNumber(String? phone) {
  if (phone == null || !RegExp(r'^[+\d ().-]+$').hasMatch(phone.trim())) {
    return null;
  }
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^0+$').hasMatch(digits)) return null;
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 10 && digits.startsWith('0')) {
    digits = '255${digits.substring(1)}';
  } else if (digits.length == 9 && RegExp(r'^[67]').hasMatch(digits)) {
    digits = '255$digits';
  }
  if (!RegExp(r'^[1-9]\d{7,14}$').hasMatch(digits) ||
      (digits.startsWith('255') && digits.length != 12)) {
    return null;
  }
  return digits;
}

Uri? whatsAppUri(String? phone) {
  final number = normalizeWhatsAppNumber(phone);
  return number == null ? null : Uri.https('wa.me', '/$number');
}
