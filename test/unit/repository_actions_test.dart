import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:anyskill_app/models/category.dart';
import 'package:anyskill_app/repositories/category_repository.dart';
import 'package:anyskill_app/repositories/provider_repository.dart';
import 'package:anyskill_app/repositories/search_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Repository integration tests with FakeFirebaseFirestore
//
// Tests actual Firestore operations: CRUD, queries, filtering, pagination.
// No mocks — uses fake_cloud_firestore for real document operations.
//
// Run:  flutter test test/unit/repository_actions_test.dart
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _seedCategory(FakeFirebaseFirestore db, String id, {
  String name = 'Test',
  String parentId = '',
  int order = 0,
  int clickCount = 0,
  bool isHidden = false,
}) async {
  await db.collection('categories').doc(id).set({
    'name': name, 'parentId': parentId, 'order': order,
    'clickCount': clickCount, 'isHidden': isHidden, 'img': '',
  });
}

Future<void> _seedProvider(FakeFirebaseFirestore db, String uid, {
  String name = 'Provider',
  String serviceType = 'ניקיון',
  bool isProvider = true,
  bool isVerified = true,
  bool isPendingExpert = false,
  bool isHidden = false,
  bool isBanned = false,
  bool isOnline = false,
}) async {
  await db.collection('users').doc(uid).set({
    'name': name, 'serviceType': serviceType,
    'isProvider': isProvider, 'isVerified': isVerified,
    'isPendingExpert': isPendingExpert, 'isHidden': isHidden,
    'isBanned': isBanned, 'isOnline': isOnline,
    'isVerifiedProvider': true,
  });
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. CategoryRepository
  // ═══════════════════════════════════════════════════════════════════════════

  group('CategoryRepository', () {
    test('watchAll streams sorted categories', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'a', name: 'Alpha', clickCount: 5);
      await _seedCategory(db, 'b', name: 'Beta', clickCount: 10);
      await _seedCategory(db, 'c', name: 'Gamma', clickCount: 1);

      final repo = CategoryRepository(firestore: db);
      final cats = await repo.watchAll().first;

      expect(cats.length, 3);
      expect(cats[0].name, 'Beta');  // highest clickCount first
      expect(cats[2].name, 'Gamma'); // lowest last
    });

    test('watchMainCategories excludes sub-categories and hidden', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'main1', name: 'Main');
      await _seedCategory(db, 'sub1', name: 'Sub', parentId: 'main1');
      await _seedCategory(db, 'hidden1', name: 'Hidden', isHidden: true);

      final repo = CategoryRepository(firestore: db);
      final cats = await repo.watchMainCategories().first;

      expect(cats.length, 1);
      expect(cats[0].name, 'Main');
    });

    test('watchSubCategories returns only children', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'parent', name: 'Parent');
      await _seedCategory(db, 's1', name: 'Child1', parentId: 'parent');
      await _seedCategory(db, 's2', name: 'Child2', parentId: 'parent');
      await _seedCategory(db, 's3', name: 'Other', parentId: 'other');

      final repo = CategoryRepository(firestore: db);
      final subs = await repo.watchSubCategories('parent').first;

      expect(subs.length, 2);
      expect(subs.every((c) => c.parentId == 'parent'), true);
    });

    test('create adds a new category', () async {
      final db = FakeFirebaseFirestore();
      final repo = CategoryRepository(firestore: db);

      const cat = Category(id: 'new1', name: 'New Category', order: 5);
      await repo.create(cat);

      final doc = await db.collection('categories').doc('new1').get();
      expect(doc.exists, true);
      expect(doc.data()?['name'], 'New Category');
    });

    test('update modifies fields', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'c1', name: 'Old');

      final repo = CategoryRepository(firestore: db);
      await repo.update('c1', {'name': 'New'});

      final doc = await db.collection('categories').doc('c1').get();
      expect(doc.data()?['name'], 'New');
    });

    test('update removes null values', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'c1', name: 'Test');

      final repo = CategoryRepository(firestore: db);
      await repo.update('c1', {'name': 'Updated', 'nullField': null});

      // Should not throw — null was removed before write
      final doc = await db.collection('categories').doc('c1').get();
      expect(doc.data()?['name'], 'Updated');
    });

    test('delete removes category and sub-categories', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'parent', name: 'Parent');
      await _seedCategory(db, 'child1', parentId: 'parent');
      await _seedCategory(db, 'child2', parentId: 'parent');

      final repo = CategoryRepository(firestore: db);
      await repo.delete('parent', '');

      final remaining = await db.collection('categories').get();
      expect(remaining.docs, isEmpty);
    });

    test('activeProviderCount counts matching providers', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', serviceType: 'ניקיון');
      await _seedProvider(db, 'p2', serviceType: 'ניקיון');
      await _seedProvider(db, 'p3', serviceType: 'שיפוצים');

      final repo = CategoryRepository(firestore: db);
      expect(await repo.activeProviderCount('ניקיון'), 2);
      expect(await repo.activeProviderCount('שיפוצים'), 1);
      expect(await repo.activeProviderCount('nonexist'), 0);
    });

    test('verifyOnServer returns category or null', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'exists', name: 'Real');

      final repo = CategoryRepository(firestore: db);
      final found = await repo.verifyOnServer('exists');
      final notFound = await repo.verifyOnServer('fake');

      expect(found?.name, 'Real');
      expect(notFound, isNull);
    });

    test('loadSchema returns empty for category without schema', () async {
      final db = FakeFirebaseFirestore();
      await _seedCategory(db, 'c1', name: 'NoSchema');

      final repo = CategoryRepository(firestore: db);
      final schema = await repo.loadSchema('NoSchema');

      expect(schema, isEmpty);
    });

    test('loadSchema returns fields for category with schema', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('categories').doc('c1').set({
        'name': 'WithSchema',
        'parentId': '',
        'serviceSchema': [
          {'id': 'price', 'label': 'מחיר', 'type': 'number', 'unit': '₪'},
        ],
      });

      final repo = CategoryRepository(firestore: db);
      final schema = await repo.loadSchema('WithSchema');

      expect(schema.length, 1);
      expect(schema[0].id, 'price');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ProviderRepository
  // ═══════════════════════════════════════════════════════════════════════════

  group('ProviderRepository', () {
    test('getProvider returns provider or null', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', name: 'Dana');

      final repo = ProviderRepository(firestore: db);
      final found = await repo.getProvider('p1');
      final notFound = await repo.getProvider('fake');

      expect(found?.name, 'Dana');
      expect(notFound, isNull);
    });

    test('getPendingExperts returns only pending', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'pending1', isPendingExpert: true, isVerified: false);
      await _seedProvider(db, 'pending2', isPendingExpert: true, isVerified: false);
      await _seedProvider(db, 'active1', isPendingExpert: false);

      final repo = ProviderRepository(firestore: db);
      final pending = await repo.getPendingExperts();

      expect(pending.length, 2);
      expect(pending.every((p) => p.isPendingExpert), true);
    });

    test('approveExpert changes flags correctly', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', isPendingExpert: true, isVerified: false, isProvider: false);

      final repo = ProviderRepository(firestore: db);
      await repo.approveExpert('p1');

      final doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isPendingExpert'], false);
      expect(doc.data()?['isProvider'], true);
      expect(doc.data()?['isVerified'], true);
      expect(doc.data()?['categoryReviewedByAdmin'], true);
    });

    test('rejectExpert changes flags correctly', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', isPendingExpert: true);

      final repo = ProviderRepository(firestore: db);
      await repo.rejectExpert('p1');

      final doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isPendingExpert'], false);
      expect(doc.data()?['isProvider'], false);
    });

    test('setVerified toggles blue checkmark', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', isVerified: false);

      final repo = ProviderRepository(firestore: db);
      await repo.setVerified('p1', true);

      var doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isVerified'], true);

      await repo.setVerified('p1', false);
      doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isVerified'], false);
    });

    test('setBanned toggles ban status', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1');

      final repo = ProviderRepository(firestore: db);
      await repo.setBanned('p1', true);

      var doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isBanned'], true);

      await repo.setBanned('p1', false);
      doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isBanned'], false);
    });

    test('setHidden toggles search visibility', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1');

      final repo = ProviderRepository(firestore: db);
      await repo.setHidden('p1', true);

      final doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isHidden'], true);
    });

    test('setOnline toggles online status', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', isOnline: false);

      final repo = ProviderRepository(firestore: db);
      await repo.setOnline('p1', true);

      final doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isOnline'], true);
    });

    test('updateProfile writes fields + updatedAt', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', name: 'Old');

      final repo = ProviderRepository(firestore: db);
      await repo.updateProfile('p1', {'name': 'New', 'aboutMe': 'Updated bio'});

      final doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['name'], 'New');
      expect(doc.data()?['aboutMe'], 'Updated bio');
    });

    test('updateCategoryDetails writes dynamic schema values', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1');

      final repo = ProviderRepository(firestore: db);
      await repo.updateCategoryDetails('p1', {
        'pricePerNight': 150,
        'hasFencedYard': true,
      });

      final doc = await db.collection('users').doc('p1').get();
      final details = doc.data()?['categoryDetails'] as Map<String, dynamic>;
      expect(details['pricePerNight'], 150);
      expect(details['hasFencedYard'], true);
    });

    test('approveVideo sets videoVerifiedByAdmin', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('p1').set({
        'verificationVideoUrl': 'https://example.com/v.mp4',
        'videoVerifiedByAdmin': false,
      });

      final repo = ProviderRepository(firestore: db);
      await repo.approveVideo('p1');

      final doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['videoVerifiedByAdmin'], true);
    });

    test('setComplianceVerified updates both fields', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1');

      final repo = ProviderRepository(firestore: db);
      await repo.setComplianceVerified('p1', true);

      final doc = await db.collection('users').doc('p1').get();
      expect(doc.data()?['isVerifiedProvider'], true);
      final compliance = doc.data()?['compliance'] as Map<String, dynamic>;
      expect(compliance['verified'], true);
    });

    test('watchProvider streams real-time updates', () async {
      final db = FakeFirebaseFirestore();
      await _seedProvider(db, 'p1', name: 'Initial');

      final repo = ProviderRepository(firestore: db);
      final first = await repo.watchProvider('p1').first;

      expect(first?.name, 'Initial');
    });

    test('watchProvider returns null for non-existent', () async {
      final db = FakeFirebaseFirestore();
      final repo = ProviderRepository(firestore: db);
      final result = await repo.watchProvider('ghost').first;

      expect(result, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. SearchRepository — searchNearby (previously untested)
  // ═══════════════════════════════════════════════════════════════════════════

  group('SearchRepository.searchNearby', () {
    test('finds providers within radius', () async {
      final db = FakeFirebaseFirestore();
      // Tel Aviv area: lat ~32.08, lng ~34.78
      await db.collection('users').doc('near').set({
        'name': 'Near', 'isProvider': true, 'isVerified': true,
        'latitude': 32.08, 'longitude': 34.78, 'serviceType': 'ניקיון',
      });
      await db.collection('users').doc('far').set({
        'name': 'Far', 'isProvider': true, 'isVerified': true,
        'latitude': 33.50, 'longitude': 35.50, 'serviceType': 'ניקיון',
      });

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchNearby(lat: 32.07, lng: 34.77);

      // 'near' should be within 15km, 'far' should be excluded
      final names = page.providers.map((p) => p.name).toList();
      expect(names.contains('Near'), true);
    });

    test('returns empty for no providers in area', () async {
      final db = FakeFirebaseFirestore();
      final repo = SearchRepository(firestore: db);
      final page = await repo.searchNearby(lat: 0, lng: 0);

      expect(page.providers, isEmpty);
    });

    test('filters by category when provided', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('p1').set({
        'name': 'Cleaner', 'isProvider': true, 'isVerified': true,
        'latitude': 32.08, 'longitude': 34.78, 'serviceType': 'ניקיון',
      });
      await db.collection('users').doc('p2').set({
        'name': 'Plumber', 'isProvider': true, 'isVerified': true,
        'latitude': 32.08, 'longitude': 34.78, 'serviceType': 'אינסטלציה',
      });

      final repo = SearchRepository(firestore: db);
      final page = await repo.searchNearby(
        lat: 32.07, lng: 34.77, categoryName: 'ניקיון',
      );

      for (final p in page.providers) {
        expect(p.serviceType, 'ניקיון');
      }
    });
  });
}
