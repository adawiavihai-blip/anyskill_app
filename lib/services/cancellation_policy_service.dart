import 'package:cloud_firestore/cloud_firestore.dart';

/// Policy labels, deadlines, and penalty calculations for AnySkill bookings.
/// Four levels: flexible | moderate | strict | nonRefundable
class CancellationPolicyService {
  static const List<String> kPolicies = [
    'flexible',
    'moderate',
    'strict',
    'nonRefundable',
  ];

  /// Hours before the appointment that the free-cancel window closes.
  /// `nonRefundable` returns 0 — there is never a free-cancel window.
  static int freeHours(String policy) {
    switch (policy) {
      case 'moderate':      return 24;
      case 'strict':        return 48;
      case 'nonRefundable': return 0;
      default:              return 4;  // flexible
    }
  }

  static String label(String policy) {
    switch (policy) {
      case 'flexible':      return 'גמישה';
      case 'moderate':      return 'בינונית';
      case 'strict':        return 'קפדנית';
      case 'nonRefundable': return 'ללא החזר';
      default:              return 'גמישה';
    }
  }

  static String description(String policy) {
    switch (policy) {
      case 'moderate':
        return 'ביטול חינם עד 24 שעות לפני. לאחר מכן: קנס 50%';
      case 'strict':
        return 'ביטול חינם עד 48 שעות לפני. לאחר מכן: קנס 100%';
      case 'nonRefundable':
        return 'ללא החזר כסף — שירותי חירום, קנס 100% בכל מקרה של ביטול';
      default:
        return 'ביטול חינם עד 4 שעות לפני. לאחר מכן: קנס 50%';
    }
  }

  /// Fraction of total amount charged as penalty after the free window.
  /// `nonRefundable` and `strict` both charge the full amount.
  static double penaltyFraction(String policy) =>
      (policy == 'strict' || policy == 'nonRefundable') ? 1.0 : 0.5;

  /// Calculates the deadline DateTime from appointment date + time slot.
  /// [timeSlot] is expected in "HH:MM" format (e.g. "14:00").
  /// Returns null if [appointmentDate] is null.
  static DateTime? deadline({
    required String policy,
    required DateTime? appointmentDate,
    required String? timeSlot,
  }) {
    if (appointmentDate == null) return null;
    int h = 0, m = 0;
    if (timeSlot != null && timeSlot.contains(':')) {
      final parts = timeSlot.split(':');
      h = int.tryParse(parts[0]) ?? 0;
      m = int.tryParse(parts[1]) ?? 0;
    }
    final apptDt = DateTime(
        appointmentDate.year, appointmentDate.month, appointmentDate.day, h, m);
    return apptDt.subtract(Duration(hours: freeHours(policy)));
  }

  /// Suggests a sensible default cancellation policy for a sub-category
  /// based on its name + parent name. Used by:
  ///   * The schema migration service when generating default schemas.
  ///   * The provider edit form to pre-select the policy on first save.
  ///
  /// Mapping logic:
  ///   * **Emergency** (locksmith, towing) → `nonRefundable`
  ///   * **High-ticket events** (events, photography, design) → `strict`
  ///   * **Scheduled professional** (repairs, lessons, beauty) → `moderate`
  ///   * **Recurring/casual** (cleaning, fitness) → `flexible`
  ///   * Default → `flexible`
  static String defaultPolicyForSubcategory({
    required String parentName,
    required String subName,
  }) {
    final hay = '${parentName.toLowerCase()} ${subName.toLowerCase()}';
    bool any(List<String> keys) =>
        keys.any((k) => hay.contains(k.toLowerCase()));

    if (any(['מנעולן', 'גרירה', 'תקר', 'פנצ\'ר', 'סוללת', 'גרר', 'חירום', 'locksmith', 'towing'])) {
      return 'nonRefundable';
    }
    if (any(['אירוע', 'הפק', 'קייטרינ', 'dj', 'בלונ', 'מתנפח', 'event',
             'צילום', 'פורטרט', 'חתונ', 'וידאו', 'photo', 'video',
             'עיצוב', 'לוגו', 'מיתוג', 'design', 'logo', 'branding'])) {
      return 'strict';
    }
    if (any(['חשמל', 'אינסטלצ', 'נגרות', 'שיפוץ', 'צביעה', 'ריצוף', 'גבס',
             'מיזוג', 'תחזוק', 'תיקונ', 'הדברה', 'מדביר',
             'שיעור', 'מתמטיק', 'אנגלית', 'תכנות', 'מוזיק', 'הכנה',
             'איפור', 'מספר', 'קוסמט', 'עיסוי', 'ספא',
             'handyman', 'repair', 'plumber', 'electrician', 'lesson', 'tutoring'])) {
      return 'moderate';
    }
    if (any(['ניקיון', 'ניקוי', 'מנקה', 'cleaning',
             'כושר', 'אימון', 'יוגה', 'פילאטיס', 'ריצה', 'תזונה', 'מאמן',
             'fitness', 'coaching', 'yoga'])) {
      return 'flexible';
    }
    return 'flexible';
  }

  /// Returns the penalty amount (₪) for a stored job map.
  /// Reads [cancellationPolicy] and [cancellationDeadline] Firestore fields.
  /// Returns 0.0 if within free window or deadline is unknown.
  static double penaltyAmountFor(Map<String, dynamic> job) {
    final policy  = job['cancellationPolicy'] as String? ?? 'flexible';
    final total   = (job['totalAmount']       as num?    ?? 0).toDouble();
    final dlTs    = job['cancellationDeadline'] as Timestamp?;
    if (dlTs == null) return 0.0;
    return DateTime.now().isAfter(dlTs.toDate())
        ? total * penaltyFraction(policy)
        : 0.0;
  }
}
