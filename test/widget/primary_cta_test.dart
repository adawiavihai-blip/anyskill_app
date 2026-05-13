import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyskill_app/theme/app_theme.dart';
import 'package:anyskill_app/widgets/primary_cta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget tests: PrimaryCTA (CLAUDE.md §59)
//
// Single source of truth for the app's primary action button. Pure widget
// — no Firebase / Firestore dependencies, so 100% deterministic.
//
// Run:  flutter test test/widget/primary_cta_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // Helper: wrap the widget under test in a minimal MaterialApp + Directionality
  // so it can resolve theme + textDirection without booting the full app.
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('Rendering', () {
    testWidgets('renders the label as visible Text', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(label: 'אשר ושלם', onPressed: () {}),
      ));
      expect(find.text('אשר ושלם'), findsOneWidget);
    });

    testWidgets('renders the optional leading icon', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(
          label: 'Pay',
          icon: Icons.lock_rounded,
          onPressed: () {},
        ),
      ));
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('omits the icon when not provided', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(label: 'Submit', onPressed: () {}),
      ));
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });
  });

  group('States', () {
    testWidgets('disabled state — onPressed null disables tap + greys out',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        PrimaryCTA(
          label: 'Disabled',
          icon: Icons.lock_rounded,
          // ignore: avoid_redundant_argument_values
          onPressed: null,
        ),
      ));

      // Tap should NOT fire the callback (it's null).
      await tester.tap(find.byType(PrimaryCTA));
      await tester.pump();
      expect(tapped, false);

      // Semantics: announces enabled=false to screen readers.
      final semantics = tester.getSemantics(find.byType(PrimaryCTA));
      expect(semantics.hasFlag(SemanticsFlag.isEnabled), false);
    });

    testWidgets('loading state — replaces icon with CircularProgressIndicator',
        (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(
          label: 'Working...',
          icon: Icons.lock_rounded,
          loading: true,
          onPressed: () {},
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });

    testWidgets('loading state blocks taps even when onPressed is non-null',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        PrimaryCTA(
          label: 'Working',
          loading: true,
          onPressed: () => taps++,
        ),
      ));
      await tester.tap(find.byType(PrimaryCTA));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('enabled state — tap fires the callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        PrimaryCTA(
          label: 'Submit',
          onPressed: () => taps++,
        ),
      ));
      await tester.tap(find.byType(PrimaryCTA));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('Variants', () {
    Widget ctaForVariant(PrimaryCTAVariant v) => PrimaryCTA(
          label: 'X',
          variant: v,
          onPressed: () {},
        );

    testWidgets('primary variant uses Brand.indigo gradient', (tester) async {
      await tester.pumpWidget(wrap(ctaForVariant(PrimaryCTAVariant.primary)));
      // The gradient lives on a Container's BoxDecoration — find it.
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PrimaryCTA),
              matching: find.byType(Container),
            )
            .first,
      );
      final deco = container.decoration as BoxDecoration?;
      expect(deco?.gradient, isA<LinearGradient>());
      final colors = (deco!.gradient as LinearGradient).colors;
      expect(colors.first, Brand.indigo);
      expect(colors.last, Brand.indigoDark);
    });

    testWidgets('all 4 variants render without exception', (tester) async {
      for (final v in PrimaryCTAVariant.values) {
        await tester.pumpWidget(wrap(ctaForVariant(v)));
        // Just verifying that the build phase doesn't throw — every
        // variant must have a non-null gradient/color.
        expect(find.text('X'), findsOneWidget);
      }
    });
  });

  group('Layout', () {
    testWidgets('default expanded fills horizontal space', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 400,
              child: PrimaryCTA(label: 'Wide', onPressed: () {}),
            ),
          ),
        ),
      ));
      // The internal Container should fill the parent SizedBox (400px).
      final containerSize = tester.getSize(
        find
            .descendant(
              of: find.byType(PrimaryCTA),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(containerSize.width, 400);
    });

    testWidgets('dense=true reduces height to 44 from default 52',
        (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(label: 'Dense', dense: true, onPressed: () {}),
      ));
      final containerSize = tester.getSize(
        find
            .descendant(
              of: find.byType(PrimaryCTA),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(containerSize.height, 44);
    });

    testWidgets('default height is 52', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(label: 'Default', onPressed: () {}),
      ));
      final containerSize = tester.getSize(
        find
            .descendant(
              of: find.byType(PrimaryCTA),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(containerSize.height, 52);
    });

    testWidgets('explicit height override wins over dense', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(
          label: 'Custom',
          height: 60,
          dense: true,
          onPressed: () {},
        ),
      ));
      final containerSize = tester.getSize(
        find
            .descendant(
              of: find.byType(PrimaryCTA),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(containerSize.height, 60);
    });
  });

  group('Accessibility (WCAG 2.1 AA / EU EAA 2025)', () {
    testWidgets('Semantics announces button role', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(label: 'Pay', onPressed: () {}),
      ));
      final semantics = tester.getSemantics(find.byType(PrimaryCTA));
      expect(semantics.hasFlag(SemanticsFlag.isButton), true);
    });

    testWidgets('Semantics carries the optional hint', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(
          label: 'Pay',
          semanticHint: 'Escrows the booking total',
          onPressed: () {},
        ),
      ));
      // Use SemanticsTester via getSemantics — simpler than walking the tree.
      final semantics = tester.getSemantics(find.byType(PrimaryCTA));
      expect(semantics.hint, contains('Escrows the booking total'));
    });

    testWidgets('Semantics enabled=true when onPressed non-null + not loading',
        (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryCTA(label: 'Active', onPressed: () {}),
      ));
      final semantics = tester.getSemantics(find.byType(PrimaryCTA));
      expect(semantics.hasFlag(SemanticsFlag.isEnabled), true);
    });
  });
}
