class MassageAddonDef {
  final String id;
  final String nameHe;
  final String nameEn;
  final String icon;
  final int recommendedPrice;
  final String descriptionHe;
  final String group;

  const MassageAddonDef({
    required this.id,
    required this.nameHe,
    required this.nameEn,
    required this.icon,
    required this.recommendedPrice,
    required this.descriptionHe,
    required this.group,
  });
}

const String kGroupRecommended = 'recommended';
const String kGroupAroma = 'aroma';
const String kGroupTherapeutic = 'therapeutic';
const String kGroupEnriching = 'enriching';

const Map<String, String> kAddonGroupLabels = {
  kGroupRecommended: '⭐ מומלצים',
  kGroupAroma: '🌿 ארומתרפיה ושמנים',
  kGroupTherapeutic: '⚕️ טכניקות טיפוליות',
  kGroupEnriching: '✨ טיפולים מעשירים',
};

const List<MassageAddonDef> kMassageAddonsCatalog = [
  // ⭐ Recommended
  MassageAddonDef(id: 'aromatherapy_oil',    nameHe: 'שמן ארומתרפיה',         nameEn: 'Aromatherapy oil',       icon: '🌸', recommendedPrice: 25, descriptionHe: 'לבנדר, ניאולי, תפוז, מנטה',    group: kGroupRecommended),
  MassageAddonDef(id: 'hot_stones',          nameHe: 'אבנים חמות',            nameEn: 'Hot stones',             icon: '🪨', recommendedPrice: 40, descriptionHe: 'להרפיה עמוקה',                  group: kGroupRecommended),
  MassageAddonDef(id: 'head_massage',        nameHe: 'עיסוי ראש בסיום',       nameEn: 'Head massage finish',    icon: '💆', recommendedPrice: 15, descriptionHe: '10 דקות נוספות',                group: kGroupRecommended),

  // 🌿 Aroma & Oils
  MassageAddonDef(id: 'cbd_oil',             nameHe: 'שמן CBD',               nameEn: 'CBD oil',                icon: '🌱', recommendedPrice: 50, descriptionHe: 'להקלת כאבים ודלקות',            group: kGroupAroma),
  MassageAddonDef(id: 'hot_towels',          nameHe: 'מגבות חמות',            nameEn: 'Hot towels',             icon: '🔥', recommendedPrice: 20, descriptionHe: 'חוויית ספא מלאה',               group: kGroupAroma),

  // ⚕️ Therapeutic
  MassageAddonDef(id: 'cupping',             nameHe: 'כוסות רוח (Cupping)',   nameEn: 'Cupping',                icon: '⚫', recommendedPrice: 35, descriptionHe: 'שחרור עמוק של רקמות',           group: kGroupTherapeutic),
  MassageAddonDef(id: 'theragun',            nameHe: 'Theragun (אקדח עיסוי)', nameEn: 'Theragun',               icon: '🔫', recommendedPrice: 30, descriptionHe: 'טיפול פרקוסיבי',                group: kGroupTherapeutic),
  MassageAddonDef(id: 'cold_compress',       nameHe: 'קומפרסים קרים',         nameEn: 'Cold compress',          icon: '❄️', recommendedPrice: 20, descriptionHe: 'הקלה על דלקות',                 group: kGroupTherapeutic),
  MassageAddonDef(id: 'assisted_stretching', nameHe: 'מתיחות מסייעות',        nameEn: 'Assisted stretching',    icon: '🌿', recommendedPrice: 25, descriptionHe: 'שיפור גמישות',                  group: kGroupTherapeutic),

  // ✨ Enriching
  MassageAddonDef(id: 'scalp_oil_treatment', nameHe: 'טיפול קרקפת בשמן חם',  nameEn: 'Hot oil scalp treatment', icon: '💧', recommendedPrice: 35, descriptionHe: '15 דקות הזנה לשיער',            group: kGroupEnriching),
  MassageAddonDef(id: 'foot_scrub',          nameHe: 'פילינג רגליים',         nameEn: 'Foot scrub',             icon: '🦶', recommendedPrice: 25, descriptionHe: 'מנטה ולימון',                   group: kGroupEnriching),
  MassageAddonDef(id: 'post_nap',            nameHe: '20 דק׳ מנוחה אחרי',    nameEn: '20 min nap',             icon: '😴', recommendedPrice: 20, descriptionHe: 'להישאר על המיטה ולנמנם',        group: kGroupEnriching),
  MassageAddonDef(id: 'face_mask',           nameHe: 'מסכת פנים',             nameEn: 'Face mask',              icon: '🌹', recommendedPrice: 40, descriptionHe: 'בעת העיסוי',                     group: kGroupEnriching),
  MassageAddonDef(id: 'body_scrub',          nameHe: 'פילינג גוף',            nameEn: 'Body scrub',             icon: '💎', recommendedPrice: 45, descriptionHe: 'סוכר + שמני אגוז',              group: kGroupEnriching),
];

MassageAddonDef? findAddon(String id) {
  for (final a in kMassageAddonsCatalog) {
    if (a.id == id) return a;
  }
  return null;
}

List<MassageAddonDef> addonsInGroup(String group) =>
    kMassageAddonsCatalog.where((a) => a.group == group).toList();
