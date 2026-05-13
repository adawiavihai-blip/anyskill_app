// Optional add-ons a customer can add at booking time.
class CleaningAddOnDef {
  final String id;
  final String nameHe;
  final String icon;
  final int defaultPrice;

  const CleaningAddOnDef({
    required this.id,
    required this.nameHe,
    required this.icon,
    required this.defaultPrice,
  });
}

const List<CleaningAddOnDef> kCleaningAddOns = [
  CleaningAddOnDef(
      id: 'oven_inside', nameHe: 'תנור פנימי', icon: '🍽️', defaultPrice: 40),
  CleaningAddOnDef(
      id: 'fridge_inside',
      nameHe: 'מקרר פנימי',
      icon: '🧊',
      defaultPrice: 30),
  CleaningAddOnDef(
      id: 'windows_outside',
      nameHe: 'חלונות חיצוניים',
      icon: '🪟',
      defaultPrice: 60),
  CleaningAddOnDef(
      id: 'sofa_steam',
      nameHe: 'ניקוי ספות בקיטור',
      icon: '🛋️',
      defaultPrice: 120),
];

CleaningAddOnDef? findCleaningAddOn(String id) {
  for (final a in kCleaningAddOns) {
    if (a.id == id) return a;
  }
  return null;
}
