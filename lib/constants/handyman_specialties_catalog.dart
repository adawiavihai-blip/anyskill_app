// Handyman specialties catalog — 23 trades the provider can pick from.
// Matches spec docs/ui-specs/Handyman/01_MAIN_PROMPT_HANDYMAN.md Section 3.
import '../models/handyman_profile.dart';

/// 23 canonical handyman specialties with Hebrew names, icons, default
/// prices + durations. These are *defaults* — providers override via the
/// pricing editor in the settings block (`HandymanPricing.customPrices`).
const List<HandymanSpecialty> kHandymanSpecialtiesCatalog = [
  // Most popular 8 — selected by default in the provider form
  HandymanSpecialty(
    id: 'tv_mounting',
    nameHe: 'תליית טלוויזיה',
    icon: '📺',
    basePrice: 180,
    estimatedMinutes: 60,
    popularity: 'hot',
  ),
  HandymanSpecialty(
    id: 'furniture_assembly',
    nameHe: 'הרכבת רהיטים',
    icon: '🪑',
    basePrice: 220,
    estimatedMinutes: 120,
    popularity: 'hot',
  ),
  HandymanSpecialty(
    id: 'plumbing_fix',
    nameHe: 'אינסטלציה קלה',
    icon: '🚿',
    basePrice: 140,
    estimatedMinutes: 90,
    popularity: 'urgent',
  ),
  HandymanSpecialty(
    id: 'electrical_minor',
    nameHe: 'חשמל קל',
    icon: '💡',
    basePrice: 150,
    estimatedMinutes: 60,
    popularity: 'urgent',
  ),
  HandymanSpecialty(
    id: 'painting',
    nameHe: 'צביעה',
    icon: '🎨',
    basePrice: 200,
    estimatedMinutes: 180,
  ),
  HandymanSpecialty(
    id: 'drywall',
    nameHe: 'גבס',
    icon: '🔨',
    basePrice: 95,
    estimatedMinutes: 30,
  ),
  HandymanSpecialty(
    id: 'doors',
    nameHe: 'דלתות',
    icon: '🚪',
    basePrice: 160,
    estimatedMinutes: 60,
  ),
  HandymanSpecialty(
    id: 'furniture_repair',
    nameHe: 'תיקון רהיטים',
    icon: '🔧',
    basePrice: 130,
    estimatedMinutes: 45,
  ),

  // Secondary 15
  HandymanSpecialty(
    id: 'blinds',
    nameHe: 'תריסים',
    icon: '🪟',
    basePrice: 110,
    estimatedMinutes: 45,
  ),
  HandymanSpecialty(
    id: 'tiles',
    nameHe: 'אריחים',
    icon: '🧱',
    basePrice: 180,
    estimatedMinutes: 120,
  ),
  HandymanSpecialty(
    id: 'gardening',
    nameHe: 'גינון קל',
    icon: '🪴',
    basePrice: 140,
    estimatedMinutes: 90,
  ),
  HandymanSpecialty(
    id: 'appliance_install',
    nameHe: 'התקנת מוצרי חשמל',
    icon: '🔌',
    basePrice: 170,
    estimatedMinutes: 60,
  ),
  HandymanSpecialty(
    id: 'shelves',
    nameHe: 'מדפים',
    icon: '🗄️',
    basePrice: 95,
    estimatedMinutes: 30,
  ),
  HandymanSpecialty(
    id: 'silicone',
    nameHe: 'סיליקון וגומיות',
    icon: '🛁',
    basePrice: 85,
    estimatedMinutes: 30,
  ),
  HandymanSpecialty(
    id: 'locks',
    nameHe: 'מנעולים',
    icon: '🔐',
    basePrice: 150,
    estimatedMinutes: 45,
  ),
  HandymanSpecialty(
    id: 'curtains',
    nameHe: 'וילונות',
    icon: '🪟',
    basePrice: 120,
    estimatedMinutes: 45,
  ),
  HandymanSpecialty(
    id: 'light_fixtures',
    nameHe: 'גופי תאורה',
    icon: '💡',
    basePrice: 140,
    estimatedMinutes: 60,
  ),
  HandymanSpecialty(
    id: 'ceiling_fan',
    nameHe: 'מאווררי תקרה',
    icon: '🪭',
    basePrice: 190,
    estimatedMinutes: 75,
  ),
  HandymanSpecialty(
    id: 'bathroom_fix',
    nameHe: 'תיקוני אמבטיה',
    icon: '🚽',
    basePrice: 160,
    estimatedMinutes: 60,
  ),
  HandymanSpecialty(
    id: 'kitchen_fix',
    nameHe: 'תיקוני מטבח',
    icon: '🍳',
    basePrice: 170,
    estimatedMinutes: 75,
  ),
  HandymanSpecialty(
    id: 'picture_hanging',
    nameHe: 'תליית תמונות ומראות',
    icon: '🖼️',
    basePrice: 70,
    estimatedMinutes: 30,
  ),
  HandymanSpecialty(
    id: 'window_fix',
    nameHe: 'תיקון חלונות',
    icon: '🪟',
    basePrice: 150,
    estimatedMinutes: 60,
  ),
  HandymanSpecialty(
    id: 'general',
    nameHe: 'תיקונים כלליים',
    icon: '🛠️',
    basePrice: 150,
    estimatedMinutes: 60,
  ),
];

/// Default initial selection when a provider first enables handyman —
/// the 8 "hot" specialties marked active.
List<HandymanSpecialty> defaultActiveSpecialties() {
  return kHandymanSpecialtiesCatalog
      .take(8)
      .map((s) => s.copyWith(active: true))
      .toList();
}

/// All 23 specialties, all inactive — for the edit form initial render.
List<HandymanSpecialty> allSpecialtiesInactive() {
  return kHandymanSpecialtiesCatalog.map((s) => s.copyWith(active: false)).toList();
}

/// Default maintenance packages (basic / premium / vip) for a new provider.
const List<Map<String, dynamic>> kDefaultMaintenancePackages = [
  {
    'id': 'basic',
    'nameHe': 'בייסיק',
    'visitsPerYear': 2,
    'yearlyPrice': 890.0,
    'enabled': true,
    'activeCustomers': 0,
    'popular': false,
  },
  {
    'id': 'premium',
    'nameHe': 'פרימיום',
    'visitsPerYear': 4,
    'yearlyPrice': 1690.0,
    'enabled': true,
    'activeCustomers': 0,
    'popular': true,
  },
  {
    'id': 'vip',
    'nameHe': 'VIP',
    'visitsPerYear': -1,
    'yearlyPrice': 2990.0,
    'enabled': true,
    'activeCustomers': 0,
    'popular': false,
  },
];

/// Common Israeli cities shown as default chips in the service-area picker.
const List<String> kHandymanDefaultCities = [
  'תל אביב',
  'רמת גן',
  'גבעתיים',
  'הרצליה',
  'חולון',
  'בת ים',
  'פתח תקווה',
  'רעננה',
  'כפר סבא',
  'ראשון לציון',
  'ירושלים',
  'חיפה',
  'באר שבע',
  'אשדוד',
  'נתניה',
];
