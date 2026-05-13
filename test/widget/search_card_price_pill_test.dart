import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyskill_app/l10n/app_localizations.dart';
import 'package:anyskill_app/widgets/category_specs_widget.dart';
import 'package:anyskill_app/widgets/search_card_price_pill.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget tests: SearchCardPricePill (CLAUDE.md §62)
//
// Pure widget — takes a userData Map + a ServiceSchema, no Firestore /
// CachedReaders dependency. The async wrapper [AsyncProviderPricePill] from
// §63 is integration-tested separately (it touches Firestore via CachedReaders).
//
// Run:  flutter test test/widget/search_card_price_pill_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // Helper: minimal MaterialApp with l10n delegates so AppLocalizations.of()
  // resolves. Hebrew locale (RTL).
  Widget wrap(Widget child) {
    return MaterialApp(
      locale: const Locale('he'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('Empty schema (legacy fallback)', () {
    testWidgets(
        'renders pricePerHour with "₪/שעה" suffix when schema is empty',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 150},
        schema: ServiceSchema.empty(),
      )));
      await tester.pumpAndSettle();

      // Big price line.
      expect(find.textContaining('₪150', findRichText: true), findsOneWidget);
      // Hebrew unit label from l10n.catResultsPerHour ("₪/שעה").
      expect(find.textContaining('₪/שעה', findRichText: true), findsOneWidget);
    });

    testWidgets('falls back to ₪100 when pricePerHour is missing',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {},
        schema: ServiceSchema.empty(),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('₪100', findRichText: true), findsOneWidget);
    });

    testWidgets('shows NO transparency badges when schema is empty',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 100},
        schema: ServiceSchema.empty(),
      )));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      expect(find.byIcon(Icons.savings_outlined), findsNothing);
      expect(find.byIcon(Icons.local_offer_outlined), findsNothing);
      expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    });
  });

  group('v2 schema with primary price field', () {
    final petBoardingSchema = ServiceSchema(
      version: 2,
      unitType: 'per_night',
      fields: const [
        SchemaField(
          id: 'pricePerNight',
          label: 'מחיר ללילה',
          type: 'number',
          unit: '₪/ללילה',
        ),
      ],
    );

    testWidgets('renders categoryDetails price with the schema unit',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {
          'pricePerHour': 100, // legacy fallback (should be ignored)
          'categoryDetails': {'pricePerNight': 250},
        },
        schema: petBoardingSchema,
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('₪250', findRichText: true), findsOneWidget);
      expect(find.textContaining('₪/ללילה', findRichText: true), findsOneWidget);
    });
  });

  group('Transparency badges', () {
    testWidgets('depositPercent > 0 → renders savings_outlined badge',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 200},
        schema: const ServiceSchema(depositPercent: 25),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
      expect(find.textContaining('פיקדון 25%'), findsOneWidget);
    });

    testWidgets('priceLocked: true → renders 🔒 lock badge', (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 300},
        schema: const ServiceSchema(priceLocked: true),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.textContaining('מחיר נעול'), findsOneWidget);
    });

    testWidgets('bundles[*].savingsPercent > 0 → renders bundle badge',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 100},
        schema: const ServiceSchema(
          bundles: [
            PricingBundle(
              id: 'pack4',
              label: '4-pack',
              price: 360,
              qty: 4,
              savingsPercent: 10,
            ),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.local_offer_outlined), findsOneWidget);
      expect(find.textContaining('חבילה: -10%'), findsOneWidget);
    });

    testWidgets('cheapest bundle wins when multiple bundles exist',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 100},
        schema: const ServiceSchema(
          bundles: [
            PricingBundle(
              id: 'pack4',
              label: '4-pack',
              price: 360,
              qty: 4,
              savingsPercent: 10,
            ),
            PricingBundle(
              id: 'pack10',
              label: '10-pack',
              price: 800,
              qty: 10,
              savingsPercent: 20, // larger savings — should win
            ),
          ],
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('-20%'), findsOneWidget);
      expect(find.textContaining('-10%'), findsNothing);
    });

    testWidgets('schema-default surcharge active → renders night badge',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 200},
        schema: const ServiceSchema(
          surcharge: SurchargeConfig(nightPercent: 30),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      expect(find.textContaining('+30% לילה'), findsOneWidget);
    });

    testWidgets('inactive surcharge (0%) → renders no badge', (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 200},
        schema: const ServiceSchema(
          surcharge: SurchargeConfig(nightPercent: 0, weekendPercent: 0),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    });
  });

  group('Provider surcharge override', () {
    const baseSchema = ServiceSchema(
      surcharge: SurchargeConfig(nightPercent: 25),
    );

    testWidgets(
        'override.enabled=true with custom nightPct overrides the schema default',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {
          'pricePerHour': 200,
          'categoryDetails': {
            '_surcharge': {'enabled': true, 'nightPct': 50},
          },
        },
        schema: baseSchema,
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('+50% לילה'), findsOneWidget);
      expect(find.textContaining('+25% לילה'), findsNothing);
    });

    testWidgets(
        'override.enabled=false → falls back to schema default',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {
          'pricePerHour': 200,
          'categoryDetails': {
            '_surcharge': {'enabled': false},
          },
        },
        schema: baseSchema,
      )));
      await tester.pumpAndSettle();
      // override disabled but schema has 25% → schema wins
      expect(find.textContaining('+25% לילה'), findsOneWidget);
    });
  });

  group('Multi-badge composition', () {
    testWidgets('all 4 conditions present → all 4 badges visible',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 200},
        schema: const ServiceSchema(
          depositPercent: 30,
          priceLocked: true,
          bundles: [
            PricingBundle(
              id: 'pack',
              label: 'pack',
              price: 100,
              savingsPercent: 15,
            ),
          ],
          surcharge: SurchargeConfig(nightPercent: 20),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.local_offer_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
    });
  });

  group('Layout', () {
    testWidgets('dense=true reduces big price font from 18 to 16',
        (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 100},
        schema: ServiceSchema.empty(),
        dense: true,
      )));
      await tester.pumpAndSettle();

      // RichText is the price + unit composite. Inspect the inner price
      // TextSpan's fontSize through the RichText's text spans.
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final priceRichText = richTexts.firstWhere((r) {
        final root = r.text;
        if (root is! TextSpan) return false;
        final children = root.children ?? const [];
        return children.any(
          (s) => s is TextSpan && (s.text ?? '').contains('₪100'),
        );
      });
      final root = priceRichText.text as TextSpan;
      final priceSpan = (root.children!.first as TextSpan);
      expect(priceSpan.style?.fontSize, 16.0);
    });

    testWidgets('default (non-dense) uses 18pt big price font', (tester) async {
      await tester.pumpWidget(wrap(SearchCardPricePill(
        userData: const {'pricePerHour': 100},
        schema: ServiceSchema.empty(),
      )));
      await tester.pumpAndSettle();
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final priceRichText = richTexts.firstWhere((r) {
        final root = r.text;
        if (root is! TextSpan) return false;
        final children = root.children ?? const [];
        return children.any(
          (s) => s is TextSpan && (s.text ?? '').contains('₪100'),
        );
      });
      final root = priceRichText.text as TextSpan;
      final priceSpan = (root.children!.first as TextSpan);
      expect(priceSpan.style?.fontSize, 18.0);
    });
  });
}
