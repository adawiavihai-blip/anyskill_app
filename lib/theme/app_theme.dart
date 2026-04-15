import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AnySkill — Material 3 Theme System
//
// Single source of truth for colors, typography, and component styles.
// Both light and dark schemes are generated from the brand seed color.
//
// Usage in main.dart:
//   theme:     AppTheme.light(context),
//   darkTheme: AppTheme.dark(context),
// ═══════════════════════════════════════════════════════════════════════════════

// ── Brand colors (for gradients and custom widgets that can't use scheme) ────

abstract final class Brand {
  // Primary palette
  static const indigo      = Color(0xFF6366F1);
  static const indigoDark  = Color(0xFF4F46E5);
  static const purple      = Color(0xFF8B5CF6);
  static const pink        = Color(0xFFEC4899);

  // Semantic
  static const success     = Color(0xFF10B981);
  static const error       = Color(0xFFEF4444);
  static const warning     = Color(0xFFF59E0B);
  static const online      = Color(0xFF22C55E);

  // Text
  static const textDark    = Color(0xFF111827);
  static const textMuted   = Color(0xFF6B7280);
  static const textLight   = Color(0xFF9CA3AF);

  // Surfaces
  static const scaffoldBg  = Color(0xFFF4F7F9);
  static const cardBg      = Colors.white;
  static const surfaceTint = Color(0xFFEEF2FF);
  static const divider     = Color(0xFFE5E7EB);

  // Dark surfaces (AI CEO, Academy)
  static const darkBg      = Color(0xFF0F0F1A);
  static const darkCard    = Color(0xFF1A1A2E);

  // Key gradients
  static const xpGradient       = [indigo, purple, pink];
  static const levelGradient    = [indigo, purple];
  static const volunteerGradient = [success, indigo];
  static const ctaGradient      = [indigo, indigoDark];
}

// ── Map screen palette (v12.9.0) ─────────────────────────────────────────────
// Scoped to the map view ONLY. Imports: providers_map_view.dart + the new
// sections of category_results_screen.dart. Keeps the rest of the app on
// Brand.* untouched so this experiment can be reverted in one commit.

abstract final class MapPalette {
  // Primary — CTA purple (matches the mockup)
  static const primary       = Color(0xFF5B5FE6);
  static const primaryLight  = Color(0xFFEDEDFD);  // selection / pill bg
  static const primaryDark   = Color(0xFF4548C7);  // pressed state

  // Semantic
  static const online        = Color(0xFF22C55E);  // availability dot
  static const gold          = Color(0xFFF5D98C);  // provider card border
  static const goldActive    = Color(0xFFF59E0B);  // active marker ring / glow
  static const red           = Color(0xFFEF4444);  // heart / unavailable

  // Neutrals
  static const textPrimary   = Color(0xFF1A1D26);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary  = Color(0xFF9CA3AF);

  // Surfaces
  static const background    = Color(0xFFF8F9FB);
  static const cardWhite     = Color(0xFFFFFFFF);
  static const border        = Color(0xFFE5E7EB);
  static const borderLight   = Color(0xFFFEF3C7);  // very-light gold

  // Semantic tag backgrounds (from the mockup)
  static const tagBlueBg     = Color(0xFFEEF2FF);  // "comes to your home"
  static const tagBlueFg     = Color(0xFF4338CA);
  static const tagGreenBg    = Color(0xFFF0FDF4);  // "certified"
  static const tagGreenFg    = Color(0xFF15803D);
  static const tagRoseBg     = Color(0xFFFFF1F2);  // "50% off first lesson"
  static const tagRoseFg     = Color(0xFFBE123C);
  static const tagGrayBg     = Color(0xFFF8F9FB);
  static const tagGrayFg     = Color(0xFF6B7280);

  // Pointer dot + glow on markers
  static const markerGlow    = Color(0x4422C55E); // online halo (27% alpha)
}

abstract final class MapShadows {
  static const card = [
    BoxShadow(
      color: Color(0x1A000000),  // 10% black
      blurRadius: 14,
      offset: Offset(0, 6),
    ),
  ];
  static const chip = [
    BoxShadow(
      color: Color(0x0F000000),  // 6% black
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  static const floatingControl = [
    BoxShadow(
      color: Color(0x1F000000),  // 12% black
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
  ];
}

// ── Radii ────────────────────────────────────────────────────────────────────

abstract final class Radii {
  static const button   = 14.0;
  static const card     = 16.0;
  static const chip     = 10.0;
  static const modal    = 24.0;
  static const field    = 14.0;
  static const avatar   = 100.0; // full circle
}

// ── Theme builder ───────────────────────────────────────────────────────────

abstract final class AppTheme {
  /// Light theme — primary mode for AnySkill.
  static ThemeData light(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor:  Brand.indigo,
      brightness: Brightness.light,
      // Override key slots so they match the brand exactly
      primary:          Brand.indigo,
      onPrimary:        Colors.white,
      secondary:        Brand.purple,
      onSecondary:      Colors.white,
      tertiary:         Brand.warning,
      onTertiary:       Colors.white,
      error:            Brand.error,
      onError:          Colors.white,
      surface:          Colors.white,
      onSurface:        Brand.textDark,
      surfaceContainerHighest: Brand.scaffoldBg,
    );

    return _build(context, colorScheme, Brightness.light);
  }

  /// Dark theme — for future use and user preference.
  static ThemeData dark(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor:  Brand.indigo,
      brightness: Brightness.dark,
      primary:          const Color(0xFF9B9DFF), // lighter indigo for dark bg
      onPrimary:        Brand.textDark,
      secondary:        const Color(0xFFB794F6), // lighter purple
      onSecondary:      Brand.textDark,
      tertiary:         Brand.warning,
      error:            const Color(0xFFF87171), // lighter red
      surface:          Brand.darkCard,
      onSurface:        const Color(0xFFE2E8F0),
      surfaceContainerHighest: Brand.darkBg,
    );

    return _build(context, colorScheme, Brightness.dark);
  }

  // ── Internal builder ────────────────────────────────────────────────────

  static ThemeData _build(
    BuildContext context,
    ColorScheme scheme,
    Brightness brightness,
  ) {
    final isLight = brightness == Brightness.light;

    // ── Typography ────────────────────────────────────────────────────────
    // Assistant is the primary font — clean, modern, high-tech feel with
    // excellent Hebrew support. NotoSansHebrew is the offline/fallback.
    final baseText = GoogleFonts.assistantTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(fontFamilyFallback: const ['NotoSansHebrew', 'sans-serif']);

    final textTheme = baseText.copyWith(
      // Display — splash screens, onboarding hero text
      displayLarge:  baseText.displayLarge?.copyWith(
        fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      displayMedium: baseText.displayMedium?.copyWith(
        fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      displaySmall:  baseText.displaySmall?.copyWith(
        fontSize: 24, fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),

      // Headline — screen titles, section headers
      headlineLarge:  baseText.headlineLarge?.copyWith(
        fontSize: 22, fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 18, fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      headlineSmall:  baseText.headlineSmall?.copyWith(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),

      // Title — card titles, list items
      titleLarge:  baseText.titleLarge?.copyWith(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 15, fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      titleSmall:  baseText.titleSmall?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),

      // Body — main content text
      bodyLarge:  baseText.bodyLarge?.copyWith(
        fontSize: 15, fontWeight: FontWeight.w400, height: 1.5,
        color: scheme.onSurface,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w400, height: 1.45,
        color: scheme.onSurface,
      ),
      bodySmall:  baseText.bodySmall?.copyWith(
        fontSize: 13, fontWeight: FontWeight.w400,
        color: isLight ? Brand.textMuted : const Color(0xFF94A3B8),
      ),

      // Label — buttons, chips, badges, captions
      labelLarge:  baseText.labelLarge?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: 12, fontWeight: FontWeight.w500,
      ),
      labelSmall:  baseText.labelSmall?.copyWith(
        fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3,
        color: isLight ? Brand.textLight : const Color(0xFF94A3B8),
      ),
    );

    return ThemeData(
      useMaterial3:         true,
      brightness:           brightness,
      colorScheme:          scheme,
      scaffoldBackgroundColor: isLight ? Brand.scaffoldBg : Brand.darkBg,
      textTheme:            textTheme,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        elevation:            0,
        scrolledUnderElevation: 0.5,
        backgroundColor:     isLight ? Colors.white : Brand.darkCard,
        foregroundColor:      scheme.onSurface,
        centerTitle:          true,
        titleTextStyle:       textTheme.headlineMedium,
      ),

      // ── ElevatedButton — primary CTA ("Book Now", "Upload") ─────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:    scheme.primary,
          foregroundColor:     scheme.onPrimary,
          elevation:           0,
          padding:             const EdgeInsets.symmetric(
              horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            color: scheme.onPrimary,
          ),
        ),
      ),

      // ── OutlinedButton — secondary actions ──────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:   scheme.primary,
          padding:           const EdgeInsets.symmetric(
              horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
        ),
      ),

      // ── TextButton — tertiary / inline actions ──────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor:   scheme.primary,
          padding:           const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ── FloatingActionButton ────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor:   scheme.primary,
        foregroundColor:    scheme.onPrimary,
        elevation:          2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),

      // ── Card ────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation:   0,
        color:       isLight ? Colors.white : Brand.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(
            color: isLight ? Brand.divider : Colors.white10,
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── TextField / InputDecoration ─────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:            true,
        fillColor:         isLight
            ? const Color(0xFFF9FAFB)
            : const Color(0xFF232336),
        contentPadding:    const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide:   BorderSide(color: Brand.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide:   BorderSide(
            color: isLight ? Brand.divider : Colors.white12,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide:   BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide:   BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide:   BorderSide(color: scheme.error, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? Brand.textLight : const Color(0xFF64748B),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? Brand.textMuted : const Color(0xFF94A3B8),
        ),
      ),

      // ── Chip ────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:   isLight ? Brand.surfaceTint : Brand.darkCard,
        selectedColor:     scheme.primary.withValues(alpha: 0.15),
        labelStyle:        textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        side: BorderSide.none,
        padding:           const EdgeInsets.symmetric(
            horizontal: 12, vertical: 6),
      ),

      // ── Dialog ──────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.modal),
        ),
        backgroundColor: isLight ? Colors.white : Brand.darkCard,
        titleTextStyle:   textTheme.headlineMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),

      // ── BottomSheet ─────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Colors.white : Brand.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.modal),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: isLight ? Brand.divider : Colors.white24,
      ),

      // ── BottomNavigationBar ─────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:      isLight ? Colors.white : Brand.darkCard,
        selectedItemColor:     scheme.primary,
        unselectedItemColor:   Brand.textLight,
        type:                  BottomNavigationBarType.fixed,
        elevation:             8,
        selectedLabelStyle:    textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600),
        unselectedLabelStyle:  textTheme.labelSmall,
      ),

      // ── SnackBar ────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior:         SnackBarBehavior.floating,
        backgroundColor:  isLight ? Brand.textDark : const Color(0xFF334155),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
      ),

      // ── TabBar ──────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor:           scheme.primary,
        unselectedLabelColor: Brand.textMuted,
        indicatorColor:       scheme.primary,
        labelStyle:           textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelMedium,
        dividerColor:         Colors.transparent,
      ),

      // ── Divider ─────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color:     isLight ? Brand.divider : Colors.white10,
        thickness: 1,
        space:     1,
      ),

      // ── ProgressIndicator ───────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color:                scheme.primary,
        linearTrackColor:     isLight ? Brand.divider : Colors.white10,
        circularTrackColor:   isLight ? Brand.divider : Colors.white10,
      ),

      // ── Switch / Checkbox ───────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(scheme.primary),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.4);
          }
          return isLight ? Brand.divider : Colors.white12;
        }),
      ),

      // ── Scrollbar ──────────────────────────────────────────────────
      scrollbarTheme: ScrollbarThemeData(
        radius:    const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(4),
        thumbColor: WidgetStatePropertyAll(
          isLight ? Brand.textLight.withValues(alpha: 0.3)
                  : Colors.white24,
        ),
      ),
    );
  }
}
