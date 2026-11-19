import 'package:flutter/material.dart';

class NovaSemanticColors extends ThemeExtension<NovaSemanticColors> {
  const NovaSemanticColors({required this.success, required this.warning});
  final Color success;
  final Color warning;
  @override
  NovaSemanticColors copyWith({Color? success, Color? warning}) =>
      NovaSemanticColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
      );
  @override
  NovaSemanticColors lerp(ThemeExtension<NovaSemanticColors>? other, double t) {
    if (other is! NovaSemanticColors) return this;
    return NovaSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension NovaSemanticColorsContext on BuildContext {
  NovaSemanticColors get nova =>
      Theme.of(this).extension<NovaSemanticColors>() ??
      const NovaSemanticColors(
        success: Color(0xFF3C7660),
        warning: Color(0xFF916420),
      );
}

/// Warm paper and violet accents leave the strongest colors to cover art.
class AppTheme {
  static const seedColor = Color(0xFF51428D);
  static const _iris = Color(0xFFC8BCFF);
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      primary: dark ? _iris : seedColor,
      onPrimary: dark ? const Color(0xFF282043) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF372D52) : const Color(0xFFEBE4FF),
      onPrimaryContainer:
          dark ? const Color(0xFFE6DEFF) : const Color(0xFF392C6A),
      secondaryContainer:
          dark ? const Color(0xFF312B3D) : const Color(0xFFF0E9F5),
      onSecondaryContainer:
          dark ? const Color(0xFFE0D6ED) : const Color(0xFF514462),
      surface: dark ? const Color(0xFF191621) : const Color(0xFFFBF8F4),
      surfaceContainerLowest:
          dark ? const Color(0xFF12101A) : const Color(0xFFFFFCF8),
      surfaceContainerLow:
          dark ? const Color(0xFF211D2B) : const Color(0xFFF5EFEA),
      surfaceContainer:
          dark ? const Color(0xFF272234) : const Color(0xFFF0E9E5),
      surfaceContainerHigh:
          dark ? const Color(0xFF30293F) : const Color(0xFFEAE0DF),
      surfaceContainerHighest:
          dark ? const Color(0xFF3D344C) : const Color(0xFFE3D9DA),
      onSurface: dark ? const Color(0xFFF4EDF8) : const Color(0xFF241D2B),
      onSurfaceVariant:
          dark ? const Color(0xFFC0B4CA) : const Color(0xFF685C70),
      outline: dark ? const Color(0xFF9D8CA9) : const Color(0xFF907D92),
      outlineVariant: dark ? const Color(0xFF40364D) : const Color(0xFFE8DEDA),
    );
    final text = ThemeData(brightness: brightness).textTheme
        .apply(
          fontFamily: 'Segoe UI',
          fontFamilyFallback: const [
            'Microsoft YaHei UI',
            'Microsoft YaHei',
            'sans-serif',
          ],
          bodyColor: colors.onSurface,
          displayColor: colors.onSurface,
        )
        .copyWith(
          headlineMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
          ),
          headlineSmall: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
          titleLarge: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.35,
          ),
          titleMedium: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          titleSmall: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: const TextStyle(fontSize: 15, height: 1.6),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
          bodySmall: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: colors.onSurfaceVariant,
          ),
          labelLarge: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'sans-serif',
      ],
      textTheme: text,
      scaffoldBackgroundColor: colors.surface,
      focusColor: colors.primary.withValues(alpha: 0.16),
      extensions: [
        NovaSemanticColors(
          success: dark ? const Color(0xFF91CBB3) : const Color(0xFF3C7660),
          warning: dark ? const Color(0xFFE0BE83) : const Color(0xFF916420),
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 28,
        toolbarHeight: 58,
        titleTextStyle: text.headlineSmall?.copyWith(color: colors.onSurface),
      ),
      cardTheme: CardTheme(
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          minimumSize: const Size(64, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: shape,
          elevation: 0,
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(64, 42),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          side: BorderSide(color: colors.outlineVariant),
          minimumSize: const Size(64, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        hintStyle: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: colors.secondaryContainer,
        side: BorderSide(color: colors.outlineVariant),
        shape: shape,
        labelStyle: text.labelLarge?.copyWith(color: colors.onSurfaceVariant),
        showCheckmark: false,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        thumbColor: colors.primary,
        inactiveTrackColor: colors.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: text.bodySmall?.copyWith(color: colors.onInverseSurface),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainerHigh,
        shape: shape,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
    );
  }
}
