import 'dart:ui';

class PestTypeDef {
  final String id;
  final String nameHe;
  final String nameEn;
  final String icon;
  final String group;
  final Color bgColor;

  const PestTypeDef({
    required this.id,
    required this.nameHe,
    required this.nameEn,
    required this.icon,
    required this.group,
    required this.bgColor,
  });
}

const kGroupInsects = 'insects';
const kGroupRodents = 'rodents';
const kGroupAnimalCapture = 'animal_capture';

const kPestGroupLabels = {
  kGroupInsects: 'חרקים ומזיקי בית',
  kGroupRodents: 'מכרסמים',
  kGroupAnimalCapture: 'לכידת בעלי חיים',
};

const kPestTypesCatalog = <PestTypeDef>[
  // insects
  PestTypeDef(id: 'cockroaches', nameHe: "ג'וקים", nameEn: 'Cockroaches', icon: '\u{1FAB2}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  PestTypeDef(id: 'ants', nameHe: 'נמלים', nameEn: 'Ants', icon: '\u{1F41C}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  PestTypeDef(id: 'bedbugs', nameHe: 'פשפשים', nameEn: 'Bedbugs', icon: '\u{1F6CF}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  PestTypeDef(id: 'fleas', nameHe: 'פרעושים', nameEn: 'Fleas', icon: '\u{1FAB3}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  PestTypeDef(id: 'mosquitoes', nameHe: 'יתושים', nameEn: 'Mosquitoes', icon: '\u{1F99F}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  PestTypeDef(id: 'flies', nameHe: 'זבובים', nameEn: 'Flies', icon: '\u{1FAB0}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  PestTypeDef(id: 'spiders', nameHe: 'עכבישים', nameEn: 'Spiders', icon: '\u{1F577}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  PestTypeDef(id: 'termites', nameHe: 'טרמיטים', nameEn: 'Termites', icon: '\u{1F41B}', group: kGroupInsects, bgColor: Color(0xFFDCFCE7)),
  // rodents
  PestTypeDef(id: 'rats', nameHe: 'חולדות', nameEn: 'Rats', icon: '\u{1F400}', group: kGroupRodents, bgColor: Color(0xFFFEF3C7)),
  PestTypeDef(id: 'mice', nameHe: 'עכברים', nameEn: 'Mice', icon: '\u{1F42D}', group: kGroupRodents, bgColor: Color(0xFFFEF3C7)),
  PestTypeDef(id: 'moles', nameHe: 'חפרפרת', nameEn: 'Moles', icon: '\u{1F9AB}', group: kGroupRodents, bgColor: Color(0xFFFEF3C7)),
  // animal capture
  PestTypeDef(id: 'snakes', nameHe: 'נחשים', nameEn: 'Snakes', icon: '\u{1F40D}', group: kGroupAnimalCapture, bgColor: Color(0xFFEFF6FF)),
  PestTypeDef(id: 'pigeons', nameHe: 'יונים', nameEn: 'Pigeons', icon: '\u{1F54A}', group: kGroupAnimalCapture, bgColor: Color(0xFFEFF6FF)),
  PestTypeDef(id: 'bats', nameHe: 'עטלפים', nameEn: 'Bats', icon: '\u{1F987}', group: kGroupAnimalCapture, bgColor: Color(0xFFEFF6FF)),
];

PestTypeDef? findPestType(String id) {
  for (final p in kPestTypesCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

List<PestTypeDef> pestTypesInGroup(String group) =>
    kPestTypesCatalog.where((p) => p.group == group).toList();
