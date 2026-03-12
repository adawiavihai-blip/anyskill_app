/// מעצב ערך מחיר גולמי לתצוגה בממשק.
///
/// קלט: int / double / String / null
/// פלט: "החל מ־{סכום} ₪"
///
/// דוגמאות:
///   formatPriceDisplay(100)    → "החל מ־100 ₪"
///   formatPriceDisplay(100.0)  → "החל מ־100 ₪"   (ללא .0 מיותר)
///   formatPriceDisplay(99.5)   → "החל מ־99.5 ₪"
///   formatPriceDisplay("150")  → "החל מ־150 ₪"
///   formatPriceDisplay(null)   → "החל מ־0 ₪"
///   formatPriceDisplay(0)      → "החל מ־0 ₪"
String formatPriceDisplay(dynamic rawPrice) {
  if (rawPrice == null) return 'החל מ־0 ₪';

  String amount;

  if (rawPrice is double) {
    // 100.0 → "100" | 99.5 → "99.5"
    amount = (rawPrice == rawPrice.truncateToDouble())
        ? rawPrice.toInt().toString()
        : rawPrice.toString();
  } else {
    final s = rawPrice.toString().trim();
    amount = s.isEmpty ? '0' : s;
  }

  return 'החל מ־$amount ₪';
}
