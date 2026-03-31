import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyskill_app/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget tests: Material 3 Theme consistency
//
// Verifies Brand colors, radii, typography, and component themes
// across light and dark modes without needing Firebase.
//
// Run:  flutter test test/widget/theme_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. BRAND CONSTANTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Brand colors', () {
    test('primary indigo is 0xFF6366F1', () {
      expect(Brand.indigo, const Color(0xFF6366F1));
    });

    test('success green is 0xFF10B981', () {
      expect(Brand.success, const Color(0xFF10B981));
    });

    test('error red is 0xFFEF4444', () {
      expect(Brand.error, const Color(0xFFEF4444));
    });

    test('warning amber is 0xFFF59E0B', () {
      expect(Brand.warning, const Color(0xFFF59E0B));
    });

    test('online green is 0xFF22C55E', () {
      expect(Brand.online, const Color(0xFF22C55E));
    });

    test('scaffold bg is 0xFFF4F7F9', () {
      expect(Brand.scaffoldBg, const Color(0xFFF4F7F9));
    });

    test('xp gradient has 3 stops', () {
      expect(Brand.xpGradient.length, 3);
      expect(Brand.xpGradient[0], Brand.indigo);
      expect(Brand.xpGradient[2], Brand.pink);
    });

    test('volunteer gradient is green to indigo', () {
      expect(Brand.volunteerGradient, [Brand.success, Brand.indigo]);
    });
  });

  group('Radii constants', () {
    test('button radius is 14', () => expect(Radii.button, 14.0));
    test('card radius is 16', () => expect(Radii.card, 16.0));
    test('chip radius is 10', () => expect(Radii.chip, 10.0));
    test('modal radius is 24', () => expect(Radii.modal, 24.0));
    test('field radius is 14', () => expect(Radii.field, 14.0));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════════════

  group('Light theme', () {
    testWidgets('uses Material 3', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.useMaterial3, true);
    });

    testWidgets('primary color is brand indigo', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.colorScheme.primary, Brand.indigo);
    });

    testWidgets('error color is brand error', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.colorScheme.error, Brand.error);
    });

    testWidgets('scaffold background is Brand.scaffoldBg', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.scaffoldBackgroundColor, Brand.scaffoldBg);
    });

    testWidgets('brightness is light', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.brightness, Brightness.light);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. DARK THEME
  // ═══════════════════════════════════════════════════════════════════════════

  group('Dark theme', () {
    testWidgets('brightness is dark', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.dark(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.brightness, Brightness.dark);
    });

    testWidgets('scaffold background is Brand.darkBg', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.dark(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.scaffoldBackgroundColor, Brand.darkBg);
    });

    testWidgets('uses Material 3', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.dark(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.useMaterial3, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. COMPONENT THEMES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Component themes (light)', () {
    late ThemeData theme;

    setUp(() {
      // Use a dummy context via Builder
    });

    testWidgets('ElevatedButton has zero elevation', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      final style = theme.elevatedButtonTheme.style!;
      final elevation = style.elevation?.resolve({});
      expect(elevation, 0);
    });

    testWidgets('Card has zero elevation', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.cardTheme.elevation, 0);
    });

    testWidgets('AppBar has no elevation', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.appBarTheme.elevation, 0);
    });

    testWidgets('SnackBar uses floating behavior', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    testWidgets('BottomSheet has drag handle', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.bottomSheetTheme.showDragHandle, true);
    });

    testWidgets('TabBar divider is transparent', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.tabBarTheme.dividerColor, Colors.transparent);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. TYPOGRAPHY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Typography', () {
    testWidgets('text theme has all 12 levels defined', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      final tt = theme.textTheme;
      expect(tt.displayLarge, isNotNull);
      expect(tt.displayMedium, isNotNull);
      expect(tt.displaySmall, isNotNull);
      expect(tt.headlineLarge, isNotNull);
      expect(tt.headlineMedium, isNotNull);
      expect(tt.headlineSmall, isNotNull);
      expect(tt.titleLarge, isNotNull);
      expect(tt.titleMedium, isNotNull);
      expect(tt.titleSmall, isNotNull);
      expect(tt.bodyLarge, isNotNull);
      expect(tt.bodyMedium, isNotNull);
      expect(tt.bodySmall, isNotNull);
    });

    testWidgets('display sizes scale correctly', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      final tt = theme.textTheme;
      expect(tt.displayLarge!.fontSize!, greaterThan(tt.displayMedium!.fontSize!));
      expect(tt.displayMedium!.fontSize!, greaterThan(tt.displaySmall!.fontSize!));
    });

    testWidgets('body sizes for readable content', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      final tt = theme.textTheme;
      expect(tt.bodyLarge!.fontSize, 15);
      expect(tt.bodyMedium!.fontSize, 14);
      expect(tt.bodySmall!.fontSize, 13);
    });

    testWidgets('headline medium is 18 (screen title size)', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          theme = AppTheme.light(ctx);
          return const SizedBox();
        }),
      ));
      expect(theme.textTheme.headlineMedium!.fontSize, 18);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. LIGHT vs DARK DIFFERENCES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Light vs Dark differences', () {
    testWidgets('scaffold backgrounds differ', (tester) async {
      late ThemeData light, dark;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          light = AppTheme.light(ctx);
          dark = AppTheme.dark(ctx);
          return const SizedBox();
        }),
      ));
      expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
    });

    testWidgets('card colors differ', (tester) async {
      late ThemeData light, dark;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          light = AppTheme.light(ctx);
          dark = AppTheme.dark(ctx);
          return const SizedBox();
        }),
      ));
      expect(light.cardTheme.color, isNot(dark.cardTheme.color));
    });

    testWidgets('both use Material 3', (tester) async {
      late ThemeData light, dark;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          light = AppTheme.light(ctx);
          dark = AppTheme.dark(ctx);
          return const SizedBox();
        }),
      ));
      expect(light.useMaterial3, true);
      expect(dark.useMaterial3, true);
    });
  });
}
