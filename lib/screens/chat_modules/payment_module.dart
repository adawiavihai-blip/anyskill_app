import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PaymentModule {
  // ── Cancel booking: refund full amount to customer ───────────────────────
  static Future<bool> cancelEscrow({
    required String jobId,
    required String customerId,
    required double totalAmount,
    String chatRoomId = '',
    FirebaseFirestore? db,
  }) async {
    final firestore = db ?? FirebaseFirestore.instance;
    try {
      await firestore.runTransaction((tx) async {
        tx.update(firestore.collection('jobs').doc(jobId), {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
        tx.update(firestore.collection('users').doc(customerId), {
          'balance': FieldValue.increment(totalAmount),
        });
        tx.set(firestore.collection('transactions').doc(), {
          'userId': customerId,
          'amount': totalAmount,
          'title': 'ביטול הזמנה — החזר כספי',
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'refund',
          'jobId': jobId,
        });
      });

      if (chatRoomId.isNotEmpty) {
        await firestore
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId': 'system',
          'message': '❌ ההזמנה בוטלה. הסכום הוחזר לארנק הלקוח.',
          'type': 'text',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      return true;
    } catch (e) {
      debugPrint("cancelEscrow error: $e");
      return false;
    }
  }

  // ── Refund after dispute: admin resolves in customer's favour ────────────
  static Future<bool> refundDisputedJob({
    required String jobId,
    required String customerId,
    required double totalAmount,
    FirebaseFirestore? db,
  }) async {
    final firestore = db ?? FirebaseFirestore.instance;
    try {
      await firestore.runTransaction((tx) async {
        tx.update(firestore.collection('jobs').doc(jobId), {
          'status': 'refunded',
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': 'admin',
          'resolution': 'refund',
        });
        tx.update(firestore.collection('users').doc(customerId), {
          'balance': FieldValue.increment(totalAmount),
        });
        tx.set(firestore.collection('transactions').doc(), {
          'userId': customerId,
          'amount': totalAmount,
          'title': 'החזר כספי — מחלוקת נפתרה לטובתך',
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'refund',
          'jobId': jobId,
        });
      });
      return true;
    } catch (e) {
      debugPrint("refundDisputedJob error: $e");
      return false;
    }
  }

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

        // 6. תיעוד עסקה בהיסטוריית הרווחים של המומחה
        transaction.set(firestore.collection('transactions').doc(), {
          'userId': expertId,
          'amount': netToExpert,
          'title': 'קיבלת תשלום — $customerName',
          'type': 'earning',
          'clientName': customerName,
          'jobId': jobId,
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