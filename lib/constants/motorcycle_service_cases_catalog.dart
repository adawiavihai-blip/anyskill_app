// Motorcycle service-case catalog.
// Provider picks which call types they handle (multi-select pills);
// customer picks ONE issue when booking (single-select).
class MotorcycleServiceCase {
  final String id;
  final String name;
  /// Single-character or short emoji icon used in the booking flow grid.
  final String emoji;
  final bool defaultEnabled;

  const MotorcycleServiceCase({
    required this.id,
    required this.name,
    required this.emoji,
    this.defaultEnabled = true,
  });
}

/// 9 cases — first 6 default-on (matches mockup), last 3 default-off.
const List<MotorcycleServiceCase> kMotorcycleServiceCasesCatalog = [
  MotorcycleServiceCase(
    id: 'accident',
    name: 'תאונות דרכים',
    emoji: '🚨',
    defaultEnabled: true,
  ),
  MotorcycleServiceCase(
    id: 'engine_fault',
    name: 'תקלות מנוע',
    emoji: '🔧',
    defaultEnabled: true,
  ),
  MotorcycleServiceCase(
    id: 'flat_tire',
    name: 'פנצ\'ר',
    emoji: '🛞',
    defaultEnabled: true,
  ),
  MotorcycleServiceCase(
    id: 'dead_battery',
    name: 'מצבר מת',
    emoji: '🔋',
    defaultEnabled: true,
  ),
  MotorcycleServiceCase(
    id: 'planned_tow',
    name: 'גרירה מתוכננת',
    emoji: '📅',
    defaultEnabled: true,
  ),
  MotorcycleServiceCase(
    id: 'off_terrain_rescue',
    name: 'חילוץ משטח/בוץ',
    emoji: '🏔️',
    defaultEnabled: true,
  ),
  MotorcycleServiceCase(
    id: 'wrong_fuel',
    name: 'דלק שגוי',
    emoji: '⛽',
    defaultEnabled: false,
  ),
  MotorcycleServiceCase(
    id: 'lockout',
    name: 'נעילת מפתחות',
    emoji: '🔑',
    defaultEnabled: false,
  ),
  MotorcycleServiceCase(
    id: 'intercity',
    name: 'העברה בין-עירונית',
    emoji: '🛣️',
    defaultEnabled: false,
  ),
];

/// Default IDs (the 6 that ship enabled). Used as initial state for new
/// providers in the settings block.
List<String> defaultMotorcycleServiceCaseIds() => kMotorcycleServiceCasesCatalog
    .where((c) => c.defaultEnabled)
    .map((c) => c.id)
    .toList();

MotorcycleServiceCase? findServiceCase(String id) {
  for (final c in kMotorcycleServiceCasesCatalog) {
    if (c.id == id) return c;
  }
  return null;
}
