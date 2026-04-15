/// AnySkill — Schema Migration Service
///
/// Automated upgrade of every `categories/{id}` document to **schema v2**:
///   1. Scans the entire `categories` collection.
///   2. For each sub-category (parentId non-empty), inspects `serviceSchema`.
///   3. If missing OR still v1 (List shape) → writes a sensible v2 default
///      based on Hebrew/English keyword matching against the sub-name and
///      its parent name.
///   4. Existing v2 schemas are LEFT UNTOUCHED — admin edits are sacred.
///
/// The service is **idempotent**: safe to run any number of times. Never
/// overwrites a schema once it has `version >= 2` set.
///
/// Triggered from: [admin_catalog_tab.dart] → "🔧 הפעל מיגרציית סכמות".
///
/// See [SchemaMigrationService.migrateAll].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../widgets/category_specs_widget.dart';

class SchemaMigrationService {
  static final _db = FirebaseFirestore.instance;

  /// Result tuple — used by the admin UI to render a snackbar after running.
  static Future<MigrationResult> migrateAll() async {
    debugPrint('[SchemaMigration] starting full migration');

    int total = 0;
    int skipped = 0;     // already v2
    int upgraded = 0;    // missing or v1 → wrote v2 default
    final errors = <String>[];

    try {
      final snap = await _db.collection('categories').limit(500).get();
      debugPrint('[SchemaMigration] loaded ${snap.docs.length} category docs');

      // Build parent name lookup so we can pass parent context to the rule engine
      final parentNameById = <String, String>{};
      for (final d in snap.docs) {
        final pid = (d.data()['parentId'] as String? ?? '').trim();
        if (pid.isEmpty) {
          parentNameById[d.id] = (d.data()['name'] as String? ?? '').trim();
        }
      }

      for (final doc in snap.docs) {
        final data = doc.data();
        final pid = (data['parentId'] as String? ?? '').trim();
        if (pid.isEmpty) {
          // Skip top-level parents — schemas live on subs
          continue;
        }
        total++;
        final subName = (data['name'] as String? ?? '').trim();
        final parentName = parentNameById[pid] ?? '';
        final raw = data['serviceSchema'];

        // Already v2? skip.
        if (raw is Map<String, dynamic> && (raw['version'] as num? ?? 0) >= 2) {
          skipped++;
          continue;
        }

        try {
          final defaults = defaultSchemaFor(parentName: parentName, subName: subName);
          await doc.reference.update({'serviceSchema': defaults.toMap()});
          upgraded++;
          debugPrint('[SchemaMigration] ✅ wrote v2 default for "$parentName › $subName"');
        } catch (e) {
          errors.add('$parentName › $subName: $e');
          debugPrint('[SchemaMigration] ❌ failed for "$parentName › $subName": $e');
        }
      }
    } catch (e) {
      errors.add('שגיאה כללית: $e');
      debugPrint('[SchemaMigration] ❌ outer failure: $e');
    }

    final result = MigrationResult(
      totalScanned: total,
      upgraded: upgraded,
      skipped: skipped,
      errors: errors,
    );
    debugPrint('[SchemaMigration] done. $result');
    return result;
  }

  // ────────────────────────────────────────────────────────────────────────
  // KEYWORD-BASED DEFAULT SCHEMA RULES
  // ────────────────────────────────────────────────────────────────────────
  //
  // Each rule has a list of Hebrew/English keywords. The first rule whose
  // keywords match the sub-name OR parent-name (case-insensitive contains)
  // wins. Rules are ordered most-specific → least-specific. Always falls
  // back to a generic "per_hour" schema.

  static ServiceSchema defaultSchemaFor({
    required String parentName,
    required String subName,
  }) {
    final hay = '${parentName.toLowerCase()} ${subName.toLowerCase()}'
        .replaceAll(RegExp(r'\s+'), ' ');
    bool any(List<String> keys) =>
        keys.any((k) => hay.contains(k.toLowerCase()));

    // ── Pest control ─────────────────────────────────────────────────────
    if (any(['הדברה', 'מדביר', 'מזיקים', 'pest'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_visit',
        defaultPolicy: 'moderate',
        depositPercent: 0,
        surcharge: const SurchargeConfig(nightPercent: 30, weekendPercent: 15),
        requireVisualDiagnosis: true, // ⭐ home-services
        priceLocked: true,            // ⭐ home-services
        fields: const [
          SchemaField(id: 'callOutFee',             label: 'תעריף קריאת שירות',  type: 'number', unit: '₪/קריאה'),
          SchemaField(id: 'pricePerRoom',           label: 'מחיר לחדר',           type: 'number', unit: '₪/חדר'),
          SchemaField(id: 'fullApartmentTreatment', label: 'טיפול לדירה שלמה',    type: 'number', unit: '₪'),
          SchemaField(id: 'followUpVisit',          label: 'ביקור עוקב',           type: 'number', unit: '₪'),
          SchemaField(id: 'warrantyMonths',         label: 'אחריות (חודשים)',      type: 'number', unit: 'חודשים'),
          SchemaField(id: 'ecoFriendly',            label: 'שיטות אקולוגיות',      type: 'bool',   unit: ''),
          SchemaField(id: 'emergencyService',       label: 'שירות חירום 24/7',     type: 'bool',   unit: ''),
        ],
        bundles: const [],
        bookingRequirements: const [
          BookingRequirement(id: 'visualDiagnosis', label: 'תמונה של הבעיה / האזור', type: 'image', required: true,
              helpText: 'תמונה ברורה תאפשר לקבל הצעת מחיר נעולה ומדויקת'),
          BookingRequirement(id: 'pestType', label: 'סוג המזיק', type: 'dropdown', required: true,
              options: ['ג׳וקים', 'נמלים', 'מכרסמים', 'פשפשי מיטה', 'נחשים', 'צרעות', 'אחר']),
          BookingRequirement(id: 'apartmentSize', label: 'גודל הנכס (חדרים)', type: 'number', required: true),
          BookingRequirement(id: 'address',  label: 'כתובת מדויקת', type: 'address', required: true),
        ],
      );
    }

    // ── Locksmith / towing / emergency ───────────────────────────────────
    if (any(['מנעולן', 'גרירה', 'תקר', 'פנצ\'ר', 'סוללת', 'גרר', 'חירום', 'locksmith', 'towing'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_call',
        defaultPolicy: 'nonRefundable',
        depositPercent: 0,
        surcharge: const SurchargeConfig(nightPercent: 50, weekendPercent: 25),
        fields: const [
          SchemaField(id: 'callOutFee',  label: 'תעריף קריאה',  type: 'number', unit: '₪/קריאה'),
          SchemaField(id: 'hourlyRate',  label: 'תעריף לשעת עבודה', type: 'number', unit: '₪/לשעה'),
          SchemaField(id: 'available247', label: 'זמינות 24/7', type: 'bool', unit: ''),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'serviceType', label: 'סוג השירות הנדרש', type: 'text', required: true),
          BookingRequirement(id: 'address',  label: 'כתובת / מיקום', type: 'address', required: true),
          BookingRequirement(id: 'urgency',  label: 'דחיפות', type: 'dropdown', required: true,
              options: ['מיידי', 'תוך שעה', 'היום', 'מחר']),
        ],
      );
    }

    // ── Cleaning ─────────────────────────────────────────────────────────
    if (any(['ניקיון', 'ניקוי', 'מנקה', 'מנקות', 'cleaning'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_hour',
        defaultPolicy: 'flexible',
        depositPercent: 0,
        fields: const [
          SchemaField(id: 'hourlyRate',     label: 'תעריף לשעה',          type: 'number', unit: '₪/לשעה'),
          SchemaField(id: 'minHours',       label: 'מינימום שעות',         type: 'number', unit: 'שעות'),
          SchemaField(id: 'suppliesIncluded', label: 'חומרי ניקוי כלולים', type: 'bool',   unit: ''),
          SchemaField(id: 'depositReturn',  label: 'מתאים לחזרת פיקדון',   type: 'bool',   unit: ''),
        ],
        bundles: const [
          PricingBundle(id: 'pack5h',  label: 'חבילת 5 שעות',  price: 0, qty: 5,  unit: 'hour'),
          PricingBundle(id: 'pack10h', label: 'חבילת 10 שעות', price: 0, qty: 10, unit: 'hour', savingsPercent: 10),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'apartmentSize', label: 'גודל הנכס (חדרים)', type: 'number', required: true),
          BookingRequirement(id: 'address', label: 'כתובת', type: 'address', required: true),
          BookingRequirement(id: 'specialNotes', label: 'הערות מיוחדות', type: 'text', required: false,
              helpText: 'למשל: יש כלב, תינוק ישן, רגישויות'),
        ],
      );
    }

    // ── Repairs / maintenance / handyman ─────────────────────────────────
    if (any([
      'חשמל', 'אינסטלצ', 'נגרות', 'שיפוץ', 'צביעה', 'ריצוף', 'גבס',
      'מיזוג', 'תחזוק', 'תיקונ', 'handyman', 'repair', 'plumber', 'electrician'
    ])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_visit',
        defaultPolicy: 'moderate',
        depositPercent: 0,
        surcharge: const SurchargeConfig(nightPercent: 30, weekendPercent: 15),
        requireVisualDiagnosis: true, // ⭐ home-services
        priceLocked: true,            // ⭐ home-services
        fields: const [
          SchemaField(id: 'callOutFee',   label: 'תעריף קריאת שירות', type: 'number', unit: '₪/קריאה'),
          SchemaField(id: 'hourlyRate',   label: 'תעריף לשעת עבודה',   type: 'number', unit: '₪/לשעה'),
          SchemaField(id: 'minimumCharge', label: 'מינימום חיוב',       type: 'number', unit: '₪'),
          SchemaField(id: 'materialsIncluded', label: 'חומרים כלולים',  type: 'bool',   unit: ''),
          SchemaField(id: 'warrantyMonths', label: 'אחריות (חודשים)',   type: 'number', unit: 'חודשים'),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'visualDiagnosis', label: 'תמונה של הבעיה', type: 'image', required: true,
              helpText: 'תמונה ברורה מאפשרת אבחון מרחוק וקיבוע מחיר'),
          BookingRequirement(id: 'workDescription', label: 'תיאור העבודה הנדרשת', type: 'text', required: true),
          BookingRequirement(id: 'address', label: 'כתובת', type: 'address', required: true),
        ],
      );
    }

    // ── Fitness / coaching / nutrition ───────────────────────────────────
    if (any([
      'כושר', 'אימון', 'יוגה', 'פילאטיס', 'ריצה', 'תזונה', 'מאמן',
      'fitness', 'coaching', 'yoga', 'pilates', 'trainer'
    ])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_session',
        defaultPolicy: 'flexible',
        depositPercent: 0,
        fields: const [
          SchemaField(id: 'sessionPrice',    label: 'מחיר סשן בודד',        type: 'number', unit: '₪/סשן'),
          SchemaField(id: 'sessionDuration', label: 'משך סשן (דקות)',       type: 'number', unit: 'דקות'),
          SchemaField(id: 'locationHome',    label: 'אצל הלקוח',             type: 'bool',   unit: ''),
          SchemaField(id: 'locationGym',     label: 'באולם / חדר כושר',      type: 'bool',   unit: ''),
          SchemaField(id: 'locationOutdoor', label: 'באוויר הפתוח / בפארק', type: 'bool',   unit: ''),
          SchemaField(id: 'nutritionPlan',   label: 'תוכנית תזונה כלולה',    type: 'bool',   unit: ''),
        ],
        bundles: const [
          PricingBundle(id: 'pack4',  label: 'חבילה חודשית — 4 סשנים',  price: 0, qty: 4,  unit: 'session', savingsPercent: 10),
          PricingBundle(id: 'pack8',  label: 'חבילה דו-חודשית — 8 סשנים', price: 0, qty: 8,  unit: 'session', savingsPercent: 15),
          PricingBundle(id: 'pack12', label: 'חבילה שלישונית — 12 סשנים', price: 0, qty: 12, unit: 'session', savingsPercent: 20),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'fitnessGoal', label: 'מטרה עיקרית', type: 'dropdown', required: true,
              options: ['הורדת משקל', 'בניית שריר', 'סיבולת', 'גמישות', 'שיקום', 'כללי']),
          BookingRequirement(id: 'experienceLevel', label: 'רמת ניסיון', type: 'dropdown', required: true,
              options: ['מתחיל', 'בינוני', 'מתקדם']),
          BookingRequirement(id: 'medicalNotes', label: 'מגבלות רפואיות', type: 'text', required: false),
        ],
      );
    }

    // ── Lessons / tutoring ───────────────────────────────────────────────
    if (any([
      'שיעור', 'מתמטיק', 'אנגלית', 'פיזיק', 'כימי', 'תכנות',
      'מוזיק', 'הכנה', 'ספרות', 'עברית', 'lesson', 'tutoring'
    ])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_session',
        defaultPolicy: 'moderate',
        depositPercent: 0,
        fields: const [
          SchemaField(id: 'sessionPrice',    label: 'מחיר שיעור בודד',  type: 'number', unit: '₪/שיעור'),
          SchemaField(id: 'sessionDuration', label: 'משך שיעור (דקות)', type: 'number', unit: 'דקות'),
          SchemaField(id: 'gradeLevel',      label: 'שכבת גיל',           type: 'text',   unit: ''),
          SchemaField(id: 'onlineAvailable', label: 'אפשרות לאונליין',    type: 'bool',   unit: ''),
          SchemaField(id: 'examPrepIncluded', label: 'הכנה לבחינות',      type: 'bool',   unit: ''),
        ],
        bundles: const [
          PricingBundle(id: 'pack4',  label: 'חבילת 4 שיעורים',  price: 0, qty: 4,  unit: 'session', savingsPercent: 10),
          PricingBundle(id: 'pack10', label: 'חבילת 10 שיעורים', price: 0, qty: 10, unit: 'session', savingsPercent: 15),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'subject',    label: 'נושא השיעור', type: 'text', required: true),
          BookingRequirement(id: 'studentAge', label: 'גיל התלמיד',  type: 'number', required: true),
          BookingRequirement(id: 'goals',      label: 'מטרות', type: 'text', required: false),
        ],
      );
    }

    // ── Photography / video ──────────────────────────────────────────────
    if (any(['צילום', 'פורטרט', 'חתונ', 'וידאו', 'וידיאו', 'תיעוד', 'photo', 'video'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_event',
        defaultPolicy: 'strict',
        depositPercent: 30,
        surcharge: const SurchargeConfig(weekendPercent: 20),
        fields: const [
          SchemaField(id: 'hourlyRate',    label: 'תעריף לשעה',           type: 'number', unit: '₪/לשעה'),
          SchemaField(id: 'fullDayPrice',  label: 'מחיר יום צילום מלא',    type: 'number', unit: '₪'),
          SchemaField(id: 'editingHours',  label: 'שעות עריכה כלולות',     type: 'number', unit: 'שעות'),
          SchemaField(id: 'rawIncluded',   label: 'קבצי RAW כלולים',       type: 'bool',   unit: ''),
          SchemaField(id: 'printsIncluded', label: 'הדפסות כלולות',         type: 'bool',   unit: ''),
        ],
        bundles: const [
          PricingBundle(id: 'mini',  label: 'חבילת מיני (שעה)',  price: 0, qty: 1, unit: 'event'),
          PricingBundle(id: 'half',  label: 'חצי יום צילום',     price: 0, qty: 4, unit: 'hour'),
          PricingBundle(id: 'full',  label: 'יום צילום מלא',     price: 0, qty: 8, unit: 'hour', savingsPercent: 15),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'eventType', label: 'סוג האירוע', type: 'dropdown', required: true,
              options: ['חתונה', 'בר/בת מצווה', 'יום הולדת', 'אירוע עסקי', 'משפחתי', 'אחר']),
          BookingRequirement(id: 'guestCount', label: 'מספר אורחים מוערך', type: 'number', required: false),
          BookingRequirement(id: 'venueAddress', label: 'כתובת המיקום', type: 'address', required: true),
          BookingRequirement(id: 'durationHours', label: 'משך הצילום (שעות)', type: 'number', required: true),
        ],
      );
    }

    // ── Design / branding ────────────────────────────────────────────────
    if (any(['עיצוב', 'לוגו', 'מיתוג', 'גרפי', 'אינפוגרפיקה', 'אריזה', 'design', 'logo', 'branding'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'flat',
        defaultPolicy: 'strict',
        depositPercent: 50,
        fields: const [
          SchemaField(id: 'logoBasic',    label: 'מחיר לוגו בסיסי',  type: 'number', unit: '₪'),
          SchemaField(id: 'logoPro',      label: 'מחיר לוגו מקצועי', type: 'number', unit: '₪'),
          SchemaField(id: 'brandPackage', label: 'חבילת מיתוג מלא',  type: 'number', unit: '₪'),
          SchemaField(id: 'revisionsIncluded', label: 'מספר תיקונים כלולים', type: 'number', unit: ''),
          SchemaField(id: 'sourceFilesIncluded', label: 'קבצי מקור (AI/PSD)', type: 'bool', unit: ''),
        ],
        bundles: const [],
        bookingRequirements: const [
          BookingRequirement(id: 'projectBrief', label: 'בריף הפרויקט', type: 'text', required: true,
              helpText: 'תאר/י את העסק, קהל היעד והסגנון הרצוי'),
          BookingRequirement(id: 'inspirationLinks', label: 'קישורי השראה', type: 'text', required: false),
        ],
      );
    }

    // ── Events / DJ / catering ───────────────────────────────────────────
    if (any(['אירוע', 'הפק', 'קייטרינ', 'dj', 'בלונ', 'מתנפח', 'event'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_event',
        defaultPolicy: 'strict',
        depositPercent: 30,
        fields: const [
          SchemaField(id: 'basePrice',      label: 'מחיר בסיס לאירוע',  type: 'number', unit: '₪'),
          SchemaField(id: 'pricePerPerson', label: 'תוספת לאדם',         type: 'number', unit: '₪/אדם'),
          SchemaField(id: 'minGuests',      label: 'מינימום משתתפים',   type: 'number', unit: 'אנשים'),
          SchemaField(id: 'setupHours',     label: 'שעות הכנה כלולות',  type: 'number', unit: 'שעות'),
          SchemaField(id: 'equipmentIncluded', label: 'ציוד כלול',       type: 'bool',   unit: ''),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'eventDate',  label: 'תאריך האירוע', type: 'text', required: true),
          BookingRequirement(id: 'guestCount', label: 'מספר אורחים', type: 'number', required: true),
          BookingRequirement(id: 'venueAddress', label: 'כתובת המיקום', type: 'address', required: true),
          BookingRequirement(id: 'theme', label: 'נושא / סגנון', type: 'text', required: false),
        ],
      );
    }

    // ── Beauty / massage / spa ───────────────────────────────────────────
    // ⭐ depositPercent: 20 — Commitment Fee (דמי רצינות) prevents no-shows.
    if (any(['איפור', 'מספר', 'שיער', 'ציפור', 'קוסמט', 'עיסוי', 'ספא', 'beauty', 'spa', 'massage'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_session',
        defaultPolicy: 'moderate',
        depositPercent: 20, // ⭐ דמי רצינות 20%
        fields: const [
          SchemaField(id: 'basePrice',       label: 'מחיר טיפול בסיס',  type: 'number', unit: '₪'),
          SchemaField(id: 'sessionDuration', label: 'משך טיפול (דקות)', type: 'number', unit: 'דקות'),
          SchemaField(id: 'mobileService',   label: 'מגיע/ה אל הלקוח',  type: 'bool',   unit: ''),
        ],
        bundles: const [
          PricingBundle(id: 'pack5', label: 'מנוי 5 טיפולים', price: 0, qty: 5, unit: 'session', savingsPercent: 10),
          PricingBundle(id: 'pack10', label: 'מנוי 10 טיפולים', price: 0, qty: 10, unit: 'session', savingsPercent: 15),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'serviceType', label: 'סוג הטיפול', type: 'text', required: true),
          BookingRequirement(id: 'allergies',   label: 'אלרגיות / רגישויות', type: 'text', required: false),
        ],
      );
    }

    // ── Pet services — DOG WALKING ───────────────────────────────────────
    // ⭐ walkTracking: true → enables Start/End Walk + GPS path map
    if (any(['דוגווקר', 'דוג ווקר', 'dogwalker', 'dog walker',
             'הליכון כלבים', 'הליכון לכלב', 'טיול כלבים', 'מטייל',
             'dog walk', 'walking'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_session',
        defaultPolicy: 'flexible',
        depositPercent: 0,
        walkTracking: true, // ⭐ pet services
        fields: const [
          SchemaField(id: 'walkPrice', label: 'מחיר הליכון בודד', type: 'number', unit: '₪/הליכון'),
          SchemaField(id: 'walkDuration', label: 'משך הליכון (דקות)', type: 'number', unit: 'דקות'),
          SchemaField(id: 'multiDogDiscount', label: 'הנחה לכלב נוסף', type: 'bool', unit: ''),
          SchemaField(id: 'pickupIncluded', label: 'איסוף מהבית כלול', type: 'bool', unit: ''),
        ],
        bundles: const [
          PricingBundle(id: 'pack10', label: 'חבילת 10 הליכונים', price: 0, qty: 10, unit: 'session', savingsPercent: 10),
          PricingBundle(id: 'monthly', label: 'מנוי חודשי (20)', price: 0, qty: 20, unit: 'session', savingsPercent: 20),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'dogName', label: 'שם הכלב', type: 'text', required: true),
          BookingRequirement(id: 'dogBreed', label: 'גזע / גודל', type: 'text', required: true),
          BookingRequirement(id: 'dogPhoto', label: 'תמונה של הכלב', type: 'image', required: true),
          BookingRequirement(id: 'specialNeeds', label: 'הערות מיוחדות', type: 'text', required: false,
              helpText: 'למשל: רגיש לכלבים אחרים, אלרגיות, מינון תרופות'),
          BookingRequirement(id: 'pickupAddress', label: 'כתובת איסוף', type: 'address', required: true),
        ],
      );
    }

    // ── Pet services — BOARDING / PENSION ────────────────────────────────
    // ⭐ dailyProof: true → prompts provider for daily photo + video
    if (any(['פנסיון ביתי', 'פנסיון לכלבים', 'פנסיון כלבים',
             'אירוח כלבים', 'בוארדינג', 'boarding', 'pension'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_night' /* will fall back to "לילה" via custom unit */,
        defaultPolicy: 'strict',
        depositPercent: 25, // ⭐ commitment fee for overnight bookings
        dailyProof: true,   // ⭐ pet services
        fields: const [
          SchemaField(id: 'pricePerNight', label: 'מחיר ללילה', type: 'number', unit: '₪/ללילה'),
          SchemaField(id: 'maxDogs', label: 'מקסימום כלבים', type: 'number', unit: 'כלבים'),
          SchemaField(id: 'fencedYard', label: 'חצר מגודרת', type: 'bool', unit: ''),
          SchemaField(id: 'dailyWalks', label: 'מספר הליכונים יומי', type: 'number', unit: 'הליכונים'),
        ],
        bundles: const [
          PricingBundle(id: 'nights3',  label: 'חבילת 3 לילות',  price: 0, qty: 3,  unit: 'night', savingsPercent: 5),
          PricingBundle(id: 'nights7',  label: 'חבילת שבוע (7 לילות)', price: 0, qty: 7, unit: 'night', savingsPercent: 10),
          PricingBundle(id: 'nights10', label: 'חבילת 10 לילות', price: 0, qty: 10, unit: 'night', savingsPercent: 15),
          PricingBundle(id: 'nights14', label: 'חבילת שבועיים (14 לילות)', price: 0, qty: 14, unit: 'night', savingsPercent: 20),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'dogName', label: 'שם הכלב', type: 'text', required: true),
          BookingRequirement(id: 'dogBreed', label: 'גזע / גודל', type: 'text', required: true),
          BookingRequirement(id: 'dogPhoto', label: 'תמונה של הכלב', type: 'image', required: true),
          BookingRequirement(id: 'medicalNotes', label: 'מידע רפואי / תרופות', type: 'text', required: false),
          BookingRequirement(id: 'vaccinationPhoto', label: 'תעודת חיסונים', type: 'image', required: true),
        ],
      );
    }

    // ── Pet services — TRAINING ──────────────────────────────────────────
    if (any(['אילוף כלבים', 'אילוף', 'training'])) {
      return ServiceSchema(
        version: 2,
        unitType: 'per_session',
        defaultPolicy: 'moderate',
        depositPercent: 0,
        fields: const [
          SchemaField(id: 'sessionPrice', label: 'מחיר סשן בודד', type: 'number', unit: '₪/סשן'),
          SchemaField(id: 'sessionDuration', label: 'משך סשן (דקות)', type: 'number', unit: 'דקות'),
          SchemaField(id: 'homeVisit', label: 'מגיע לבית הלקוח', type: 'bool', unit: ''),
          SchemaField(id: 'puppyTraining', label: 'מתמחה בגורים', type: 'bool', unit: ''),
        ],
        bundles: const [
          PricingBundle(id: 'starter', label: 'חבילת מתחילים — 5 סשנים', price: 0, qty: 5, unit: 'session', savingsPercent: 10),
          PricingBundle(id: 'advanced', label: 'חבילה מקצועית — 10 סשנים', price: 0, qty: 10, unit: 'session', savingsPercent: 18),
        ],
        bookingRequirements: const [
          BookingRequirement(id: 'dogName', label: 'שם הכלב', type: 'text', required: true),
          BookingRequirement(id: 'dogAge', label: 'גיל הכלב', type: 'number', required: true),
          BookingRequirement(id: 'goals', label: 'מטרות האילוף', type: 'text', required: true,
              helpText: 'למשל: ציות, חברותיות, חרדת נטישה, תגובתיות'),
        ],
      );
    }

    // ── Generic fallback (per_hour) ──────────────────────────────────────
    return const ServiceSchema(
      version: 2,
      unitType: 'per_hour',
      defaultPolicy: 'flexible',
      depositPercent: 0,
      fields: [
        SchemaField(id: 'hourlyRate', label: 'תעריף לשעה', type: 'number', unit: '₪/לשעה'),
        SchemaField(id: 'minHours',   label: 'מינימום שעות', type: 'number', unit: 'שעות'),
      ],
      bundles: [],
      bookingRequirements: [
        BookingRequirement(id: 'description', label: 'תיאור הבקשה', type: 'text', required: true),
      ],
    );
  }
}

class MigrationResult {
  final int totalScanned;
  final int upgraded;
  final int skipped;
  final List<String> errors;

  const MigrationResult({
    required this.totalScanned,
    required this.upgraded,
    required this.skipped,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'scanned=$totalScanned, upgraded=$upgraded, skipped=$skipped, errors=${errors.length}';
}
