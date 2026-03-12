/// מסנן רשימת מומחים לפי שאילתת שם ו/או מסנן מחיר.
///
/// [query]        — חיפוש חופשי לפי שם (לא רגיש לרישיות, ריק = ללא סינון)
/// [underHundred] — אם true, מסנן רק מומחים עם pricePerHour < 100
List<Map<String, dynamic>> filterExperts(
  List<Map<String, dynamic>> experts, {
  String query = '',
  bool underHundred = false,
}) {
  return experts.where((data) {
    // סינון שם
    if (query.isNotEmpty) {
      final name = (data['name'] ?? '').toString().toLowerCase();
      if (!name.contains(query.toLowerCase())) return false;
    }

    // סינון מחיר
    if (underHundred) {
      final price = (data['pricePerHour'] is num)
          ? (data['pricePerHour'] as num).toDouble()
          : double.tryParse(data['pricePerHour']?.toString() ?? '') ?? 9999.0;
      if (price >= 100) return false;
    }

    return true;
  }).toList();
}
