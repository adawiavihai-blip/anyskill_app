import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// A single service tier offered by a provider.
// ─────────────────────────────────────────────────────────────────────────────
class ServiceTemplate {
  final String   title;       // e.g. 'ביקור ואבחון'
  final String   subtitle;    // e.g. 'בדיקה מקצועית + הצעת מחיר'
  final String   unitLabel;   // e.g. 'ביקור', 'שעה', 'פרויקט'
  final IconData unitIcon;    // shown in the pill next to unitLabel
  final double   multiplier;  // applied to the provider's base price

  const ServiceTemplate({
    required this.title,
    required this.subtitle,
    required this.unitLabel,
    required this.unitIcon,
    required this.multiplier,
  });
}

class _CategoryConfig {
  final List<ServiceTemplate> templates;   // exactly 3
  final String                priceLabel;  // label for the price field
  final String                bioSuggestion;

  const _CategoryConfig({
    required this.templates,
    required this.priceLabel,
    required this.bioSuggestion,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
/// Maps each app category to 3 professional service templates.
///
/// Usage:
///   ServiceArchitect.templatesFor('שיפוצים')  → [ServiceTemplate, ...]
///   ServiceArchitect.priceLabelFor('צילום')    → 'מחיר לשעת צילום (₪)'
/// ─────────────────────────────────────────────────────────────────────────────
class ServiceArchitect {
  ServiceArchitect._();

  // ── Per-category configurations ─────────────────────────────────────────
  static const Map<String, _CategoryConfig> _configs = {

    // ── Home Renovation ──────────────────────────────────────────────────
    'שיפוצים': _CategoryConfig(
      priceLabel:     'מחיר לביקור (₪)',
      bioSuggestion:  'טכנאי שיפוצים מוסמך עם ניסיון של 10+ שנים. מתמחה בשיפוצי דירות, תיקוני רטיבות, ריצוף וצנרת. עבודה נקייה ומהירה, עם אחריות מלאה על העבודה.',
      templates: [
        ServiceTemplate(
          title:      'ביקור ואבחון',
          subtitle:   'בדיקה מקצועית + הצעת מחיר',
          unitLabel:  'ביקור',
          unitIcon:   Icons.home_repair_service_rounded,
          multiplier: 1.0,
        ),
        ServiceTemplate(
          title:      'תיקון בסיסי',
          subtitle:   'טיפול בתקלה אחת כולל חלקים',
          unitLabel:  'ביקור',
          unitIcon:   Icons.build_circle_rounded,
          multiplier: 1.8,
        ),
        ServiceTemplate(
          title:      'שיפוץ מלא',
          subtitle:   'עבודה יסודית + חומרים וניקיון',
          unitLabel:  'פרויקט',
          unitIcon:   Icons.construction_rounded,
          multiplier: 4.0,
        ),
      ],
    ),

    // ── Cleaning ─────────────────────────────────────────────────────────
    'ניקיון': _CategoryConfig(
      priceLabel:    'מחיר לביקור (₪)',
      bioSuggestion: 'מנקה מקצועי/ת עם ניסיון של 5+ שנים. מציע/ת שירותי ניקיון ביתי ועסקי עם חומרי ניקוי מקצועיים. אמין/ה, יסודי/ת ומדוייק/ת בזמנים.',
      templates: [
        ServiceTemplate(
          title:      'ניקיון שוטף',
          subtitle:   'ניקיון סטנדרטי של הבית',
          unitLabel:  'ביקור',
          unitIcon:   Icons.cleaning_services_rounded,
          multiplier: 1.0,
        ),
        ServiceTemplate(
          title:      'ניקיון מעמיק',
          subtitle:   'ניקיון יסודי כולל פינות ומכשירים',
          unitLabel:  'ביקור',
          unitIcon:   Icons.cleaning_services_rounded,
          multiplier: 1.9,
        ),
        ServiceTemplate(
          title:      'ניקיון לפני/אחרי מעבר',
          subtitle:   'הכנה מלאה לדייר חדש',
          unitLabel:  'פרויקט',
          unitIcon:   Icons.apartment_rounded,
          multiplier: 3.0,
        ),
      ],
    ),

    // ── Photography ───────────────────────────────────────────────────────
    'צילום': _CategoryConfig(
      priceLabel:    'מחיר לשעת צילום (₪)',
      bioSuggestion: 'צלם/ת מקצועי/ת עם ניסיון של 8 שנים. מתמחה בצילומי אירועים, פורטרט ועסקי. ציוד מקצועי ועיבוד תמונות ברמה גבוהה.',
      templates: [
        ServiceTemplate(
          title:      'שעת צילום',
          subtitle:   'עד 30 תמונות מעובדות',
          unitLabel:  'שעה',
          unitIcon:   Icons.camera_alt_rounded,
          multiplier: 1.0,
        ),
        ServiceTemplate(
          title:      'חבילת אירוע (3 שעות)',
          subtitle:   'עד 100 תמונות + גלריה דיגיטלית',
          unitLabel:  'חבילה',
          unitIcon:   Icons.photo_library_rounded,
          multiplier: 2.5,
        ),
        ServiceTemplate(
          title:      'יום צילום מלא',
          subtitle:   'עד 6 שעות + עיבוד מקצועי',
          unitLabel:  'יום',
          unitIcon:   Icons.wb_sunny_rounded,
          multiplier: 4.5,
        ),
      ],
    ),

    // ── Fitness ───────────────────────────────────────────────────────────
    'אימון כושר': _CategoryConfig(
      priceLabel:    'מחיר לאימון (₪)',
      bioSuggestion: 'מאמן/ת כושר מוסמך/ת. מתמחה באימון אישי, עיצוב הגוף וירידה במשקל. בונה תכניות אימון מותאמות אישית לכל מטרה ורמה.',
      templates: [
        ServiceTemplate(
          title:      'אימון אישי',
          subtitle:   'שיעור מותאם אישית 60 דקות',
          unitLabel:  'אימון',
          unitIcon:   Icons.fitness_center_rounded,
          multiplier: 1.0,
        ),
        ServiceTemplate(
          title:      'חבילת 5 אימונים',
          subtitle:   'בתיאום מראש — חיסכון של 15%',
          unitLabel:  'חבילה',
          unitIcon:   Icons.local_fire_department_rounded,
          multiplier: 4.25,
        ),
        ServiceTemplate(
          title:      'תכנית חודשית',
          subtitle:   '12 אימונים + תפריט תזונה',
          unitLabel:  'חודש',
          unitIcon:   Icons.calendar_month_rounded,
          multiplier: 10.0,
        ),
      ],
    ),

    // ── Tutoring ──────────────────────────────────────────────────────────
    'שיעורים פרטיים': _CategoryConfig(
      priceLabel:    'מחיר לשיעור (₪)',
      bioSuggestion: 'מורה פרטי/ת מנוסה עם תואר רלוונטי. מתמחה בהוראה אינדיבידואלית, הכנה לבגרויות ולמבחנים. שיטת הוראה פשוטה וברורה שמביאה תוצאות.',
      templates: [
        ServiceTemplate(
          title:      'שיעור יחיד',
          subtitle:   'מפגש אישי ממוקד 60 דקות',
          unitLabel:  'שיעור',
          unitIcon:   Icons.school_rounded,
          multiplier: 1.0,
        ),
        ServiceTemplate(
          title:      'חבילת 4 שיעורים',
          subtitle:   'הנחה + המשכיות בלמידה',
          unitLabel:  'חבילה',
          unitIcon:   Icons.menu_book_rounded,
          multiplier: 3.6,
        ),
        ServiceTemplate(
          title:      'קורס אינטנסיבי',
          subtitle:   '10 שיעורים + חומר לימוד',
          unitLabel:  'קורס',
          unitIcon:   Icons.workspace_premium_rounded,
          multiplier: 8.5,
        ),
      ],
    ),

    // ── Graphic Design ────────────────────────────────────────────────────
    'עיצוב גרפי': _CategoryConfig(
      priceLabel:    'מחיר בסיס לפרויקט (₪)',
      bioSuggestion: 'מעצב/ת גרפי/ת עם ניסיון של 6+ שנים. מתמחה במיתוג עסקי, עיצוב לוגו, קמפיינים דיגיטליים ופרינט. יצירתיות ועמידה בדדליינים.',
      templates: [
        ServiceTemplate(
          title:      'ייעוץ ראשוני',
          subtitle:   'שיחת אפיון + הצעת מחיר',
          unitLabel:  'שעה',
          unitIcon:   Icons.lightbulb_rounded,
          multiplier: 1.0,
        ),
        ServiceTemplate(
          title:      'עיצוב לוגו',
          subtitle:   '3 קונספטים + תיקונים ללא הגבלה',
          unitLabel:  'פרויקט',
          unitIcon:   Icons.palette_rounded,
          multiplier: 4.0,
        ),
        ServiceTemplate(
          title:      'חבילת מיתוג מלאה',
          subtitle:   'לוגו + כרטיס ביקור + עיצוב רשתות',
          unitLabel:  'פרויקט',
          unitIcon:   Icons.auto_awesome_rounded,
          multiplier: 9.0,
        ),
      ],
    ),
  };

  // ── Generic fallback ────────────────────────────────────────────────────
  static const _defaultConfig = _CategoryConfig(
    priceLabel:    'מחיר לשעה (₪)',
    bioSuggestion: 'ספר/י על עצמך ועל ניסיונך בתחום. מה מייחד אותך? מה לקוחות אומרים עליך?',
    templates: [
      ServiceTemplate(
        title:      'פגישה קצרה',
        subtitle:   'מפגש אישי ממוקד',
        unitLabel:  'שעה',
        unitIcon:   Icons.schedule_rounded,
        multiplier: 1.0,
      ),
      ServiceTemplate(
        title:      'שירות מורחב',
        subtitle:   'כולל סיכום ומשימות',
        unitLabel:  'שעה',
        unitIcon:   Icons.schedule_rounded,
        multiplier: 1.4,
      ),
      ServiceTemplate(
        title:      'חבילה מלאה',
        subtitle:   'עבודה מעמיקה + תכנית אישית',
        unitLabel:  'חבילה',
        unitIcon:   Icons.workspace_premium_rounded,
        multiplier: 1.8,
      ),
    ],
  );

  // ── Public API ────────────────────────────────────────────────────────────
  static _CategoryConfig _configFor(String category) =>
      _configs[category] ?? _defaultConfig;

  /// 3 service templates for the given category.
  static List<ServiceTemplate> templatesFor(String category) =>
      _configFor(category).templates;

  /// Localised price-field label for the registration form.
  static String priceLabelFor(String category) =>
      _configFor(category).priceLabel;

  /// Pre-filled bio suggestion shown during registration.
  static String bioSuggestionFor(String category) =>
      _configFor(category).bioSuggestion;
}
