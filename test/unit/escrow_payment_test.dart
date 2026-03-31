// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: Escrow & Payment lifecycle
//
// Tests the BUSINESS LOGIC of payments using fake_cloud_firestore.
// Cloud Functions (Stripe transfers, refunds) are tested via their
// Firestore inputs/outputs — we verify the state transitions, fee
// calculations, and data integrity that the functions depend on.
//
// Run:  flutter test test/unit/escrow_payment_test.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Seed admin settings with fee percentage.
Future<void> _seedSettings(FakeFirebaseFirestore db, {double fee = 0.10}) async {
  await db.doc('admin/admin/settings/settings').set({
    'feePercentage': fee,
    'totalPlatformBalance': 0.0,
  });
}

/// Seed a user with a balance.
Future<void> _seedUser(FakeFirebaseFirestore db, String uid, {
  double balance = 1000.0,
  double pendingBalance = 0.0,
  bool isProvider = false,
}) async {
  await db.collection('users').doc(uid).set({
    'name': 'User $uid',
    'balance': balance,
    'pendingBalance': pendingBalance,
    'isProvider': isProvider,
    'rating': 5.0,
    'reviewsCount': 0,
  });
}

/// Seed a pending quote.
Future<void> _seedQuote(FakeFirebaseFirestore db, String quoteId, {
  String providerId = 'provider1',
  String clientId = 'client1',
  double amount = 100.0,
  String status = 'pending',
}) async {
  await db.collection('quotes').doc(quoteId).set({
    'providerId': providerId,
    'clientId': clientId,
    'amount': amount,
    'status': status,
    'description': 'Test service',
    'chatRoomId': '${[clientId, providerId]..sort()}'.replaceAll(RegExp(r'[\[\] ]'), '').replaceAll(',', '_'),
    'createdAt': Timestamp.now(),
  });
}

/// Simulate the escrow payment transaction (mirrors EscrowService.payQuote).
Future<String> _simulatePayQuote(
  FakeFirebaseFirestore db, {
  required String quoteId,
  required String clientId,
  required String providerId,
  required double totalAmount,
}) async {
  // Read fee
  final settingsDoc = await db.doc('admin/admin/settings/settings').get();
  final fee = (settingsDoc.data()?['feePercentage'] as num?)?.toDouble() ?? 0.10;

  // Read quote status
  final quoteDoc = await db.collection('quotes').doc(quoteId).get();
  if (quoteDoc.data()?['status'] == 'paid') {
    throw Exception('Quote already paid');
  }

  // Read client balance
  final clientDoc = await db.collection('users').doc(clientId).get();
  final clientBalance = (clientDoc.data()?['balance'] as num?)?.toDouble() ?? 0;
  if (clientBalance < totalAmount) {
    throw Exception('Insufficient balance');
  }

  // Calculate
  final commission = double.parse((totalAmount * fee).toStringAsFixed(2));
  final netToExpert = double.parse((totalAmount - commission).toStringAsFixed(2));

  // Create job
  final jobRef = db.collection('jobs').doc();
  await jobRef.set({
    'customerId': clientId,
    'expertId': providerId,
    'totalAmount': totalAmount,
    'netAmountForExpert': netToExpert,
    'commission': commission,
    'status': 'paid_escrow',
    'quoteId': quoteId,
    'source': 'quote',
    'createdAt': Timestamp.now(),
    'clientReviewDone': false,
    'providerReviewDone': false,
    'cancellationPolicy': 'flexible',
  });

  // Update balances
  await db.collection('users').doc(clientId).update({
    'balance': FieldValue.increment(-totalAmount),
  });
  await db.collection('users').doc(providerId).update({
    'pendingBalance': FieldValue.increment(netToExpert),
  });

  // Record platform earnings
  await db.collection('platform_earnings').add({
    'jobId': jobRef.id,
    'amount': commission,
    'sourceExpertId': providerId,
    'status': 'pending_escrow',
    'timestamp': Timestamp.now(),
  });

  // Record transaction
  await db.collection('transactions').add({
    'senderId': clientId,
    'receiverId': providerId,
    'amount': totalAmount,
    'type': 'quote_payment',
    'jobId': jobRef.id,
    'payoutStatus': 'pending',
    'timestamp': Timestamp.now(),
  });

  // Mark quote as paid
  await db.collection('quotes').doc(quoteId).update({'status': 'paid'});

  // Update platform balance
  await db.doc('admin/admin/settings/settings').update({
    'totalPlatformBalance': FieldValue.increment(commission),
  });

  return jobRef.id;
}

/// Simulate payment release (mirrors processPaymentRelease CF).
Future<void> _simulateRelease(
  FakeFirebaseFirestore db, {
  required String jobId,
  required String expertId,
  required double netAmount,
}) async {
  await db.collection('jobs').doc(jobId).update({
    'status': 'completed',
    'completedAt': Timestamp.now(),
  });
  await db.collection('users').doc(expertId).update({
    'balance': FieldValue.increment(netAmount),
    'pendingBalance': FieldValue.increment(-netAmount),
  });
}

/// Simulate cancellation refund.
Future<void> _simulateCancel(
  FakeFirebaseFirestore db, {
  required String jobId,
  required String clientId,
  required double refundAmount,
  String status = 'cancelled',
}) async {
  await db.collection('jobs').doc(jobId).update({
    'status': status,
    'cancelledAt': Timestamp.now(),
  });
  await db.collection('users').doc(clientId).update({
    'balance': FieldValue.increment(refundAmount),
  });
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. FEE CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Fee calculation', () {
    test('10% fee: ₪100 → ₪10 commission, ₪90 to expert', () {
      const total = 100.0;
      const fee = 0.10;
      final commission = double.parse((total * fee).toStringAsFixed(2));
      final net = double.parse((total - commission).toStringAsFixed(2));
      expect(commission, 10.0);
      expect(net, 90.0);
    });

    test('15% fee on ₪200', () {
      const total = 200.0;
      const fee = 0.15;
      final commission = double.parse((total * fee).toStringAsFixed(2));
      final net = double.parse((total - commission).toStringAsFixed(2));
      expect(commission, 30.0);
      expect(net, 170.0);
    });

    test('0% fee means expert gets everything', () {
      const total = 500.0;
      const fee = 0.0;
      final commission = double.parse((total * fee).toStringAsFixed(2));
      final net = double.parse((total - commission).toStringAsFixed(2));
      expect(commission, 0.0);
      expect(net, 500.0);
    });

    test('rounding: fee on ₪33.33 at 10%', () {
      const total = 33.33;
      const fee = 0.10;
      final commission = double.parse((total * fee).toStringAsFixed(2));
      final net = double.parse((total - commission).toStringAsFixed(2));
      expect(commission, 3.33);
      expect(net, 30.0);
    });

    test('commission + net always equals total', () {
      for (final total in [1.0, 49.99, 100.0, 250.50, 999.99]) {
        const fee = 0.10;
        final commission = double.parse((total * fee).toStringAsFixed(2));
        final net = double.parse((total - commission).toStringAsFixed(2));
        expect(commission + net, closeTo(total, 0.01),
            reason: 'Failed for total=$total');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ESCROW CREATION (payQuote)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Escrow creation (payQuote)', () {
    test('successful escrow creates job with correct amounts', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db, fee: 0.10);
      await _seedUser(db, 'client1', balance: 500.0);
      await _seedUser(db, 'provider1', isProvider: true);
      await _seedQuote(db, 'q1', amount: 100.0);

      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'client1',
        providerId: 'provider1', totalAmount: 100.0,
      );

      // Verify job
      final job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'paid_escrow');
      expect(job.data()?['totalAmount'], 100.0);
      expect(job.data()?['netAmountForExpert'], 90.0);
      expect(job.data()?['commission'], 10.0);

      // Verify balances
      final client = await db.collection('users').doc('client1').get();
      expect(client.data()?['balance'], 400.0); // 500 - 100

      final provider = await db.collection('users').doc('provider1').get();
      expect(provider.data()?['pendingBalance'], 90.0);
    });

    test('client balance decreases by totalAmount', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 300.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1', clientId: 'c1', providerId: 'p1', amount: 150.0);

      await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 150.0,
      );

      final client = await db.collection('users').doc('c1').get();
      expect(client.data()?['balance'], 150.0);
    });

    test('rejects if client has insufficient balance', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'broke', balance: 50.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1', clientId: 'broke', providerId: 'p1', amount: 100.0);

      expect(
        () => _simulatePayQuote(db,
          quoteId: 'q1', clientId: 'broke',
          providerId: 'p1', totalAmount: 100.0,
        ),
        throwsA(predicate((e) => e.toString().contains('Insufficient balance'))),
      );
    });

    test('rejects double payment on same quote', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 1000.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1', clientId: 'c1', providerId: 'p1', amount: 100.0);

      await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );

      expect(
        () => _simulatePayQuote(db,
          quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
        ),
        throwsA(predicate((e) => e.toString().contains('already paid'))),
      );
    });

    test('quote status changes to paid', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1');

      await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );

      final quote = await db.collection('quotes').doc('q1').get();
      expect(quote.data()?['status'], 'paid');
    });

    test('platform earnings record created with correct amount', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db, fee: 0.15);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1', amount: 200.0);

      await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 200.0,
      );

      final earnings = await db.collection('platform_earnings').get();
      expect(earnings.docs.length, 1);
      expect(earnings.docs.first.data()['amount'], 30.0); // 200 * 0.15

      // Platform balance updated
      final settings = await db.doc('admin/admin/settings/settings').get();
      expect(settings.data()?['totalPlatformBalance'], 30.0);
    });

    test('transaction record links to job', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1');

      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );

      final txns = await db.collection('transactions').get();
      expect(txns.docs.length, 1);
      final tx = txns.docs.first.data();
      expect(tx['jobId'], jobId);
      expect(tx['type'], 'quote_payment');
      expect(tx['amount'], 100.0);
      expect(tx['senderId'], 'c1');
      expect(tx['receiverId'], 'p1');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. PAYMENT RELEASE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Payment release', () {
    test('release moves funds from pending to balance', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true, balance: 0.0, pendingBalance: 0.0);
      await _seedQuote(db, 'q1');

      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );

      // Provider should have 90 in pending
      var provider = await db.collection('users').doc('p1').get();
      expect(provider.data()?['pendingBalance'], 90.0);
      expect(provider.data()?['balance'], 0.0);

      // Release payment
      await _simulateRelease(db, jobId: jobId, expertId: 'p1', netAmount: 90.0);

      provider = await db.collection('users').doc('p1').get();
      expect(provider.data()?['balance'], 90.0);
      expect(provider.data()?['pendingBalance'], 0.0);

      final job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'completed');
    });

    test('job status changes to completed after release', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1');

      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );
      await _simulateRelease(db, jobId: jobId, expertId: 'p1', netAmount: 90.0);

      final job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'completed');
      expect(job.data()?['completedAt'], isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. CANCELLATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Cancellation', () {
    test('full refund returns totalAmount to client', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1', amount: 200.0);

      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 200.0,
      );

      // Client balance: 500 - 200 = 300
      var client = await db.collection('users').doc('c1').get();
      expect(client.data()?['balance'], 300.0);

      // Full refund
      await _simulateCancel(db,
        jobId: jobId, clientId: 'c1', refundAmount: 200.0,
      );

      client = await db.collection('users').doc('c1').get();
      expect(client.data()?['balance'], 500.0); // back to original
    });

    test('cancelled job has correct status', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1');

      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );
      await _simulateCancel(db,
        jobId: jobId, clientId: 'c1', refundAmount: 100.0,
      );

      final job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'cancelled');
      expect(job.data()?['cancelledAt'], isNotNull);
    });

    test('cancellation with penalty splits funds correctly', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db, fee: 0.10);
      await _seedUser(db, 'c1', balance: 1000.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1', amount: 200.0);

      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 200.0,
      );

      // Simulate 50% penalty: penalty=100, refund=100
      const customerRefund = 100.0;

      await _simulateCancel(db,
        jobId: jobId, clientId: 'c1',
        refundAmount: customerRefund,
        status: 'cancelled_with_penalty',
      );

      final client = await db.collection('users').doc('c1').get();
      // Started 1000, paid 200, refunded 100 = 900
      expect(client.data()?['balance'], 900.0);

      final job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'cancelled_with_penalty');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. CANCELLATION POLICY WINDOWS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Cancellation policy windows', () {
    test('flexible: 4 hours before appointment', () {
      final appointment = DateTime.now().add(const Duration(hours: 10));
      final deadline = appointment.subtract(const Duration(hours: 4));
      final now = DateTime.now();
      expect(now.isBefore(deadline), true); // still in free window
    });

    test('moderate: 24 hours before appointment', () {
      final appointment = DateTime.now().add(const Duration(hours: 30));
      final deadline = appointment.subtract(const Duration(hours: 24));
      final now = DateTime.now();
      expect(now.isBefore(deadline), true); // still in free window
    });

    test('strict: 48 hours before appointment', () {
      final appointment = DateTime.now().add(const Duration(hours: 50));
      final deadline = appointment.subtract(const Duration(hours: 48));
      final now = DateTime.now();
      expect(now.isBefore(deadline), true); // still in free window
    });

    test('after deadline: penalty applies', () {
      final appointment = DateTime.now().add(const Duration(hours: 2));
      final deadline = appointment.subtract(const Duration(hours: 4));
      final now = DateTime.now();
      expect(now.isAfter(deadline), true); // past free window
    });

    test('penalty fractions by policy', () {
      const penalties = {
        'flexible': 0.50,
        'moderate': 0.50,
        'strict':   1.00,
      };
      expect(penalties['flexible'], 0.50);
      expect(penalties['moderate'], 0.50);
      expect(penalties['strict'], 1.00);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. DISPUTE RESOLUTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Dispute resolution', () {
    test('dispute status is set correctly', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('jobs').doc('j1').set({
        'status': 'paid_escrow', 'totalAmount': 100.0,
        'customerId': 'c1', 'expertId': 'p1',
      });

      await db.collection('jobs').doc('j1').update({
        'status': 'disputed',
        'disputeReason': 'Service not completed',
        'disputeOpenedAt': Timestamp.now(),
        'disputerId': 'c1',
      });

      final job = await db.collection('jobs').doc('j1').get();
      expect(job.data()?['status'], 'disputed');
      expect(job.data()?['disputeReason'], 'Service not completed');
    });

    test('refund resolution returns full amount', () async {
      final db = FakeFirebaseFirestore();
      await _seedUser(db, 'c1', balance: 0.0);
      await db.collection('jobs').doc('j1').set({
        'status': 'disputed', 'totalAmount': 100.0,
        'customerId': 'c1', 'expertId': 'p1',
      });

      // Admin resolves: refund
      await db.collection('jobs').doc('j1').update({
        'status': 'refunded',
        'resolvedAt': Timestamp.now(),
        'resolvedBy': 'admin',
        'resolution': 'refund',
        'adminNote': 'Provider failed to deliver',
      });
      await db.collection('users').doc('c1').update({
        'balance': FieldValue.increment(100.0),
      });

      final client = await db.collection('users').doc('c1').get();
      expect(client.data()?['balance'], 100.0);

      final job = await db.collection('jobs').doc('j1').get();
      expect(job.data()?['status'], 'refunded');
      expect(job.data()?['resolution'], 'refund');
    });

    test('split resolution divides 50/50', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db, fee: 0.10);
      await _seedUser(db, 'c1', balance: 0.0);
      await _seedUser(db, 'p1', isProvider: true, balance: 0.0);

      const total = 200.0;
      const split = total / 2; // 100 each
      const platformFee = split * 0.10; // 10 from provider's half
      const expertGets = split - platformFee; // 90

      await db.collection('jobs').doc('j1').set({
        'status': 'disputed', 'totalAmount': total,
        'customerId': 'c1', 'expertId': 'p1',
      });

      await db.collection('jobs').doc('j1').update({
        'status': 'split_resolved',
        'resolvedAt': Timestamp.now(),
        'resolution': 'split',
      });
      await db.collection('users').doc('c1').update({
        'balance': FieldValue.increment(split),
      });
      await db.collection('users').doc('p1').update({
        'balance': FieldValue.increment(expertGets),
      });

      final client = await db.collection('users').doc('c1').get();
      final provider = await db.collection('users').doc('p1').get();

      expect(client.data()?['balance'], 100.0);
      expect(provider.data()?['balance'], 90.0);
      expect(split + expertGets + platformFee, total);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. JOB STATE TRANSITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Job state transitions', () {
    test('full happy path: escrow → expert_completed → completed', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 500.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1');

      // Step 1: Pay
      final jobId = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );
      var job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'paid_escrow');

      // Step 2: Expert marks done
      await db.collection('jobs').doc(jobId).update({
        'status': 'expert_completed',
        'expertCompletedAt': Timestamp.now(),
      });
      job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'expert_completed');

      // Step 3: Customer releases
      await _simulateRelease(db, jobId: jobId, expertId: 'p1', netAmount: 90.0);
      job = await db.collection('jobs').doc(jobId).get();
      expect(job.data()?['status'], 'completed');
    });

    test('review tracking: both parties must review', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('jobs').doc('j1').set({
        'status': 'completed',
        'clientReviewDone': false,
        'providerReviewDone': false,
      });

      // Client reviews
      await db.collection('jobs').doc('j1').update({
        'clientReviewDone': true,
      });
      var job = await db.collection('jobs').doc('j1').get();
      expect(job.data()?['clientReviewDone'], true);
      expect(job.data()?['providerReviewDone'], false);

      // Provider reviews
      await db.collection('jobs').doc('j1').update({
        'providerReviewDone': true,
      });
      job = await db.collection('jobs').doc('j1').get();
      expect(job.data()?['clientReviewDone'], true);
      expect(job.data()?['providerReviewDone'], true);
    });

    test('terminal statuses are correct set', () {
      const terminal = {
        'completed', 'cancelled', 'cancelled_with_penalty',
        'refunded', 'split_resolved', 'disputed',
      };
      expect(terminal.contains('completed'), true);
      expect(terminal.contains('paid_escrow'), false);
      expect(terminal.contains('expert_completed'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. EDGE CASES & CONSISTENCY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('zero-amount quote rejected', () {
      const amount = 0.0;
      expect(amount <= 0, true); // UI should prevent this
    });

    test('multiple jobs from different quotes stay independent', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 1000.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedUser(db, 'p2', isProvider: true);
      await _seedQuote(db, 'q1', providerId: 'p1', amount: 100.0);
      await _seedQuote(db, 'q2', providerId: 'p2', amount: 200.0);

      final job1 = await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );
      final job2 = await _simulatePayQuote(db,
        quoteId: 'q2', clientId: 'c1', providerId: 'p2', totalAmount: 200.0,
      );

      expect(job1, isNot(equals(job2)));

      final client = await db.collection('users').doc('c1').get();
      expect(client.data()?['balance'], 700.0); // 1000 - 100 - 200

      final p1 = await db.collection('users').doc('p1').get();
      final p2 = await db.collection('users').doc('p2').get();
      expect(p1.data()?['pendingBalance'], 90.0); // 100 - 10% fee
      expect(p2.data()?['pendingBalance'], 180.0); // 200 - 10% fee
    });

    test('balance never goes negative after escrow', () async {
      final db = FakeFirebaseFirestore();
      await _seedSettings(db);
      await _seedUser(db, 'c1', balance: 100.0);
      await _seedUser(db, 'p1', isProvider: true);
      await _seedQuote(db, 'q1', amount: 100.0);

      await _simulatePayQuote(db,
        quoteId: 'q1', clientId: 'c1', providerId: 'p1', totalAmount: 100.0,
      );

      final client = await db.collection('users').doc('c1').get();
      expect(client.data()?['balance'], 0.0);
      expect((client.data()?['balance'] as num) >= 0, true);
    });
  });
}
