import 'package:cloud_firestore/cloud_firestore.dart';

/// Policy labels, deadlines, and penalty calculations for AnySkill bookings.
/// Three levels: flexible | moderate | strict
class CancellationPolicyService {
  static const List<String> kPolicies = ['flexible', 'moderate', 'strict'];

  /// Hours before the appointment that the free-cancel window closes.
  static int freeHours(String policy) {
    switch (policy) {
      case 'moderate': return 24;
      case 'strict':   return 48;
      default:         return 4;  // flexible
    }
  }

  static String label(String policy) {
    switch (policy) {
      case 'flexible': return 'גמישה';
      case 'moderate': return 'בינונית';
      case 'strict':   return 'קפדנית';
      default:         return 'גמישה';
    }
  }

  static String description(String policy) {
    switch (policy) {
      case 'moderate':
        return 'ביטול חינם עד 24 שעות לפני. לאחר מכן: קנס 50%';
      case 'strict':
        return 'ביטול חינם עד 48 שעות לפני. לאחר מכן: קנס 100%';
      default:
        return 'ביטול חינם עד 4 שעות לפני. לאחר מכן: קנס 50%';
    }
  }

  /// Fraction of total amount charged as penalty after the free window.
  static double penaltyFraction(String policy) =>
      policy == 'strict' ? 1.0 : 0.5;

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
