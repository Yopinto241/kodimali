import 'package:intl/intl.dart';

class DateFormatters {
  static final DateFormat _dateTime = DateFormat("dd MMM yyyy, HH:mm");
  static final NumberFormat _currency = NumberFormat.currency(
    locale: "en_TZ",
    symbol: "TZS ",
    decimalDigits: 0,
  );

  static String formatDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return "-";
    }
    return _dateTime.format(DateTime.parse(value).toLocal());
  }

  static String formatCurrency(num? amount) {
    if (amount == null) {
      return "-";
    }
    return _currency.format(amount);
  }
}
