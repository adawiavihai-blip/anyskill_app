// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:anyskill_app/models/category.dart';
import 'package:anyskill_app/models/service_provider.dart';
import 'package:anyskill_app/providers/category_provider.dart';
import 'package:anyskill_app/providers/service_provider_notifier.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: Category + ServiceProvider models, providers, and Firestore ops
//
// Run:  flutter test test/unit/category_provider_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Category MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('Category model', () {
    test('fromFirestore parses all fields', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('categories').doc('plumbing').set({
        'name':       'אינסטלציה',
        'img':        'https://example.com/img.jpg',
        'iconName':   'plumbing',
        'order':      3,
        'parentId':   '',
        'clickCount': 42,
        'bookingCount': 10,
        'autoCreated': false,
        'isHidden':    false,
        'serviceSchema': [
          {'id': 'price', 'label': 'מחיר', 'type': 'number', 'unit': '₪/לשעה'},
          {'id': 'hasTruck', 'label': 'יש משאית?', 'type': 'bool'},
        ],
      });

      final doc = await db.collection('categories').doc('plumbing').get();
      final cat = Category.fromFirestore(doc);

      expect(cat.id,         'plumbing');
      expect(cat.name,       'אינסטלציה');
      expect(cat.img,        'https://example.com/img.jpg');
      expect(cat.order,      3);
      expect(cat.isTopLevel, true);
      expect(cat.clickCount, 42);
      expect(cat.hasImage,   true);
      expect(cat.hasSchema,  true);
      expect(cat.serviceSchema.length, 2);
      expect(cat.serviceSchema[0].isPriceField, true);
      expect(cat.serviceSchema[1].type, 'bool');
    });

    test('fromFirestore handles missing fields', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('categories').doc('empty').set({'name': 'x'});

      final doc = await db.collection('categories').doc('empty').get();
      final cat = Category.fromFirestore(doc);

      expect(cat.id,           'empty');
      expect(cat.name,         'x');
      expect(cat.img,          '');
      expect(cat.order,        999);
      expect(cat.parentId,     '');
      expect(cat.clickCount,   0);
      expect(cat.hasImage,     false);
      expect(cat.hasSchema,    false);
      expect(cat.serviceSchema, isEmpty);
    });

    test('isTopLevel vs isSubCategory', () {
      const topLevel = Category(id: 'a', parentId: '');
      const sub      = Category(id: 'b', parentId: 'a');

      expect(topLevel.isTopLevel,    true);
      expect(topLevel.isSubCategory, false);
      expect(sub.isTopLevel,         false);
      expect(sub.isSubCategory,      true);
    });

    test('primaryPriceField returns first number field with ₪', () {
      const cat = Category(
        id: 'test',
        serviceSchema: [
          SchemaField(id: 'desc', type: 'text'),
          SchemaField(id: 'price', type: 'number', unit: '₪/ללילה'),
          SchemaField(id: 'extra', type: 'number', unit: '₪/לשעה'),
        ],
      );
      expect(cat.primaryPriceField?.id, 'price');
    });

    test('primaryPriceField returns null when no price field', () {
      const cat = Category(
        id: 'test',
        serviceSchema: [
          SchemaField(id: 'desc', type: 'text'),
        ],
      );
      expect(cat.primaryPriceField, isNull);
    });

    test('toJson round-trips correctly', () async {
      final db = FakeFirebaseFirestore();
      const original = Category(
        id:         'rt',
        name:       'שיפוצים',
        img:        'https://example.com/img.jpg',
        order:      2,
        parentId:   '',
        clickCount: 5,
        serviceSchema: [
          SchemaField(id: 'p', label: 'מחיר', type: 'number', unit: '₪/לשעה'),
        ],
      );

      await db.collection('categories').doc('rt').set(original.toJson());
      final doc = await db.collection('categories').doc('rt').get();
      final loaded = Category.fromFirestore(doc);

      expect(loaded.name,       original.name);
      expect(loaded.img,        original.img);
      expect(loaded.order,      original.order);
      expect(loaded.clickCount, original.clickCount);
      expect(loaded.serviceSchema.length, 1);
      expect(loaded.serviceSchema[0].unit, '₪/לשעה');
    });

    test('copyWith updates only specified fields', () {
      const cat = Category(id: 'c1', name: 'Old', clickCount: 10);
      final updated = cat.copyWith(name: 'New', clickCount: 11);

      expect(updated.id,         'c1');
      expect(updated.name,       'New');
      expect(updated.clickCount, 11);
      expect(cat.name,           'Old'); // original unchanged
    });

    test('equality is based on id', () {
      const a = Category(id: 'x', name: 'A');
      const b = Category(id: 'x', name: 'B');
      const c = Category(id: 'y', name: 'A');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. SchemaField
  // ═══════════════════════════════════════════════════════════════════════════

  group('SchemaField', () {
    test('fromMap parses dropdown with options', () {
      final field = SchemaField.fromMap({
        'id': 'size',
        'label': 'גודל',
        'type': 'dropdown',
        'unit': '',
        'options': ['קטן', 'בינוני', 'גדול'],
      });

      expect(field.id,      'size');
      expect(field.type,    'dropdown');
      expect(field.options, ['קטן', 'בינוני', 'גדול']);
      expect(field.isPriceField, false);
    });

    test('isPriceField only true for number + ₪', () {
      const yes = SchemaField(id: 'p', type: 'number', unit: '₪/לשעה');
      const no1 = SchemaField(id: 'p', type: 'text',   unit: '₪/לשעה');
      const no2 = SchemaField(id: 'p', type: 'number', unit: 'יח׳');

      expect(yes.isPriceField, true);
      expect(no1.isPriceField, false);
      expect(no2.isPriceField, false);
    });

    test('toJson omits empty options', () {
      const field = SchemaField(id: 'x', type: 'text');
      final json = field.toJson();
      expect(json.containsKey('options'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. ServiceProvider MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('ServiceProvider model', () {
    test('fromFirestore parses provider-specific fields', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('prov1').set({
        'name':             'דנה',
        'email':            'dana@test.com',
        'profileImage':     'https://example.com/av.jpg',
        'isProvider':       true,
        'isVerified':       true,
        'isPendingExpert':  false,
        'isVerifiedProvider': true,
        'isOnline':         true,
        'serviceType':      'אינסטלציה',
        'subCategory':      'חשמל',
        'pricePerHour':     120,
        'rating':           4.8,
        'reviewsCount':     25,
        'xp':               1500,
        'categoryDetails':  {'price': 150},
        'cancellationPolicy': 'moderate',
      });

      final doc = await db.collection('users').doc('prov1').get();
      final prov = ServiceProvider.fromFirestore(doc);

      expect(prov.uid,                'prov1');
      expect(prov.name,               'דנה');
      expect(prov.isProvider,         true);
      expect(prov.isVerified,         true);
      expect(prov.isOnline,           true);
      expect(prov.serviceType,        'אינסטלציה');
      expect(prov.subCategory,        'חשמל');
      expect(prov.pricePerHour,       120);
      expect(prov.rating,             4.8);
      expect(prov.xp,                 1500);
      expect(prov.categoryDetails,    {'price': 150});
      expect(prov.cancellationPolicy, 'moderate');
    });

    test('fromFirestore handles missing fields with defaults', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('sparse').set({'name': 'x'});

      final doc = await db.collection('users').doc('sparse').get();
      final prov = ServiceProvider.fromFirestore(doc);

      expect(prov.isProvider,          false);
      expect(prov.isVerified,          false);
      expect(prov.isVerifiedProvider,  true); // default is true
      expect(prov.rating,             5.0);  // default
      expect(prov.pricePerHour,       0);
      expect(prov.gallery,            isEmpty);
      expect(prov.categoryDetails,    isEmpty);
    });

    test('phone falls back to phoneNumber', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('fb').set({
        'phoneNumber': '0501234567',
      });

      final doc = await db.collection('users').doc('fb').get();
      final prov = ServiceProvider.fromFirestore(doc);
      expect(prov.phone, '0501234567');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Verification STATUS
  // ═══════════════════════════════════════════════════════════════════════════

  group('VerificationStatus', () {
    test('pending when isPendingExpert', () {
      const prov = ServiceProvider(uid: 'u1', isPendingExpert: true);
      expect(prov.verificationStatus, VerificationStatus.pending);
    });

    test('verified when all flags are true', () {
      const prov = ServiceProvider(
        uid: 'u1',
        isProvider: true,
        isVerified: true,
        isVerifiedProvider: true,
      );
      expect(prov.verificationStatus, VerificationStatus.verified);
    });

    test('unverifiedCompliance when compliance missing', () {
      const prov = ServiceProvider(
        uid: 'u1',
        isProvider: true,
        isVerified: true,
        isVerifiedProvider: false,
      );
      expect(prov.verificationStatus, VerificationStatus.unverifiedCompliance);
    });

    test('banned overrides everything', () {
      const prov = ServiceProvider(
        uid: 'u1',
        isProvider: true,
        isVerified: true,
        isBanned: true,
      );
      expect(prov.verificationStatus, VerificationStatus.banned);
    });

    test('pending when not provider and not pending', () {
      const prov = ServiceProvider(uid: 'u1');
      expect(prov.verificationStatus, VerificationStatus.pending);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Search VISIBILITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('isSearchVisible', () {
    test('visible when provider + verified + not hidden + not banned', () {
      const prov = ServiceProvider(
        uid: 'u1', isProvider: true, isVerified: true,
      );
      expect(prov.isSearchVisible, true);
    });

    test('hidden provider is not visible', () {
      const prov = ServiceProvider(
        uid: 'u1', isProvider: true, isVerified: true, isHidden: true,
      );
      expect(prov.isSearchVisible, false);
    });

    test('banned provider is not visible', () {
      const prov = ServiceProvider(
        uid: 'u1', isProvider: true, isVerified: true, isBanned: true,
      );
      expect(prov.isSearchVisible, false);
    });

    test('unverified provider is not visible', () {
      const prov = ServiceProvider(
        uid: 'u1', isProvider: true, isVerified: false,
      );
      expect(prov.isSearchVisible, false);
    });

    test('non-provider is not visible', () {
      const prov = ServiceProvider(uid: 'u1', isVerified: true);
      expect(prov.isSearchVisible, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. Computed PROPERTIES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Computed properties', () {
    test('hasLocation checks both lat and lng', () {
      const yes = ServiceProvider(uid: 'u', latitude: 32.0, longitude: 34.0);
      const no1 = ServiceProvider(uid: 'u', latitude: 32.0);
      const no2 = ServiceProvider(uid: 'u');

      expect(yes.hasLocation, true);
      expect(no1.hasLocation, false);
      expect(no2.hasLocation, false);
    });

    test('isProfileBoosted checks expiry', () {
      final active = ServiceProvider(
        uid: 'u',
        profileBoostUntil: DateTime.now().add(const Duration(hours: 6)),
      );
      final expired = ServiceProvider(
        uid: 'u',
        profileBoostUntil: DateTime.now().subtract(const Duration(hours: 1)),
      );
      const none = ServiceProvider(uid: 'u');

      expect(active.isProfileBoosted, true);
      expect(expired.isProfileBoosted, false);
      expect(none.isProfileBoosted, false);
    });

    test('hasUnreviewedVideo', () {
      const yes = ServiceProvider(
        uid: 'u',
        verificationVideoUrl: 'https://example.com/v.mp4',
        videoVerifiedByAdmin: false,
      );
      const no1 = ServiceProvider(
        uid: 'u',
        verificationVideoUrl: 'https://example.com/v.mp4',
        videoVerifiedByAdmin: true,
      );
      const no2 = ServiceProvider(uid: 'u');

      expect(yes.hasUnreviewedVideo, true);
      expect(no1.hasUnreviewedVideo, false);
      expect(no2.hasUnreviewedVideo, false);
    });

    test('copyWith updates only specified fields', () {
      const prov = ServiceProvider(uid: 'u1', name: 'Old', rating: 4.0);
      final updated = prov.copyWith(name: 'New');

      expect(updated.name,   'New');
      expect(updated.rating, 4.0);    // unchanged
      expect(prov.name,      'Old');   // original unchanged
    });

    test('equality is based on uid', () {
      const a = ServiceProvider(uid: 'x', name: 'A');
      const b = ServiceProvider(uid: 'x', name: 'B');
      const c = ServiceProvider(uid: 'y', name: 'A');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. Provider STATE MANAGEMENT (no Firebase needed)
  // ═══════════════════════════════════════════════════════════════════════════

  group('CategoryProvider state', () {
    test('initial state is clean', () {
      final p = CategoryProvider.test();
      expect(p.allCategories,  isEmpty);
      expect(p.mainCategories, isEmpty);
      expect(p.isLoading,      false);
      expect(p.error,          isNull);
      expect(p.activeAction,   CategoryAction.none);
      p.dispose();
    });

    test('findByName returns null on empty', () {
      final p = CategoryProvider.test();
      expect(p.findByName('test'), isNull);
      p.dispose();
    });

    test('clearError resets error', () {
      final p = CategoryProvider.test();
      p.clearError();
      expect(p.error, isNull);
      p.dispose();
    });
  });

  group('ServiceProviderNotifier state', () {
    test('initial state is clean', () {
      final p = ServiceProviderNotifier.test();
      expect(p.searchResults,  isEmpty);
      expect(p.pendingExperts, isEmpty);
      expect(p.currentProfile, isNull);
      expect(p.isLoading,      false);
      expect(p.error,          isNull);
      expect(p.activeAction,   ProviderAction.none);
      p.dispose();
    });

    test('clearError resets error', () {
      final p = ServiceProviderNotifier.test();
      p.clearError();
      expect(p.error, isNull);
      p.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. Firestore ROUND-TRIP (category + provider lifecycle)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Firestore round-trip', () {
    test('Category survives write → read cycle', () async {
      final db = FakeFirebaseFirestore();
      const cat = Category(
        id:    'rt_cat',
        name:  'פנסיון',
        img:   'https://example.com/cat.jpg',
        order: 1,
        serviceSchema: [
          SchemaField(id: 'pn', label: 'מחיר ללילה', type: 'number', unit: '₪/ללילה'),
          SchemaField(id: 'yard', label: 'חצר?', type: 'bool'),
        ],
      );

      await db.collection('categories').doc(cat.id).set(cat.toJson());
      final doc = await db.collection('categories').doc(cat.id).get();
      final loaded = Category.fromFirestore(doc);

      expect(loaded.name, cat.name);
      expect(loaded.serviceSchema.length, 2);
      expect(loaded.primaryPriceField?.id, 'pn');
    });

    test('Provider approval lifecycle works correctly', () async {
      final db = FakeFirebaseFirestore();

      // Step 1: Create pending expert
      await db.collection('users').doc('expert1').set({
        'name':            'יוסי',
        'isPendingExpert': true,
        'isProvider':      false,
        'isVerified':      false,
        'isVerifiedProvider': true,
        'serviceType':     'אינסטלציה',
      });

      var doc = await db.collection('users').doc('expert1').get();
      var prov = ServiceProvider.fromFirestore(doc);
      expect(prov.verificationStatus, VerificationStatus.pending);
      expect(prov.isSearchVisible,    false);

      // Step 2: Admin approves
      await db.collection('users').doc('expert1').update({
        'isPendingExpert':        false,
        'isProvider':             true,
        'isVerified':             true,
        'categoryReviewedByAdmin': true,
      });

      doc = await db.collection('users').doc('expert1').get();
      prov = ServiceProvider.fromFirestore(doc);
      expect(prov.verificationStatus, VerificationStatus.verified);
      expect(prov.isSearchVisible,    true);

      // Step 3: Admin bans
      await db.collection('users').doc('expert1').update({
        'isBanned': true,
      });

      doc = await db.collection('users').doc('expert1').get();
      prov = ServiceProvider.fromFirestore(doc);
      expect(prov.verificationStatus, VerificationStatus.banned);
      expect(prov.isSearchVisible,    false);
    });

    test('Category click count increments atomically', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('categories').doc('click').set({
        'name': 'test', 'clickCount': 0,
      });

      await db.collection('categories').doc('click').update({
        'clickCount': FieldValue.increment(1),
      });
      await db.collection('categories').doc('click').update({
        'clickCount': FieldValue.increment(1),
      });

      final doc = await db.collection('categories').doc('click').get();
      final cat = Category.fromFirestore(doc);
      expect(cat.clickCount, 2);
    });

    test('Sub-categories link to parent', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('categories').doc('parent1').set({
        'name': 'שיפוצים', 'parentId': '',
      });
      await db.collection('categories').doc('sub1').set({
        'name': 'חשמל', 'parentId': 'parent1',
      });
      await db.collection('categories').doc('sub2').set({
        'name': 'אינסטלציה', 'parentId': 'parent1',
      });

      final snap = await db.collection('categories')
          .where('parentId', isEqualTo: 'parent1').get();

      final subs = snap.docs.map(Category.fromFirestore).toList();
      expect(subs.length, 2);
      expect(subs.every((s) => s.isSubCategory), true);
      expect(subs.every((s) => s.parentId == 'parent1'), true);
    });

    test('Delete cascade removes sub-categories', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('categories').doc('p').set({
        'name': 'parent', 'parentId': '',
      });
      await db.collection('categories').doc('s1').set({
        'name': 'sub1', 'parentId': 'p',
      });

      // Simulate cascade delete
      final subs = await db.collection('categories')
          .where('parentId', isEqualTo: 'p').get();
      for (final sub in subs.docs) {
        await sub.reference.delete();
      }
      await db.collection('categories').doc('p').delete();

      final remaining = await db.collection('categories').get();
      expect(remaining.docs, isEmpty);
    });

    test('toProfileUpdate excludes server-only fields', () {
      const prov = ServiceProvider(
        uid: 'u1',
        name: 'Test',
        xp: 500,
        balance: 100,
        serviceType: 'ניקיון',
      );
      final update = prov.toProfileUpdate();

      expect(update['name'],        'Test');
      expect(update['serviceType'], 'ניקיון');
      expect(update.containsKey('xp'),      false);
      expect(update.containsKey('balance'), false);
      expect(update.containsKey('uid'),     false);
    });
  });
}
