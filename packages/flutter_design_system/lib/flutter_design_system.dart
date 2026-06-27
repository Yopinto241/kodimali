import 'package:flutter/material.dart';

class KodimaliColors {
  static const Color navy = Color(0xFF0B1F3A);
  static const Color blueSurface = Color(0xFF122B4A);
  static const Color blueSurfaceStrong = Color(0xFF17385F);
  static const Color green = Color(0xFFA8D62A);
  static const Color greenStrong = Color(0xFF91BF11);
  static const Color lightGreen = Color(0xFFEAF4D2);
  static const Color background = Color(0xFFF6F8FB);
  static const Color backgroundRaised = Color(0xFFEDF2F8);
  static const Color textDark = Color(0xFF132238);
  static const Color mutedText = Color(0xFF64748B);
  static const Color warning = Color(0xFFE8A317);
  static const Color warningSoft = Color(0xFFFFF3D0);
  static const Color danger = Color(0xFFD94848);
  static const Color dangerSoft = Color(0xFFFCE7E7);
  static const Color info = Color(0xFF1F6EA9);
  static const Color infoSoft = Color(0xFFE6F2FB);
  static const Color border = Color(0xFFDCE4ED);
  static const Color borderStrong = Color(0xFFC6D1DE);
  static const Color white = Colors.white;

  static const Color darkBackground = Color(0xFF08162B);
  static const Color darkSurface = Color(0xFF102847);
  static const Color darkSurfaceSoft = Color(0xFF132D4D);
  static const Color darkCard = Color(0xFF17304F);
  static const Color darkText = Color(0xFFF5F8FC);
  static const Color darkMutedText = Color(0xFFB5C1D1);
  static const Color darkBorder = Color(0xFF30455F);
}

class KodimaliSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double xxxl = 48;

  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(md, md, md, xl);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets cardPaddingLarge = EdgeInsets.all(20);
}

class KodimaliRadii {
  static const double input = 16;
  static const double card = 18;
  static const double panel = 20;
  static const double hero = 24;
  static const double pill = 999;
}

enum KodimaliStatusTone { active, pending, danger, muted, info }

class KodimaliShadows {
  static List<BoxShadow> soft(Color color) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: 0.08),
        blurRadius: 22,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> lifted(Color color) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: 0.14),
        blurRadius: 28,
        offset: const Offset(0, 16),
      ),
    ];
  }
}

class KodimaliButtonStyles {
  static ButtonStyle success(BuildContext context) {
    return FilledButton.styleFrom(
      backgroundColor: KodimaliColors.green,
      foregroundColor: KodimaliColors.navy,
      disabledBackgroundColor: KodimaliColors.green.withValues(alpha: 0.45),
      disabledForegroundColor: KodimaliColors.navy.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(
        horizontal: KodimaliSpacing.md,
        vertical: KodimaliSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KodimaliRadii.input),
      ),
      textStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static ButtonStyle outline(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return OutlinedButton.styleFrom(
      foregroundColor: scheme.primary,
      side: BorderSide(color: scheme.outline),
      padding: const EdgeInsets.symmetric(
        horizontal: KodimaliSpacing.md,
        vertical: KodimaliSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KodimaliRadii.input),
      ),
      textStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static ButtonStyle danger(BuildContext context) {
    return FilledButton.styleFrom(
      backgroundColor: KodimaliColors.danger,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: KodimaliSpacing.md,
        vertical: KodimaliSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KodimaliRadii.input),
      ),
      textStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class KodimaliStatusBadge extends StatelessWidget {
  const KodimaliStatusBadge({
    super.key,
    required this.label,
    this.tone = KodimaliStatusTone.info,
  });

  final String label;
  final KodimaliStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final ({Color background, Color foreground, Color border}) colors =
        _resolveColors(Theme.of(context).brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(KodimaliRadii.pill),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  ({Color background, Color foreground, Color border}) _resolveColors(
    Brightness brightness,
  ) {
    final bool isDark = brightness == Brightness.dark;
    switch (tone) {
      case KodimaliStatusTone.active:
        return (
          background: isDark
              ? KodimaliColors.green.withValues(alpha: 0.22)
              : KodimaliColors.lightGreen,
          foreground: isDark ? KodimaliColors.green : KodimaliColors.navy,
          border: isDark
              ? KodimaliColors.green.withValues(alpha: 0.28)
              : KodimaliColors.greenStrong.withValues(alpha: 0.24),
        );
      case KodimaliStatusTone.pending:
        return (
          background: isDark
              ? KodimaliColors.warning.withValues(alpha: 0.2)
              : KodimaliColors.warningSoft,
          foreground: isDark
              ? const Color(0xFFFFD480)
              : const Color(0xFF8A5C00),
          border: isDark
              ? KodimaliColors.warning.withValues(alpha: 0.28)
              : KodimaliColors.warning.withValues(alpha: 0.24),
        );
      case KodimaliStatusTone.danger:
        return (
          background: isDark
              ? KodimaliColors.danger.withValues(alpha: 0.2)
              : KodimaliColors.dangerSoft,
          foreground: isDark
              ? const Color(0xFFFFC1C1)
              : const Color(0xFFAD2E2E),
          border: isDark
              ? KodimaliColors.danger.withValues(alpha: 0.28)
              : KodimaliColors.danger.withValues(alpha: 0.24),
        );
      case KodimaliStatusTone.muted:
        return (
          background: isDark
              ? KodimaliColors.darkSurfaceSoft
              : KodimaliColors.backgroundRaised,
          foreground: isDark
              ? KodimaliColors.darkMutedText
              : KodimaliColors.mutedText,
          border: isDark ? KodimaliColors.darkBorder : KodimaliColors.border,
        );
      case KodimaliStatusTone.info:
        return (
          background: isDark
              ? KodimaliColors.info.withValues(alpha: 0.2)
              : KodimaliColors.infoSoft,
          foreground: isDark ? const Color(0xFFB9E2FF) : KodimaliColors.info,
          border: isDark
              ? KodimaliColors.info.withValues(alpha: 0.28)
              : KodimaliColors.info.withValues(alpha: 0.18),
        );
    }
  }
}

class KodimaliTheme {
  static ThemeData light() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: KodimaliColors.navy,
          brightness: Brightness.light,
        ).copyWith(
          primary: KodimaliColors.navy,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFE6EDF5),
          onPrimaryContainer: KodimaliColors.navy,
          secondary: KodimaliColors.green,
          onSecondary: KodimaliColors.navy,
          secondaryContainer: KodimaliColors.lightGreen,
          onSecondaryContainer: KodimaliColors.navy,
          tertiary: KodimaliColors.warning,
          onTertiary: KodimaliColors.navy,
          tertiaryContainer: KodimaliColors.warningSoft,
          onTertiaryContainer: const Color(0xFF8A5C00),
          error: KodimaliColors.danger,
          onError: Colors.white,
          errorContainer: KodimaliColors.dangerSoft,
          onErrorContainer: const Color(0xFFA73030),
          surface: Colors.white,
          onSurface: KodimaliColors.textDark,
          onSurfaceVariant: KodimaliColors.mutedText,
          outline: KodimaliColors.borderStrong,
          outlineVariant: KodimaliColors.border,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFFAFBFD),
          surfaceContainer: const Color(0xFFF5F8FB),
          surfaceContainerHigh: const Color(0xFFF0F4F9),
          surfaceContainerHighest: KodimaliColors.backgroundRaised,
          shadow: const Color(0x140B1F3A),
          scrim: Colors.black54,
        );

    return _buildTheme(
      scheme: scheme,
      scaffoldColor: KodimaliColors.background,
      dividerColor: KodimaliColors.border,
      shadowColor: const Color(0x140B1F3A),
      canvasColor: KodimaliColors.background,
    );
  }

  static ThemeData dark() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: KodimaliColors.navy,
          brightness: Brightness.dark,
        ).copyWith(
          primary: KodimaliColors.green,
          onPrimary: KodimaliColors.navy,
          primaryContainer: KodimaliColors.darkSurface,
          onPrimaryContainer: KodimaliColors.darkText,
          secondary: KodimaliColors.green,
          onSecondary: KodimaliColors.navy,
          secondaryContainer: KodimaliColors.green.withValues(alpha: 0.16),
          onSecondaryContainer: KodimaliColors.darkText,
          tertiary: KodimaliColors.warning,
          onTertiary: KodimaliColors.navy,
          tertiaryContainer: KodimaliColors.warning.withValues(alpha: 0.18),
          onTertiaryContainer: const Color(0xFFFFD480),
          error: KodimaliColors.danger,
          onError: Colors.white,
          errorContainer: KodimaliColors.danger.withValues(alpha: 0.18),
          onErrorContainer: const Color(0xFFFFC1C1),
          surface: KodimaliColors.darkSurface,
          onSurface: KodimaliColors.darkText,
          onSurfaceVariant: KodimaliColors.darkMutedText,
          outline: KodimaliColors.darkBorder,
          outlineVariant: KodimaliColors.darkBorder.withValues(alpha: 0.85),
          surfaceContainerLowest: KodimaliColors.darkBackground,
          surfaceContainerLow: KodimaliColors.darkSurface,
          surfaceContainer: KodimaliColors.darkSurfaceSoft,
          surfaceContainerHigh: KodimaliColors.darkCard,
          surfaceContainerHighest: KodimaliColors.darkCard,
          shadow: Colors.black54,
          scrim: Colors.black87,
        );

    return _buildTheme(
      scheme: scheme,
      scaffoldColor: KodimaliColors.darkBackground,
      dividerColor: KodimaliColors.darkBorder,
      shadowColor: Colors.black54,
      canvasColor: KodimaliColors.darkBackground,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required Color scaffoldColor,
    required Color dividerColor,
    required Color shadowColor,
    required Color canvasColor,
  }) {
    final Brightness brightness = scheme.brightness;
    final bool isDark = brightness == Brightness.dark;

    final TextTheme baseTextTheme = Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: scheme,
    ).black.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final TextTheme textTheme = baseTextTheme.copyWith(
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: scheme.onSurface,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.55,
        color: scheme.onSurface,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.45,
        color: scheme.onSurfaceVariant,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scaffoldColor,
      canvasColor: canvasColor,
      dividerColor: dividerColor,
      shadowColor: shadowColor,
      splashFactory: InkRipple.splashFactory,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? KodimaliColors.darkCard : KodimaliColors.navy,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.card),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shadowColor: shadowColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.panel),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        modalBackgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KodimaliRadii.hero),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? KodimaliColors.darkSurfaceSoft : Colors.white,
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        helperStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: scheme.error,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KodimaliSpacing.md,
          vertical: KodimaliSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.input),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.input),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.input),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.input),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.input),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? KodimaliColors.green : KodimaliColors.navy,
          foregroundColor: isDark ? KodimaliColors.navy : Colors.white,
          disabledBackgroundColor: scheme.outlineVariant,
          disabledForegroundColor: scheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(
            horizontal: KodimaliSpacing.md,
            vertical: KodimaliSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KodimaliRadii.input),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? scheme.onSurface : scheme.primary,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(
            horizontal: KodimaliSpacing.md,
            vertical: KodimaliSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KodimaliRadii.input),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        disabledColor: scheme.surfaceContainer,
        selectedColor: scheme.secondaryContainer,
        secondarySelectedColor: scheme.secondaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KodimaliRadii.pill),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(
          horizontal: KodimaliSpacing.sm,
          vertical: 6,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        height: 78,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: isDark
            ? KodimaliColors.green.withValues(alpha: 0.22)
            : KodimaliColors.lightGreen,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((
          Set<WidgetState> states,
        ) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
          Set<WidgetState> states,
        ) {
          final bool selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? KodimaliColors.green : KodimaliColors.navy,
      ),
    );
  }
}
