// Motorcycle towing tracking stages — drives the timeline on the live
// tracking screen. Six ordered stages from order confirmation to arrival.
//
// The provider advances through these stages via dedicated buttons in their
// order card. The customer sees a real-time timeline with the current stage
// highlighted.
class MotorcycleTrackingStage {
  /// Stable id — also the value written to `motorcycle_tows/{towId}.status`.
  final String id;
  final String name;
  /// Optional subtitle shown under the stage label.
  final String detail;
  /// Whether this stage is reached by the provider's "advance" button
  /// (true) or set automatically by the system (false).
  final bool providerControlled;

  const MotorcycleTrackingStage({
    required this.id,
    required this.name,
    this.detail = '',
    this.providerControlled = true,
  });
}

const List<MotorcycleTrackingStage> kMotorcycleTrackingStages = [
  MotorcycleTrackingStage(
    id: 'order_confirmed',
    name: 'הזמנה אושרה',
    providerControlled: false,
  ),
  MotorcycleTrackingStage(
    id: 'driver_assigned',
    name: 'הנהג קיבל את הקריאה',
    providerControlled: false,
  ),
  MotorcycleTrackingStage(
    id: 'en_route_pickup',
    name: 'בדרך אל האופנוע',
  ),
  MotorcycleTrackingStage(
    id: 'arrived_pickup',
    name: 'הגעה ובדיקת האופנוע',
    detail: 'תיעוד תמונות "לפני"',
  ),
  MotorcycleTrackingStage(
    id: 'loaded_in_transit',
    name: 'העמסה ויציאה ליעד',
  ),
  MotorcycleTrackingStage(
    id: 'arrived_destination',
    name: 'הגעה ופריקה ביעד',
    detail: 'תיעוד תמונות "אחרי" + תשלום',
  ),
];

/// Returns the index of [stageId] in the canonical sequence, or -1 if unknown.
int motorcycleStageIndex(String stageId) {
  for (var i = 0; i < kMotorcycleTrackingStages.length; i++) {
    if (kMotorcycleTrackingStages[i].id == stageId) return i;
  }
  return -1;
}

MotorcycleTrackingStage? findMotorcycleStage(String id) {
  for (final s in kMotorcycleTrackingStages) {
    if (s.id == id) return s;
  }
  return null;
}
