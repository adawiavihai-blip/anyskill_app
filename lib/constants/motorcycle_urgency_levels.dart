// Motorcycle towing urgency levels — drives the Step 4 picker in the
// booking block. The 'immediate' level triggers the emergency surcharge
// configured by the provider (default +50%).
class MotorcycleUrgencyLevel {
  final String id;
  final String name;
  /// Short subtitle shown in the picker card.
  final String sub;
  /// Surcharge applied as a percentage of the (subtotal + nightSurcharge).
  /// Only 'immediate' has a non-zero value in this catalog — providers can
  /// override the percentage in their pricing config.
  final double surchargePercent;

  const MotorcycleUrgencyLevel({
    required this.id,
    required this.name,
    required this.sub,
    this.surchargePercent = 0,
  });
}

const List<MotorcycleUrgencyLevel> kMotorcycleUrgencyLevels = [
  MotorcycleUrgencyLevel(
    id: 'immediate',
    name: 'מיד',
    sub: 'הגעה תוך 22–35 דקות',
    surchargePercent: 50,
  ),
  MotorcycleUrgencyLevel(
    id: 'within_hour',
    name: 'בשעה הקרובה',
    sub: 'הגעה תוך 60–90 דקות',
  ),
  MotorcycleUrgencyLevel(
    id: 'today',
    name: 'במהלך היום',
    sub: 'בחר חלון שעות',
  ),
  MotorcycleUrgencyLevel(
    id: 'scheduled',
    name: 'לתכנן ליום אחר',
    sub: 'בחר תאריך ושעה',
  ),
];

MotorcycleUrgencyLevel? findUrgencyLevel(String id) {
  for (final u in kMotorcycleUrgencyLevels) {
    if (u.id == id) return u;
  }
  return null;
}
