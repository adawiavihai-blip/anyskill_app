import 'package:geolocator/geolocator.dart';

/// מסנן רשימת מומחים לפי שאילתת שם, מחיר, דירוג, ורדיוס מיקום.
///
/// [query]          — חיפוש חופשי לפי שם (לא רגיש לרישיות, ריק = ללא סינון)
/// [underHundred]   — אם true, מסנן רק מומחים עם pricePerHour < 100
/// [minRating]      — דירוג מינימלי (0 = ללא סינון)
/// [maxPricePerHour]— מחיר מקסימלי (null = ללא הגבלה)
/// [maxDistanceKm]  — רדיוס מקסימלי בק"מ (null = ללא הגבלה)
/// [myPosition]     — המיקום הנוכחי של הלקוח (נדרש אם maxDistanceKm != null)
/// [onlineOnly]     — (v12.9.0) אם true, מציג רק מומחים עם `isOnline == true`
List<Map<String, dynamic>> filterExperts(
  List<Map<String, dynamic>> experts, {
  String query = '',
  bool underHundred = false,
  double minRating = 0,
  double? maxPricePerHour,
  double? maxDistanceKm,
  Position? myPosition,
  bool onlineOnly = false,
}) {
  return experts.where((data) {
    // סינון שם
    if (query.isNotEmpty) {
      final name = (data['name'] ?? '').toString().toLowerCase();
      if (!name.contains(query.toLowerCase())) return false;
    }

    // סינון מחיר (מתחת ל-100)
    final price = (data['pricePerHour'] is num)
        ? (data['pricePerHour'] as num).toDouble()
        : double.tryParse(data['pricePerHour']?.toString() ?? '') ?? 9999.0;
    if (underHundred && price >= 100) return false;

    // סינון מחיר מקסימלי (slider)
    if (maxPricePerHour != null && price > maxPricePerHour) return false;

    // סינון דירוג מינימלי
    if (minRating > 0) {
      final rating = (data['rating'] is num)
          ? (data['rating'] as num).toDouble()
          : double.tryParse(data['rating']?.toString() ?? '') ?? 0.0;
      if (rating < minRating) return false;
    }

    // סינון רדיוס מיקום
    if (maxDistanceKm != null && myPosition != null) {
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        final distMeters = Geolocator.distanceBetween(
          myPosition.latitude, myPosition.longitude, lat, lng,
        );
        if (distMeters > maxDistanceKm * 1000) return false;
      }
      // If provider has no location, don't filter them out — they just won't
      // benefit from the proximity sort.
    }

    // Online-only filter (v12.9.0)
    if (onlineOnly && data['isOnline'] != true) return false;

    return true;
  }).toList();
}
