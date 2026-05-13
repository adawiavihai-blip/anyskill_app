class BabysitterCertificationDef {
  final String id;
  final String type;
  final String labelHe;
  final String emoji;

  const BabysitterCertificationDef({
    required this.id,
    required this.type,
    required this.labelHe,
    required this.emoji,
  });
}

const List<BabysitterCertificationDef> kBabysitterCertifications = [
  BabysitterCertificationDef(
    id: 'first_aid',
    type: 'first_aid',
    labelHe: 'עזרה ראשונה',
    emoji: '🩹',
  ),
  BabysitterCertificationDef(
    id: 'bls',
    type: 'bls',
    labelHe: 'החייאה (BLS)',
    emoji: '❤️‍🩹',
  ),
  BabysitterCertificationDef(
    id: 'childcare_diploma',
    type: 'childcare_diploma',
    labelHe: 'תעודה בטיפול בילדים',
    emoji: '🎓',
  ),
  BabysitterCertificationDef(
    id: 'teaching_cert',
    type: 'teaching_cert',
    labelHe: 'תעודת הוראה',
    emoji: '🏫',
  ),
  BabysitterCertificationDef(
    id: 'special_needs_cert',
    type: 'special_needs_cert',
    labelHe: 'הכשרה לצרכים מיוחדים',
    emoji: '💙',
  ),
  BabysitterCertificationDef(
    id: 'driver_license',
    type: 'driver_license',
    labelHe: 'רישיון נהיגה',
    emoji: '🚗',
  ),
];
