/// AnySkill — Category Tags Service
///
/// Reads the category-specific tag catalog from Firestore
/// (`category_tags/{categoryName}.tags`), with in-memory caching.
/// Exposes a one-shot admin seeder ([seedAll]) that writes the initial
/// 6 category docs mapped from the spec to the app's current
/// `APP_CATEGORIES` (Hebrew-label doc IDs).
///
/// This complements the existing `quickTags` system (max 3 general tags)
/// — providers can additionally pick up to 5 category-specific tags into
/// `users/{uid}.categoryTags`. Together up to 8 differentiators.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/category_tag.dart';

class CategoryTagsService {
  CategoryTagsService._();
  static final CategoryTagsService instance = CategoryTagsService._();

  static const int maxSelectedTags = 5;

  final Map<String, List<CategoryTag>> _cache = {};

  /// Loads tags for a given category (Hebrew doc ID). Cached for the
  /// session — future reads return instantly. Returns `[]` for unknown
  /// categories so the UI can gracefully hide the section.
  Future<List<CategoryTag>> loadFor(String category) async {
    if (category.isEmpty) return const [];
    final cached = _cache[category];
    if (cached != null) return cached;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('category_tags')
          .doc(category)
          .get();
      if (!snap.exists) {
        _cache[category] = const [];
        return const [];
      }
      final raw = (snap.data()?['tags'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => CategoryTag.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      _cache[category] = raw;
      return raw;
    } catch (e) {
      debugPrint('[CategoryTags] load failed for "$category": $e');
      return const [];
    }
  }

  /// Clears the cache — call after admin runs the seeder so the fresh
  /// docs are picked up without a full app restart.
  void invalidate() => _cache.clear();

  // ────────────────────────────────────────────────────────────────────
  // Seeder
  // ────────────────────────────────────────────────────────────────────

  /// Writes the initial 6 category tag docs to Firestore. Idempotent —
  /// docs that already exist are NOT overwritten unless [overwrite] is
  /// true. Returns a human-readable summary.
  static Future<String> seedAll({bool overwrite = false}) async {
    final db = FirebaseFirestore.instance;
    int written = 0;
    int skipped = 0;

    for (final entry in _seedCatalog.entries) {
      final ref = db.collection('category_tags').doc(entry.key);
      final existing = await ref.get();
      if (existing.exists && !overwrite) {
        skipped++;
        continue;
      }
      await ref.set({
        'tags': entry.value.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      written++;
    }
    CategoryTagsService.instance.invalidate();
    return 'Tag catalog seeded — $written written, $skipped skipped.';
  }

  /// Seed catalog — doc ID = app category Hebrew name (matches
  /// `users/{uid}.serviceType`). Per user-confirmed mapping:
  /// - אימון כושר        → spec "כושר וספורט"
  /// - ניקיון            → spec "שירותי בית"
  /// - שיפוצים           → spec "תחזוקה ותיקונים"
  /// - צילום             → spec "אירועים והפקות"
  /// - שיעורים פרטיים    → spec "לימודים שפות ותרבויות"
  /// - עיצוב גרפי        → custom set (new)
  static final Map<String, List<CategoryTag>> _seedCatalog = {
    'אימון כושר': [
      CategoryTag(id: 'combat_unit', label: 'יוצא/ת יחידה קרבית', iconName: 'military_tech'),
      CategoryTag(id: 'certified_international', label: 'מוסמך/ת בינלאומי', iconName: 'verified'),
      CategoryTag(id: 'experience_10_plus', label: 'ניסיון 10+ שנים', iconName: 'workspace_premium'),
      CategoryTag(id: 'injury_rehab', label: 'מתמחה בשיקום פציעות', iconName: 'healing'),
      CategoryTag(id: 'works_with_elderly', label: 'עובד/ת עם קשישים', iconName: 'elderly'),
      CategoryTag(id: 'outdoor_training', label: 'אימון בחוץ', iconName: 'park'),
      CategoryTag(id: 'couples_training', label: 'אימון זוגות', iconName: 'people'),
      CategoryTag(id: 'pregnancy_friendly', label: 'מתאים לנשים בהריון', iconName: 'pregnant_woman'),
      CategoryTag(id: 'kids_friendly', label: 'מתאים לילדים', iconName: 'child_care'),
      CategoryTag(id: 'brings_equipment', label: 'מביא/ה ציוד', iconName: 'fitness_center'),
    ],
    'ניקיון': [
      CategoryTag(id: 'brings_supplies', label: 'מביא/ה ציוד וחומרים', iconName: 'cleaning_services'),
      CategoryTag(id: 'eco_materials', label: 'חומרים אקולוגיים', iconName: 'eco'),
      CategoryTag(id: 'post_renovation', label: 'מתמחה בניקיון אחרי שיפוץ', iconName: 'construction'),
      CategoryTag(id: 'move_in_out', label: 'ניקיון לפני/אחרי כניסה לדירה', iconName: 'home'),
      CategoryTag(id: 'hypoallergenic', label: 'חומרים היפואלרגניים', iconName: 'health_and_safety'),
      CategoryTag(id: 'luxury_experience', label: 'ניסיון עם דירות יוקרה', iconName: 'villa'),
      CategoryTag(id: 'team_work', label: 'מגיע/ה בזוג - עבודה מהירה', iconName: 'group_work'),
    ],
    'שיפוצים': [
      CategoryTag(id: 'emergency_available', label: 'זמין/ה לחירום', iconName: 'emergency'),
      CategoryTag(id: 'works_saturday', label: 'עובד/ת בשבת', iconName: 'calendar_today'),
      CategoryTag(id: 'licensed_professional', label: 'בעל/ת רישיון מקצועי', iconName: 'badge'),
      CategoryTag(id: 'work_warranty', label: 'אחריות על העבודה', iconName: 'verified_user'),
      CategoryTag(id: 'brings_materials', label: 'מביא/ה חומרים', iconName: 'hardware'),
      CategoryTag(id: 'old_buildings', label: 'ניסיון עם בניינים ישנים', iconName: 'apartment'),
      CategoryTag(id: 'water_damage', label: 'מומחה/ית לנזקי מים', iconName: 'water_damage'),
      CategoryTag(id: 'same_day_service', label: 'שירות באותו יום', iconName: 'bolt'),
      CategoryTag(id: 'upfront_quote', label: 'הצעת מחיר מראש', iconName: 'request_quote'),
    ],
    'צילום': [
      CategoryTag(id: 'kids_events', label: 'מתאים לאירועי ילדים', iconName: 'celebration'),
      CategoryTag(id: 'weddings', label: 'מתאים לחתונות', iconName: 'favorite'),
      CategoryTag(id: 'corporate_events', label: 'מתאים לאירועי חברה', iconName: 'business'),
      CategoryTag(id: 'full_equipment', label: 'מביא/ה ציוד מלא', iconName: 'inventory'),
      CategoryTag(id: 'setup_teardown', label: 'כולל הקמה ופירוק', iconName: 'construction'),
      CategoryTag(id: 'available_weekends', label: 'זמין/ה בשישי-שבת', iconName: 'calendar_today'),
      CategoryTag(id: 'event_insurance', label: 'מבטח/ת את האירוע', iconName: 'shield'),
    ],
    'שיעורים פרטיים': [
      CategoryTag(id: 'native_speaker', label: 'דובר/ת שפת אם', iconName: 'record_voice_over'),
      CategoryTag(id: 'bagrut_prep', label: 'מכין/ה לבגרות', iconName: 'school'),
      CategoryTag(id: 'psychometric_prep', label: 'מכין/ה לפסיכומטרי', iconName: 'psychology'),
      CategoryTag(id: 'teaches_kids', label: 'מלמד/ת ילדים', iconName: 'child_care'),
      CategoryTag(id: 'ld_experience', label: 'ניסיון עם תלמידי LD', iconName: 'accessibility'),
      CategoryTag(id: 'linguistics_degree', label: 'בוגר/ת תואר בלשנות / ספרות', iconName: 'menu_book'),
      CategoryTag(id: 'free_trial', label: 'שיעור ניסיון חינם', iconName: 'redeem'),
      CategoryTag(id: 'online_lesson', label: 'שיעור אונליין', iconName: 'videocam'),
    ],
    'עיצוב גרפי': [
      CategoryTag(id: 'logo_specialist', label: 'מתמחה בלוגואים', iconName: 'palette'),
      CategoryTag(id: 'figma_pro', label: 'עובד/ת עם Figma', iconName: 'design_services'),
      CategoryTag(id: 'ui_ux_designer', label: 'מעצב/ת UI/UX', iconName: 'draw'),
      CategoryTag(id: 'branding_experience', label: 'ניסיון עם מיתוג', iconName: 'branding_watermark'),
      CategoryTag(id: 'social_specialist', label: 'מתמחה בסושיאל', iconName: 'share'),
      CategoryTag(id: 'print_design', label: 'עיצוב דפוס', iconName: 'print'),
      CategoryTag(id: 'package_design', label: 'עיצוב אריזות', iconName: 'inventory_2'),
      CategoryTag(id: 'notable_brands', label: 'מותגים מוכרים בתיק', iconName: 'star'),
    ],
  };
}
