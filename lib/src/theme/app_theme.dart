import 'package:flutter/material.dart';

class ThemeTones {
  const ThemeTones(
    this.background,
    this.surface,
    this.text,
    this.muted,
    this.primary,
    this.onPrimary,
  );
  final int background, surface, text, muted, primary, onPrimary;
}

enum AppPalette {
  ink(
    '经典墨蓝',
    ThemeTones(
      0xfff8f7f4,
      0xffffffff,
      0xff242628,
      0xff58616a,
      0xff3459a6,
      0xffffffff,
    ),
    ThemeTones(
      0xff15191f,
      0xff1e242c,
      0xffeef1f5,
      0xffacb6c3,
      0xffa7c3ff,
      0xff14274c,
    ),
  ),
  sea(
    '海盐青',
    ThemeTones(
      0xfff0f6f5,
      0xfffbfefd,
      0xff1f3336,
      0xff4c6466,
      0xff1d696b,
      0xffffffff,
    ),
    ThemeTones(
      0xff142529,
      0xff1c3035,
      0xffe4f1f0,
      0xffa6bdbd,
      0xff83cec8,
      0xff103335,
    ),
  ),
  amber(
    '琥珀纸',
    ThemeTones(
      0xfff8f1df,
      0xfffffaed,
      0xff382f23,
      0xff695d4a,
      0xff875017,
      0xffffffff,
    ),
    ThemeTones(
      0xff231e18,
      0xff302820,
      0xfff2e8d5,
      0xffc2b29b,
      0xffe9b676,
      0xff3c290e,
    ),
  ),
  plum(
    '雾莓紫',
    ThemeTones(
      0xfff7f2fa,
      0xfffefaff,
      0xff342b3c,
      0xff66596f,
      0xff744780,
      0xffffffff,
    ),
    ThemeTones(
      0xff221e29,
      0xff302936,
      0xfff2e8f6,
      0xffc6b5ce,
      0xffdab2e4,
      0xff3e2545,
    ),
  );

  const AppPalette(this.label, this.day, this.night);
  final String label;
  final ThemeTones day, night;
  static AppPalette parse(String? value) =>
      values.where((p) => p.name == value).firstOrNull ?? ink;
}

class AppTheme {
  static ThemeData light({
    AppPalette palette = AppPalette.ink,
    bool serif = true,
  }) => _build(Brightness.light, palette.day, serif);
  static ThemeData dark({
    AppPalette palette = AppPalette.ink,
    bool serif = true,
  }) => _build(Brightness.dark, palette.night, serif);
  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xff8ed0a8)
      : const Color(0xff266747);

  static ThemeData _build(Brightness brightness, ThemeTones tones, bool serif) {
    final isDark = brightness == Brightness.dark;
    final primary = Color(tones.primary),
        background = Color(tones.background),
        surface = Color(tones.surface);
    final elevatedSurface = Color.lerp(
      surface,
      primary,
      isDark ? 0.08 : 0.035,
    )!;
    final outline = Color.lerp(surface, Color(tones.muted), .42)!;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: Color(tones.onPrimary),
          secondary: primary,
          surface: surface,
          onSurface: Color(tones.text),
          onSurfaceVariant: Color(tones.muted),
          surfaceContainerHighest: elevatedSurface,
          outline: outline,
          outlineVariant: Color.lerp(surface, outline, .58),
          error: Color(isDark ? 0xffffaab3 : 0xffaa373f),
        );
    final base =
        ThemeData(
          brightness: brightness,
          useMaterial3: true,
          colorScheme: scheme,
        ).textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );
    final textTheme = base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        fontFamily: serif ? 'serif' : null,
        fontFamilyFallback: serif
            ? const [
                'Source Han Serif SC',
                'Noto Serif CJK SC',
                'Noto Serif SC',
                'Songti SC',
                'SimSun',
                'serif',
              ]
            : null,
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      cardColor: surface,
      dividerColor: scheme.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevatedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: elevatedSurface,
          foregroundColor: scheme.onSurfaceVariant,
          selectedBackgroundColor: scheme.primary.withValues(alpha: 0.14),
          selectedForegroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return isDark ? const Color(0xFFE5E5EA) : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.outlineVariant;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: isDark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFF1D1D1F),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
