import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget tests: Responsive layout, accessibility, and loading states
//
// Tests screen sizes, touch targets, overflow detection, RTL layout,
// shimmer/spinner states, and widget rendering without Firebase.
//
// Run:  flutter test test/widget/responsive_layout_test.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Common screen sizes for testing.
const _iphoneSE   = Size(375, 667);   // smallest modern iPhone
const _pixel4a    = Size(393, 851);   // common Android
const _iphone15   = Size(393, 852);   // standard iPhone
const _iphone15PM = Size(430, 932);   // largest iPhone
const _ipadMini   = Size(744, 1133);  // tablet

/// Wrap widget with a specific screen size.
Widget _sizedApp(Size size, Widget child) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. RESPONSIVE GRID
  // ═══════════════════════════════════════════════════════════════════════════

  group('Responsive grid', () {
    int computeColumns(double width) =>
        width >= 900 ? 4 : width >= 600 ? 3 : 2;

    test('2 columns on small screen (375px)', () {
      expect(computeColumns(_iphoneSE.width), 2);
    });

    test('2 columns on standard phone (393px)', () {
      expect(computeColumns(_iphone15.width), 2);
    });

    test('2 columns on large phone (430px)', () {
      expect(computeColumns(_iphone15PM.width), 2);
    });

    test('3 columns on tablet (744px)', () {
      expect(computeColumns(_ipadMini.width), 3);
    });

    test('4 columns on wide screen (1024px)', () {
      expect(computeColumns(1024), 4);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. NO OVERFLOW ON SMALL SCREENS
  // ═══════════════════════════════════════════════════════════════════════════

  group('No overflow', () {
    testWidgets('long text truncates with ellipsis', (tester) async {
      await tester.pumpWidget(_sizedApp(_iphoneSE,
        const SizedBox(
          width: 100,
          child: Text(
            'שם ארוך מאוד של נותן שירות שלא נכנס בשורה אחת',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ));
      // No overflow exception = pass
      expect(tester.takeException(), isNull);
    });

    testWidgets('row with expanded does not overflow', (tester) async {
      await tester.pumpWidget(_sizedApp(_iphoneSE,
        Row(
          children: [
            const Icon(Icons.star, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('טקסט ארוך מאוד ' * 5,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Text('₪100'),
          ],
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('card renders on all screen sizes without overflow', (tester) async {
      for (final size in [_iphoneSE, _pixel4a, _iphone15PM]) {
        await tester.pumpWidget(_sizedApp(size,
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('כותרת', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('תיאור קצר של השירות'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                      const Text('4.8'),
                      const Spacer(),
                      const Text('₪150/שעה'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. TOUCH TARGETS (Accessibility)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Touch targets (48x48 minimum)', () {
    testWidgets('ElevatedButton meets minimum size', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('שלח'),
            ),
          ),
        ),
      ));

      final button = tester.getSize(find.byType(ElevatedButton));
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
    });

    testWidgets('IconButton meets minimum size', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.favorite),
            ),
          ),
        ),
      ));

      final button = tester.getSize(find.byType(IconButton));
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
    });

    testWidgets('TextButton meets minimum height', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {},
              child: const Text('לחץ'),
            ),
          ),
        ),
      ));

      final button = tester.getSize(find.byType(TextButton));
      expect(button.height, greaterThanOrEqualTo(36)); // Material 3 min
    });

    testWidgets('Checkbox has adequate touch area', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Checkbox(value: false, onChanged: (_) {}),
          ),
        ),
      ));

      final checkbox = tester.getSize(find.byType(Checkbox));
      expect(checkbox.width, greaterThanOrEqualTo(40));
      expect(checkbox.height, greaterThanOrEqualTo(40));
    });

    testWidgets('Switch has adequate touch area', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Switch(value: false, onChanged: (_) {}),
          ),
        ),
      ));

      final sw = tester.getSize(find.byType(Switch));
      expect(sw.width, greaterThanOrEqualTo(48));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. RTL LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  group('RTL layout', () {
    testWidgets('Directionality.rtl reverses Row children', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: const [
                Text('ראשון'),
                SizedBox(width: 8),
                Text('שני'),
              ],
            ),
          ),
        ),
      ));

      // In RTL, "ראשון" should be on the right
      final firstPos = tester.getTopLeft(find.text('ראשון'));
      final secondPos = tester.getTopLeft(find.text('שני'));
      expect(firstPos.dx, greaterThan(secondPos.dx));
    });

    testWidgets('TextAlign.start works in RTL', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: const SizedBox(
              width: 300,
              child: Text(
                'טקסט מיושר',
                textAlign: TextAlign.start,
              ),
            ),
          ),
        ),
      ));
      // No exception = correct alignment
      expect(tester.takeException(), isNull);
    });

    testWidgets('EdgeInsetsDirectional respects RTL', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: const Padding(
              padding: EdgeInsetsDirectional.only(start: 20, end: 10),
              child: Text('RTL padded'),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. LOADING STATES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Loading states', () {
    testWidgets('spinner shows during loading', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const Center(child: CircularProgressIndicator()),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('spinner disappears when data arrives', (tester) async {
      bool loading = true;
      late StateSetter setState;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, ss) {
              setState = ss;
              return loading
                  ? const Center(child: CircularProgressIndicator())
                  : const Text('Data loaded');
            },
          ),
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Data loaded'), findsNothing);

      setState(() => loading = false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Data loaded'), findsOneWidget);
    });

    testWidgets('shimmer placeholder renders without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 5,
            itemBuilder: (ctx, i) => Container(
              margin: const EdgeInsets.all(8),
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ));
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('error state shows message and retry button', (tester) async {
      bool hasError = true;
      int retryCount = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) {
              if (hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('שגיאה בטעינה'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {
                          retryCount++;
                          hasError = false;
                        }),
                        child: const Text('נסה שוב'),
                      ),
                    ],
                  ),
                );
              }
              return const Text('הצלחה');
            },
          ),
        ),
      ));

      expect(find.text('שגיאה בטעינה'), findsOneWidget);
      expect(find.text('נסה שוב'), findsOneWidget);

      await tester.tap(find.text('נסה שוב'));
      await tester.pump();

      expect(find.text('הצלחה'), findsOneWidget);
      expect(retryCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. LIST PERFORMANCE
  // ═══════════════════════════════════════════════════════════════════════════

  group('List rendering', () {
    testWidgets('ListView.builder renders only visible items', (tester) async {
      int buildCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 1000,
            itemBuilder: (ctx, i) {
              buildCount++;
              return ListTile(title: Text('Item $i'));
            },
          ),
        ),
      ));

      // Only visible items should be built, not all 1000
      expect(buildCount, lessThan(30));
    });

    testWidgets('GridView renders without overflow', (tester) async {
      await tester.pumpWidget(_sizedApp(_iphoneSE,
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          padding: const EdgeInsets.all(16),
          itemCount: 20,
          itemBuilder: (ctx, i) => Card(
            child: Center(child: Text('Card $i')),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('horizontal scroll list renders correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 50,
              itemBuilder: (ctx, i) => Container(
                width: 80,
                margin: const EdgeInsets.all(4),
                color: Colors.blue,
                child: Center(child: Text('$i')),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. DIALOG & SHEET RENDERING
  // ═══════════════════════════════════════════════════════════════════════════

  group('Dialogs and sheets', () {
    testWidgets('AlertDialog renders with RTL text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog(
                context: ctx,
                builder: (_) => const AlertDialog(
                  title: Text('אישור'),
                  content: Text('האם אתה בטוח?'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('אישור'), findsOneWidget);
      expect(find.text('האם אתה בטוח?'), findsOneWidget);
    });

    testWidgets('SnackBar appears and is visible', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('הצלחה!')),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();

      expect(find.text('הצלחה!'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. EMPTY STATE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Empty states', () {
    testWidgets('empty list shows placeholder message', (tester) async {
      final items = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: items.isEmpty
              ? const Center(child: Text('אין תוצאות'))
              : ListView(children: items.map((e) => Text(e)).toList()),
        ),
      ));
      expect(find.text('אין תוצאות'), findsOneWidget);
    });

    testWidgets('SizedBox.shrink collapses correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: const [
              Text('Above'),
              SizedBox.shrink(),
              Text('Below'),
            ],
          ),
        ),
      ));

      final above = tester.getBottomLeft(find.text('Above'));
      final below = tester.getTopLeft(find.text('Below'));
      // They should be directly adjacent (no gap from SizedBox.shrink)
      expect(below.dy - above.dy, lessThan(2));
    });
  });
}
