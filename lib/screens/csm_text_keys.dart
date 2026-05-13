// Registry of editable CSM text keys.
//
// Stage 1 (CLAUDE.md §54-area, 2026-04-29): only "title-level" strings —
// section headers, hero labels, banners. Each entry = one editable string
// in the admin's "CSM 🔧" tab.
//
// Adding a new editable string:
//   1. Pick (or extend) a CsmTextKey here with a stable [id].
//   2. In the matching settings block, replace the hardcoded literal with
//      `CsmTextOverrideService.instance.t(csmId, id, fallback)` (or the
//      block's local `_t(id, fallback)` helper).
//   3. The fallback MUST equal the original literal — overrides only apply
//      when an admin has explicitly written to Firestore.
//
// `id` becomes the Firestore field name on `csm_text_overrides/{csmId}`.
// Keep ids dotted + ASCII so Firestore is happy.

class CsmTextKey {
  /// `csmId` — `fitness_trainer`, `massage`, etc. Matches the doc id under
  /// `csm_text_overrides/{csmId}`.
  final String csmId;

  /// Stable identifier for the string. Becomes the Firestore field name.
  final String id;

  /// Original Hebrew literal — shown as placeholder + used as fallback.
  final String defaultValue;

  /// Hebrew label rendered above the TextField in the admin editor.
  final String label;

  /// Section grouping in the admin editor (e.g. "כותרות מקטעים", "באנרים").
  final String group;

  /// Optional hint shown under the label so the admin knows what's affected.
  final String? hint;

  /// `true` for multi-line strings (banner copy etc.). Renders a TextField
  /// with `maxLines: null`.
  final bool multiline;

  const CsmTextKey({
    required this.csmId,
    required this.id,
    required this.defaultValue,
    required this.label,
    required this.group,
    this.hint,
    this.multiline = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Fitness Trainer (CLAUDE.md §44) — 17 keys.
// ─────────────────────────────────────────────────────────────────────────────

const String kCsmFitnessTrainer = 'fitness_trainer';

const List<CsmTextKey> kFitnessTrainerTextKeys = [
  // ── Hero ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'hero.title',
    defaultValue: 'ההגדרות שלך',
    label: 'כותרת ראשית (Hero)',
    group: 'Hero',
  ),
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'hero.subtitle',
    defaultValue: '9 סקציות לבניית פרופיל מנצח — כל פריט עריך',
    label: 'תת-כותרת (Hero)',
    group: 'Hero',
  ),

  // ── Section: Specialties ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'specialties.title',
    defaultValue: 'תחומי התמחות',
    label: 'כותרת — תחומי התמחות',
    group: 'כותרות מקטעים',
  ),

  // ── Section: Pricing ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'pricing.title',
    defaultValue: 'חבילות ומחירים',
    label: 'כותרת — חבילות ומחירים',
    group: 'כותרות מקטעים',
  ),
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'pricing.subtitle',
    defaultValue: 'הוסיפי חבילות ומנויים',
    label: 'תת-כותרת — חבילות',
    group: 'כותרות מקטעים',
  ),

  // ── Section: Locations ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'locations.title',
    defaultValue: 'איפה את מאמנת',
    label: 'כותרת — מיקומי אימון',
    group: 'כותרות מקטעים',
  ),
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'locations.subtitle',
    defaultValue: '3 אפשרויות: בית / פארק / חדר כושר',
    label: 'תת-כותרת — מיקומי אימון',
    group: 'כותרות מקטעים',
  ),

  // ── Section: Certifications ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'certs.title',
    defaultValue: 'תעודות והסמכות',
    label: 'כותרת — תעודות',
    group: 'כותרות מקטעים',
  ),
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'certs.subtitle',
    defaultValue: 'NASM, Wingate, ACSM, ISSA ועוד',
    label: 'תת-כותרת — תעודות',
    group: 'כותרות מקטעים',
  ),

  // ── Section: Stories ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'stories.title',
    defaultValue: 'סיפורי הצלחה',
    label: 'כותרת — סיפורי הצלחה',
    group: 'כותרות מקטעים',
  ),
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'stories.subtitle',
    defaultValue: 'תמונות לפני/אחרי עם אישור הלקוח',
    label: 'תת-כותרת — סיפורי הצלחה',
    group: 'כותרות מקטעים',
  ),

  // ── Section: Offers ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'offers.title',
    defaultValue: 'מבצעים והטבות',
    label: 'כותרת — מבצעים',
    group: 'כותרות מקטעים',
  ),
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'offers.subtitle',
    defaultValue: 'מגדיל פניות פי 3',
    label: 'תת-כותרת — מבצעים',
    group: 'כותרות מקטעים',
  ),

  // ── Section: Dashboard ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'dashboard.title',
    defaultValue: '📊 לוח ביצועים',
    label: 'כותרת — לוח ביצועים',
    group: 'כותרות מקטעים',
  ),

  // ── Section: AI Suggestions ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'aiSuggestions.title',
    defaultValue: 'הצעות חכמות מה-AI',
    label: 'כותרת — הצעות AI',
    group: 'כותרות מקטעים',
  ),
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'aiSuggestions.applyButton',
    defaultValue: '✨ החילי הכל אוטומטית',
    label: 'כפתור החלת הצעות AI',
    group: 'כפתורים',
  ),

  // ── Calendar banner ──
  CsmTextKey(
    csmId: kCsmFitnessTrainer,
    id: 'calendarBanner.text',
    defaultValue: 'שעות פעילות נקבעות דרך היומן — פתח/י את לוח המשימות שלך',
    label: 'באנר יומן (תחתית)',
    group: 'באנרים',
    multiline: true,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Babysitter (CLAUDE.md §53) — 15 keys.
// ─────────────────────────────────────────────────────────────────────────────

const String kCsmBabysitter = 'babysitter';

const List<CsmTextKey> kBabysitterTextKeys = [
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'hero.title',
      defaultValue: 'בייביסיטר — ההגדרות שלך',
      label: 'כותרת ראשית (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'hero.subtitle',
      defaultValue:
          'תעריפים, ניסיון, אזורי שירות וחיוב חכם על איחור הורים',
      label: 'תת-כותרת (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'experience.title',
      defaultValue: '🌟 ניסיון',
      label: 'כותרת — ניסיון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'ageGroups.title',
      defaultValue: '👶 גילאים שאני מטפלת בהם',
      label: 'כותרת — גילאים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'services.title',
      defaultValue: '🤲 שירותים נוספים שאני מציעה',
      label: 'כותרת — שירותים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'certifications.title',
      defaultValue: '🎓 תעודות והכשרות',
      label: 'כותרת — תעודות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'pricing.title',
      defaultValue: '💰 חיוב חכם — תעריפי שעה',
      label: 'כותרת — תעריפי שעה',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'nightSurcharge.title',
      defaultValue: '🌙 תוספת לילה',
      label: 'כותרת — תוספת לילה',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'holidaySurcharge.title',
      defaultValue: '🎉 תוספת חג',
      label: 'כותרת — תוספת חג',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'lateFee.title',
      defaultValue: '⏰ קנס איחור',
      label: 'כותרת — קנס איחור',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'overnightFlat.title',
      defaultValue: '🌃 תעריף לילה (Flat)',
      label: 'כותרת — תעריף לילה (Flat)',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'lastMinute.title',
      defaultValue: '⚡ הזמנה ברגע האחרון',
      label: 'כותרת — הזמנה ברגע אחרון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'availability.title',
      defaultValue: '📅 ימי זמינות',
      label: 'כותרת — זמינות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'serviceArea.title',
      defaultValue: '📍 אזור שירות',
      label: 'כותרת — אזור שירות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'arrivalRadius.title',
      defaultValue: '🎯 רדיוס הגעה ל-GPS',
      label: 'כותרת — רדיוס GPS',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'trust.title',
      defaultValue: '🛡️ אמון',
      label: 'כותרת — אמון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmBabysitter,
      id: 'introNote.title',
      defaultValue: '💌 הודעה אישית להורים',
      label: 'כותרת — הודעה להורים',
      group: 'כותרות מקטעים'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Pest Control (CLAUDE.md §32) — 19 keys.
// ─────────────────────────────────────────────────────────────────────────────

const String kCsmPestControl = 'pest_control';

const List<CsmTextKey> kPestControlTextKeys = [
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'hero.title',
      defaultValue: 'הגדרות ייעודיות להדברה',
      label: 'כותרת ראשית (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'hero.subtitle',
      defaultValue:
          'הלקוחות יראו רק את מה שתסמן כאן · רישיון משרד הגנ"ס נדרש',
      label: 'תת-כותרת (Hero)',
      group: 'Hero',
      multiline: true),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'licenses.title',
      defaultValue: 'רישיונות חובה',
      label: 'כותרת — רישיונות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'licenses.subtitle',
      defaultValue: 'חובה לפי חוק - אימות נדרש',
      label: 'תת-כותרת — רישיונות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'pestTypes.title',
      defaultValue: 'סוגי מזיקים שאני מטפל',
      label: 'כותרת — סוגי מזיקים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'methods.title',
      defaultValue: 'שיטות הטיפול שלי',
      label: 'כותרת — שיטות טיפול',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'methods.subtitle',
      defaultValue: 'בחר לפחות שיטה אחת',
      label: 'תת-כותרת — שיטות טיפול',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'availability.title',
      defaultValue: 'זמינות ותגובה',
      label: 'כותרת — זמינות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'availability.subtitle',
      defaultValue: 'חירום = +35% הזמנות',
      label: 'תת-כותרת — זמינות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'pricing.title',
      defaultValue: 'מחירון שקוף',
      label: 'כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'pricing.subtitle',
      defaultValue: 'לקוחות סומכים על מחיר ברור',
      label: 'תת-כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'warranty.title',
      defaultValue: 'אחריות ושירות',
      label: 'כותרת — אחריות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'warranty.subtitle',
      defaultValue: 'מבדיל בינך לבין מתחרים',
      label: 'תת-כותרת — אחריות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'packages.title',
      defaultValue: 'חבילות תחזוקה',
      label: 'כותרת — חבילות תחזוקה',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'packages.subtitle',
      defaultValue: 'הכנסה קבועה · לקוחות חוזרים',
      label: 'תת-כותרת — חבילות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'instructions.title',
      defaultValue: 'הוראות והתנהלות לאחר טיפול',
      label: 'כותרת — הוראות לאחר טיפול',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmPestControl,
      id: 'instructions.subtitle',
      defaultValue: 'מתורגם אוטומטית ללקוחות',
      label: 'תת-כותרת — הוראות',
      group: 'כותרות מקטעים'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Cleaning (CLAUDE.md §34) — 20 keys.
// ─────────────────────────────────────────────────────────────────────────────

const String kCsmCleaning = 'cleaning';

const List<CsmTextKey> kCleaningTextKeys = [
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'hero.title',
      defaultValue: 'המקצועיות שלך',
      label: 'כותרת ראשית (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'hero.subtitle',
      defaultValue: 'הגדרות שיביאו לך לקוחות בכל החודש',
      label: 'תת-כותרת (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'verifications.title',
      defaultValue: 'אימותים',
      label: 'כותרת — אימותים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'verifications.subtitle',
      defaultValue: 'חובה - אימות נדרש לאישור הפרופיל',
      label: 'תת-כותרת — אימותים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'cleaningTypes.title',
      defaultValue: 'סוגי נקיון שאני מבצעת',
      label: 'כותרת — סוגי נקיון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'cleaningTypes.subtitle',
      defaultValue: 'בחרי את הסוגים - רק הם יוצגו ללקוחות',
      label: 'תת-כותרת — סוגי נקיון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'customerTypes.title',
      defaultValue: 'סוגי לקוחות',
      label: 'כותרת — סוגי לקוחות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'customerTypes.subtitle',
      defaultValue: 'מי רלוונטי עבורך?',
      label: 'תת-כותרת — סוגי לקוחות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'eco.title',
      defaultValue: 'Eco-Friendly Mode',
      label: 'כותרת — Eco Mode',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'eco.subtitle',
      defaultValue: '⭐ 78% מהלקוחות בוחרים בעדיפות',
      label: 'תת-כותרת — Eco Mode',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'checklist.title',
      defaultValue: 'Checklist בסיסי שלך',
      label: 'כותרת — Checklist',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'checklist.subtitle',
      defaultValue: '⭐ הלקוחות יוכלו להוסיף/להוריד לעצמם לפי הצורך',
      label: 'תת-כותרת — Checklist',
      group: 'כותרות מקטעים',
      multiline: true),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'pricing.title',
      defaultValue: 'מחירון לפי גודל הבית',
      label: 'כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'pricing.subtitle',
      defaultValue: 'המערכת תחשב אוטומטית ללקוח',
      label: 'תת-כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'discounts.title',
      defaultValue: 'מנוי קבוע - הנחות',
      label: 'כותרת — הנחות מנוי',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'discounts.subtitle',
      defaultValue: '⭐ הכנסה צפויה לאורך זמן',
      label: 'תת-כותרת — הנחות מנוי',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'serviceArea.title',
      defaultValue: 'אזורי שירות וזמינות',
      label: 'כותרת — אזורי שירות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'serviceArea.subtitle',
      defaultValue: 'היכן ובאילו שעות את עובדת',
      label: 'תת-כותרת — אזורי שירות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'businessPackages.title',
      defaultValue: 'חבילות לעסקים',
      label: 'כותרת — חבילות לעסקים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmCleaning,
      id: 'businessPackages.subtitle',
      defaultValue: 'מנוי חודשי · משרדים, חנויות · הכנסה קבועה',
      label: 'תת-כותרת — חבילות לעסקים',
      group: 'כותרות מקטעים',
      multiline: true),
];

// ─────────────────────────────────────────────────────────────────────────────
// Handyman (CLAUDE.md §41) — 18 keys.
// ─────────────────────────────────────────────────────────────────────────────

const String kCsmHandyman = 'handyman';

const List<CsmTextKey> kHandymanTextKeys = [
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'hero.title',
      defaultValue: 'ההגדרות שלך',
      label: 'כותרת ראשית (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'hero.subtitle',
      defaultValue: 'ככל שתגדיר יותר טוב — יותר לקוחות ימצאו אותך',
      label: 'תת-כותרת (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'verifications.title',
      defaultValue: 'אימותים (חובה)',
      label: 'כותרת — אימותים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'verifications.subtitle',
      defaultValue: 'חובה לאישור פרופיל — מוכיח ללקוחות שאפשר לסמוך עליך',
      label: 'תת-כותרת — אימותים',
      group: 'כותרות מקטעים',
      multiline: true),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'aiPhoto.title',
      defaultValue: 'AI Photo-to-Quote',
      label: 'כותרת — AI Photo',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'aiPhoto.subtitle',
      defaultValue: '⭐ פרופיל עם AI = +40% הזמנות',
      label: 'תת-כותרת — AI Photo',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'specialties.title',
      defaultValue: 'תחומי ההתמחות שלך',
      label: 'כותרת — תחומי התמחות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'pricing.title',
      defaultValue: 'מחירון חכם לפי עבודה',
      label: 'כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'pricing.subtitle',
      defaultValue: 'AI משווה למחירי שוק תל אביב',
      label: 'תת-כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'punchList.title',
      defaultValue: 'Punch List Discount',
      label: 'כותרת — Punch List',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'punchList.subtitle',
      defaultValue: 'עוד עבודות בביקור = יותר הנחה',
      label: 'תת-כותרת — Punch List',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'serviceArea.title',
      defaultValue: 'אזורי שירות',
      label: 'כותרת — אזורי שירות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'serviceArea.subtitle',
      defaultValue: 'איפה אתה עובד',
      label: 'תת-כותרת — אזורי שירות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'materials.title',
      defaultValue: 'ניהול חומרים וציוד',
      label: 'כותרת — חומרים וציוד',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'materials.subtitle',
      defaultValue: 'שקיפות = יותר לקוחות סומכים עליך',
      label: 'תת-כותרת — חומרים וציוד',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'maintenance.title',
      defaultValue: 'חוזי תחזוקה שנתיים',
      label: 'כותרת — חוזי תחזוקה',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmHandyman,
      id: 'maintenance.subtitle',
      defaultValue: 'הכנסה קבועה',
      label: 'תת-כותרת — חוזי תחזוקה',
      group: 'כותרות מקטעים'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Massage (CLAUDE.md §3d) — 13 keys.
// ─────────────────────────────────────────────────────────────────────────────

const String kCsmMassage = 'massage';

const List<CsmTextKey> kMassageTextKeys = [
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'hero.title',
      defaultValue: 'הגדרות ייעודיות לעיסוי',
      label: 'כותרת ראשית (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'hero.subtitle',
      defaultValue: 'הלקוחות יראו רק את מה שתסמני כאן',
      label: 'תת-כותרת (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'specialties.title',
      defaultValue: 'סוגי טיפולים שאני מציעה',
      label: 'כותרת — סוגי טיפולים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'specialties.subtitle',
      defaultValue:
          'סמני את כל הסוגים שאת יודעת לעשות. רק אלו יוצגו ללקוחות.',
      label: 'תת-כותרת — סוגי טיפולים',
      group: 'כותרות מקטעים',
      multiline: true),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'locations.title',
      defaultValue: 'איפה את נותנת טיפולים',
      label: 'כותרת — מיקומי טיפול',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'locations.subtitle',
      defaultValue: 'בחרי באילו אופציות הלקוחות יוכלו לבחור',
      label: 'תת-כותרת — מיקומי טיפול',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'addOns.title',
      defaultValue: 'תוספות שאני מציעה',
      label: 'כותרת — תוספות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'addOns.subtitle',
      defaultValue: 'סמני, שני מחיר אם רוצה, או הוסיפי משלך',
      label: 'תת-כותרת — תוספות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'durations.title',
      defaultValue: 'משכי טיפול ומחירים',
      label: 'כותרת — משכי טיפול',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'durations.subtitle',
      defaultValue: 'מחירי בסיס לטיפול שוודי · ניתן לעדכן לכל סוג בנפרד',
      label: 'תת-כותרת — משכי טיפול',
      group: 'כותרות מקטעים',
      multiline: true),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'packages.title',
      defaultValue: 'חבילות הנחה',
      label: 'כותרת — חבילות הנחה',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'packages.subtitle',
      defaultValue: 'צרי חבילות שמקנות הנחה ללקוחות חוזרים',
      label: 'תת-כותרת — חבילות הנחה',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmMassage,
      id: 'preferences.title',
      defaultValue: 'העדפות ושירות',
      label: 'כותרת — העדפות',
      group: 'כותרות מקטעים'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Delivery (CLAUDE.md §33) — 18 keys.
// ─────────────────────────────────────────────────────────────────────────────

const String kCsmDelivery = 'delivery';

const List<CsmTextKey> kDeliveryTextKeys = [
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'hero.title',
      defaultValue: 'הקריירה שלך',
      label: 'כותרת ראשית (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'hero.subtitle',
      defaultValue: 'כל מה שצריך כדי להרוויח יותר',
      label: 'תת-כותרת (Hero)',
      group: 'Hero'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'documents.title',
      defaultValue: 'מסמכים ורישיונות',
      label: 'כותרת — מסמכים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'documents.subtitle',
      defaultValue: 'חובה — אימות נדרש לאישור הפרופיל',
      label: 'תת-כותרת — מסמכים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'fleet.title',
      defaultValue: 'הצי שלי',
      label: 'כותרת — הצי שלי',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'fleet.subtitle',
      defaultValue: 'לקוחות יראו את האפשרויות',
      label: 'תת-כותרת — הצי שלי',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'deliveryTypes.title',
      defaultValue: 'סוגי משלוחים',
      label: 'כותרת — סוגי משלוחים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'deliveryTypes.subtitle',
      defaultValue: 'סמן את מה שאתה מבצע',
      label: 'תת-כותרת — סוגי משלוחים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'customerTypes.title',
      defaultValue: 'סוגי לקוחות',
      label: 'כותרת — סוגי לקוחות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'customerTypes.subtitle',
      defaultValue: 'עם מי אתה עובד',
      label: 'תת-כותרת — סוגי לקוחות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'availability.title',
      defaultValue: 'זמינות',
      label: 'כותרת — זמינות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'availability.subtitle',
      defaultValue: '3 סוגי הזמנות',
      label: 'תת-כותרת — זמינות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'serviceArea.title',
      defaultValue: 'אזורי שירות',
      label: 'כותרת — אזורי שירות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'serviceArea.subtitle',
      defaultValue: 'היכן אתה פעיל',
      label: 'תת-כותרת — אזורי שירות',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'pricing.title',
      defaultValue: 'מחירון לפי משקל',
      label: 'כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'pricing.subtitle',
      defaultValue: 'שקיפות מלאה ללקוח',
      label: 'תת-כותרת — מחירון',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'rules.title',
      defaultValue: 'הכללים שלך',
      label: 'כותרת — כללים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'rules.subtitle',
      defaultValue: 'הלקוחות יראו לפני ההזמנה',
      label: 'תת-כותרת — כללים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'businessPackages.title',
      defaultValue: 'חבילות לעסקים',
      label: 'כותרת — חבילות עסקים',
      group: 'כותרות מקטעים'),
  CsmTextKey(
      csmId: kCsmDelivery,
      id: 'businessPackages.subtitle',
      defaultValue: '💰 שליחים עם חבילות = פי 2.5 הכנסה',
      label: 'תת-כותרת — חבילות עסקים',
      group: 'כותרות מקטעים'),
];

// ─────────────────────────────────────────────────────────────────────────────
// All-CSM index. Wired into the admin panel's edit dropdown.
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, List<CsmTextKey>> kAllCsmTextKeys = {
  kCsmFitnessTrainer: kFitnessTrainerTextKeys,
  kCsmBabysitter: kBabysitterTextKeys,
  kCsmPestControl: kPestControlTextKeys,
  kCsmCleaning: kCleaningTextKeys,
  kCsmHandyman: kHandymanTextKeys,
  kCsmMassage: kMassageTextKeys,
  kCsmDelivery: kDeliveryTextKeys,
};

/// Hebrew display name for a `csmId`. Keeps the admin tab + service in sync.
String csmDisplayName(String csmId) {
  switch (csmId) {
    case 'fitness_trainer':
      return 'מאמני כושר';
    case 'massage':
      return 'עיסוי';
    case 'pest_control':
      return 'הדברה';
    case 'delivery':
      return 'משלוחים';
    case 'cleaning':
      return 'נקיון';
    case 'handyman':
      return 'הנדימן';
    case 'babysitter':
      return 'בייביסיטר';
    case 'motorcycle_tow':
      return 'גרר אופנועים';
  }
  return csmId;
}
