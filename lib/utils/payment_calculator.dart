/// תוצאת חישוב תשלום — immutable
class PaymentResult {
  final double totalAmount;
  final double feePercentage;
  final double feeAmount;      // עמלת הפלטפורמה
  final double netToExpert;    // מה שמגיע למומחה

  const PaymentResult({
    required this.totalAmount,
    required this.feePercentage,
    required this.feeAmount,
    required this.netToExpert,
  });

  @override
  String toString() =>
      'PaymentResult(total=$totalAmount, fee=$feeAmount, net=$netToExpert)';
}

/// מחשב את פיצול התשלום בין מומחה לפלטפורמה.
///
/// [totalAmount]    — הסכום הכולל ששילם הלקוח
/// [feePercentage]  — עמלת הפלטפורמה כ-0..1 (למשל 0.10 = 10%)
///
/// זורק [ArgumentError] אם הקלטים אינם תקינים.
PaymentResult calculatePayment(double totalAmount, double feePercentage) {
  if (totalAmount < 0) {
    throw ArgumentError('totalAmount לא יכול להיות שלילי: $totalAmount');
  }
  if (feePercentage < 0 || feePercentage > 1) {
    throw ArgumentError(
        'feePercentage חייב להיות בין 0 ל-1, קיבלנו: $feePercentage');
  }

  // עיגול ל-2 ספרות עשרוניות למניעת שגיאות floating-point
  final fee = double.parse((totalAmount * feePercentage).toStringAsFixed(2));
  final net = double.parse((totalAmount - fee).toStringAsFixed(2));

  return PaymentResult(
    totalAmount:   totalAmount,
    feePercentage: feePercentage,
    feeAmount:     fee,
    netToExpert:   net,
  );
}

/// בודק אם יתרה מספיקה לביצוע תשלום.
bool hasSufficientBalance(double balance, double requiredAmount) =>
    balance >= requiredAmount;
