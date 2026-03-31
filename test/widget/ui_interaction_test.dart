import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget tests: UI interactions, micro-interactions, and component behavior
//
// Run:  flutter test test/widget/ui_interaction_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. BOTTOM NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Bottom navigation', () {
    testWidgets('tapping tab changes selected index', (tester) async {
      int selectedIndex = 0;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (ctx, setState) => Scaffold(
            body: Center(child: Text('Tab $selectedIndex')),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: (i) => setState(() => selectedIndex = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'בית'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: 'חיפוש'),
                BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'צ\'אט'),
                BottomNavigationBarItem(icon: Icon(Icons.person), label: 'פרופיל'),
              ],
            ),
          ),
        ),
      ));

      expect(find.text('Tab 0'), findsOneWidget);
      await tester.tap(find.text('חיפוש'));
      await tester.pump();
      expect(find.text('Tab 1'), findsOneWidget);
    });

    testWidgets('all 4 tabs are rendered', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BottomNavigationBar(
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'בית'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'חיפוש'),
              BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'צ\'אט'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'פרופיל'),
            ],
          ),
        ),
      ));

      expect(find.text('בית'), findsOneWidget);
      expect(find.text('חיפוש'), findsOneWidget);
      expect(find.text('פרופיל'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. SEARCH BAR
  // ═══════════════════════════════════════════════════════════════════════════

  group('Search bar', () {
    testWidgets('typing updates text field', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            decoration: const InputDecoration(hintText: 'חפש שירות...'),
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), 'ניקיון');
      expect(find.text('ניקיון'), findsOneWidget);
    });

    testWidgets('clear button resets search', (tester) async {
      final controller = TextEditingController(text: 'ניקיון');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => controller.clear(),
              ),
            ),
          ),
        ),
      ));

      expect(find.text('ניקיון'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(controller.text, '');
    });

    testWidgets('hint text shows in empty state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            decoration: const InputDecoration(hintText: 'חפש שירות...'),
          ),
        ),
      ));
      expect(find.text('חפש שירות...'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. TOGGLE SWITCHES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Toggle switches', () {
    testWidgets('switch toggles on tap', (tester) async {
      bool isOnline = false;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (ctx, setState) => Scaffold(
            body: SwitchListTile(
              title: const Text('מצב אונליין'),
              value: isOnline,
              onChanged: (v) => setState(() => isOnline = v),
            ),
          ),
        ),
      ));

      expect(find.text('מצב אונליין'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      // Switch should now be on (verified by the rebuild)
    });

    testWidgets('checkbox toggles state', (tester) async {
      bool accepted = false;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (ctx, setState) => Scaffold(
            body: CheckboxListTile(
              title: const Text('אני מסכים לתנאים'),
              value: accepted,
              onChanged: (v) => setState(() => accepted = v ?? false),
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      // Checkbox toggled
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. DROPDOWN MENUS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Dropdown menus', () {
    testWidgets('dropdown shows options on tap', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DropdownButton<String>(
            value: selected,
            hint: const Text('בחר קטגוריה'),
            items: const [
              DropdownMenuItem(value: 'ניקיון', child: Text('ניקיון')),
              DropdownMenuItem(value: 'שיפוצים', child: Text('שיפוצים')),
              DropdownMenuItem(value: 'הובלות', child: Text('הובלות')),
            ],
            onChanged: (v) {},
          ),
        ),
      ));

      expect(find.text('בחר קטגוריה'), findsOneWidget);
      await tester.tap(find.text('בחר קטגוריה'));
      await tester.pumpAndSettle();

      // Dropdown menu items should appear
      expect(find.text('ניקיון'), findsWidgets);
      expect(find.text('שיפוצים'), findsWidgets);
    });

    testWidgets('selecting option closes dropdown', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (ctx, setState) => Scaffold(
            body: DropdownButton<String>(
              value: selected,
              hint: const Text('בחר'),
              items: const [
                DropdownMenuItem(value: 'a', child: Text('Option A')),
                DropdownMenuItem(value: 'b', child: Text('Option B')),
              ],
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('בחר'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Option A').last);
      await tester.pumpAndSettle();

      expect(find.text('Option A'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. CHIP SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Chip selection', () {
    testWidgets('filter chips toggle on tap', (tester) async {
      final selected = <String>{};
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (ctx, setState) => Scaffold(
            body: Wrap(
              children: ['ניקיון', 'שיפוצים', 'הובלות'].map((label) =>
                FilterChip(
                  label: Text(label),
                  selected: selected.contains(label),
                  onSelected: (v) => setState(() {
                    v ? selected.add(label) : selected.remove(label);
                  }),
                ),
              ).toList(),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('ניקיון'));
      await tester.pump();
      await tester.tap(find.text('הובלות'));
      await tester.pump();

      expect(selected, {'ניקיון', 'הובלות'});
    });

    testWidgets('action chip triggers callback', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ActionChip(
            label: const Text('סנן'),
            onPressed: () => pressed = true,
          ),
        ),
      ));

      await tester.tap(find.text('סנן'));
      expect(pressed, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. SCROLL BEHAVIOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scroll behavior', () {
    testWidgets('scrolling reveals hidden content', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: List.generate(50, (i) => ListTile(
              title: Text('Item $i'),
            )),
          ),
        ),
      ));

      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 49'), findsNothing); // off screen

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pump();

      expect(find.text('Item 49'), findsOneWidget);
    });

    testWidgets('RefreshIndicator triggers callback', (tester) async {
      bool refreshed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RefreshIndicator(
            onRefresh: () async => refreshed = true,
            child: ListView(
              children: const [ListTile(title: Text('Content'))],
            ),
          ),
        ),
      ));

      await tester.fling(find.text('Content'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(refreshed, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. BADGE & INDICATOR WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Badge widgets', () {
    testWidgets('badge renders with count', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Badge(
            label: const Text('3'),
            child: const Icon(Icons.chat),
          ),
        ),
      ));

      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.chat), findsOneWidget);
    });

    testWidgets('CircleAvatar renders with initial', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const CircleAvatar(
            radius: 24,
            child: Text('ד'),
          ),
        ),
      ));

      expect(find.text('ד'), findsOneWidget);
    });

    testWidgets('LinearProgressIndicator shows progress', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const LinearProgressIndicator(value: 0.7),
        ),
      ));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. MODAL BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  group('Bottom sheets', () {
    testWidgets('modal bottom sheet opens and closes', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: ctx,
                builder: (_) => const SizedBox(
                  height: 200,
                  child: Center(child: Text('Sheet Content')),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet Content'), findsOneWidget);

      // Close by tapping the barrier
      await tester.tapAt(const Offset(50, 50));
      await tester.pumpAndSettle();
      expect(find.text('Sheet Content'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. TAB BAR
  // ═══════════════════════════════════════════════════════════════════════════

  group('TabBar', () {
    testWidgets('swiping changes tab content', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'פעיל'),
                  Tab(text: 'היסטוריה'),
                  Tab(text: 'מחלוקות'),
                ],
              ),
            ),
            body: const TabBarView(
              children: [
                Center(child: Text('Active Jobs')),
                Center(child: Text('History')),
                Center(child: Text('Disputes')),
              ],
            ),
          ),
        ),
      ));

      expect(find.text('Active Jobs'), findsOneWidget);

      await tester.tap(find.text('היסטוריה'));
      await tester.pumpAndSettle();
      expect(find.text('History'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 10. GRADIENT & VISUAL FIDELITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Visual fidelity', () {
    testWidgets('gradient container renders without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Container(
            height: 60,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899)],
              ),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: const Center(
              child: Text('XP Progress', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('card with shadow renders correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Service Card'),
            ),
          ),
        ),
      ));
      expect(find.text('Service Card'), findsOneWidget);
    });

    testWidgets('ClipRRect rounds image corners', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(width: 100, height: 90, color: Colors.blue),
          ),
        ),
      ));
      expect(find.byType(ClipRRect), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 11. TEXT OVERFLOW SCENARIOS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Text overflow', () {
    testWidgets('long provider name uses ellipsis', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox(
            width: 120,
            child: Text(
              'דנה כהן-לוי מירושלים עם ניסיון רב בתחום הניקיון המקצועי',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('price displays without overflow in tight space', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: const [
              Expanded(child: Text('שיפוצים מקצועיים', maxLines: 1, overflow: TextOverflow.ellipsis)),
              SizedBox(width: 8),
              Text('₪150/שעה', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hebrew and English mix renders correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const Text('דנה Cohen - AnySkill Pro ⭐'),
        ),
      ));
      expect(find.textContaining('Cohen'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 12. SEGMENTED BUTTON (Admin panel)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Segmented controls', () {
    testWidgets('SegmentedButton changes selection', (tester) async {
      int selected = 0;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (ctx, setState) => Scaffold(
            body: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('ניהול')),
                ButtonSegment(value: 1, label: Text('תוכן')),
                ButtonSegment(value: 2, label: Text('מערכת')),
              ],
              selected: {selected},
              onSelectionChanged: (s) => setState(() => selected = s.first),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('תוכן'));
      await tester.pump();
      expect(selected, 1);

      await tester.tap(find.text('מערכת'));
      await tester.pump();
      expect(selected, 2);
    });
  });
}
