import 'dart:ui';

class InstructionDef {
  final String id;
  final String type;
  final String icon;
  final String titleHe;
  final String descHe;
  final String colorName;
  final Color bgStart;
  final Color bgEnd;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final List<String>? durationOptions;

  const InstructionDef({
    required this.id,
    required this.type,
    required this.icon,
    required this.titleHe,
    this.descHe = '',
    required this.colorName,
    required this.bgStart,
    required this.bgEnd,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    this.durationOptions,
  });
}

const kStructuredInstructions = <InstructionDef>[
  InstructionDef(
    id: 'evacuate_home',
    type: 'evacuate_home',
    icon: '\u{1F6AA}',
    titleHe: 'פינוי הבית',
    descHe: 'בני הבית לא יוכלו להיות בבית',
    colorName: 'red',
    bgStart: Color(0xFFFEE2E2),
    bgEnd: Color(0xFFFECACA),
    border: Color(0xFFFCA5A5),
    textPrimary: Color(0xFF991B1B),
    textSecondary: Color(0xFFB91C1C),
    durationOptions: ['2_hours', '4_hours', '8_hours'],
  ),
  InstructionDef(
    id: 'remove_pets',
    type: 'remove_pets',
    icon: '\u{1F415}',
    titleHe: 'הרחקת חיות מחמד',
    descHe: 'כלבים, חתולים, ציפורים',
    colorName: 'orange',
    bgStart: Color(0xFFFEF3C7),
    bgEnd: Color(0xFFFDE68A),
    border: Color(0xFFFBBF24),
    textPrimary: Color(0xFF92400E),
    textSecondary: Color(0xFFB45309),
    durationOptions: ['4_hours', '8_hours', '24_hours'],
  ),
  InstructionDef(
    id: 'no_washing',
    type: 'no_washing',
    icon: '\u{1F4A7}',
    titleHe: 'לא לשטוף את הבית',
    descHe: 'משטחים בהם בוצע טיפול',
    colorName: 'blue',
    bgStart: Color(0xFFDBEAFE),
    bgEnd: Color(0xFFBFDBFE),
    border: Color(0xFF93C5FD),
    textPrimary: Color(0xFF1E3A8A),
    textSecondary: Color(0xFF1E40AF),
    durationOptions: ['3_days', '1_week', '2_weeks'],
  ),
  InstructionDef(
    id: 'ventilation',
    type: 'ventilation',
    icon: '\u{1FA9F}',
    titleHe: 'לאוורר אחרי החזרה',
    descHe: 'לפתוח חלונות בעת חזרה',
    colorName: 'green',
    bgStart: Color(0xFFDCFCE7),
    bgEnd: Color(0xFFBBF7D0),
    border: Color(0xFF86EFAC),
    textPrimary: Color(0xFF14532D),
    textSecondary: Color(0xFF166534),
    durationOptions: ['30_min', '1_hour'],
  ),
  InstructionDef(
    id: 'cover_food',
    type: 'cover_food',
    icon: '\u{1F37D}',
    titleHe: 'לכסות מזון ומים',
    descHe: 'לפני הגעת המדביר',
    colorName: 'grey',
    bgStart: Color(0xFFF3F4F6),
    bgEnd: Color(0xFFE5E7EB),
    border: Color(0xFFD1D5DB),
    textPrimary: Color(0xFF374151),
    textSecondary: Color(0xFF6B7280),
  ),
  InstructionDef(
    id: 'cover_aquarium',
    type: 'cover_aquarium',
    icon: '\u{1F420}',
    titleHe: 'לכסות אקווריומים',
    descHe: 'לכבות משאבת אוויר',
    colorName: 'grey',
    bgStart: Color(0xFFF3F4F6),
    bgEnd: Color(0xFFE5E7EB),
    border: Color(0xFFD1D5DB),
    textPrimary: Color(0xFF374151),
    textSecondary: Color(0xFF6B7280),
  ),
  InstructionDef(
    id: 'remove_ceramics',
    type: 'remove_ceramics',
    icon: '\u{1F9F4}',
    titleHe: 'להוציא חפצי קרמיקה',
    descHe: 'משטחים פתוחים בלבד',
    colorName: 'grey',
    bgStart: Color(0xFFF3F4F6),
    bgEnd: Color(0xFFE5E7EB),
    border: Color(0xFFD1D5DB),
    textPrimary: Color(0xFF374151),
    textSecondary: Color(0xFF6B7280),
  ),
];

const kDurationLabels = <String, Map<String, String>>{
  'evacuate_home': {
    '2_hours': '2 שעות',
    '4_hours': '4 שעות',
    '8_hours': '8 שעות',
  },
  'remove_pets': {
    '4_hours': '4 שעות',
    '8_hours': '8 שעות',
    '24_hours': '24 שעות',
  },
  'no_washing': {
    '3_days': '3 ימים',
    '1_week': 'שבוע',
    '2_weeks': 'שבועיים',
  },
  'ventilation': {
    '30_min': '30 דקות',
    '1_hour': 'שעה',
  },
};

String durationLabel(String type, String? duration) {
  if (duration == null) return '';
  return kDurationLabels[type]?[duration] ?? duration;
}

InstructionDef? findInstruction(String id) {
  for (final i in kStructuredInstructions) {
    if (i.id == id) return i;
  }
  return null;
}
