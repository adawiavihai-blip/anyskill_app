// ignore_for_file: use_build_context_synchronously
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../utils/safe_image_provider.dart';
import '../widgets/category_specs_widget.dart';

/// Admin tab — create, edit, delete and toggle visibility of Demo Experts.
///
/// **v11.9.x** — Soft Launch ready:
///   • Demo profiles now appear in category search (no longer filtered out).
///   • Auto-creates a `provider_listings` doc on save so demos show up in
///     the same query path as real providers.
///   • Full provider profile fields (price, working hours, gallery×6,
///     cancellation policy, quick tags, contact info).
///   • Reviews are editable AFTER creation (not just on first save).
///   • New "Demo Bookings" sub-tab shows every attempted booking on a demo
///     profile, with customer info and timestamp.
///   • Sticky bottom action button (no more cut-off on long forms).
///
/// Firestore touched:
///   users/{uid}                — profile + gallery + stats (isDemo: true)
///   provider_listings/{id}     — auto-created for search visibility
///   reviews/{id}               — sample reviews (isDemo: true)
///   demo_bookings/{id}         — admin-visible record of every booking attempt
///   notifications/{id}         — push to every admin when a booking is attempted
class AdminDemoExpertsTab extends StatefulWidget {
  const AdminDemoExpertsTab({super.key});

  @override
  State<AdminDemoExpertsTab> createState() => _AdminDemoExpertsTabState();
}

class _AdminDemoExpertsTabState extends State<AdminDemoExpertsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF6366F1),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF6366F1),
              indicatorWeight: 3,
              tabs: const [
                Tab(
                  icon: Icon(Icons.people_outline, size: 20),
                  text: 'מומחי דמו',
                ),
                Tab(
                  icon: Icon(Icons.event_note_outlined, size: 20),
                  text: 'הזמנות שניסו לקבוע',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _DemoExpertsListTab(),
                _DemoBookingsListTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — Demo experts list
// ═══════════════════════════════════════════════════════════════════════════

class _DemoExpertsListTab extends StatefulWidget {
  const _DemoExpertsListTab();

  @override
  State<_DemoExpertsListTab> createState() => _DemoExpertsListTabState();
}

class _DemoExpertsListTabState extends State<_DemoExpertsListTab> {
  final _db = FirebaseFirestore.instance;
  bool _autoSeedRan = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _demoStream => _db
      .collection('users')
      .where('isDemo', isEqualTo: true)
      .limit(100)
      .snapshots();

  @override
  void initState() {
    super.initState();
    // Fire-and-forget auto-seed of starter demo profiles. Idempotent —
    // uses deterministic UIDs so re-runs are no-ops once seeded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_autoSeedRan) {
        _autoSeedRan = true;
        _autoSeedStarterDemos();
      }
    });
  }

  Future<void> _toggleHidden(String uid, bool current) async {
    final newHidden = !current;
    // Update both user and listing for sync
    await _db.collection('users').doc(uid).update({'isHidden': newHidden});
    // Sync the listing too
    final listings = await _db
        .collection('provider_listings')
        .where('uid', isEqualTo: uid)
        .limit(2)
        .get();
    for (final l in listings.docs) {
      await l.reference.update({'isHidden': newHidden});
    }
  }

  Future<void> _delete(BuildContext ctx, String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('מחק מומחה דמו'),
        content: Text(
          'האם למחוק את "$name"?\n\n'
          'גם הביקורות והמודעות (provider_listings) של המשתמש יימחקו.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Delete fake reviews
    final reviews = await _db
        .collection('reviews')
        .where('expertId', isEqualTo: uid)
        .where('isDemo', isEqualTo: true)
        .get();
    for (final r in reviews.docs) {
      await r.reference.delete();
    }

    // Delete provider_listings docs (the visible search records)
    final listings = await _db
        .collection('provider_listings')
        .where('uid', isEqualTo: uid)
        .limit(2)
        .get();
    for (final l in listings.docs) {
      await l.reference.delete();
    }

    // Finally the user doc
    await _db.collection('users').doc(uid).delete();
  }

  void _showForm({String? uid, Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DemoExpertForm(uid: uid, existing: existing),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO-SEED — three starter demo profiles, idempotent (deterministic UIDs)
  // ─────────────────────────────────────────────────────────────────────────

  /// Three starter demo templates that match the structure of any
  /// hand-created demo profile. UIDs are deterministic so this runs once
  /// per profile and never duplicates on rebuild.
  static const _starterDemos = [
    {
      'uid': 'demo_seed_cleaning_dana',
      'name': 'דנה לוי',
      'phone': '054-7100001',
      'email': 'dana.levi@example.com',
      'aboutMe':
          'מנקה דירות מקצועית עם 10+ שנות ניסיון. ניקיון יסודי לדירות, '
              'משרדים ולאחר שיפוץ. שימוש בחומרים ידידותיים לסביבה, יחס אישי '
              'וחיוך.',
      'parentCategory': 'ניקיון',
      'subCategory': 'ניקיון בית',
      'profileImage':
          'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400&h=400&fit=crop',
      'pricePerHour': 80,
      'completedJobs': 312,
      'cancellationPolicy': 'flexible',
      'quickTags': ['reliable', 'clean_work', 'punctual', 'fast_response'],
      'reviews': [
        {'name': 'מיכל ברק',  'rating': 5, 'comment': 'דנה הגיעה בזמן, הדירה הברקה. מקצוענית אמיתית!', 'daysAgo': 7},
        {'name': 'אמיר כהן',  'rating': 5, 'comment': 'יסודיות ברמה אחרת. ממליץ בחום.',                'daysAgo': 18},
        {'name': 'תמר אדרי',  'rating': 5, 'comment': 'שירות מעולה ומחיר הוגן. כבר הזמנתי שוב.',         'daysAgo': 29},
        {'name': 'יואב פלד',  'rating': 5, 'comment': 'הכי טוב שהיה לי. שמה לב לכל פינה.',               'daysAgo': 41},
        {'name': 'שירה גל',   'rating': 5, 'comment': 'נחמדה, מקצועית, אמינה. שווה כל שקל.',             'daysAgo': 56},
      ],
    },
    {
      'uid': 'demo_seed_fitness_roi',
      'name': 'רועי אזולאי',
      'phone': '054-7100002',
      'email': 'roi.azulay@example.com',
      'aboutMe':
          'מאמן כושר אישי מוסמך, מומחה בהורדת משקל ובניית שרירים. '
              '8+ שנות ניסיון, אימונים בבית הלקוח, בפארק או באולם. '
              'תוכנית תזונה מותאמת אישית במתנה.',
      'parentCategory': 'אימון כושר',
      'subCategory': 'כושר כללי',
      'profileImage':
          'https://images.unsplash.com/photo-1567013127542-490d757e51fc?w=400&h=400&fit=crop',
      'pricePerHour': 200,
      'completedJobs': 198,
      'cancellationPolicy': 'moderate',
      'quickTags': ['experienced', 'reliable', 'top_quality', 'flexible'],
      'reviews': [
        {'name': 'נועה שמש',   'rating': 5, 'comment': 'ירדתי 8 קילו ב-3 חודשים עם רועי. אלוף!',           'daysAgo': 9},
        {'name': 'עידן רוזן',  'rating': 5, 'comment': 'מאמן ענק. סבלני, מקצועי וממש דוחף קדימה.',         'daysAgo': 21},
        {'name': 'הילה בן עמי','rating': 5, 'comment': 'אימונים מאתגרים אבל מהנים. מומלץ בחום!',           'daysAgo': 34},
        {'name': 'אורי דהן',   'rating': 5, 'comment': 'התוכנית התזונתית עזרה לי המון. תודה רועי.',         'daysAgo': 48},
      ],
    },
    {
      'uid': 'demo_seed_moving_eli',
      'name': 'אלי מזרחי',
      'phone': '054-7100003',
      'email': 'eli.mizrahi@example.com',
      'aboutMe':
          'הובלות דירות ומשרדים — צוות של 3 עובדים, רכב גדול עם רמפה. '
              'אריזה מקצועית, פירוק והרכבת רהיטים, ביטוח מלא. '
              'זמינים גם בסופי שבוע.',
      'parentCategory': 'שיפוצים',
      'subCategory': 'שיפוץ כללי',
      'profileImage':
          'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?w=400&h=400&fit=crop',
      'pricePerHour': 350,
      'completedJobs': 487,
      'cancellationPolicy': 'strict',
      'quickTags': ['fast_response', 'experienced', 'reliable', 'punctual'],
      'reviews': [
        {'name': 'רן שפירא',   'rating': 5, 'comment': 'הובילו אותי בלי שריטה אחת. מקצוענים!',                'daysAgo': 6},
        {'name': 'דנה אילון',  'rating': 5, 'comment': 'הגיעו בזמן, עבדו מהר ובאחריות. ממליצה.',              'daysAgo': 17},
        {'name': 'מאיה פרץ',   'rating': 5, 'comment': 'אריזה מושלמת, אדיבים מאוד. שירות 10/10.',              'daysAgo': 28},
        {'name': 'אסף לוי',    'rating': 5, 'comment': 'מחיר הוגן, שירות מעולה. הצוות של אלי הכי טוב בארץ.', 'daysAgo': 39},
        {'name': 'גל ניסים',   'rating': 5, 'comment': 'עבודה יסודית. הם פירקו והרכיבו את כל הרהיטים.',       'daysAgo': 52},
      ],
    },
    // ── PEST CONTROL TRIO — תחזוקה ותיקונים › הדברה ──────────────────────
    {
      'uid': 'demo_seed_pest_oren_v2',
      'name': 'אורן אברהמי',
      'phone': '054-7100004',
      'email': 'oren.avrahami@example.com',
      'aboutMe':
          'מדביר מקצועי עם 12+ שנות ניסיון. מוסמך לטיפולים למגורים ולעסקים. '
              'מתמחה בג׳וקים, נמלים, מכרסמים ופשפשי מיטה. עבודה עם חומרים '
              'מאושרי משרד הבריאות, אחריות מלאה לכל טיפול.',
      'parentCategory': 'תחזוקה ותיקונים',
      'subCategory': 'הדברה',
      'profileImage':
          'https://images.unsplash.com/photo-1560250097-0b93528c311a?w=400&h=400&fit=crop',
      'pricePerHour': 280,
      'completedJobs': 247,
      'cancellationPolicy': 'moderate',
      'quickTags': ['experienced', 'reliable', 'punctual', 'top_quality'],
      'reviews': [
        {'name': 'דנה כהן',     'rating': 5, 'comment': 'אורן הגיע בזמן, עבד ביסודיות וכל הג׳וקים נעלמו תוך יומיים. ממליצה בחום!', 'daysAgo': 12},
        {'name': 'יוסי לוי',     'rating': 5, 'comment': 'מקצוען אמיתי. הסביר בדיוק מה הוא עושה ולמה. הבעיה נפתרה לחלוטין.',           'daysAgo': 24},
        {'name': 'שירה ברק',     'rating': 5, 'comment': 'שירות מעולה, מחיר הוגן והתוצאה דיברה בעד עצמה. תודה רבה!',                    'daysAgo': 38},
        {'name': 'משה אברמוביץ', 'rating': 4, 'comment': 'עבודה טובה ויסודית, אבל הגיע באיחור של חצי שעה. מעבר לזה — מצוין.',          'daysAgo': 51},
        {'name': 'נועה פרץ',     'rating': 5, 'comment': 'הזמנתי לטיפול בנמלים בדירה — תוך שבוע אין סימן. ממליצה!',                    'daysAgo': 67},
      ],
    },
    {
      'uid': 'demo_seed_pest_sara_v2',
      'name': 'שרה כהן',
      'phone': '054-7100005',
      'email': 'sara.cohen.pest@example.com',
      'aboutMe':
          'טכנאית הדברה מורשית, מתמחה בטיפולים אקולוגיים וידידותיים לסביבה. '
              '8+ שנות ניסיון, פתרונות בטוחים למשפחות עם ילדים וחיות מחמד. '
              'שימוש בחומרים אורגניים בלבד כשניתן.',
      'parentCategory': 'תחזוקה ותיקונים',
      'subCategory': 'הדברה',
      'profileImage':
          'https://images.unsplash.com/photo-1594824476967-48c8b964273f?w=400&h=400&fit=crop',
      'pricePerHour': 320,
      'completedJobs': 156,
      'cancellationPolicy': 'flexible',
      'quickTags': ['clean_work', 'reliable', 'fast_response', 'flexible'],
      'reviews': [
        {'name': 'מיכל אדרי',  'rating': 5, 'comment': 'שרה השתמשה בחומרים אקולוגיים והרגשנו בטוחים עם הילדים בבית. תוצאה מעולה!', 'daysAgo': 8},
        {'name': 'רון שמש',    'rating': 5, 'comment': 'מקצועית ויסודית, הסבירה כל שלב. מומלץ במיוחד למי שיש לו ילדים או חיות.',  'daysAgo': 19},
        {'name': 'טל גרינברג', 'rating': 5, 'comment': 'הגיעה תוך יומיים, עבדה מהר ויעיל. ללא ריח חזק כמו אצל מדבירים אחרים.',     'daysAgo': 33},
        {'name': 'עידו ניסים', 'rating': 4, 'comment': 'שירות איכותי, יקר טיפה אבל שווה כי בטוח לסביבה.',                            'daysAgo': 47},
      ],
    },
    {
      'uid': 'demo_seed_pest_yossi_v2',
      'name': 'יוסי רמן',
      'phone': '054-7100006',
      'email': 'yossi.raman.pest@example.com',
      'aboutMe':
          'שירות הדברה חירום 24/7. מוסמך לכל סוגי המזיקים — נחשים, צרעות, '
              'פשפשים, מכרסמים. הגעה מהירה גם בלילות וסופי שבוע. ניסיון של '
              '15+ שנים בטיפולים מורכבים ובמקומות עם מערכות אחסון מזון.',
      'parentCategory': 'תחזוקה ותיקונים',
      'subCategory': 'הדברה',
      'profileImage':
          'https://images.unsplash.com/photo-1582719471384-894fbb16e074?w=400&h=400&fit=crop',
      'pricePerHour': 450,
      'completedJobs': 412,
      'cancellationPolicy': 'nonRefundable',
      'quickTags': ['fast_response', 'experienced', 'reliable', 'top_quality'],
      'reviews': [
        {'name': 'אבי שפירא',   'rating': 5, 'comment': 'התקשרתי בלילה אחרי שראיתי נחש בחצר. יוסי הגיע תוך 40 דקות וטיפל. מציל חיים!', 'daysAgo': 5},
        {'name': 'רחל בן עמי',  'rating': 5, 'comment': 'קן צרעות ענק על המרפסת — יוסי טיפל ביעילות וללא סיכון. שירות חירום אמיתי.',  'daysAgo': 14},
        {'name': 'דוד אילון',   'rating': 5, 'comment': 'הגיע ביום שישי בלילה לטפל בפשפשי מיטה. מקצוען אמיתי, פתר את הבעיה לחלוטין.',  'daysAgo': 22},
        {'name': 'יעל ספיר',    'rating': 4, 'comment': 'יקר אבל מצוין לחירומים. הגעה מאוד מהירה, אין על מי לסמוך כמוהו.',              'daysAgo': 35},
        {'name': 'גלעד אוחיון', 'rating': 5, 'comment': 'שירות 24/7 אמיתי. התקשרתי ב-2 לפנות בוקר והוא ענה מיד. מקצוען של פעם.',         'daysAgo': 48},
      ],
    },
  ];

  Map<String, Map<String, String>> _seedWorkingHours() => {
        '0': {'from': '08:00', 'to': '19:00'},
        '1': {'from': '08:00', 'to': '19:00'},
        '2': {'from': '08:00', 'to': '19:00'},
        '3': {'from': '08:00', 'to': '19:00'},
        '4': {'from': '08:00', 'to': '19:00'},
        '5': {'from': '08:00', 'to': '14:00'},
      };

  /// Loads ALL categories from Firestore and returns a list of
  /// `{id, name, parentId}`. Used by the seeder to resolve template
  /// category names to actual Firestore docs (so the demos sync to
  /// whatever categories the admin has on the live DB, not hardcoded).
  Future<List<Map<String, dynamic>>> _loadAllCategoriesFromFirestore() async {
    final snap = await _db.collection('categories').limit(500).get();
    return snap.docs
        .map((d) => {
              'id': d.id,
              'name': (d.data()['name'] as String? ?? '').trim(),
              'parentId': (d.data()['parentId'] as String? ?? '').trim(),
            })
        .toList();
  }

  /// SMART category resolver — tries multiple matching strategies in order:
  ///
  ///   1. **Exact normalized match** — sub name == desiredSub (no spaces, lowercase)
  ///   2. **Sub name contains desired** — e.g. "חיטוי והדברה" contains "הדברה"
  ///   3. **Desired contains sub name** — e.g. "מדביר מקצועי" contains "מדביר"
  ///
  /// When multiple subs match, prefers the one whose parent matches
  /// `desiredParent` (with the same fuzzy logic).
  ///
  /// Returns null only if absolutely nothing matches. The caller treats
  /// null as a hard failure (skip + report) — no silent random fallback.
  /// (Past bug: lenient resolver fell back to "אירועים והפקות / DJ".)
  ({String parentName, String subName})? _findSubByExactName({
    required List<Map<String, dynamic>> allCats,
    required String desiredParent,
    required String desiredSub,
  }) {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final dsN = norm(desiredSub);
    final dpN = norm(desiredParent);

    // Helper: find parent doc by id
    Map<String, dynamic>? parentOf(Map<String, dynamic> sub) {
      for (final c in allCats) {
        if (c['id'] == sub['parentId']) return c;
      }
      return null;
    }

    // Collect all sub-categories (any doc with non-empty parentId)
    final allSubs = allCats
        .where((c) => (c['parentId'] as String).isNotEmpty)
        .toList();

    // Strategy 1 — exact normalized match
    var matches = allSubs.where((c) {
      return norm(c['name'] as String) == dsN;
    }).toList();
    debugPrint(
        '[DemoSeed]   strategy 1 (exact) for "$desiredSub": ${matches.length} matches');

    // Strategy 2 — sub name contains desired (handles e.g. "חיטוי והדברה" ⊃ "הדברה")
    if (matches.isEmpty) {
      matches = allSubs.where((c) {
        final n = norm(c['name'] as String);
        return n.contains(dsN);
      }).toList();
      debugPrint(
          '[DemoSeed]   strategy 2 (sub contains "$desiredSub"): ${matches.length} matches');
    }

    // Strategy 3 — desired contains sub name (handles e.g. desired "הדברה ביתית" ⊃ "הדברה")
    if (matches.isEmpty) {
      matches = allSubs.where((c) {
        final n = norm(c['name'] as String);
        return n.length >= 3 && dsN.contains(n);
      }).toList();
      debugPrint(
          '[DemoSeed]   strategy 3 ("$desiredSub" contains sub): ${matches.length} matches');
    }

    if (matches.isEmpty) return null;

    // Among matches, prefer the one whose parent matches desiredParent
    // (also fuzzy: exact OR contains in either direction).
    for (final s in matches) {
      final p = parentOf(s);
      if (p == null) continue;
      final pn = norm(p['name'] as String);
      if (pn == dpN || pn.contains(dpN) || dpN.contains(pn)) {
        debugPrint(
            '[DemoSeed]   ✓ matched parent "${p['name']}" → sub "${s['name']}"');
        return (
          parentName: p['name'] as String,
          subName: s['name'] as String,
        );
      }
    }

    // No parent match — use the first matching sub.
    // The sub name itself is still correct, so the demo lands in a
    // valid pest-control category even if the parent name differs.
    final first = matches.first;
    final p = parentOf(first);
    if (p == null) return null;
    debugPrint(
        '[DemoSeed]   ⚠ no parent match for "$desiredParent" — using first sub match: "${p['name']} / ${first['name']}"');
    return (
      parentName: p['name'] as String,
      subName: first['name'] as String,
    );
  }

  /// Writes the 3 starter demos to Firestore. Skips any whose user doc
  /// already exists, so this is safe to call on every screen mount.
  Future<void> _autoSeedStarterDemos() async {
    int created = 0;
    int skipped = 0;
    final errors = <String>[];

    debugPrint('[DemoSeed] starting auto-seed of ${_starterDemos.length} demos');

    try {
      // Load real categories so demos sync to whatever the admin has
      final allCats = await _loadAllCategoriesFromFirestore();
      debugPrint('[DemoSeed] loaded ${allCats.length} categories from Firestore');

      // Dump the entire category tree to console — this is the ONLY way to
      // diagnose name mismatches without running a separate Firestore query.
      // Look for these lines in DevTools → Console after a hard refresh.
      final parents = allCats
          .where((c) => (c['parentId'] as String).isEmpty)
          .toList();
      debugPrint('[DemoSeed] ─── CATEGORY TREE DUMP ──────────────────');
      for (final p in parents) {
        final pid = p['id'] as String;
        final pname = p['name'] as String;
        final subs = allCats.where((c) => c['parentId'] == pid).toList();
        debugPrint('[DemoSeed]   📁 "$pname" (id=$pid)');
        for (final s in subs) {
          debugPrint('[DemoSeed]      └─ "${s['name']}" (id=${s['id']})');
        }
      }
      debugPrint('[DemoSeed] ─── END CATEGORY TREE ──────────────────');

      for (final t in _starterDemos) {
        final uid = t['uid'] as String;
        try {
          final existing = await _db.collection('users').doc(uid).get();
          if (existing.exists) {
            skipped++;
            debugPrint('[DemoSeed] skip — already exists: $uid');
            continue;
          }

          // STRICT category resolution — fail loudly if no match.
          // (Past bug: lenient resolver fell back to a random category and
          // landed all 3 demos in "אירועים והפקות / DJ".)
          final desiredParent = t['parentCategory'] as String;
          final desiredSub = t['subCategory'] as String;
          final resolved = _findSubByExactName(
            allCats: allCats,
            desiredParent: desiredParent,
            desiredSub: desiredSub,
          );
          if (resolved == null) {
            errors.add(
                '${t['name']}: לא נמצאה תת-קטגוריה "$desiredSub" תחת "$desiredParent" ב-Firestore');
            debugPrint(
                '[DemoSeed] ❌ no exact sub-category match for "$desiredSub" — skipping ${t['name']}');
            continue;
          }
          final parentCategory = resolved.parentName;
          final subCategory = resolved.subName;
          debugPrint(
              '[DemoSeed] resolved "$desiredParent / $desiredSub" → '
              '"$parentCategory / $subCategory"');

          final reviews =
              (t['reviews'] as List).cast<Map<String, dynamic>>();
          final ratings =
              reviews.map((r) => (r['rating'] as num).toDouble()).toList();
          final avg = ratings.reduce((a, b) => a + b) / ratings.length;
          final rating = double.parse(avg.toStringAsFixed(1));
          final isTopRated = rating >= 4.8;

          final quickTags = (t['quickTags'] as List).cast<String>();
          final hours = _seedWorkingHours();
          final listingId = 'demo_$uid';

        final userData = <String, dynamic>{
          'name': t['name'],
          'phone': t['phone'],
          'email': t['email'],
          'aboutMe': t['aboutMe'],
          'profileImage': t['profileImage'],
          'serviceType': subCategory,
          'subCategoryName': subCategory,
          'parentCategory': parentCategory,
          'gallery': <String>[],
          'completedJobs': t['completedJobs'],
          'rating': rating,
          'reviewsCount': reviews.length,
          'pricePerHour': t['pricePerHour'],
          'categoryDetails': <String, dynamic>{},
          'workingHours': hours,
          'cancellationPolicy': t['cancellationPolicy'],
          'quickTags': quickTags,
          'isProvider': true,
          'isCustomer': false,
          'isDemo': true,
          'isOnline': true,
          'isVerified': true,
          'isTopRated': isTopRated,
          'isHidden': false,
          'balance': 0,
        };
        await _db.collection('users').doc(uid).set(userData);

        final listingData = <String, dynamic>{
          'uid': uid,
          'identityIndex': 0,
          'name': t['name'],
          'profileImage': t['profileImage'],
          'isVerified': true,
          'isHidden': false,
          'isDemo': true,
          'isVolunteer': false,
          'isOnline': true,
          'isAnySkillPro': isTopRated,
          'isPromoted': false,
          'serviceType': subCategory,
          'parentCategory': parentCategory,
          'subCategory': subCategory,
          'aboutMe': t['aboutMe'],
          'pricePerHour': t['pricePerHour'],
          'gallery': <String>[],
          'categoryDetails': <String, dynamic>{},
          'priceList': <String, dynamic>{},
          'quickTags': quickTags,
          'workingHours': hours,
          'cancellationPolicy': t['cancellationPolicy'],
          'rating': rating,
          'reviewsCount': reviews.length,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await _db
            .collection('provider_listings')
            .doc(listingId)
            .set(listingData);

        await _db.collection('users').doc(uid).update({
          'listingIds': [listingId],
          'activeIdentityCount': 1,
        });

          // Reviews — deterministic IDs so they're also idempotent
          for (int i = 0; i < reviews.length; i++) {
            final r = reviews[i];
            final daysAgo = r['daysAgo'] as int;
            final ts = DateTime.now().subtract(Duration(days: daysAgo));
            final reviewId = '${uid}_review_$i';
            await _db.collection('reviews').doc(reviewId).set({
              'expertId': uid,
              'listingId': listingId,
              'reviewerId': '${uid}_reviewer_$i',
              'reviewerName': r['name'],
              'rating': (r['rating'] as num).toDouble(),
              'comment': r['comment'],
              'timestamp': Timestamp.fromDate(ts),
              'traitTags': const ['professional', 'punctual'],
              'isDemo': true,
            });
          }

          created++;
          debugPrint('[DemoSeed] ✅ created $uid (${t['name']})');
        } catch (e) {
          errors.add('${t['name']}: $e');
          debugPrint('[DemoSeed] ❌ failed for $uid: $e');
        }
      }
    } catch (e) {
      errors.add('שגיאה כללית: $e');
      debugPrint('[DemoSeed] ❌ outer failure: $e');
    }

    debugPrint(
        '[DemoSeed] done. created=$created skipped=$skipped errors=${errors.length}');

    // Report results to the admin via snackbar so failures are not silent
    if (mounted) {
      if (errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'זרעו דמו: ${errors.length} שגיאות. '
              'בדוק את ה-console (F12).\n${errors.first}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      } else if (created > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ נוצרו $created פרופילי דמו חדשים'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // If created=0 and errors=0, all 3 already exist — silent (good).
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _demoStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];

        return Scaffold(
          backgroundColor: Colors.grey[50],
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF6366F1),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'הוסף מומחה דמו',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () => _showForm(),
          ),
          body: docs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'אין מומחי דמו עדיין',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'לחץ על + כדי ליצור פרופיל ראשון',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final doc = docs[i];
                    final d = doc.data();
                    final uid = doc.id;
                    final name = d['name'] as String? ?? '—';
                    final img = d['profileImage'] as String? ?? '';
                    final parent = d['parentCategory'] as String?;
                    final sub = (d['subCategoryName'] as String?)?.isNotEmpty == true
                        ? d['subCategoryName'] as String
                        : null;
                    final cat = parent != null && sub != null
                        ? '$parent › $sub'
                        : (parent ?? sub ?? d['serviceType'] as String? ?? '—');
                    final rating = (d['rating'] as num? ?? 0).toDouble();
                    final reviews = (d['reviewsCount'] as num? ?? 0).toInt();
                    final gallery = (d['gallery'] as List? ?? []).length;
                    final hidden = d['isHidden'] as bool? ?? false;
                    final isTopRated = d['isTopRated'] as bool? ?? false;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: safeImageProvider(img),
                          child: safeImageProvider(img) == null
                              ? const Icon(Icons.person, color: Colors.grey)
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (isTopRated)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.workspace_premium,
                                    color: Color(0xFFF59E0B), size: 16),
                              ),
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'DEMO',
                                style: TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 3),
                            Text(
                              cat,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 13, color: Color(0xFFF59E0B)),
                                Text(
                                  ' ${rating.toStringAsFixed(1)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '  •  $reviews ביקורות',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                                Text(
                                  '  •  $gallery תמונות',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            GestureDetector(
                              onTap: () => _toggleHidden(uid, hidden),
                              child: Row(
                                children: [
                                  Icon(
                                    hidden
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 14,
                                    color: hidden
                                        ? Colors.red[400]
                                        : Colors.green[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    hidden ? 'מוסתר מחיפוש' : 'מוצג בחיפוש',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hidden
                                          ? Colors.red[400]
                                          : Colors.green[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: !hidden,
                              onChanged: (_) => _toggleHidden(uid, hidden),
                              activeColor: const Color(0xFF10B981),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Color(0xFF6366F1), size: 20),
                              onPressed: () =>
                                  _showForm(uid: uid, existing: d),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () => _delete(ctx, uid, name),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — Demo bookings list (every customer who tried to book a demo expert)
// ═══════════════════════════════════════════════════════════════════════════

class _DemoBookingsListTab extends StatelessWidget {
  const _DemoBookingsListTab();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('demo_bookings')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'שגיאת טעינה: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy_rounded, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'אין עדיין ניסיונות הזמנה לדמו',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                SizedBox(height: 6),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'כשלקוח ילחץ "הזמן עכשיו" על פרופיל דמו, הניסיון יופיע כאן',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final customerName = d['customerName'] as String? ?? 'לקוח';
            final customerImage = d['customerImage'] as String? ?? '';
            final customerPhone = d['customerPhone'] as String? ?? '';
            final demoExpertName = d['demoExpertName'] as String? ?? '—';
            final demoExpertCategory =
                d['demoExpertCategory'] as String? ?? '—';
            final ts = (d['createdAt'] as Timestamp?)?.toDate();
            final selectedDate = d['selectedDate'] as String? ?? '';
            final selectedTime = d['selectedTime'] as String? ?? '';
            final amount = (d['totalAmount'] as num? ?? 0).toDouble();
            final status = d['status'] as String? ?? 'pending';
            final isContacted = status == 'contacted';

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isContacted
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF6366F1)
                              .withValues(alpha: 0.12),
                          backgroundImage: safeImageProvider(customerImage),
                          child: safeImageProvider(customerImage) == null
                              ? Text(
                                  customerName.isNotEmpty
                                      ? customerName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (customerPhone.isNotEmpty)
                                Text(
                                  customerPhone,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isContacted
                                ? const Color(0xFF10B981)
                                    .withValues(alpha: 0.12)
                                : const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isContacted ? '✓ טופל' : 'ממתין',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isContacted
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 18),
                    // Details
                    _detailRow(
                      icon: Icons.person_outline_rounded,
                      label: 'מומחה דמו',
                      value: '$demoExpertName ($demoExpertCategory)',
                    ),
                    if (selectedDate.isNotEmpty)
                      _detailRow(
                        icon: Icons.calendar_today_rounded,
                        label: 'תאריך מבוקש',
                        value: '$selectedDate ${selectedTime.isNotEmpty ? "• $selectedTime" : ""}',
                      ),
                    if (amount > 0)
                      _detailRow(
                        icon: Icons.payments_outlined,
                        label: 'סכום הזמנה',
                        value: '₪${amount.toStringAsFixed(0)}',
                      ),
                    if (ts != null)
                      _detailRow(
                        icon: Icons.access_time_rounded,
                        label: 'ניסיון הזמנה',
                        value: DateFormat('dd/MM/yyyy HH:mm', 'he').format(ts),
                      ),
                    const SizedBox(height: 10),
                    // Actions
                    Row(
                      children: [
                        if (!isContacted)
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('סמן כטופל'),
                              onPressed: () =>
                                  docs[i].reference.update({
                                'status': 'contacted',
                                'contactedAt': FieldValue.serverTimestamp(),
                              }),
                            ),
                          ),
                        if (!isContacted) const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side:
                                const BorderSide(color: Color(0xFFEF4444)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('מחק'),
                          onPressed: () => docs[i].reference.delete(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _FakeReview model — supports both create and edit (with docId)
// ═══════════════════════════════════════════════════════════════════════════

class _FakeReview {
  final nameCtrl = TextEditingController();
  final commentCtrl = TextEditingController();
  double rating = 5.0;
  int daysAgo = 14;
  String? existingDocId; // null = new review, non-null = existing

  void dispose() {
    nameCtrl.dispose();
    commentCtrl.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _DemoExpertForm — full provider profile creator/editor
// ═══════════════════════════════════════════════════════════════════════════

class _DemoExpertForm extends StatefulWidget {
  final String? uid;
  final Map<String, dynamic>? existing;

  const _DemoExpertForm({this.uid, this.existing});

  @override
  State<_DemoExpertForm> createState() => _DemoExpertFormState();
}

class _DemoExpertFormState extends State<_DemoExpertForm> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;
  final _rng = Random();

  // ── Text controllers ──────────────────────────────────────────────────────
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _jobsCtrl;
  late final TextEditingController _priceCtrl;

  // ── Category ──────────────────────────────────────────────────────────────
  String? _selectedCategoryName;
  String? _selectedSubCategory;
  List<Map<String, String>> _mainCats = []; // [{id, name}]
  List<String> _subCats = [];
  bool _catsLoaded = false;

  // ── Images: profile + 6 gallery slots ─────────────────────────────────────
  String _profileImageUrl = '';
  bool _uploadingProfile = false;
  final List<String> _galleryUrls = ['', '', '', '', '', ''];
  final List<bool> _uploadingGallery = [false, false, false, false, false, false];

  // ── Working hours (per day, 0=Sun..6=Sat) ─────────────────────────────────
  // Default: 09:00–18:00 Sun-Thu, closed Fri-Sat
  Map<String, Map<String, String>> _workingHours = {
    '0': {'from': '09:00', 'to': '18:00'},
    '1': {'from': '09:00', 'to': '18:00'},
    '2': {'from': '09:00', 'to': '18:00'},
    '3': {'from': '09:00', 'to': '18:00'},
    '4': {'from': '09:00', 'to': '18:00'},
  };

  // ── Cancellation policy ───────────────────────────────────────────────────
  String _cancellationPolicy = 'flexible';

  // ── Dynamic v2 schema (per sub-category) ──────────────────────────────────
  ServiceSchema _activeSchema = ServiceSchema.empty();
  Map<String, dynamic> _categoryDetails = {};
  bool _loadingSchema = false;

  // ── Quick tags (selectable) ───────────────────────────────────────────────
  static const _availableQuickTags = [
    {'key': 'fast_response', 'emoji': '⚡', 'label': 'מגיב מהר'},
    {'key': 'reliable', 'emoji': '🛡️', 'label': 'אמין'},
    {'key': 'experienced', 'emoji': '💼', 'label': 'מנוסה'},
    {'key': 'flexible', 'emoji': '🤝', 'label': 'גמיש'},
    {'key': 'punctual', 'emoji': '⏰', 'label': 'מדייק בזמנים'},
    {'key': 'clean_work', 'emoji': '✨', 'label': 'עבודה נקייה'},
    {'key': 'budget_friendly', 'emoji': '💰', 'label': 'מחיר הוגן'},
    {'key': 'top_quality', 'emoji': '⭐', 'label': 'איכות גבוהה'},
  ];
  final Set<String> _selectedQuickTags = {};

  // ── Reviews — now editable in both create AND edit mode ──────────────────
  final List<_FakeReview> _reviews = [];
  bool _reviewsLoaded = false;

  // ── Misc ──────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? {};
    _nameCtrl = TextEditingController(text: e['name'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: e['phone'] as String? ?? '');
    _emailCtrl = TextEditingController(text: e['email'] as String? ?? '');
    _bioCtrl = TextEditingController(text: e['aboutMe'] as String? ?? '');
    _jobsCtrl = TextEditingController(
        text: (e['completedJobs'] as num? ?? 54).toString());
    _priceCtrl = TextEditingController(
        text: (e['pricePerHour'] as num? ?? 150).toString());

    _profileImageUrl = e['profileImage'] as String? ?? '';
    final gallery = (e['gallery'] as List? ?? []).cast<String>();
    for (int i = 0; i < 6 && i < gallery.length; i++) {
      _galleryUrls[i] = gallery[i];
    }

    // Working hours from existing user doc
    final wh = e['workingHours'] as Map<String, dynamic>?;
    if (wh != null && wh.isNotEmpty) {
      _workingHours = wh.map((k, v) {
        final m = (v as Map<String, dynamic>?) ?? {};
        return MapEntry(k, {
          'from': m['from'] as String? ?? '09:00',
          'to': m['to'] as String? ?? '18:00',
        });
      });
    }

    _cancellationPolicy =
        e['cancellationPolicy'] as String? ?? 'flexible';

    final existingTags =
        (e['quickTags'] as List? ?? []).cast<String>();
    _selectedQuickTags.addAll(existingTags);

    final existingDetails = e['categoryDetails'] as Map<String, dynamic>?;
    if (existingDetails != null) {
      _categoryDetails = Map<String, dynamic>.from(existingDetails);
    }

    final parentCat = e['parentCategory'] as String?;
    _selectedCategoryName = parentCat?.isNotEmpty == true
        ? parentCat
        : e['serviceType'] as String?;
    _selectedSubCategory = e['subCategoryName'] as String? ??
        e['subCategory'] as String?;

    _loadCategories();

    // Load existing reviews if editing
    if (widget.uid != null) {
      _loadExistingReviews();
    } else {
      // Create mode: start with 5 empty review slots
      for (int i = 0; i < 5; i++) {
        _reviews.add(_FakeReview());
      }
      _reviewsLoaded = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    _jobsCtrl.dispose();
    _priceCtrl.dispose();
    for (final r in _reviews) {
      r.dispose();
    }
    super.dispose();
  }

  // ── Load existing reviews (edit mode) ─────────────────────────────────────

  Future<void> _loadExistingReviews() async {
    try {
      final snap = await _db
          .collection('reviews')
          .where('expertId', isEqualTo: widget.uid)
          .where('isDemo', isEqualTo: true)
          .limit(20)
          .get();
      final loaded = <_FakeReview>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final r = _FakeReview()
          ..existingDocId = doc.id
          ..rating = (d['rating'] as num? ?? 5).toDouble();
        r.nameCtrl.text = d['reviewerName'] as String? ?? '';
        r.commentCtrl.text = d['comment'] as String? ?? '';

        final ts = d['timestamp'] as Timestamp?;
        if (ts != null) {
          final daysAgo = DateTime.now().difference(ts.toDate()).inDays;
          r.daysAgo = daysAgo > 0 ? daysAgo : 1;
        }
        loaded.add(r);
      }
      // Pad with empty slots so admin can add more (up to 5 total)
      while (loaded.length < 5) {
        loaded.add(_FakeReview());
      }
      if (mounted) {
        setState(() {
          _reviews.addAll(loaded);
          _reviewsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          for (int i = 0; i < 5; i++) {
            _reviews.add(_FakeReview());
          }
          _reviewsLoaded = true;
        });
      }
    }
  }

  // ── Load categories ───────────────────────────────────────────────────────

  Future<void> _loadCategories() async {
    final snap = await _db.collection('categories').limit(100).get();
    final mains = <Map<String, String>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final parentId = (d['parentId'] as String?) ?? '';
      if (parentId.isEmpty) {
        mains.add({'id': doc.id, 'name': (d['name'] as String? ?? '')});
      }
    }
    mains.sort((a, b) => a['name']!.compareTo(b['name']!));
    if (!mounted) return;
    setState(() {
      _mainCats = mains;
      _catsLoaded = true;
    });

    if (_selectedCategoryName != null) {
      final match = mains.firstWhere(
        (c) => c['name'] == _selectedCategoryName,
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        await _loadSubCategories(match['id']!);
      }
    }

    // Edit mode: if a sub-category is already selected, load its schema.
    if ((_selectedSubCategory ?? '').isNotEmpty) {
      await _loadSchemaFor(_selectedSubCategory!);
    } else if ((_selectedCategoryName ?? '').isNotEmpty) {
      await _loadSchemaFor(_selectedCategoryName!);
    }
  }

  /// Loads the v2 service schema for the given category/sub-category name.
  /// Stores it on `_activeSchema` so the v2 form can render fields + bundles
  /// + surcharge + booking requirements. Auto-applies the schema's default
  /// cancellation policy when the demo doesn't have one set yet.
  Future<void> _loadSchemaFor(String categoryName) async {
    if (!mounted) return;
    setState(() => _loadingSchema = true);
    try {
      final schema = await loadServiceSchemaFor(categoryName);
      if (mounted) {
        setState(() {
          _activeSchema = schema;
          _loadingSchema = false;
          // Auto-apply default policy when the admin hasn't picked one
          // (i.e. it's still on the initial 'flexible' default and the
          // existing demo doc didn't carry a value either).
          final hasExistingPolicy =
              (widget.existing?['cancellationPolicy'] as String?)?.isNotEmpty ??
                  false;
          if (!hasExistingPolicy && schema.defaultPolicy.isNotEmpty) {
            _cancellationPolicy = schema.defaultPolicy;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSchema = false);
    }
  }

  Future<void> _loadSubCategories(String parentDocId) async {
    final snap = await _db
        .collection('categories')
        .where('parentId', isEqualTo: parentDocId)
        .limit(50)
        .get();
    final subs = snap.docs
        .map((d) => (d.data()['name'] as String? ?? ''))
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
    if (!mounted) return;
    setState(() => _subCats = subs);
  }

  // ── Image upload helpers ──────────────────────────────────────────────────

  Future<String?> _pickAndUpload(String storagePath) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (xfile == null) return null;
      final bytes = await xfile.readAsBytes();
      final ext = xfile.name.split('.').last.toLowerCase();
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/$ext'),
      );
      return await task.ref.getDownloadURL();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאת העלאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _uploadProfileImage() async {
    setState(() => _uploadingProfile = true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = await _pickAndUpload('demo_experts/${ts}_profile.jpg');
    if (mounted) {
      setState(() {
        if (url != null) _profileImageUrl = url;
        _uploadingProfile = false;
      });
    }
  }

  Future<void> _uploadGalleryImage(int index) async {
    setState(() => _uploadingGallery[index] = true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = await _pickAndUpload('demo_experts/${ts}_gallery_$index.jpg');
    if (mounted) {
      setState(() {
        if (url != null) _galleryUrls[index] = url;
        _uploadingGallery[index] = false;
      });
    }
  }

  // ── Calculated rating ─────────────────────────────────────────────────────

  double get _calculatedRating {
    final filled =
        _reviews.where((r) => r.commentCtrl.text.trim().isNotEmpty).toList();
    if (filled.isEmpty) return 5.0;
    final sum = filled.fold<double>(0, (acc, r) => acc + r.rating);
    return double.parse((sum / filled.length).toStringAsFixed(1));
  }

  int get _filledReviewsCount =>
      _reviews.where((r) => r.commentCtrl.text.trim().isNotEmpty).length;

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryName == null || _selectedCategoryName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לבחור קטגוריה')),
      );
      return;
    }
    setState(() => _isSaving = true);

    try {
      final rating = _calculatedRating;
      final reviewsCount = _filledReviewsCount;
      final isTopRated = rating >= 4.8;
      final gallery = _galleryUrls.where((u) => u.isNotEmpty).toList();
      final uid = widget.uid ?? _db.collection('users').doc().id;
      final price = double.tryParse(_priceCtrl.text.trim()) ?? 150;

      // serviceType must equal the MOST SPECIFIC category name so search
      // queries find this expert when the user taps a sub-category card.
      final hasSub = (_selectedSubCategory ?? '').isNotEmpty;
      final effectiveType =
          hasSub ? _selectedSubCategory! : (_selectedCategoryName ?? '');

      // ── 1. Build user doc data ────────────────────────────────────────────
      final userData = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'aboutMe': _bioCtrl.text.trim(),
        'profileImage': _profileImageUrl,
        'serviceType': effectiveType,
        'subCategoryName': _selectedSubCategory ?? '',
        if (hasSub) 'parentCategory': _selectedCategoryName ?? '',
        'gallery': gallery,
        'completedJobs': int.tryParse(_jobsCtrl.text.trim()) ?? 54,
        'rating': rating,
        'reviewsCount': reviewsCount,
        'pricePerHour': price,
        'categoryDetails': _categoryDetails,
        'workingHours': _workingHours,
        'cancellationPolicy': _cancellationPolicy,
        'quickTags': _selectedQuickTags.toList(),
        'isProvider': true,
        'isCustomer': false,
        'isDemo': true,
        'isOnline': true,
        'isVerified': true,
        'isTopRated': isTopRated,
        'isHidden': widget.existing?['isHidden'] as bool? ?? false,
        'balance': 0,
      };

      // ── 2. Write user doc ─────────────────────────────────────────────────
      if (widget.uid != null) {
        await _db.collection('users').doc(uid).update(userData);
      } else {
        await _db.collection('users').doc(uid).set(userData);
      }

      // ── 3. Sync provider_listings doc ─────────────────────────────────────
      // Demo experts MUST have a listing or they won't appear in search.
      // Use a deterministic listing ID so we can upsert (id pattern: demo_{uid})
      final listingId = 'demo_$uid';
      final listingData = <String, dynamic>{
        'uid': uid,
        'identityIndex': 0,
        // Denormalized shared fields
        'name': _nameCtrl.text.trim(),
        'profileImage': _profileImageUrl,
        'isVerified': true,
        'isHidden': widget.existing?['isHidden'] as bool? ?? false,
        'isDemo': true,
        'isVolunteer': false,
        'isOnline': true,
        'isAnySkillPro': isTopRated,
        'isPromoted': false,
        // Identity-specific fields
        'serviceType': effectiveType,
        'parentCategory': hasSub ? (_selectedCategoryName ?? '') : '',
        'subCategory': _selectedSubCategory ?? '',
        'aboutMe': _bioCtrl.text.trim(),
        'pricePerHour': price,
        'gallery': gallery,
        'categoryDetails': _categoryDetails,
        'priceList': <String, dynamic>{},
        'quickTags': _selectedQuickTags.toList(),
        'workingHours': _workingHours,
        'cancellationPolicy': _cancellationPolicy,
        'rating': rating,
        'reviewsCount': reviewsCount,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // On create, also set createdAt
      if (widget.uid == null) {
        listingData['createdAt'] = FieldValue.serverTimestamp();
      }
      await _db
          .collection('provider_listings')
          .doc(listingId)
          .set(listingData, SetOptions(merge: true));

      // Also update the user doc with the listing reference
      await _db.collection('users').doc(uid).update({
        'listingIds': [listingId],
        'activeIdentityCount': 1,
      });

      // ── 4. Sync reviews ───────────────────────────────────────────────────
      // For each review slot:
      //   • New (existingDocId == null) and content present → add new doc
      //   • Existing and content present → update existing doc
      //   • Existing but content cleared → delete the existing doc
      for (final r in _reviews) {
        final name = r.nameCtrl.text.trim();
        final comment = r.commentCtrl.text.trim();
        final hasContent = name.isNotEmpty && comment.isNotEmpty;

        if (r.existingDocId != null) {
          if (hasContent) {
            // Update existing
            await _db.collection('reviews').doc(r.existingDocId).update({
              'reviewerName': name,
              'rating': r.rating,
              'comment': comment,
              // Don't update timestamp on edit — keeps the "X days ago" stable
            });
          } else {
            // Delete (cleared)
            await _db.collection('reviews').doc(r.existingDocId).delete();
          }
        } else if (hasContent) {
          // Brand new review
          final date = DateTime.now()
              .subtract(Duration(days: r.daysAgo + _rng.nextInt(3)));
          await _db.collection('reviews').add({
            'expertId': uid,
            'listingId': listingId,
            'reviewerId': 'demo_${_db.collection('users').doc().id}',
            'reviewerName': name,
            'rating': r.rating,
            'comment': comment,
            'timestamp': Timestamp.fromDate(date),
            'traitTags': const ['professional', 'punctual'],
            'isDemo': true,
          });
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.uid != null
                  ? '✅ פרופיל הדמו עודכן'
                  : '✅ פרופיל הדמו נוצר ויופיע בחיפוש',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.uid != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          // Use Stack so the bottom CTA stays sticky regardless of content length
          child: Stack(
            children: [
              ListView(
                controller: scrollCtrl,
                // Bottom padding leaves room for the sticky CTA bar
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isEdit ? 'ערוך מומחה דמו' : 'צור מומחה דמו חדש',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'הפרופיל יופיע בחיפוש כספק רגיל. לקוחות יוכלו לנסות להזמין.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // ── 1. Basic info ─────────────────────────────────────────
                  _sectionHeader('📋 פרטים בסיסיים'),
                  _field(_nameCtrl, 'שם המומחה *', Icons.person_outline),
                  _field(_phoneCtrl, 'טלפון', Icons.phone_outlined,
                      keyboard: TextInputType.phone),
                  _field(_emailCtrl, 'אימייל', Icons.email_outlined,
                      keyboard: TextInputType.emailAddress),
                  _field(_bioCtrl, 'ביו / תיאור שירות', Icons.notes_outlined,
                      maxLines: 3),
                  _field(_jobsCtrl, 'עבודות שהושלמו', Icons.work_outline,
                      keyboard: TextInputType.number),

                  // ── 2. Pricing ────────────────────────────────────────────
                  _sectionHeader('💰 תמחור'),
                  _field(_priceCtrl, 'מחיר לשעה (₪) — ברירת מחדל',
                      Icons.attach_money_rounded,
                      keyboard: TextInputType.number),
                  if (_loadingSchema)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!_activeSchema.isEmpty)
                    DynamicServiceSchemaForm(
                      key: ValueKey(
                          'schema_${_selectedSubCategory ?? _selectedCategoryName ?? ''}'),
                      schema: _activeSchema,
                      initialValues: _categoryDetails,
                      onChanged: (v) {
                        _categoryDetails = v;
                      },
                    ),

                  // ── 3. Category ───────────────────────────────────────────
                  _sectionHeader('🏷️ קטגוריה'),
                  if (!_catsLoaded)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    DropdownButtonFormField<String>(
                      value: _selectedCategoryName,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'קטגוריה ראשית *',
                        prefixIcon:
                            const Icon(Icons.category_outlined, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      items: _mainCats
                          .map((c) => DropdownMenuItem<String>(
                                value: c['name'],
                                child: Text(c['name']!,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedCategoryName = v;
                          _selectedSubCategory = null;
                          _subCats = [];
                          _activeSchema = ServiceSchema.empty();
                          _categoryDetails = {};
                        });
                        final match = _mainCats.firstWhere(
                          (c) => c['name'] == v,
                          orElse: () => {},
                        );
                        if (match.isNotEmpty) {
                          _loadSubCategories(match['id']!);
                        }
                        if (v != null && v.isNotEmpty) {
                          _loadSchemaFor(v);
                        }
                      },
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'נא לבחור קטגוריה'
                          : null,
                    ),
                    if (_subCats.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _selectedSubCategory,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'תת-קטגוריה (אופציונלי)',
                          prefixIcon: const Icon(
                              Icons.subdirectory_arrow_right,
                              size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('— ללא תת-קטגוריה —',
                                style: TextStyle(color: Colors.grey)),
                          ),
                          ..._subCats.map((s) => DropdownMenuItem<String>(
                                value: s,
                                child:
                                    Text(s, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _selectedSubCategory = v;
                            _activeSchema = ServiceSchema.empty();
                            _categoryDetails = {};
                          });
                          if (v != null && v.isNotEmpty) {
                            _loadSchemaFor(v);
                          } else if ((_selectedCategoryName ?? '').isNotEmpty) {
                            // Fallback to parent category schema
                            _loadSchemaFor(_selectedCategoryName!);
                          }
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),

                  // ── 4. Profile image ──────────────────────────────────────
                  _sectionHeader('📸 תמונת פרופיל'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                          image: safeImageProvider(_profileImageUrl) != null
                              ? DecorationImage(
                                  image: safeImageProvider(_profileImageUrl)!,
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: safeImageProvider(_profileImageUrl) == null
                            ? const Icon(Icons.person_outline,
                                color: Colors.grey, size: 36)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _uploadingProfile
                                  ? null
                                  : _uploadProfileImage,
                              icon: _uploadingProfile
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.upload_rounded,
                                      size: 18),
                              label: Text(_uploadingProfile
                                  ? 'מעלה...'
                                  : 'העלה מהמחשב'),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Color(0xFF6366F1)),
                                foregroundColor: const Color(0xFF6366F1),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: _profileImageUrl,
                              decoration: InputDecoration(
                                hintText: 'או הדבק URL של תמונה',
                                hintStyle: TextStyle(
                                    color: Colors.grey[400], fontSize: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                              onChanged: (v) => setState(
                                  () => _profileImageUrl = v.trim()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── 5. Gallery (6 slots) ──────────────────────────────────
                  _sectionHeader('🖼️ גלריית עבודות (עד 6 תמונות)'),
                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: 6,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.0,
                    ),
                    itemBuilder: (_, i) {
                      final url = _galleryUrls[i];
                      return GestureDetector(
                        onTap: () => _uploadGalleryImage(i),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.4),
                            ),
                            image: safeImageProvider(url) != null
                                ? DecorationImage(
                                    image: safeImageProvider(url)!,
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _uploadingGallery[i]
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : url.isEmpty
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate_outlined,
                                          color: Colors.grey[400],
                                          size: 28,
                                        ),
                                        Text(
                                          'תמונה ${i + 1}',
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Align(
                                      alignment: Alignment.topRight,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                            () => _galleryUrls[i] = ''),
                                        child: Container(
                                          margin: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: const Icon(Icons.close,
                                              color: Colors.white, size: 14),
                                        ),
                                      ),
                                    ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── 6. Working hours ──────────────────────────────────────
                  _sectionHeader('🕐 שעות פעילות'),
                  _buildWorkingHoursEditor(),
                  const SizedBox(height: 20),

                  // ── 7. Cancellation policy ────────────────────────────────
                  _sectionHeader('🛡️ מדיניות ביטולים'),
                  _buildPolicySelector(),
                  const SizedBox(height: 20),

                  // ── 8. Quick tags ─────────────────────────────────────────
                  _sectionHeader('🏷️ תגיות מהירות'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableQuickTags.map((tag) {
                      final selected =
                          _selectedQuickTags.contains(tag['key']);
                      return FilterChip(
                        label: Text('${tag['emoji']} ${tag['label']}'),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedQuickTags.add(tag['key']!);
                            } else {
                              _selectedQuickTags.remove(tag['key']);
                            }
                          });
                        },
                        selectedColor: const Color(0xFF6366F1)
                            .withValues(alpha: 0.15),
                        checkmarkColor: const Color(0xFF6366F1),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── 9. Reviews (editable) ─────────────────────────────────
                  _sectionHeader('⭐ ביקורות'),
                  if (!_reviewsLoaded)
                    const Center(child: CircularProgressIndicator())
                  else
                    ...List.generate(
                      _reviews.length,
                      (i) => _buildReviewSlot(i),
                    ),

                  const SizedBox(height: 8),
                  // Rating preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFF59E0B), size: 22),
                        const SizedBox(width: 6),
                        Text(
                          'דירוג מחושב: ${_calculatedRating.toStringAsFixed(1)} '
                          '($_filledReviewsCount ביקורות)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4338CA),
                            fontSize: 14,
                          ),
                        ),
                        if (_calculatedRating >= 4.8 &&
                            _filledReviewsCount > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.workspace_premium,
                              color: Color(0xFFF59E0B), size: 18),
                          const Text(
                            ' Top Rated',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),

              // ── Sticky bottom CTA bar ─────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        offset: const Offset(0, -2),
                        blurRadius: 8,
                      ),
                    ],
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text(
                            'ביטול',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              minimumSize:
                                  const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isSaving ? null : _save,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2),
                                  )
                                : Text(
                                    isEdit
                                        ? 'אשר ועדכן'
                                        : 'אשר והעלה',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Working hours editor ──────────────────────────────────────────────────

  Widget _buildWorkingHoursEditor() {
    const dayLabels = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    return Column(
      children: List.generate(7, (i) {
        final key = '$i';
        final isActive = _workingHours.containsKey(key);
        final from = _workingHours[key]?['from'] ?? '09:00';
        final to = _workingHours[key]?['to'] ?? '18:00';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Row(
                  children: [
                    Checkbox(
                      value: isActive,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _workingHours[key] = {
                              'from': '09:00',
                              'to': '18:00',
                            };
                          } else {
                            _workingHours.remove(key);
                          }
                        });
                      },
                    ),
                    Text(
                      dayLabels[i],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (isActive) ...[
                Expanded(
                  child: TextFormField(
                    initialValue: from,
                    enabled: isActive,
                    decoration: InputDecoration(
                      labelText: 'מ-',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) {
                      _workingHours[key] = {
                        ..._workingHours[key]!,
                        'from': v,
                      };
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: to,
                    enabled: isActive,
                    decoration: InputDecoration(
                      labelText: 'עד',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) {
                      _workingHours[key] = {
                        ..._workingHours[key]!,
                        'to': v,
                      };
                    },
                  ),
                ),
              ] else
                const Expanded(
                  child: Text(
                    'סגור',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // ── Cancellation policy selector ──────────────────────────────────────────

  Widget _buildPolicySelector() {
    final policies = [
      {
        'key': 'flexible',
        'label': 'גמיש',
        'desc': 'ביטול חינם עד 4 שעות לפני',
        'color': const Color(0xFF10B981),
      },
      {
        'key': 'moderate',
        'label': 'בינוני',
        'desc': 'ביטול חינם עד 24 שעות לפני',
        'color': const Color(0xFFF59E0B),
      },
      {
        'key': 'strict',
        'label': 'מחמיר',
        'desc': 'ביטול חינם עד 48 שעות לפני',
        'color': const Color(0xFFEF4444),
      },
      {
        'key': 'nonRefundable',
        'label': 'ללא החזר',
        'desc': 'ללא החזר כסף — שירותי חירום, קנס 100% תמיד',
        'color': const Color(0xFF7C2D12),
      },
    ];
    return Column(
      children: policies.map((p) {
        final selected = _cancellationPolicy == p['key'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () =>
                setState(() => _cancellationPolicy = p['key'] as String),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? (p['color'] as Color).withValues(alpha: 0.08)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? (p['color'] as Color)
                      : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? (p['color'] as Color)
                        : Colors.grey,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['label'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: selected
                                ? (p['color'] as Color)
                                : Colors.black87,
                          ),
                        ),
                        Text(
                          p['desc'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Review slot ───────────────────────────────────────────────────────────

  Widget _buildReviewSlot(int i) {
    final r = _reviews[i];
    final isExisting = r.existingDocId != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ביקורת ${i + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF4338CA),
                ),
              ),
              const SizedBox(width: 8),
              if (isExisting)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'נשמר',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              if (r.commentCtrl.text.isNotEmpty || r.nameCtrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      r.nameCtrl.clear();
                      r.commentCtrl.clear();
                      r.rating = 5.0;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: r.nameCtrl,
            textDirection: TextDirection.rtl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'שם הלקוח (למשל: ישראל ישראלי)',
              prefixIcon: const Icon(Icons.person_outline, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: r.commentCtrl,
            maxLines: 2,
            textDirection: TextDirection.rtl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'תוכן הביקורת',
              prefixIcon: const Icon(Icons.rate_review_outlined, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          // Star rating picker
          Row(
            children: [
              const Text('דירוג: ',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              ...List.generate(5, (s) {
                final filled = s < r.rating.round();
                return GestureDetector(
                  onTap: () => setState(() => r.rating = (s + 1).toDouble()),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 26,
                  ),
                );
              }),
              const SizedBox(width: 8),
              Text(
                r.rating.toStringAsFixed(0),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          // Days ago slider — only for new reviews (existing reviews keep their date)
          if (!isExisting) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'לפני ${r.daysAgo} ימים',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Expanded(
                  child: Slider(
                    value: r.daysAgo.toDouble(),
                    min: 1,
                    max: 90,
                    divisions: 89,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (v) =>
                        setState(() => r.daysAgo = v.round()),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        validator: label.endsWith('*')
            ? (v) =>
                (v == null || v.trim().isEmpty) ? 'שדה חובה' : null
            : null,
      ),
    );
  }
}
