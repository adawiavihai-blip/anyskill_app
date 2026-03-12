import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PaymentModule {
  static Future<bool> releaseEscrowFunds({
    required String jobId,
    required String expertId,
    required String expertName,   // QA: נוסף כדי להציג בהיסטוריה
    required String customerName, // QA: נוסף כדי להציג בהיסטוריה
    required double totalAmount,
    FirebaseFirestore? db,        // injectable for testing; null = production instance
  }) async {
    final firestore = db ?? FirebaseFirestore.instance;

    try {
      // הנתיב המדויק לפי ה-Console שלך
      final DocumentReference adminSettingsRef = firestore
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings');

      await firestore.runTransaction((transaction) async {
        // 1. קריאת נתונים מקדימה
        DocumentSnapshot adminSnap = await transaction.get(adminSettingsRef);
        
        double feePercentage = 0.10;
        if (adminSnap.exists) {
          feePercentage = (adminSnap.get('feePercentage') ?? 0.10).toDouble();
        }

        double feeAmount = totalAmount * feePercentage;
        double netToExpert = totalAmount - feeAmount;

        // 2. עדכון סטטוס העבודה
        transaction.update(firestore.collection('jobs').doc(jobId), {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'feeAmount': feeAmount,
          'netAmountForExpert': netToExpert,
        });

        // 3. העברת כסף למאמן (הנטו)
        transaction.update(firestore.collection('users').doc(expertId), {
          'balance': FieldValue.increment(netToExpert)
        });

        // 4. עדכון יתרת המערכת (העמלה שלך)
        transaction.set(adminSettingsRef, {
          'totalPlatformBalance': FieldValue.increment(feeAmount),
          'lastFinanceUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 5. 🔥 התיקון לבקשתך: תיעוד מפורט עם שמות הלקוח והמומחה
        transaction.set(firestore.collection('platform_earnings').doc(), {
          'jobId': jobId,
          'amount': feeAmount,
          'customerName': customerName,
          'expertName': expertName,
          'description': '$customerName ➔ $expertName', // מה שיוצג בלשונית מערכת
          'timestamp': FieldValue.serverTimestamp(),
        });
      });
      return true;
    } catch (e) {
      debugPrint("QA_FINANCE_ERROR: $e");
      return false;
    }
  }
}