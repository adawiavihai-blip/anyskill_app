import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyskill_app/screens/chat_modules/payment_module.dart';
import 'package:anyskill_app/utils/payment_calculator.dart';

// ── קבועי בדיקה ────────────────────────────────────────────────────────────
const _jobId       = 'job_001';
const _expertId    = 'expert_001';
const _customerId  = 'customer_001';
const _expertName  = 'אריאל כהן';
const _customerName = 'דנה לוי';
const _totalAmount = 200.0;
const _feePercentage = 0.10;

// ── עוזר: מאתחל Firestore מזויף עם מצב מוצא ───────────────────────────────
Future<FakeFirebaseFirestore> _buildFakeFirestore({
  double expertInitialBalance = 0.0,
  double platformInitialBalance = 0.0,
  double? feeOverride,
}) async {
  final db = FakeFirebaseFirestore();

  // מסמך ה-job (סטטוס: expert_completed לפני שחרור)
  await db.collection('jobs').doc(_jobId).set({
    'customerId': _customerId,
    'expertId': _expertId,
    'totalAmount': _totalAmount,
    'status': 'expert_completed',
    'customerName': _customerName,
    'expertName': _expertName,
  });

  // פרופיל המומחה
  await db.collection('users').doc(_expertId).set({
    'name': _expertName,
    'balance': expertInitialBalance,
  });

  // הגדרות אדמין
  await db
      .collection('admin')
      .doc('admin')
      .collection('settings')
      .doc('settings')
      .set({
    'feePercentage': feeOverride ?? _feePercentage,
    'totalPlatformBalance': platformInitialBalance,
  });

  return db;
}

void main() {

  // ══════════════════════════════════════════════════════════════════════════
  // חלק א׳: calculatePayment — בדיקות יחידה לפונקציה הטהורה
  // ══════════════════════════════════════════════════════════════════════════
  group('calculatePayment — unit tests', () {

    test('10% עמלה על 200 ₪', () {
      final r = calculatePayment(200, 0.10);
      expect(r.feeAmount,   20.0);
      expect(r.netToExpert, 180.0);
      expect(r.totalAmount, 200.0);
      expect(r.feePercentage, 0.10);
    });

    test('15% עמלה על 133.33 ₪ — עיגול נכון', () {
      final r = calculatePayment(133.33, 0.15);
      // 133.33 * 0.15 = 19.9995 → 20.00
      expect(r.feeAmount,   20.00);
      expect(r.netToExpert, 113.33);
    });

    test('0% עמלה — המומחה מקבל הכל', () {
      final r = calculatePayment(100, 0.0);
      expect(r.feeAmount,   0.0);
      expect(r.netToExpert, 100.0);
    });

    test('100% עמלה — המומחה לא מקבל כלום', () {
      final r = calculatePayment(100, 1.0);
      expect(r.feeAmount,   100.0);
      expect(r.netToExpert, 0.0);
    });

    test('סכום אפס — תוצאה תקינה', () {
      final r = calculatePayment(0, 0.10);
      expect(r.feeAmount,   0.0);
      expect(r.netToExpert, 0.0);
    });

    test('סכום שלילי — זורק ArgumentError', () {
      expect(() => calculatePayment(-50, 0.10), throwsArgumentError);
    });

    test('עמלה שלילית — זורק ArgumentError', () {
      expect(() => calculatePayment(100, -0.01), throwsArgumentError);
    });

    test('עמלה גדולה מ-1 — זורק ArgumentError', () {
      expect(() => calculatePayment(100, 1.01), throwsArgumentError);
    });

    test('feeAmount + netToExpert = totalAmount תמיד', () {
      for (final fee in [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.50, 1.0]) {
        final r = calculatePayment(999.99, fee);
        expect(
          (r.feeAmount + r.netToExpert).toStringAsFixed(2),
          r.totalAmount.toStringAsFixed(2),
          reason: 'נכשל עבור עמלה $fee',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // חלק ב׳: hasSufficientBalance — בדיקות יחידה
  // ══════════════════════════════════════════════════════════════════════════
  group('hasSufficientBalance — unit tests', () {

    test('יתרה גדולה מהסכום — מספיקה', () {
      expect(hasSufficientBalance(500, 200), isTrue);
    });

    test('יתרה שווה לסכום — מספיקה', () {
      expect(hasSufficientBalance(200, 200), isTrue);
    });

    test('יתרה קטנה מהסכום — לא מספיקה', () {
      expect(hasSufficientBalance(199.99, 200), isFalse);
    });

    test('יתרה אפס — לא מספיקה לסכום חיובי', () {
      expect(hasSufficientBalance(0, 0.01), isFalse);
    });

    test('יתרה אפס וסכום נדרש אפס — מספיקה', () {
      expect(hasSufficientBalance(0, 0), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // חלק ג׳: releaseEscrowFunds — אינטגרציה עם FakeFirebaseFirestore
  // ══════════════════════════════════════════════════════════════════════════
  group('releaseEscrowFunds — integration tests', () {

    test('מחזיר true בהצלחה', () async {
      final db = await _buildFakeFirestore();
      final result = await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      expect(result, isTrue);
    });

    test('סטטוס ה-job מתעדכן ל-"completed"', () async {
      final db = await _buildFakeFirestore();
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final snap = await db.collection('jobs').doc(_jobId).get();
      expect(snap.get('status'), 'completed');
    });

    test('ה-job מכיל feeAmount ו-netAmountForExpert אחרי שחרור', () async {
      final db = await _buildFakeFirestore();
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final snap = await db.collection('jobs').doc(_jobId).get();
      expect(snap.get('feeAmount'),          20.0);   // 10% מ-200
      expect(snap.get('netAmountForExpert'), 180.0);  // 200 - 20
    });

    test('יתרת המומחה עולה ב-netToExpert', () async {
      final db = await _buildFakeFirestore(expertInitialBalance: 50.0);
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final snap = await db.collection('users').doc(_expertId).get();
      expect(snap.get('balance'), 230.0); // 50 + 180
    });

    test('יתרת המומחה מתחילה מאפס — מקבל בדיוק netToExpert', () async {
      final db = await _buildFakeFirestore(expertInitialBalance: 0.0);
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final snap = await db.collection('users').doc(_expertId).get();
      expect(snap.get('balance'), 180.0);
    });

    test('totalPlatformBalance מוגדל ב-feeAmount', () async {
      // fake_cloud_firestore אינו תומך ב-FieldValue.increment בתוך transaction.set()
      // עם merge — הוא כותב את ה-delta ישירות. לכן מוודאים שהערך הכתוב שווה ל-feeAmount.
      final db = await _buildFakeFirestore(platformInitialBalance: 0.0);
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final snap = await db
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings')
          .get();
      // 10% מ-200 = 20 ₪ עמלה
      expect(snap.get('totalPlatformBalance'), 20.0);
    });

    test('רשומת platform_earnings נוצרת עם השדות הנכונים', () async {
      final db = await _buildFakeFirestore();
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final earningsSnap = await db.collection('platform_earnings').get();
      expect(earningsSnap.docs.length, 1);

      final doc = earningsSnap.docs.first.data();
      expect(doc['jobId'],       _jobId);
      expect(doc['amount'],      20.0);
      expect(doc['expertName'],  _expertName);
      expect(doc['customerName'], _customerName);
      expect(doc['description'], '$_customerName ➔ $_expertName');
    });

    test('עמלה 15% — חישוב נכון', () async {
      final db = await _buildFakeFirestore(feeOverride: 0.15);
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final snap = await db.collection('jobs').doc(_jobId).get();
      expect(snap.get('feeAmount'),          30.0);  // 15% מ-200
      expect(snap.get('netAmountForExpert'), 170.0); // 200 - 30

      final expertSnap = await db.collection('users').doc(_expertId).get();
      expect(expertSnap.get('balance'), 170.0);
    });

    test('ללא מסמך הגדרות אדמין — fallback ל-10%', () async {
      final db = FakeFirebaseFirestore();

      await db.collection('jobs').doc(_jobId).set({
        'customerId': _customerId,
        'expertId': _expertId,
        'totalAmount': _totalAmount,
        'status': 'expert_completed',
      });
      await db.collection('users').doc(_expertId).set({
        'name': _expertName,
        'balance': 0.0,
      });
      // לא יוצרים מסמך admin settings — כדי לבדוק fallback

      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );

      final snap = await db.collection('users').doc(_expertId).get();
      expect(snap.get('balance'), 180.0); // fallback 10%: 200 - 20 = 180
    });

    test('לא נוצרות רשומות עודפות — שחרור חד-פעמי', () async {
      final db = await _buildFakeFirestore();
      await PaymentModule.releaseEscrowFunds(
        jobId: _jobId,
        expertId: _expertId,
        expertName: _expertName,
        customerName: _customerName,
        totalAmount: _totalAmount,
        db: db,
      );
      final earningsSnap = await db.collection('platform_earnings').get();
      expect(earningsSnap.docs.length, 1);
    });
  });
}
