/// Delivery CSM — the 5 built-in structured rules (plus free-text custom).
class CourierRuleDef {
  final String id;
  final String type;
  final String icon;
  final String titleHe;
  final String descHe;
  final String colorName; // red | amber | blue | grey

  const CourierRuleDef({
    required this.id,
    required this.type,
    required this.icon,
    required this.titleHe,
    required this.descHe,
    required this.colorName,
  });
}

const kCourierRules = <CourierRuleDef>[
  CourierRuleDef(
    id: 'no_dangerous',
    type: 'no_dangerous',
    icon: '🚫',
    titleHe: 'לא אקח חבילות מסוכנות',
    descHe: 'חומרים דליקים או מסוכנים',
    colorName: 'red',
  ),
  CourierRuleDef(
    id: 'photo_documentation',
    type: 'photo_documentation',
    icon: '📷',
    titleHe: 'תיעוד תמונה בכל משלוח',
    descHe: 'תמונה באיסוף + מסירה (אוטומטי)',
    colorName: 'amber',
  ),
  CourierRuleDef(
    id: 'call_before_arrival',
    type: 'call_before_arrival',
    icon: '📱',
    titleHe: 'התקשרות לפני הגעה',
    descHe: "תמיד אצלצל 5 דק' לפני",
    colorName: 'blue',
  ),
  CourierRuleDef(
    id: 'weight_verification',
    type: 'weight_verification',
    icon: '⚖️',
    titleHe: 'שקילה לאישור משקל',
    descHe: 'אם משקל לא תואם הצהרה',
    colorName: 'grey',
  ),
  CourierRuleDef(
    id: 'rain_delivery',
    type: 'rain_delivery',
    icon: '🌧️',
    titleHe: 'משלוח גם בגשם',
    descHe: 'בעטיפת ניילון בלבד',
    colorName: 'grey',
  ),
];

CourierRuleDef? findCourierRule(String id) {
  try {
    return kCourierRules.firstWhere((r) => r.id == id);
  } catch (_) {
    return null;
  }
}
