// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:anyskill_app/repositories/search_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: SearchRepository — pagination, name search, filtering
//
// Run:  flutter test test/unit/search_repository_test.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Helper: seed a provider doc with common defaults.
Future<void> _seed(
  FakeFirebaseFirestore db,
  String uid, {
  String name = 'Provider',
  String serviceType = 'ניקיון',
  bool isProvider = true,
  bool isVerified = true,
  bool isHidden = false,
  bool isBanned = false,
  bool isOnline = false,
  double? lat,
  double? lng,
}) async {
  await db.collection('users').doc(uid).set({
    'name':        name,
    'serviceType': serviceType,
    'isProvider':  isProvider,
    'isVerified':  isVerified,
    'isHidden':    isHidden,
    'isBanned':    isBanned,
    'isOnline':    isOnline,
    if (lat != null) 'latitude':  lat,
    if (lng != null) 'longitude': lng,
  });
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. SearchPage model
  // ═══════════════════════════════════════════════════════════════════════════

  group('SearchPage', () {
    test('empty returns no providers', () {
      expect(SearchPage.empty.providers, isEmpty);
      expect(SearchPage.empty.cursor, isNull);
      expect(SearchPage.empty.hasMore, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Category search
  // ═══════════════════════════════════════════════════════════════════════════

  group('searchByCategory', () {
    test('returns providers matching category', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'p1', name: 'דנה', serviceType: 'ניקיון');
      await _seed(db, 'p2', name: 'יוסי', serviceType: 'שיפוצים');
      await _seed(db, 'p3', name: 'שרה', serviceType: 'ניקיון');

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByCategory(categoryName: 'ניקיון');

      expect(page.providers.length, 2);
      expect(page.providers.every((p) => p.serviceType == 'ניקיון'), true);
    });

    test('filters out hidden and banned providers', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'visible', serviceType: 'ניקיון');
      await _seed(db, 'hidden', serviceType: 'ניקיון', isHidden: true);
      await _seed(db, 'banned', serviceType: 'ניקיון', isBanned: true);

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByCategory(categoryName: 'ניקיון');

      expect(page.providers.length, 1);
      expect(page.providers.first.uid, 'visible');
    });

    test('filters out unverified providers', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'verified', serviceType: 'ניקיון', isVerified: true);
      await _seed(db, 'unverified', serviceType: 'ניקיון', isVerified: false);

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByCategory(categoryName: 'ניקיון');

      expect(page.providers.length, 1);
      expect(page.providers.first.uid, 'verified');
    });

    test('returns empty for unknown category', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'p1', serviceType: 'ניקיון');

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByCategory(categoryName: 'nonexistent');

      expect(page.providers, isEmpty);
      expect(page.hasMore, false);
    });

    test('pagination: first page returns cursor', () async {
      final db = FakeFirebaseFirestore();
      // Seed more than pageSize providers
      for (int i = 0; i < 5; i++) {
        await _seed(db, 'p$i', name: 'Provider $i', serviceType: 'ניקיון');
      }

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByCategory(
        categoryName: 'ניקיון',
        pageSize: 3,
      );

      expect(page.providers.length, 3);
      expect(page.cursor, isNotNull);
      expect(page.hasMore, true);
    });

    test('pagination: second page returns remaining', () async {
      final db = FakeFirebaseFirestore();
      for (int i = 0; i < 5; i++) {
        await _seed(db, 'p$i', name: 'Provider $i', serviceType: 'ניקיון');
      }

      final repo = SearchRepository(firestore: db);
      final page1 = await repo.searchByCategory(
        categoryName: 'ניקיון',
        pageSize: 3,
      );
      final page2 = await repo.searchByCategory(
        categoryName: 'ניקיון',
        pageSize: 3,
        startAfter: page1.cursor,
      );

      expect(page2.providers.length, 2);
      expect(page2.hasMore, false);

      // No overlap between pages
      final page1Uids = page1.providers.map((p) => p.uid).toSet();
      final page2Uids = page2.providers.map((p) => p.uid).toSet();
      expect(page1Uids.intersection(page2Uids), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. Name search
  // ═══════════════════════════════════════════════════════════════════════════

  group('searchByName', () {
    test('finds providers by Hebrew name prefix', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'p1', name: 'דנה כהן');
      await _seed(db, 'p2', name: 'דניאל לוי');
      await _seed(db, 'p3', name: 'שרה אביב');

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByName(query: 'דנ');

      expect(page.providers.length, 2);
      expect(page.providers.every((p) => p.name.startsWith('דנ')), true);
    });

    test('returns empty for empty query', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'p1', name: 'דנה');

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByName(query: '');

      expect(page.providers, isEmpty);
    });

    test('returns empty for no match', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'p1', name: 'דנה');

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByName(query: 'zzz');

      expect(page.providers, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Suggest (autocomplete)
  // ═══════════════════════════════════════════════════════════════════════════

  group('suggest', () {
    test('returns up to limit results', () async {
      final db = FakeFirebaseFirestore();
      for (int i = 0; i < 10; i++) {
        await _seed(db, 'p$i', name: 'אבי $i');
      }

      final repo = SearchRepository(firestore: db);
      final results = await repo.suggest('אבי', limit: 3);

      expect(results.length, lessThanOrEqualTo(3));
    });

    test('returns empty for query shorter than 2 chars', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'p1', name: 'אבי');

      final repo = SearchRepository(firestore: db);
      final results = await repo.suggest('א');

      expect(results, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Online providers
  // ═══════════════════════════════════════════════════════════════════════════

  group('watchOnline', () {
    test('returns only online providers', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'on1', isOnline: true, serviceType: 'ניקיון');
      await _seed(db, 'off1', isOnline: false, serviceType: 'ניקיון');
      await _seed(db, 'on2', isOnline: true, serviceType: 'ניקיון');

      final repo = SearchRepository(firestore: db);
      final providers = await repo
          .watchOnline(categoryName: 'ניקיון')
          .first;

      expect(providers.length, 2);
      expect(providers.every((p) => p.isOnline), true);
    });

    test('filters by category when provided', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'p1', isOnline: true, serviceType: 'ניקיון');
      await _seed(db, 'p2', isOnline: true, serviceType: 'שיפוצים');

      final repo = SearchRepository(firestore: db);
      final providers = await repo
          .watchOnline(categoryName: 'ניקיון')
          .first;

      expect(providers.length, 1);
      expect(providers.first.serviceType, 'ניקיון');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. Visibility rules
  // ═══════════════════════════════════════════════════════════════════════════

  group('visibility filtering', () {
    test('non-providers are excluded from all searches', () async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'customer', isProvider: false, serviceType: 'ניקיון');
      await _seed(db, 'provider', isProvider: true, serviceType: 'ניקיון');

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchByCategory(categoryName: 'ניקיון');

      expect(page.providers.length, 1);
      expect(page.providers.first.uid, 'provider');
    });
  });
}
