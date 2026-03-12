import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentService {
  static Future<void> processPayment({
    required String senderId,
    required String receiverId,
    required double amount,
    required String senderName,
    required String receiverName,
  }) async {
    final db = FirebaseFirestore.instance;
    final adminSettingsRef = db
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings');

    return db.runTransaction((transaction) async {
      DocumentSnapshot adminDoc = await transaction.get(adminSettingsRef);
      double feePercent = (adminDoc.get('feePercentage') ?? 0.10).toDouble();
      double adminFee = amount * feePercent;
      double providerAmount = amount - adminFee;

      DocumentSnapshot senderDoc = await transaction.get(db.collection('users').doc(senderId));
      double currentBalance = (senderDoc.get('balance') ?? 0.0).toDouble();
      if (currentBalance < amount) throw Exception("אין מספיק יתרה");

      transaction.update(db.collection('users').doc(senderId), {'balance': FieldValue.increment(-amount)});
      transaction.update(db.collection('users').doc(receiverId), {'balance': FieldValue.increment(providerAmount)});
      transaction.set(adminSettingsRef, {'totalPlatformBalance': FieldValue.increment(adminFee)}, SetOptions(merge: true));

      transaction.set(db.collection('transactions').doc(), {
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': receiverId,
        'receiverName': receiverName,
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  // הפונקציה ששומרת את הביקורת ומעדכנת את הפרופיל
  static Future<void> submitReview({
    required String expertId,
    required double rating,
    required String comment,
    required String reviewerName,
  }) async {
    final db = FirebaseFirestore.instance;

    // 1. שמירת הביקורת באוסף חדש
    await db.collection('reviews').add({
      'expertId': expertId,
      'rating': rating,
      'comment': comment,
      'reviewerName': reviewerName,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 2. עדכון ממוצע הכוכבים של המומחה
    await db.runTransaction((transaction) async {
      DocumentReference expertRef = db.collection('users').doc(expertId);
      DocumentSnapshot expertDoc = await transaction.get(expertRef);

      double currentRating = (expertDoc.get('rating') ?? 0.0).toDouble();
      int currentReviewCount = expertDoc.get('reviewCount') ?? 0;

      int newReviewCount = currentReviewCount + 1;
      double newRating = ((currentRating * currentReviewCount) + rating) / newReviewCount;

      transaction.update(expertRef, {
        'rating': double.parse(newRating.toStringAsFixed(1)),
        'reviewCount': newReviewCount,
      });
    });
  }
}
