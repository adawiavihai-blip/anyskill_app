import 'dart:ui';

class TreatmentMethodDef {
  final String id;
  final String nameHe;
  final String nameEn;
  final String icon;
  final String descHe;
  final Color bgColor;
  final bool isRecommended;

  const TreatmentMethodDef({
    required this.id,
    required this.nameHe,
    required this.nameEn,
    required this.icon,
    this.descHe = '',
    required this.bgColor,
    this.isRecommended = false,
  });
}

const kTreatmentMethods = <TreatmentMethodDef>[
  TreatmentMethodDef(
    id: 'green',
    nameHe: 'הדברה ירוקה',
    nameEn: 'Green Pest Control',
    icon: '\u{1F33F}',
    descHe: 'בטוח לילדים, חיות ונשים בהריון',
    bgColor: Color(0xFFDCFCE7),
    isRecommended: true,
  ),
  TreatmentMethodDef(
    id: 'regular_spray',
    nameHe: 'ריסוס רגיל',
    nameEn: 'Regular Spray',
    icon: '\u{1F4A8}',
    descHe: 'יעיל לרוב סוגי המזיקים',
    bgColor: Color(0xFFF3F4F6),
  ),
  TreatmentMethodDef(
    id: 'heat_treatment',
    nameHe: 'טיפול בחום',
    nameEn: 'Heat Treatment',
    icon: '\u{1F525}',
    descHe: 'יעיל במיוחד לפשפשים',
    bgColor: Color(0xFFF3F4F6),
  ),
  TreatmentMethodDef(
    id: 'injection_baits',
    nameHe: 'הזרקה ופיתיון',
    nameEn: 'Injection & Baits',
    icon: '\u{1F489}',
    descHe: 'פעולה ממושכת נגד מכרסמים',
    bgColor: Color(0xFFF3F4F6),
  ),
  TreatmentMethodDef(
    id: 'fumigation_anoxia',
    nameHe: 'איוד / אנוקסיה',
    nameEn: 'Fumigation / Anoxia',
    icon: '\u{1F321}',
    descHe: 'למבנים גדולים ומחסנים',
    bgColor: Color(0xFFF3F4F6),
  ),
];

TreatmentMethodDef? findTreatmentMethod(String id) {
  for (final m in kTreatmentMethods) {
    if (m.id == id) return m;
  }
  return null;
}
