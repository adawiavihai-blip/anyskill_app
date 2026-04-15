import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/category_service.dart';
import '../services/visual_fetcher_service.dart';
import 'pending_categories_screen.dart';

/// Self-contained Categories Management tab extracted from AdminScreen.
/// Owns its own state for image refresh, counter reset, and category CRUD.
class AdminCategoriesManagementTab extends StatefulWidget {
  const AdminCategoriesManagementTab({super.key});

  @override
  State<AdminCategoriesManagementTab> createState() =>
      _AdminCategoriesManagementTabState();
}

class _AdminCategoriesManagementTabState
    extends State<AdminCategoriesManagementTab> {
  bool _refreshingImages   = false;
  bool _fixingImages       = false;
  bool _resettingCounters  = false;
  int  _fixImagesDone      = 0;
  int  _fixImagesTotal     = 0;

  /// Formats raw click counts for compact display: 1 234 -> "1.2k", < 1 000 -> "$n".
  static String _fmtClicks(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  /// Resets clickCount to 0 on every category document in a single batch.
  Future<void> _resetPopularityCounters(
      List<Map<String, dynamic>> allCats) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.restart_alt_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('איפוס מונים', style: TextStyle(fontSize: 17)),
        ]),
        content: const Text(
          'פעולה זו תאפס את מונה הלחיצות של כל הקטגוריות ל-0.\n'
          'הדירוג הדינמי יתחיל מחדש.\n\n'
          'האם אתה בטוח?',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('אפס', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingCounters = true);
    try {
      final db    = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final cat in allCats) {
        batch.update(
          db.collection('categories').doc(cat['id'] as String),
          {'clickCount': 0},
        );
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          content: Text('מוני הפופולריות אופסו בהצלחה'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('שגיאה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _resettingCounters = false);
    }
  }

  /// Top-5 leaderboard card shown at the top of the categories tab.
  Widget _buildPopularityLeaderboard(List<Map<String, dynamic>> mainCats) {
    final top = (List.of(mainCats)
          ..sort((a, b) {
            final cA = (a['clickCount'] as num? ?? 0).toInt();
            final cB = (b['clickCount'] as num? ?? 0).toInt();
            return cB.compareTo(cA);
          }))
        .take(5)
        .toList();

    // Don't show the leaderboard if no category has any clicks yet.
    final totalClicks =
        top.fold<int>(0, (s, c) => s + (c['clickCount'] as num? ?? 0).toInt());
    if (totalClicks == 0) return const SizedBox.shrink();

    const medals = ['🥇', '🥈', '🥉', '4.', '5.'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.local_fire_department_rounded,
                  color: Color(0xFFFBBF24), size: 20),
              SizedBox(width: 6),
              Text('Top 5 — קטגוריות הכי פופולריות',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ]),
            const SizedBox(height: 12),
            ...top.asMap().entries.map((e) {
              final rank   = e.key;
              final cat    = e.value;
              final clicks = (cat['clickCount'] as num? ?? 0).toInt();
              final pct    = totalClicks > 0 ? clicks / totalClicks : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  // Medal / rank
                  SizedBox(
                    width: 28,
                    child: Text(medals[rank],
                        style: const TextStyle(fontSize: 14)),
                  ),
                  // Name
                  Expanded(
                    child: Text(
                      cat['name'] as String? ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Progress bar
                  SizedBox(
                    width: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct.toDouble(),
                        minHeight: 6,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFBBF24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Count
                  Text(
                    '${_fmtClicks(clicks)} 👁',
                    style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CategoryService.stream(),
      builder: (context, snapshot) {
        final cats = snapshot.data ?? [];
        final mainCats = cats.where((c) => (c['parentId'] as String? ?? '').isEmpty).toList();
        final subCats  = cats.where((c) => (c['parentId'] as String? ?? '').isNotEmpty).toList();

        // Build grouped items: for each main cat append its subs
        final List<Map<String, dynamic>> grouped = [];
        for (final main in mainCats) {
          grouped.add({...main, '_isMain': true});
          final children = subCats.where((s) => s['parentId'] == main['id']).toList();
          for (final sub in children) {
            grouped.add({...sub, '_isMain': false, '_parentName': main['name']});
          }
        }

        return Column(
          children: [
            // ── Global card scale slider ────────────────────────────────────
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('system_settings')
                  .doc('global')
                  .snapshots(),
              builder: (context, settingsSnap) {
                final settingsData =
                    (settingsSnap.data?.data() as Map<String, dynamic>?) ?? {};
                final currentScale =
                    (settingsData['categoryCardScale'] as num? ?? 1.0).toDouble();

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  decoration: BoxDecoration(
                    color:        Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.aspect_ratio_rounded,
                              color: Color(0xFF6366F1), size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'גודל כרטיסי קטגוריה — גלובלי',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${currentScale.toStringAsFixed(2)}x',
                              style: const TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value:       currentScale,
                        min:         0.6,
                        max:         1.5,
                        divisions:   18,
                        activeColor: const Color(0xFF6366F1),
                        inactiveColor:
                            const Color(0xFF6366F1).withValues(alpha: 0.15),
                        // onChanged is required by Flutter; visual feedback only --
                        // the StreamBuilder will re-render when Firestore updates.
                        onChanged:   (_) {},
                        onChangeEnd: (v) {
                          FirebaseFirestore.instance
                              .collection('system_settings')
                              .doc('global')
                              .set({'categoryCardScale': v},
                                  SetOptions(merge: true));
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0.6x',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 11)),
                          TextButton(
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero),
                            onPressed: (currentScale - 1.0).abs() < 0.01
                                ? null
                                : () {
                                    FirebaseFirestore.instance
                                        .collection('system_settings')
                                        .doc('global')
                                        .set({'categoryCardScale': 1.0},
                                            SetOptions(merge: true));
                                  },
                            child: const Text('איפוס לברירת מחדל (1.0x)',
                                style: TextStyle(fontSize: 11)),
                          ),
                          Text('1.5x',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text("הוסף קטגוריה", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () => _showCategoryDialog(existingCount: cats.length),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1)),
                label: const Text("קטגוריות ממתינות לאישור AI",
                    style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PendingCategoriesScreen())),
              ),
            ),
            // ── AI Auto-Created Categories Log ──────────────────────────
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('admin_logs')
                  .where('type', isEqualTo: 'new_category')
                  .where('isReviewed', isEqualTo: false)
                  .orderBy('createdAt', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Row(children: [
                        const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6), size: 18),
                        const SizedBox(width: 6),
                        Text('קטגוריות חדשות שנוצרו ע"י AI (${docs.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8B5CF6))),
                      ]),
                    ),
                    ...docs.map((doc) {
                      final d = doc.data()! as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFDDD6FE)),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.new_label_rounded, color: Color(0xFF8B5CF6), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['categoryName'] ?? '—',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (d['subCategoryName'] != null)
                                      Text('תת-קטגוריה: ${d['subCategoryName']}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                                    const SizedBox(height: 4),
                                    Text('על בסיס: "${d['triggerDescription'] ?? ''}"',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                    Text('ביטחון: ${((d['confidence'] as num? ?? 0) * 100).round()}%',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => FirebaseFirestore.instance
                                    .collection('admin_logs')
                                    .doc(doc.id)
                                    .update({'isReviewed': true}),
                                child: const Text('סמן כנבדק', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
            // ── Refresh Category Images ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _refreshingImages
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.image_search_rounded, color: Colors.white),
                label: Text(
                  _refreshingImages ? 'מרענן תמונות...' : 'רענן תמונות קטגוריה',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: _refreshingImages
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _refreshingImages = true);
                        try {
                          await VisualFetcherService.forceRefreshAll();
                          messenger.showSnackBar(const SnackBar(
                            backgroundColor: Color(0xFF22C55E),
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              'תמונות הקטגוריות עודכנו בהצלחה',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ));
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('שגיאה: $e'),
                          ));
                        } finally {
                          if (mounted) setState(() => _refreshingImages = false);
                        }
                      },
              ),
            ),
            // ── Fix All Images (unique, no duplicates) ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _fixingImages
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_fix_high_rounded, color: Colors.white),
                label: Text(
                  _fixingImages
                      ? 'מתקן תמונות... $_fixImagesDone/$_fixImagesTotal'
                      : 'תקן כל התמונות (ייחודי)',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: (_fixingImages || _refreshingImages)
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() {
                          _fixingImages   = true;
                          _fixImagesDone  = 0;
                          _fixImagesTotal = 0;
                        });
                        try {
                          await VisualFetcherService.fixAllImages(
                            onProgress: (done, total) {
                              if (mounted) {
                                setState(() {
                                  _fixImagesDone  = done;
                                  _fixImagesTotal = total;
                                });
                              }
                            },
                          );
                          messenger.showSnackBar(const SnackBar(
                            backgroundColor: Color(0xFF22C55E),
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              'כל תמונות הקטגוריות עודכנו בהצלחה!',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ));
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('שגיאה: $e'),
                          ));
                        } finally {
                          if (mounted) setState(() => _fixingImages = false);
                        }
                      },
              ),
            ),
            // ── Popularity Leaderboard ──────────────────────────────────────
            _buildPopularityLeaderboard(mainCats),

            // ── Reset Counters button ───────────────────────────────────────
            if (cats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _resettingCounters
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.orange))
                      : const Icon(Icons.restart_alt_rounded),
                  label: Text(
                    _resettingCounters
                        ? 'מאפס...'
                        : 'אפס מוני פופולריות',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed:
                      _resettingCounters ? null : () => _resetPopularityCounters(cats),
                ),
              ),

            if (!snapshot.hasData)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (cats.isEmpty)
              const Expanded(
                child: Center(
                  child: Text("אין קטגוריות — לחץ 'הוסף'", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final cat = grouped[index];
                    final isMain = cat['_isMain'] as bool;
                    final parentName = cat['_parentName'] as String?;

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: 10,
                        left: isMain ? 0 : 24, // indent sub-categories
                      ),
                      child: Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isMain ? Colors.grey.shade200 : Colors.blue.shade100,
                          ),
                        ),
                        color: isMain ? Colors.white : Colors.blue.shade50,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isMain ? Colors.blue[50] : Colors.blue[100],
                            child: Icon(
                              CategoryService.getIcon(cat['iconName']),
                              color: isMain ? Colors.blueAccent : Colors.blue[700],
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              if (!isMain)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[200],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text("תת", style: TextStyle(fontSize: 10, color: Colors.blue[900], fontWeight: FontWeight.bold)),
                                ),
                              Expanded(
                                child: Text(
                                  cat['name'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMain ? 15 : 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            isMain ? (cat['iconName'] ?? '') : "תחת: $parentName",
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ── Click-count badge ──────────────────────
                              Builder(builder: (_) {
                                final clicks =
                                    (cat['clickCount'] as num? ?? 0).toInt();
                                final isHot  = clicks >= 100;
                                final isWarm = clicks >= 10;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isHot
                                        ? Colors.orange[50]
                                        : isWarm
                                            ? Colors.amber[50]
                                            : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isHot
                                          ? Colors.orange.shade300
                                          : isWarm
                                              ? Colors.amber.shade300
                                              : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isHot ? '🔥' : '👁',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _fmtClicks(clicks),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isHot
                                              ? Colors.orange[800]
                                              : isWarm
                                                  ? Colors.amber[800]
                                                  : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                                onPressed: () => _showCategoryDialog(existing: cat, existingCount: cats.length),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => _confirmDeleteCategory(cat['id'] as String, cat['name'] ?? '', isMain: isMain),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Category CRUD dialogs ─────────────────────────────────────────────────

  void _showCategoryDialog({Map<String, dynamic>? existing, int existingCount = 0}) {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final imgController = TextEditingController(text: existing?['img'] ?? '');
    String selectedIcon = existing?['iconName'] ?? CategoryService.iconMap.keys.first;
    String selectedParentId = existing?['parentId'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(existing == null ? "הוסף קטגוריה" : "עריכת קטגוריה", textAlign: TextAlign.right),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Parent category selector ──────────────────────────────
                const Text("קטגוריית אב", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: CategoryService.streamMainCategories(),
                  builder: (_, snap) {
                    final mainCats = snap.data ?? [];
                    final validParentId = mainCats.any((c) => c['id'] == selectedParentId)
                        ? selectedParentId
                        : '';
                    if (validParentId != selectedParentId) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setDialog(() => selectedParentId = validParentId);
                      });
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButton<String>(
                        value: validParentId,
                        isExpanded: true,
                        underline: const SizedBox(),
                        onChanged: (val) {
                          if (val != null) setDialog(() => selectedParentId = val);
                        },
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Row(children: [
                              Icon(Icons.folder_outlined, size: 18, color: Colors.grey),
                              SizedBox(width: 8),
                              Text("ראשי (ללא הורה)", style: TextStyle(fontSize: 13)),
                            ]),
                          ),
                          ...mainCats.map((c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Row(children: [
                              Icon(CategoryService.getIcon(c['iconName']), size: 18, color: Colors.blueAccent),
                              const SizedBox(width: 8),
                              Text(c['name'] ?? '', style: const TextStyle(fontSize: 13)),
                            ]),
                          )),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // ── Name ─────────────────────────────────────────────────
                const Text("שם קטגוריה", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: "לדוגמה: פילאטיס",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Icon ─────────────────────────────────────────────────
                const Text("אייקון", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: selectedIcon,
                    isExpanded: true,
                    underline: const SizedBox(),
                    onChanged: (val) {
                      if (val != null) setDialog(() => selectedIcon = val);
                    },
                    items: CategoryService.iconMap.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Icon(e.value, size: 20, color: Colors.blueAccent),
                          const SizedBox(width: 10),
                          Text(e.key, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Image URL ────────────────────────────────────────────
                const Text("קישור תמונה (אופציונלי)", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: imgController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: "https://...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                if (existing == null) {
                  await FirebaseFirestore.instance.collection('categories').doc(name).set({
                    'name': name,
                    'iconName': selectedIcon,
                    'img': imgController.text.trim(),
                    'order': existingCount,
                    'parentId': selectedParentId,
                  });
                } else {
                  await FirebaseFirestore.instance.collection('categories').doc(existing['id'] as String).update({
                    'name': name,
                    'iconName': selectedIcon,
                    'img': imgController.text.trim(),
                    'parentId': selectedParentId,
                  });
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: Colors.green, content: Text(existing == null ? "הקטגוריה נוספה!" : "הקטגוריה עודכנה!")),
                  );
                }
              },
              child: const Text("שמור", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCategory(String docId, String name, {bool isMain = true}) async {
    // For main categories, check how many sub-categories will also be deleted
    int subCount = 0;
    if (isMain) {
      final subSnap = await FirebaseFirestore.instance
          .collection('categories')
          .where('parentId', isEqualTo: docId)
          .get();
      subCount = subSnap.docs.length;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("מחיקת קטגוריה", textAlign: TextAlign.right),
        content: Text(
          subCount > 0
              ? "האם למחוק את הקטגוריה \"$name\"?\nגם $subCount תת-קטגוריות שלה יימחקו.\nפעולה זו אינה ניתנת לביטול."
              : "האם למחוק את הקטגוריה \"$name\"?\nפעולה זו אינה ניתנת לביטול.",
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              // Cascade delete: remove all sub-categories first, then the parent
              final subSnap = await FirebaseFirestore.instance
                  .collection('categories')
                  .where('parentId', isEqualTo: docId)
                  .get();
              final batch = FirebaseFirestore.instance.batch();
              for (final sub in subSnap.docs) {
                batch.delete(sub.reference);
              }
              batch.delete(FirebaseFirestore.instance.collection('categories').doc(docId));
              await batch.commit();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("הקטגוריה \"$name\" נמחקה")),
                );
              }
            },
            child: const Text("מחק", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
