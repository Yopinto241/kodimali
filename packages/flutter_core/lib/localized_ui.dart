import 'package:flutter/material.dart';

import 'src/ui_copy.dart';

/// Translate application-owned copy only. Never pass names, messages or form values.
String translateMobileUi(String language, String value) {
  if (const {'apartment', 'book', 'booking'}.contains(value.toLowerCase())) {
    return value;
  }
  final suffix = RegExp(r'^(.*?)(\s+\*|:)$').firstMatch(value);
  if (suffix != null) {
    return translateMobileUi(language, suffix[1]!) + suffix[2]!;
  }
  final key =
      uiAliases[value] ??
      (uiCopy.containsKey(value) ? value : uiEnglish[value]);
  if (key == null) return value;
  return language == 'en' ? key : uiCopy[key] ?? value;
}

String mobileUi(BuildContext context, String value) => translateMobileUi(
  Localizations.maybeLocaleOf(context)?.languageCode ?? 'sw',
  value,
);

/// Interpolate original data only after translating the application template.
String mobileUiFormat(
  BuildContext context,
  String template,
  List<Object?> values,
) =>
    mobileUi(context, template).replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < values.length ? '${values[index]}' : match[0]!;
    });

/// A const-friendly Text for static application copy; keeps normal Text layout.
class LocalizedUiText extends StatelessWidget {
  const LocalizedUiText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) => Text(
    mobileUi(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null
        ? null
        : mobileUi(context, semanticsLabel!),
    semanticsIdentifier: semanticsIdentifier,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
