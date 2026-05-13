// Motorcycle equipment + tow technique catalog.
// Provider sets booleans on these via the settings block (§5 of the
// motorcycle CSM spec). The customer profile view shows only the enabled
// ones with a green checkmark.
class MotorcycleEquipmentDef {
  final String id;
  final String name;
  final String description;
  final bool defaultEnabled;

  const MotorcycleEquipmentDef({
    required this.id,
    required this.name,
    required this.description,
    this.defaultEnabled = true,
  });
}

/// Five equipment types matching `motorcycleTowDefaults.js`.
const List<MotorcycleEquipmentDef> kMotorcycleEquipmentCatalog = [
  MotorcycleEquipmentDef(
    id: 'flatbed',
    name: 'משאית פלטה (Flatbed)',
    description: 'השיטה הכי בטוחה — האופנוע מורם לחלוטין מהקרקע',
    defaultEnabled: true,
  ),
  MotorcycleEquipmentDef(
    id: 'wheelCradle',
    name: 'עריסת גלגל קדמי (Wheel Cradle)',
    description: 'לאופנועי ספורט עם פיירינג נמוך',
    defaultEnabled: true,
  ),
  MotorcycleEquipmentDef(
    id: 'softStraps',
    name: 'רצועות בד רכות (Soft Straps)',
    description: 'לא פוגעות בכרום, צבע ופיירינג',
    defaultEnabled: true,
  ),
  MotorcycleEquipmentDef(
    id: 'electricWinch',
    name: 'כננת חשמלית',
    description: 'לאופנועים עם מנוע תקוע או גיר נעול',
    defaultEnabled: true,
  ),
  MotorcycleEquipmentDef(
    id: 'towDolly',
    name: 'דולי עגלה (Tow Dolly)',
    description: 'למרחקים קצרים — גלגל אחורי על הכביש',
    defaultEnabled: false,
  ),
];

MotorcycleEquipmentDef? findEquipmentDef(String id) {
  for (final e in kMotorcycleEquipmentCatalog) {
    if (e.id == id) return e;
  }
  return null;
}
