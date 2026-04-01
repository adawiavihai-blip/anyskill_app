import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:anyskill_app/models/quote.dart';
import 'package:anyskill_app/models/review.dart';
import 'package:anyskill_app/models/pricing_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Complete model tests: QuoteModel, ReviewModel, PricingModel, AddOn
//
// Run:  flutter test test/unit/models_complete_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. QuoteModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('QuoteModel', () {
    test('fromDoc parses all fields', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('quotes').doc('q1').set({
        'providerId':  'p1',
        'clientId':    'c1',
        'chatRoomId':  'c1_p1',
        'description': 'ניקיון דירה',
        'amount':      350.0,
        'status':      'pending',
        'jobId':       'j1',
        'createdAt':   Timestamp.now(),
      });

      final doc = await db.collection('quotes').doc('q1').get();
      final q = QuoteModel.fromDoc(doc);

      expect(q.id, 'q1');
      expect(q.providerId, 'p1');
      expect(q.clientId, 'c1');
      expect(q.chatRoomId, 'c1_p1');
      expect(q.description, 'ניקיון דירה');
      expect(q.amount, 350.0);
      expect(q.status, 'pending');
      expect(q.jobId, 'j1');
    });

    test('fromDoc handles missing fields gracefully', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('quotes').doc('sparse').set({});

      final doc = await db.collection('quotes').doc('sparse').get();
      final q = QuoteModel.fromDoc(doc);

      expect(q.id, 'sparse');
      expect(q.providerId, '');
      expect(q.amount, 0.0);
      expect(q.status, 'pending'); // default
      expect(q.jobId, isNull);
    });

    test('toMap produces correct fields', () {
      const q = QuoteModel(
        id: 'q1', providerId: 'p1', clientId: 'c1',
        chatRoomId: 'c1_p1', description: 'test',
        amount: 100.0, status: 'pending',
      );
      final map = q.toMap();

      expect(map['providerId'], 'p1');
      expect(map['clientId'], 'c1');
      expect(map['amount'], 100.0);
      expect(map['status'], 'pending');
      expect(map.containsKey('createdAt'), true);
      // id and jobId are NOT in toMap (id is the doc key, jobId is set later)
      expect(map.containsKey('id'), false);
    });

    test('round-trip: toMap → Firestore → fromDoc', () async {
      final db = FakeFirebaseFirestore();
      const original = QuoteModel(
        id: 'rt', providerId: 'p', clientId: 'c',
        chatRoomId: 'c_p', description: 'שירות',
        amount: 250.5, status: 'approved',
      );

      await db.collection('quotes').doc('rt').set(original.toMap());
      final doc = await db.collection('quotes').doc('rt').get();
      final loaded = QuoteModel.fromDoc(doc);

      expect(loaded.providerId, original.providerId);
      expect(loaded.amount, original.amount);
      expect(loaded.status, original.status);
      expect(loaded.description, original.description);
    });

    test('status values are correct strings', () {
      for (final s in ['pending', 'approved', 'paid', 'rejected']) {
        final q = QuoteModel(
          id: 'x', providerId: '', clientId: '', chatRoomId: '',
          description: '', amount: 0, status: s,
        );
        expect(q.status, s);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ReviewModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('ReviewModel', () {
    test('fromDoc parses all fields including ratingParams', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('reviews').doc('r1').set({
        'jobId':               'j1',
        'reviewerId':          'c1',
        'reviewerName':        'דנה',
        'revieweeId':          'p1',
        'isClientReview':      true,
        'ratingParams': {
          'professional':   5.0,
          'timing':         4.0,
          'communication':  4.5,
          'value':          3.5,
        },
        'overallRating':       4.25,
        'publicComment':       'שירות מצוין',
        'privateAdminComment': 'ללא הערות',
        'isPublished':         true,
        'traitTags':           ['professional', 'friendly'],
        'createdAt':           Timestamp.now(),
      });

      final doc = await db.collection('reviews').doc('r1').get();
      final r = ReviewModel.fromDoc(doc);

      expect(r.id, 'r1');
      expect(r.jobId, 'j1');
      expect(r.reviewerId, 'c1');
      expect(r.reviewerName, 'דנה');
      expect(r.revieweeId, 'p1');
      expect(r.isClientReview, true);
      expect(r.ratingParams['professional'], 5.0);
      expect(r.ratingParams['value'], 3.5);
      expect(r.overallRating, 4.25);
      expect(r.publicComment, 'שירות מצוין');
      expect(r.isPublished, true);
      expect(r.traitTags, 'professional,friendly');
    });

    test('fromDoc calculates overallRating from params when missing', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('reviews').doc('r2').set({
        'ratingParams': {
          'professional':   5.0,
          'timing':         3.0,
          'communication':  4.0,
          'value':          4.0,
        },
        // overallRating intentionally missing
      });

      final doc = await db.collection('reviews').doc('r2').get();
      final r = ReviewModel.fromDoc(doc);

      expect(r.overallRating, 4.0); // (5+3+4+4)/4
    });

    test('fromDoc falls back to legacy rating field', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('reviews').doc('r3').set({
        'rating': 4.5,
        // no ratingParams, no overallRating
      });

      final doc = await db.collection('reviews').doc('r3').get();
      final r = ReviewModel.fromDoc(doc);

      expect(r.overallRating, 4.5);
    });

    test('fromDoc handles missing fields', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('reviews').doc('empty').set({});

      final doc = await db.collection('reviews').doc('empty').get();
      final r = ReviewModel.fromDoc(doc);

      expect(r.reviewerName, 'משתמש'); // default
      expect(r.isClientReview, true);  // default
      expect(r.isPublished, true);     // default
      expect(r.publicComment, '');
    });

    test('fromDoc reads expertId as fallback for revieweeId', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('reviews').doc('legacy').set({
        'expertId': 'old_expert_id',
        // revieweeId intentionally missing
      });

      final doc = await db.collection('reviews').doc('legacy').get();
      final r = ReviewModel.fromDoc(doc);

      expect(r.revieweeId, 'old_expert_id');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. PricingModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('PricingModel', () {
    test('fromFirestore parses all fields', () {
      final m = PricingModel.fromFirestore({
        'pricingType': 'fixed',
        'basePrice':   200.0,
        'unitType':    'visit',
        'addOns': [
          {'title': 'חומרים', 'price': 50.0},
          {'title': 'הובלה', 'price': 30.0},
        ],
      });

      expect(m.type, PricingType.fixed);
      expect(m.basePrice, 200.0);
      expect(m.unitType, 'visit');
      expect(m.addOns.length, 2);
      expect(m.addOns[0].title, 'חומרים');
      expect(m.addOns[0].price, 50.0);
    });

    test('fromFirestore falls back to pricePerHour', () {
      final m = PricingModel.fromFirestore({
        'pricePerHour': 150.0,
        // no basePrice, no pricingType
      });

      expect(m.type, PricingType.hourly); // default
      expect(m.basePrice, 150.0);
      expect(m.unitType, 'hour');
    });

    test('fromFirestore handles empty data', () {
      final m = PricingModel.fromFirestore({});

      expect(m.type, PricingType.hourly);
      expect(m.basePrice, 100.0); // default
      expect(m.addOns, isEmpty);
    });

    test('fromFirestore filters empty-title addOns', () {
      final m = PricingModel.fromFirestore({
        'addOns': [
          {'title': 'Valid', 'price': 10.0},
          {'title': '', 'price': 20.0},     // empty title → filtered
          {'title': '  ', 'price': 30.0},   // whitespace → filtered
        ],
      });

      expect(m.addOns.length, 1);
      expect(m.addOns[0].title, 'Valid');
    });

    test('toFirestore round-trips correctly', () {
      final original = PricingModel.fromFirestore({
        'pricingType': 'flexible',
        'basePrice':   300.0,
        'unitType':    'session',
        'addOns':      [{'title': 'Extra', 'price': 25.0}],
      });

      final map = original.toFirestore();
      final loaded = PricingModel.fromFirestore(map);

      expect(loaded.type, original.type);
      expect(loaded.basePrice, original.basePrice);
      expect(loaded.unitType, original.unitType);
      expect(loaded.addOns.length, original.addOns.length);
    });

    test('toFirestore keeps pricePerHour in sync', () {
      const m = PricingModel(
        type: PricingType.fixed,
        basePrice: 250.0,
        unitType: 'visit',
        addOns: [],
      );
      final map = m.toFirestore();

      expect(map['basePrice'], 250.0);
      expect(map['pricePerHour'], 250.0); // backwards compat
    });

    test('unitLabel returns Hebrew strings', () {
      expect(
        const PricingModel(type: PricingType.hourly, basePrice: 0, unitType: '', addOns: []).unitLabel,
        'לשעה',
      );
      expect(
        const PricingModel(type: PricingType.fixed, basePrice: 0, unitType: '', addOns: []).unitLabel,
        'לביקור',
      );
      expect(
        const PricingModel(type: PricingType.flexible, basePrice: 0, unitType: '', addOns: []).unitLabel,
        'להצעה',
      );
    });

    test('total() sums base + selected addOns', () {
      const m = PricingModel(
        type: PricingType.fixed,
        basePrice: 100.0,
        unitType: 'visit',
        addOns: [
          AddOn(title: 'A', price: 20.0),
          AddOn(title: 'B', price: 30.0),
          AddOn(title: 'C', price: 50.0),
        ],
      );

      expect(m.total(), 100.0); // no addOns selected
      expect(m.total(selectedAddOnIndices: {0}), 120.0);
      expect(m.total(selectedAddOnIndices: {0, 2}), 170.0);
      expect(m.total(selectedAddOnIndices: {0, 1, 2}), 200.0);
    });

    test('total() ignores invalid indices', () {
      const m = PricingModel(
        type: PricingType.fixed,
        basePrice: 100.0,
        unitType: 'visit',
        addOns: [AddOn(title: 'A', price: 20.0)],
      );

      expect(m.total(selectedAddOnIndices: {5, -1, 100}), 100.0);
    });

    test('totalWithSurge applies multiplier', () {
      const m = PricingModel(
        type: PricingType.hourly,
        basePrice: 100.0,
        unitType: 'hour',
        addOns: [AddOn(title: 'A', price: 50.0)],
      );

      expect(m.totalWithSurge(1.0), 100.0);
      expect(m.totalWithSurge(1.5), 150.0);
      expect(m.totalWithSurge(2.0, selectedAddOnIndices: {0}), 300.0);
    });

    test('defaultUnitType maps correctly', () {
      expect(PricingModel.defaultUnitType(PricingType.hourly), 'hour');
      expect(PricingModel.defaultUnitType(PricingType.fixed), 'visit');
      expect(PricingModel.defaultUnitType(PricingType.flexible), 'session');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. AddOn
  // ═══════════════════════════════════════════════════════════════════════════

  group('AddOn', () {
    test('fromMap parses correctly', () {
      final a = AddOn.fromMap({'title': 'חומרים', 'price': 45.5});
      expect(a.title, 'חומרים');
      expect(a.price, 45.5);
    });

    test('fromMap handles missing fields', () {
      final a = AddOn.fromMap({});
      expect(a.title, '');
      expect(a.price, 0.0);
    });

    test('toMap round-trips', () {
      const a = AddOn(title: 'Test', price: 25.0);
      final map = a.toMap();
      final loaded = AddOn.fromMap(map);
      expect(loaded.title, a.title);
      expect(loaded.price, a.price);
    });
  });
}
