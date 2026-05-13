// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:anyskill_app/services/cache_service.dart';
import 'package:anyskill_app/services/cached_readers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: CachedReaders (CLAUDE.md §61 + §71 testability hook)
//
// Verifies the cache layer's read-through + invalidation behavior using
// FakeFirebaseFirestore as the injected backing store. No singleton
// override needed — §71 added a `db` parameter to CacheService.getDoc /
// CachedReaders.providerProfile.
//
// Run:  flutter test test/unit/cached_readers_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // Reset the in-memory cache between tests so they don't see each other's
  // state (CacheService is a process-static map).
  //
  // Audit fix (post-§75): clearing only `users/` prefix would leak state
  // for any future test that touches `categories/`, `admin/`, etc. Use
  // empty-prefix to clear EVERYTHING — defensive default.
  setUp(() {
    CacheService.invalidatePrefix('');
  });

  group('CachedReaders.providerProfile', () {
    test('returns user doc data on first call (cache miss → fetch)',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('u1').set({
        'name': 'Alice',
        'isProvider': true,
        'pricePerHour': 150,
      });

      final data = await CachedReaders.providerProfile('u1', db: db);

      expect(data['name'], 'Alice');
      expect(data['isProvider'], true);
      expect(data['pricePerHour'], 150);
    });

    test('second call returns cached data even after Firestore mutation',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('u2').set({'name': 'Bob v1'});

      // Prime the cache.
      final first = await CachedReaders.providerProfile('u2', db: db);
      expect(first['name'], 'Bob v1');

      // Mutate the underlying doc.
      await db.collection('users').doc('u2').update({'name': 'Bob v2'});

      // Without invalidation, the second call returns the cached v1.
      final second = await CachedReaders.providerProfile('u2', db: db);
      expect(second['name'], 'Bob v1', reason: 'cache should hide mutation');
    });

    test('invalidateProvider() forces fresh fetch on next call', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('u3').set({'name': 'Carol v1'});

      // Prime the cache.
      await CachedReaders.providerProfile('u3', db: db);

      // Mutate + invalidate.
      await db.collection('users').doc('u3').update({'name': 'Carol v2'});
      CachedReaders.invalidateProvider('u3');

      final fresh = await CachedReaders.providerProfile('u3', db: db);
      expect(fresh['name'], 'Carol v2',
          reason: 'invalidate should force re-fetch');
    });

    test('returns empty map for missing user (no throw)', () async {
      final db = FakeFirebaseFirestore();
      // No doc populated.

      final data = await CachedReaders.providerProfile('nonexistent', db: db);
      expect(data, isEmpty);
    });

    test('empty uid returns empty map without crashing (post-audit guard)',
        () async {
      // Audit fix: BookingProfileAvatar can be constructed with a stale
      // empty uid. Pre-fix: Firestore SDK threw "A document path must
      // be a non-empty string". Post-fix: short-circuit with empty map.
      final data = await CachedReaders.providerProfile('');
      expect(data, isEmpty,
          reason: 'empty uid must NOT crash and must NOT touch Firestore');
    });

    test('different uids do not collide in the cache', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('u4').set({'name': 'Dave'});
      await db.collection('users').doc('u5').set({'name': 'Eve'});

      final daveData = await CachedReaders.providerProfile('u4', db: db);
      final eveData = await CachedReaders.providerProfile('u5', db: db);

      expect(daveData['name'], 'Dave');
      expect(eveData['name'], 'Eve');
    });
  });

  group('CachedReaders.providerProfiles (batched, §74 db hook)', () {
    test('returns map keyed by uid — all uids cold (parallel fetch)',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('a').set({'name': 'Anna'});
      await db.collection('users').doc('b').set({'name': 'Boris'});
      await db.collection('users').doc('c').set({'name': 'Charlie'});

      // §74: plural API now accepts db too — full cold-fetch path testable.
      final results =
          await CachedReaders.providerProfiles(['a', 'b', 'c'], db: db);

      expect(results['a']?['name'], 'Anna');
      expect(results['b']?['name'], 'Boris');
      expect(results['c']?['name'], 'Charlie');
    });

    test('mixed warm + cold — plural fetch only the cold uids', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('warm').set({'name': 'Warm v1'});
      await db.collection('users').doc('cold').set({'name': 'Cold v1'});

      // Prime "warm" only.
      await CachedReaders.providerProfile('warm', db: db);

      // Mutate the warm doc — plural read should hit cache for warm,
      // network for cold.
      await db.collection('users').doc('warm').update({'name': 'Warm v2'});

      final results =
          await CachedReaders.providerProfiles(['warm', 'cold'], db: db);

      expect(results['warm']?['name'], 'Warm v1',
          reason: 'cache hit on warm should hide mutation');
      expect(results['cold']?['name'], 'Cold v1',
          reason: 'cold uid should fetch fresh');
    });
  });

  group('CacheService.getDoc with injected db', () {
    test('caches the result so the second call does not hit Firestore again',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('cache_test').set({'value': 42});

      // First call — cache miss.
      final first = await CacheService.getDoc(
        'users',
        'cache_test',
        db: db,
      );
      expect(first['value'], 42);

      // Mutate the underlying doc — second call should still see 42.
      await db.collection('users').doc('cache_test').update({'value': 99});

      final second = await CacheService.getDoc(
        'users',
        'cache_test',
        db: db,
      );
      expect(second['value'], 42, reason: 'cache hit should hide mutation');
    });

    test('forceRefresh: true bypasses cache', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('force_test').set({'value': 1});

      await CacheService.getDoc('users', 'force_test', db: db);
      await db.collection('users').doc('force_test').update({'value': 2});

      // forceRefresh skips the cache check.
      final fresh = await CacheService.getDoc(
        'users',
        'force_test',
        db: db,
        forceRefresh: true,
      );
      expect(fresh['value'], 2);
    });
  });
}
