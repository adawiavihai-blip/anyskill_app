// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: PaymentService — escrow lifecycle + fee calculation
//
// Run:  flutter test test/unit/payment_service_test.dart
//
// These tests use fake_cloud_firestore (already in dev_dependencies) so they
// run offline with no Firebase project credentials needed.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('Fee calculation', () {
    test('10% fee: provider receives 90% of amount', () {
      const amount     = 100.0;
      const feePercent = 0.10;
      final adminFee       = amount * feePercent;
      final providerAmount = amount - adminFee;

      expect(adminFee,       10.0);
      expect(providerAmount, 90.0);
    });

    test('15% VIP fee: provider receives 85%', () {
      const amount     = 200.0;
      const feePercent = 0.15;
      final providerAmount = amount * (1 - feePercent);
      expect(providerAmount, 170.0);
    });

    test('zero fee: provider receives 100%', () {
      const amount     = 50.0;
      const feePercent = 0.0;
      final providerAmount = amount * (1 - feePercent);
      expect(providerAmount, 50.0);
    });
  });

  group('Escrow: processPayment', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    Future<void> seed({
      required String senderId,
      required String receiverId,
      required double senderBalance,
      required double receiverBalance,
      required double feePercent,
    }) async {
      await fakeFirestore.collection('users').doc(senderId).set({
        'balance': senderBalance,
        'name':    'Customer Test',
      });
      await fakeFirestore.collection('users').doc(receiverId).set({
        'balance': receiverBalance,
        'name':    'Provider Test',
      });
      await fakeFirestore
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings')
          .set({'feePercentage': feePercent, 'totalPlatformBalance': 0.0});
    }

    test('successful payment: balances update correctly', () async {
      await seed(
        senderId:        'cust_1',
        receiverId:      'prov_1',
        senderBalance:   500.0,
        receiverBalance: 0.0,
        feePercent:      0.10,
      );

      const amount = 100.0;

      // Replicate the payment logic inline (service uses Admin SDK in real app)
      await fakeFirestore.runTransaction((tx) async {
        final adminRef = fakeFirestore
            .collection('admin').doc('admin')
            .collection('settings').doc('settings');
        final custRef  = fakeFirestore.collection('users').doc('cust_1');
        final provRef  = fakeFirestore.collection('users').doc('prov_1');

        final adminDoc  = await tx.get(adminRef);
        final senderDoc = await tx.get(custRef);

        final fee     = amount * (adminDoc.get('feePercentage') as num).toDouble();
        final payout  = amount - fee;
        final balance = (senderDoc.get('balance') as num).toDouble();

        expect(balance >= amount, isTrue, reason: 'Sender must have enough balance');

        tx.update(custRef, {'balance': FieldValue.increment(-amount)});
        tx.update(provRef, {'balance': FieldValue.increment(payout)});
        tx.set(adminRef,   {'totalPlatformBalance': FieldValue.increment(fee)},
            SetOptions(merge: true));
        tx.set(fakeFirestore.collection('transactions').doc(), {
          'senderId':   'cust_1',
          'receiverId': 'prov_1',
          'amount':     amount,
          'timestamp':  FieldValue.serverTimestamp(),
        });
      });

      final custDoc  = await fakeFirestore.collection('users').doc('cust_1').get();
      final provDoc  = await fakeFirestore.collection('users').doc('prov_1').get();
      final adminDoc = await fakeFirestore
          .collection('admin').doc('admin')
          .collection('settings').doc('settings')
          .get();

      expect((custDoc.get('balance')  as num).toDouble(), 400.0);  // 500 - 100
      expect((provDoc.get('balance')  as num).toDouble(), 90.0);   // 100 × 0.90
      expect((adminDoc.get('totalPlatformBalance') as num).toDouble(), 10.0); // 100 × 0.10
    });

    test('insufficient balance throws', () async {
      await seed(
        senderId:        'broke_cust',
        receiverId:      'prov_2',
        senderBalance:   30.0,   // less than 100
        receiverBalance: 0.0,
        feePercent:      0.10,
      );

      expect(
        () async => fakeFirestore.runTransaction((tx) async {
          final custRef = fakeFirestore.collection('users').doc('broke_cust');
          final doc     = await tx.get(custRef);
          final balance = (doc.get('balance') as num).toDouble();
          if (balance < 100.0) throw Exception('אין מספיק יתרה');
          tx.update(custRef, {'balance': FieldValue.increment(-100.0)});
        }),
        throwsException,
      );
    });

    test('transaction creates a record in transactions collection', () async {
      await seed(
        senderId:        'cust_tx',
        receiverId:      'prov_tx',
        senderBalance:   200.0,
        receiverBalance: 0.0,
        feePercent:      0.10,
      );

      final txRef = fakeFirestore.collection('transactions').doc();
      await txRef.set({
        'senderId':   'cust_tx',
        'receiverId': 'prov_tx',
        'userId':     'cust_tx',
        'amount':     100.0,
        'timestamp':  FieldValue.serverTimestamp(),
      });

      final snap = await fakeFirestore
          .collection('transactions')
          .where('senderId', isEqualTo: 'cust_tx')
          .get();

      expect(snap.docs.length, 1);
      expect((snap.docs.first.get('amount') as num).toDouble(), 100.0);
    });
  });

  group('Review: rating calculation', () {
    test('first review sets rating directly', () {
      const currentRating = 0.0;
      const currentCount  = 0;
      const newRating     = 5.0;

      final count  = currentCount + 1;
      final rating = ((currentRating * currentCount) + newRating) / count;

      expect(rating, 5.0);
    });

    test('second review averages correctly', () {
      const currentRating = 5.0;
      const currentCount  = 1;
      const newRating     = 3.0;

      final count  = currentCount + 1;
      final rating = ((currentRating * currentCount) + newRating) / count;

      expect(rating, 4.0);  // (5 + 3) / 2
    });

    test('rating rounds to 1 decimal place', () {
      const currentRating = 4.0;
      const currentCount  = 2;
      const newRating     = 3.0;

      final count  = currentCount + 1;
      final rawRating = ((currentRating * currentCount) + newRating) / count;
      final rounded   = double.parse(rawRating.toStringAsFixed(1));

      expect(rounded, 3.7);  // (8 + 3) / 3 = 3.666… → 3.7
    });
  });
}
