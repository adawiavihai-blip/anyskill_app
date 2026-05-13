// motorcycleTowDefaults.js
// ערכי ברירת מחדל וקבועים לפיצ'ר גרר אופנועים

export const BIKE_TYPES = [
  {
    id: 'sport',
    name: 'ספורט',
    nameEn: 'Sport',
    defaultImage: 'https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=600&h=450&fit=crop',
  },
  {
    id: 'cruiser',
    name: 'קרוזר',
    nameEn: 'Cruiser',
    defaultImage: 'https://images.unsplash.com/photo-1558981403-c5f9899a28bc?w=600&h=450&fit=crop',
  },
  {
    id: 'adventure',
    name: 'אדוונצ\'ר',
    nameEn: 'Adventure',
    defaultImage: 'https://images.unsplash.com/photo-1599819811279-d5ad9cccf838?w=600&h=450&fit=crop',
  },
  {
    id: 'scooter',
    name: 'קטנוע',
    nameEn: 'Scooter',
    defaultImage: 'https://images.unsplash.com/photo-1591216105232-d23bea36b827?w=600&h=450&fit=crop',
  },
  {
    id: 'offroad',
    name: 'אופנועי שטח',
    nameEn: 'Off-road',
    defaultImage: 'https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=600&h=450&fit=crop',
  },
  {
    id: 'vintage',
    name: 'וינטג\'',
    nameEn: 'Vintage',
    defaultImage: 'https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=600&h=450&fit=crop',
  },
];

export const EQUIPMENT_TYPES = [
  {
    id: 'flatbed',
    name: 'משאית פלטה (Flatbed)',
    description: 'השיטה הכי בטוחה — האופנוע מורם לחלוטין מהקרקע',
    defaultEnabled: true,
  },
  {
    id: 'wheel_cradle',
    name: 'עריסת גלגל קדמי (Wheel Cradle)',
    description: 'לאופנועי ספורט עם פיירינג נמוך',
    defaultEnabled: true,
  },
  {
    id: 'soft_straps',
    name: 'רצועות בד רכות (Soft Straps)',
    description: 'לא פוגעות בכרום, צבע ופיירינג',
    defaultEnabled: true,
  },
  {
    id: 'electric_winch',
    name: 'כננת חשמלית',
    description: 'לאופנועים עם מנוע תקוע או גיר נעול',
    defaultEnabled: true,
  },
  {
    id: 'tow_dolly',
    name: 'דולי עגלה (Tow Dolly)',
    description: 'למרחקים קצרים — גלגל אחורי על הכביש',
    defaultEnabled: false,
  },
];

export const SERVICE_CASES = [
  { id: 'accident', name: 'תאונות דרכים', defaultEnabled: true },
  { id: 'engine_fault', name: 'תקלות מנוע', defaultEnabled: true },
  { id: 'flat_tire', name: 'פנצ\'ר', defaultEnabled: true },
  { id: 'dead_battery', name: 'מצבר מת', defaultEnabled: true },
  { id: 'planned_tow', name: 'גרירה מתוכננת', defaultEnabled: true },
  { id: 'off_terrain_rescue', name: 'חילוץ משטח/בוץ', defaultEnabled: true },
  { id: 'wrong_fuel', name: 'דלק שגוי', defaultEnabled: false },
  { id: 'lockout', name: 'נעילת מפתחות', defaultEnabled: false },
  { id: 'intercity', name: 'העברה בין-עירונית', defaultEnabled: false },
];

export const SMART_FEATURES = [
  {
    id: 'before_after_photos',
    name: 'תמונות "לפני/אחרי" אוטומטיות',
    description: 'המערכת תזכיר לך לצלם בכל גרירה — מגן עליך מפני תלונות',
    defaultEnabled: true,
  },
  {
    id: 'instant_quote',
    name: 'הצעת מחיר מיידית',
    description: 'מחושבת אוטומטית מהמחירים שמילאת למעלה',
    defaultEnabled: true,
  },
  {
    id: 'internal_chat',
    name: 'צ\'אט פנימי עם הלקוח',
    description: 'תקשורת מאובטחת — בלי לחשוף מספר טלפון',
    defaultEnabled: true,
  },
];

export const DEFAULT_PRICING = {
  basePrice: 180,           // ₪
  pricePerKm: 4.5,          // ₪
  nightSurchargePercent: 25,
  nightStartTime: '22:00',
  nightEndTime: '06:00',
  emergencySurchargePercent: 50,
};

export const DEFAULT_SERVICE_AREA = {
  mode: 'radius',           // 'radius' | 'polygon'
  baseAddress: 'פתח תקווה, גוש דן',
  baseCoordinates: { lat: 32.0853, lng: 34.7818 },
  radiusKm: 50,
  polygonPoints: [],        // [[lat, lng], ...]
};

export const URGENCY_LEVELS = [
  { id: 'immediate', name: 'מיד', sub: 'הגעה תוך 22–35 דקות', surchargePercent: 50 },
  { id: 'within_hour', name: 'בשעה הקרובה', sub: 'הגעה תוך 60–90 דקות', surchargePercent: 0 },
  { id: 'today', name: 'במהלך היום', sub: 'בחר חלון שעות', surchargePercent: 0 },
  { id: 'scheduled', name: 'לתכנן ליום אחר', sub: 'בחר תאריך ושעה', surchargePercent: 0 },
];

export const TRACKING_STAGES = [
  { id: 'order_confirmed', name: 'הזמנה אושרה' },
  { id: 'driver_assigned', name: 'הנהג קיבל את הקריאה' },
  { id: 'en_route_pickup', name: 'בדרך אל האופנוע' },
  { id: 'arrived_pickup', name: 'הגעה ובדיקת האופנוע', detail: 'תיעוד תמונות "לפני"' },
  { id: 'loaded_in_transit', name: 'העמסה ויציאה ליעד' },
  { id: 'arrived_destination', name: 'הגעה ופריקה ביעד', detail: 'תיעוד תמונות "אחרי" + תשלום' },
];
