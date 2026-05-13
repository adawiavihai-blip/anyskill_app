// Admin CSM Preview tab.
//
// Lets the admin pick a category + sub-category and preview the full
// category-specific module (CSM) settings block that the provider sees
// after they pick that sub-category in their profile.
//
// Read-only preview: the blocks accept a no-op onChanged so nothing
// persists. Internal block state still responds to taps so the admin
// can explore + try fields. Wrapped in a local _CsmSafeBoundary so a
// crash in any single block doesn't take down the admin shell — same
// pattern as admin_demo_experts_tab.dart (CLAUDE.md §4.7).
//
// Supported CSMs (CLAUDE.md §3d/§32/§33/§34/§41/§44/§53/§motorcycle):
//   • עיסוי              → MassageSettingsBlock
//   • הדברה             → PestControlSettingsBlock
//   • משלוחים           → DeliverySettingsBlock
//   • נקיון              → CleaningSettingsBlock
//   • הנדימן            → HandymanSettingsBlock
//   • מאמני כושר        → FitnessTrainerSettingsBlock
//   • בייביסיטר          → BabysitterSettingsBlock
//   • גרר אופנועים      → MotorcycleTowSettingsBlock

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/babysitter_profile.dart';
import '../models/cleaning_profile.dart';
import '../models/delivery_profile.dart';
import '../models/fitness_trainer_profile.dart';
import '../models/handyman_profile.dart';
import '../models/massage_profile.dart';
import '../models/motorcycle_tow_profile.dart';
import '../models/pest_control_profile.dart';

import '../services/csm_text_override_service.dart';
import 'csm_text_keys.dart';

import 'babysitter/babysitter_settings_block.dart';
import 'cleaning/cleaning_settings_block.dart';
import 'delivery/delivery_settings_block.dart';
import 'fitness_trainer/fitness_trainer_settings_block.dart';
import 'handyman/handyman_settings_block.dart';
import 'massage/massage_settings_block.dart';
import 'motorcycle_tow/motorcycle_tow_settings_block.dart';
import 'pest_control/pest_control_settings_block.dart';

class AdminCsmPreviewTab extends StatefulWidget {
  const AdminCsmPreviewTab({super.key});

  @override
  State<AdminCsmPreviewTab> createState() => _AdminCsmPreviewTabState();
}

class _AdminCsmPreviewTabState extends State<AdminCsmPreviewTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Map<String, String>> _mainCats = []; // [{id, name}]
  List<String> _subCats = [];
  bool _catsLoaded = false;
  bool _loadingSubs = false;

  String? _selectedCategoryName;
  String? _selectedSubCategory;

  @override
  void initState() {
    super.initState();
    _loadMainCategories();
  }

  Future<void> _loadMainCategories() async {
    try {
      final snap = await _db.collection('categories').limit(100).get();
      final mains = <Map<String, String>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final parentId = (d['parentId'] as String?) ?? '';
        if (parentId.isEmpty) {
          mains.add({'id': doc.id, 'name': (d['name'] as String? ?? '')});
        }
      }
      mains.removeWhere((m) => (m['name'] ?? '').isEmpty);
      mains.sort((a, b) => a['name']!.compareTo(b['name']!));
      if (!mounted) return;
      setState(() {
        _mainCats = mains;
        _catsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _catsLoaded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בטעינת קטגוריות: $e')),
      );
    }
  }

  Future<void> _loadSubCategoriesFor(String parentDocId) async {
    setState(() {
      _loadingSubs = true;
      _subCats = [];
    });
    try {
      final snap = await _db
          .collection('categories')
          .where('parentId', isEqualTo: parentDocId)
          .limit(100)
          .get();
      final subs = snap.docs
          .map((d) => (d.data()['name'] as String? ?? ''))
          .where((n) => n.isNotEmpty)
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _subCats = subs;
        _loadingSubs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSubs = false);
    }
  }

  // ── CSM detection ──────────────────────────────────────────────────────────

  /// Tries the sub-category first, then falls back to the main category.
  /// Same priority as `admin_demo_experts_tab.dart`.
  String? _matchedCsm() {
    final sub = _selectedSubCategory ?? '';
    final main = _selectedCategoryName ?? '';
    if (isMassageCategory(sub) || isMassageCategory(main)) return 'massage';
    if (isPestControlCategory(sub) || isPestControlCategory(main)) {
      return 'pest_control';
    }
    if (isDeliveryCategory(sub) || isDeliveryCategory(main)) return 'delivery';
    if (isCleaningCategory(sub) || isCleaningCategory(main)) return 'cleaning';
    if (isHandymanCategory(sub) || isHandymanCategory(main)) return 'handyman';
    if (isFitnessTrainerCategory(sub) || isFitnessTrainerCategory(main)) {
      return 'fitness_trainer';
    }
    if (isBabysitterCategory(sub) || isBabysitterCategory(main)) {
      return 'babysitter';
    }
    if (isMotorcycleTowingCategory(sub) ||
        isMotorcycleTowingCategory(main)) {
      return 'motorcycle_tow';
    }
    return null;
  }

  Widget _buildCsmBlock(String csm) {
    // Each block gets a const empty profile + no-op onChanged so nothing
    // ever persists. Keyed on the csm id so swapping sub-categories
    // mounts a fresh State instead of leaking values across.
    switch (csm) {
      case 'massage':
        return MassageSettingsBlock(
          key: const ValueKey('csm_preview_massage'),
          initialProfile: const MassageProfile(),
          onChanged: (_) {},
        );
      case 'pest_control':
        return PestControlSettingsBlock(
          key: const ValueKey('csm_preview_pest'),
          initialProfile: const PestControlProfile(),
          onChanged: (_) {},
        );
      case 'delivery':
        return DeliverySettingsBlock(
          key: const ValueKey('csm_preview_delivery'),
          initialProfile: const DeliveryProfile(),
          onChanged: (_) {},
        );
      case 'cleaning':
        return CleaningSettingsBlock(
          key: const ValueKey('csm_preview_cleaning'),
          initialProfile: const CleaningProfile(),
          onChanged: (_) {},
        );
      case 'handyman':
        return HandymanSettingsBlock(
          key: const ValueKey('csm_preview_handyman'),
          initialProfile: const HandymanProfile(),
          onChanged: (_) {},
        );
      case 'fitness_trainer':
        return FitnessTrainerSettingsBlock(
          key: const ValueKey('csm_preview_fitness'),
          initialProfile: const FitnessTrainerProfile(),
          onChanged: (_) {},
        );
      case 'babysitter':
        return BabysitterSettingsBlock(
          key: const ValueKey('csm_preview_babysitter'),
          initialProfile: const BabysitterProfile(),
          onChanged: (_) {},
        );
      case 'motorcycle_tow':
        return MotorcycleTowSettingsBlock(
          key: const ValueKey('csm_preview_motorcycle_tow'),
          initialProfile: const MotorcycleTowProfile(),
          onChanged: (_) {},
        );
    }
    return const SizedBox.shrink();
  }

  String _csmHebrewLabel(String csm) {
    switch (csm) {
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
      case 'fitness_trainer':
        return 'מאמני כושר';
      case 'babysitter':
        return 'בייביסיטר';
      case 'motorcycle_tow':
        return 'גרר אופנועים';
    }
    return csm;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final matched = _matchedCsm();

    return Container(
      color: const Color(0xFFF5F7FA),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildIntroCard(),
            const SizedBox(height: 14),
            _buildPickerCard(),
            const SizedBox(height: 14),
            if (_selectedSubCategory == null && _selectedCategoryName == null)
              _buildPlaceholder(
                icon: Icons.touch_app_rounded,
                title: 'בחר/י קטגוריה ותת-קטגוריה',
                body:
                    'אחרי הבחירה יופיע כאן כל הבלוק שהנותן שירות צריך למלא בקטגוריה הזו.',
              )
            else if (matched == null)
              _buildPlaceholder(
                icon: Icons.info_outline_rounded,
                title: 'אין CSM מותאם לקטגוריה הזו',
                body:
                    'הקטגוריות שיש להן בלוק ייעודי כרגע: עיסוי, הדברה, משלוחים, נקיון, הנדימן, מאמני כושר, בייביסיטר, גרר אופנועים.\n\nבקטגוריות אחרות הנותן שירות רואה רק את שדות הפרופיל הסטנדרטיים (מחיר, תיאור, גלריה וכו׳).',
              )
            else ...[
              _buildPreviewBanner(_csmHebrewLabel(matched)),
              const SizedBox(height: 12),
              if ((kAllCsmTextKeys[matched] ?? const []).isNotEmpty) ...[
                _CsmTextEditPanel(
                  csmId: matched,
                  csmLabel: _csmHebrewLabel(matched),
                  keys: kAllCsmTextKeys[matched]!,
                ),
                const SizedBox(height: 12),
              ],
              _CsmSafeBoundary(
                child: RepaintBoundary(child: _buildCsmBlock(matched)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x336366F1), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.preview_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('CSM Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    )),
                SizedBox(height: 2),
                Text(
                  'בחר/י קטגוריה + תת-קטגוריה ותראה/י את הבלוק המלא שהנותן שירות יקבל באותה קטגוריה.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_catsLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _selectedCategoryName,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'קטגוריה ראשית',
                prefixIcon: const Icon(Icons.category_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
              items: _mainCats
                  .map((c) => DropdownMenuItem<String>(
                        value: c['name'],
                        child: Text(
                          c['name']!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedCategoryName = v;
                  _selectedSubCategory = null;
                  _subCats = [];
                });
                if (v == null) return;
                final match = _mainCats.firstWhere(
                  (c) => c['name'] == v,
                  orElse: () => {},
                );
                if (match.isNotEmpty) {
                  _loadSubCategoriesFor(match['id']!);
                }
              },
            ),
            const SizedBox(height: 12),
            if (_selectedCategoryName != null) ...[
              if (_loadingSubs)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_subCats.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'אין תתי-קטגוריות לקטגוריה זו ב-Firestore.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedSubCategory,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'תת-קטגוריה',
                    prefixIcon:
                        const Icon(Icons.subdirectory_arrow_right, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        '— ללא תת-קטגוריה —',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ..._subCats.map((s) => DropdownMenuItem<String>(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedSubCategory = v),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewBanner(String csmLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFBBF24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_rounded,
              color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'תצוגה מקדימה — CSM "$csmLabel"',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFB45309),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'זה בדיוק הבלוק שהנותן שירות רואה. מילוי שדות בבלוק עצמו לא נשמר — לעריכת טקסטים השתמש/י בלוח שלמטה.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: const Color(0xFF6B7280)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Color(0xFF111827)),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF6B7280), height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local crash boundary (mirrors admin_demo_experts_tab.dart's _CsmSafeBoundary).
// CSM blocks are 1k–3k LOC widgets — a single build error must NOT take down
// the whole admin shell.
// ─────────────────────────────────────────────────────────────────────────────

class _CsmSafeBoundary extends StatefulWidget {
  const _CsmSafeBoundary({required this.child});
  final Widget child;

  @override
  State<_CsmSafeBoundary> createState() => _CsmSafeBoundaryState();
}

class _CsmSafeBoundaryState extends State<_CsmSafeBoundary> {
  Object? _error;
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'שגיאה בטעינת בלוק הקטגוריה',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$_error',
              style: const TextStyle(fontSize: 11, color: Color(0xFF7F1D1D)),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _error = null;
                  _attempt++;
                }),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('נסה שוב'),
              ),
            ),
          ],
        ),
      );
    }
    return _CsmGuardedChild(
      key: ValueKey(_attempt),
      onError: (e, st) {
        if (!mounted) return;
        // ignore: avoid_print
        print('[AdminCsmPreview] crash: $e\n$st');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _error = e);
        });
      },
      child: widget.child,
    );
  }
}

class _CsmGuardedChild extends StatelessWidget {
  const _CsmGuardedChild({
    super.key,
    required this.child,
    required this.onError,
  });
  final Widget child;
  final void Function(Object error, StackTrace stack) onError;

  @override
  Widget build(BuildContext context) {
    try {
      return child;
    } catch (e, st) {
      onError(e, st);
      return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CSM Text Edit Panel.
//
// Shown above the live preview when the matched CSM has a Stage-1 key
// registry (`kAllCsmTextKeys[csmId]`). Each editable string is a TextField
// pre-populated with the current Firestore override (or empty if the key
// falls back to default). Save → bulk-write to `csm_text_overrides/{csmId}`.
// Reset (per-row) deletes that key. Reset-all clears every override for
// this CSM. The live preview below auto-rebuilds via the service's
// ChangeNotifier — admin sees their edit immediately.
// ─────────────────────────────────────────────────────────────────────────────

class _CsmTextEditPanel extends StatefulWidget {
  final String csmId;
  final String csmLabel;
  final List<CsmTextKey> keys;

  const _CsmTextEditPanel({
    required this.csmId,
    required this.csmLabel,
    required this.keys,
  });

  @override
  State<_CsmTextEditPanel> createState() => _CsmTextEditPanelState();
}

class _CsmTextEditPanelState extends State<_CsmTextEditPanel> {
  final _service = CsmTextOverrideService.instance;

  /// One controller per key. Pre-populated with the current override (if any).
  /// Empty means "fall through to default" — placeholder shows the default.
  final Map<String, TextEditingController> _ctrls = {};

  bool _expanded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service.ensureLoaded(widget.csmId);
    _service.addListener(_syncFromService);
    for (final k in widget.keys) {
      _ctrls[k.id] = TextEditingController();
    }
    _syncFromService();
  }

  @override
  void didUpdateWidget(covariant _CsmTextEditPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.csmId != widget.csmId) {
      // Different CSM picked — wipe controllers, re-seed from new CSM's
      // overrides. Keys differ between CSMs so we rebuild the map.
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      for (final k in widget.keys) {
        _ctrls[k.id] = TextEditingController();
      }
      _service.ensureLoaded(widget.csmId);
      _syncFromService();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_syncFromService);
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rehydrates each controller's text from the service snapshot. Only
  /// runs if the field doesn't already have user-typed text matching what
  /// the snapshot holds — otherwise admin's in-progress edit would get
  /// stomped by a stream tick.
  void _syncFromService() {
    if (!mounted) return;
    final snap = _service.snapshotFor(widget.csmId);
    bool changed = false;
    for (final k in widget.keys) {
      final remote = snap[k.id] ?? '';
      final ctrl = _ctrls[k.id];
      if (ctrl == null) continue;
      // Don't fight the user mid-typing — only sync if the field is empty
      // OR matches the previous remote value. After a save round-trip the
      // text == remote, so this is safe.
      if (ctrl.text.isEmpty || ctrl.text == remote) {
        if (ctrl.text != remote) {
          ctrl.text = remote;
          changed = true;
        }
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    final snap = _service.snapshotFor(widget.csmId);
    final edits = <String, String?>{};
    for (final k in widget.keys) {
      final ctrl = _ctrls[k.id];
      if (ctrl == null) continue;
      final typed = ctrl.text.trim();
      final current = snap[k.id] ?? '';
      if (typed != current) {
        // Empty value → null = FieldValue.delete() → falls back to default.
        edits[k.id] = typed.isEmpty ? null : typed;
      }
    }
    if (edits.isEmpty) {
      _showSnack('אין שינויים לשמור');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.bulkSetOverrides(widget.csmId, edits);
      if (!mounted) return;
      _showSnack('נשמרו ${edits.length} שינויים — הנותני שירות יראו אותם מיידית');
    } catch (e) {
      if (!mounted) return;
      _showSnack('שגיאה בשמירה: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetSingle(CsmTextKey k) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('איפוס לברירת מחדל'),
        content: Text(
            'הטקסט "${k.label}" יחזור לערך המקורי:\n\n${k.defaultValue}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('אפס',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.resetOverride(widget.csmId, k.id);
      _ctrls[k.id]?.text = '';
      if (!mounted) return;
      _showSnack('"${k.label}" אופס');
    } catch (e) {
      if (!mounted) return;
      _showSnack('שגיאה: $e', isError: true);
    }
  }

  Future<void> _resetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('איפוס הכל'),
        content: Text(
          'כל הטקסטים שערכת ב-CSM "${widget.csmLabel}" יחזרו לברירת המחדל. '
          'הפעולה מיידית ולא ניתנת לביטול.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('אפס הכל',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final edits = <String, String?>{};
    for (final k in widget.keys) {
      edits[k.id] = null;
    }
    setState(() => _saving = true);
    try {
      await _service.bulkSetOverrides(widget.csmId, edits);
      for (final c in _ctrls.values) {
        c.text = '';
      }
      if (!mounted) return;
      _showSnack('כל הטקסטים אופסו לברירת המחדל');
    } catch (e) {
      if (!mounted) return;
      _showSnack('שגיאה: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? const Color(0xFFDC2626) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group keys by their `group` field for visual sectioning.
    final groups = <String, List<CsmTextKey>>{};
    for (final k in widget.keys) {
      groups.putIfAbsent(k.group, () => []).add(k);
    }

    final overrideCount = _service.snapshotFor(widget.csmId).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded,
                        color: Color(0xFF6366F1), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'עריכת טקסטים — ${widget.csmLabel}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (overrideCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$overrideCount מותאמים',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF166534),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _expanded
                              ? 'ערוך כותרות וטקסטים — שמירה מסונכרנת לכל הנותני שירות'
                              : 'לחץ/י לפתוח ולערוך טקסטים שיוצגו לנותני השירות',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in groups.entries) ...[
                    _buildGroupHeader(entry.key),
                    const SizedBox(height: 8),
                    for (final k in entry.value) ...[
                      _buildEditRow(k),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveAll,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label:
                              Text(_saving ? 'שומר...' : 'שמור שינויים'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _saving || overrideCount == 0
                            ? null
                            : _resetAll,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('אפס הכל'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB91C1C),
                          side:
                              const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String name) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }

  Widget _buildEditRow(CsmTextKey k) {
    final ctrl = _ctrls[k.id]!;
    final hasOverride = ctrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                k.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            if (hasOverride)
              IconButton(
                icon: const Icon(Icons.restart_alt_rounded,
                    size: 16, color: Color(0xFFB91C1C)),
                tooltip: 'אפס לברירת מחדל',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _resetSingle(k),
              ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: k.multiline ? null : 1,
          minLines: k.multiline ? 2 : 1,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: k.defaultValue,
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 13,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => setState(() {}),
        ),
        if (k.hint != null) ...[
          const SizedBox(height: 4),
          Text(
            k.hint!,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF9CA3AF)),
          ),
        ],
      ],
    );
  }
}
