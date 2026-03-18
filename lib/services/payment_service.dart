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
    required String reviewerId,
    required double rating,
    required String comment,
    required String reviewerName,
    List<String> traitTags = const [],
  }) async {
    final db = FirebaseFirestore.instance;

    // 1. שמירת הביקורת עם תגיות תכונה
    await db.collection('reviews').add({
      'expertId':    expertId,
      'reviewerId':  reviewerId,
      'rating':      rating,
      'comment':     comment,
      'reviewerName': reviewerName,
      'traitTags':   traitTags,
      'timestamp':   FieldValue.serverTimestamp(),
    });

    // 2. עדכון ממוצע הכוכבים ומספר הביקורות של המומחה
    await db.runTransaction((transaction) async {
      final expertRef = db.collection('users').doc(expertId);
      final expertDoc = await transaction.get(expertRef);

      final data = expertDoc.data() ?? {};
      final currentRating      = (data['rating'] ?? 0.0).toDouble();
      final currentReviewCount = (data['reviewsCount'] ?? 0) as int;

      final newReviewCount = currentReviewCount + 1;
      final newRating =
          ((currentRating * currentReviewCount) + rating) / newReviewCount;

      transaction.update(expertRef, {
        'rating':       double.parse(newRating.toStringAsFixed(1)),
        'reviewsCount': newReviewCount,
      });
    });
  }
}
