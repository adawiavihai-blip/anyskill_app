import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// AnySkill — XP & Levels Manager
/// Admin-only screen embedded as a tab in AdminScreen.
/// Manages the settings_gamification collection:
///   - __levels__ doc  : silver / gold thresholds
///   - all other docs  : XP event definitions (eventName, points, description)
class XpManagerScreen extends StatefulWidget {
  const XpManagerScreen({super.key});

  @override
  State<XpManagerScreen> createState() => _XpManagerScreenState();
}

class _XpManagerScreenState extends State<XpManagerScreen> {
  static const String _levelsDocId = '__levels__';
  static const Color _indigo = Color(0xFF6366F1);

  // Level thresholds state
  int  _silverThreshold = 500;
  int  _goldThreshold   = 2000;
  bool _levelsLoaded    = false;

  final _silverCtrl = TextEditingController();
  final _goldCtrl   = TextEditingController();

  // ── Seed data (used once if collection is empty) ──────────────────────────
  static const List<Map<String, dynamic>> _seedEvents = [
    {
      'id':          'finish_job',
      'eventName':   'סיום עבודה מוצלחת',
      'points':      50,
      'description': 'ספק סיים עבודה ולקוח שחרר את התשלום',
    },
    {
      'id':          'five_star_review',
      'eventName':   'קיבל ביקורת 5 כוכבים',
      'points':      20,
      'description': 'לקוח דירג את הספק בדירוג מושלם',
    },
    {
      'id':          'quick_response',
      'eventName':   'מענה מהיר (<5 דקות)',
      'points':      10,
      'description': 'ספק הגיב להודעת לקוח בפחות מ-5 דקות',
    },
    {
      'id':          'story_upload',
      'eventName':   'העלאת עבודה לגלריה',
      'points':      5,
      'description': 'ספק העלה עבודה חדשה לתיק העבודות שלו',
    },
    {
      'id':          'join_opportunity',
      'eventName':   'הצטרפות להזדמנות',
      'points':      5,
      'description': 'ספק הביע עניין בבקשת שירות פתוחה',
    },
    {
      'id':          'provider_cancel',
      'eventName':   'ביטול מצד הספק',
      'points':      -100,
      'description': 'ספק ביטל הזמנה קיימת — עונש XP כבד',
    },
    {
      'id':          'no_response',
      'eventName':   'אי-מענה (>2 שעות)',
      'points':      -5,
      'description': 'ספק לא הגיב ללקוח תוך שעתיים',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadLevels();
    _seedIfEmpty();
  }

  @override
  void dispose() {
    _silverCtrl.dispose();
    _goldCtrl.dispose();
    super.dispose();
  }

  // ── Load level thresholds from Firestore ─────────────────────────────────
  Future<void> _loadLevels() async {
    final doc = await FirebaseFirestore.instance
        .collection('settings_gamification')
        .doc(_levelsDocId)
        .get();
    if (!mounted) return;
    final d = doc.data() ?? {};
    final silver = (d['silver'] as num?)?.toInt() ?? 500;
    final gold   = (d['gold']   as num?)?.toInt() ?? 2000;
    setState(() {
      _silverThreshold  = silver;
      _goldThreshold    = gold;
      _silverCtrl.text  = silver.toString();
      _goldCtrl.text    = gold.toString();
      _levelsLoaded     = true;
    });
  }

  // ── Seed default events once if collection has no event docs ─────────────
  Future<void> _seedIfEmpty() async {
    final snap = await FirebaseFirestore.instance
        .collection('settings_gamification')
        .limit(3)
        .get();

    final hasEvents = snap.docs.any((d) => d.id != _levelsDocId);
    if (hasEvents) return;

    final batch = FirebaseFirestore.instance.batch();
    final col   = FirebaseFirestore.instance.collection('settings_gamification');

    for (final ev in _seedEvents) {
      batch.set(col.doc(ev['id'] as String), {
        'eventName':   ev['eventName'],
        'points':      ev['points'],
        'description': ev['description'],
      });
    }

    batch.set(col.doc(_levelsDocId), {
      'bronze': 0,
      'silver': _silverThreshold,
      'gold':   _goldThreshold,
    });

    await batch.commit();
  }

  // ── Save level thresholds to Firestore ────────────────────────────────────
  Future<void> _saveLevels() async {
    final silver = int.tryParse(_silverCtrl.text.trim());
    final gold   = int.tryParse(_goldCtrl.text.trim());

    if (silver == null || gold == null || silver <= 0 || gold <= silver) {
      _snack('כסף חייב להיות > 0 וזהב חייב להיות > כסף', isError: true);
      return;
    }

    await FirebaseFirestore.instance
        .collection('settings_gamification')
        .doc(_levelsDocId)
        .set({'bronze': 0, 'silver': silver, 'gold': gold});

    if (!mounted) return;
    setState(() { _silverThreshold = silver; _goldThreshold = gold; });
    _snack('סף הרמות עודכן ✓');
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  void _showEditEventDialog(String docId, Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: data['eventName']   as String? ?? '');
    final ptsCtrl  = TextEditingController(text: (data['points'] as int? ?? 0).toString());
    final descCtrl = TextEditingController(text: data['description'] as String? ?? '');

    showDialog(
      context: context,
      builder: (ctx) => _eventDialog(
        title:    'עריכת אירוע XP',
        idCtrl:   null,
        nameCtrl: nameCtrl,
        ptsCtrl:  ptsCtrl,
        descCtrl: descCtrl,
        onSave: () async {
          final pts = int.tryParse(ptsCtrl.text.trim());
          if (pts == null || nameCtrl.text.trim().isEmpty) return;
          await FirebaseFirestore.instance
              .collection('settings_gamification')
              .doc(docId)
              .update({
                'eventName':   nameCtrl.text.trim(),
                'points':      pts,
                'description': descCtrl.text.trim(),
              });
          if (ctx.mounted) Navigator.pop(ctx);
          _snack('האירוע עודכן ✓');
        },
        actionLabel: 'שמור',
      ),
    );
  }

  void _showAddEventDialog() {
    final idCtrl   = TextEditingController();
    final nameCtrl = TextEditingController();
    final ptsCtrl  = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => _eventDialog(
        title:    'הוספת אירוע XP חדש',
        idCtrl:   idCtrl,
        nameCtrl: nameCtrl,
        ptsCtrl:  ptsCtrl,
        descCtrl: descCtrl,
        onSave: () async {
          final docId = idCtrl.text.trim().replaceAll(' ', '_').toLowerCase();
          final pts   = int.tryParse(ptsCtrl.text.trim());
          if (docId.isEmpty || pts == null || nameCtrl.text.trim().isEmpty) return;
          if (docId == _levelsDocId) {
            _snack('המזהה "__levels__" שמור למערכת', isError: true);
            return;
          }
          await FirebaseFirestore.instance
              .collection('settings_gamification')
              .doc(docId)
              .set({
                'eventName':   nameCtrl.text.trim(),
                'points':      pts,
                'description': descCtrl.text.trim(),
              });
          if (ctx.mounted) Navigator.pop(ctx);
          _snack('האירוע נוסף ✓');
        },
        actionLabel: 'הוסף',
      ),
    );
  }

  void _confirmDeleteEvent(String docId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('מחיקת אירוע', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('למחוק את האירוע "$name"?\nפעולה זו אינה הפיכה.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('settings_gamification')
                  .doc(docId)
                  .delete();
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('האירוע נמחק');
            },
            child: const Text('מחק', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Shared event dialog builder ───────────────────────────────────────────
  Widget _eventDialog({
    required String title,
    required TextEditingController? idCtrl,
    required TextEditingController nameCtrl,
    required TextEditingController ptsCtrl,
    required TextEditingController descCtrl,
    required Future<void> Function() onSave,
    required String actionLabel,
  }) {
    bool saving = false;

    return StatefulBuilder(
      builder: (ctx, setStateLocal) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (idCtrl != null) ...[
                _dialogField(idCtrl, 'מזהה אירוע (באנגלית, ללא רווחים)', hint: 'e.g. late_delivery'),
                const SizedBox(height: 12),
              ],
              _dialogField(nameCtrl, 'שם האירוע בעברית'),
              const SizedBox(height: 12),
              _dialogField(ptsCtrl, 'נקודות XP (שלילי = עונש)',
                  inputType: const TextInputType.numberWithOptions(signed: true)),
              const SizedBox(height: 12),
              _dialogField(descCtrl, 'תיאור קצר'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: saving ? null : () async {
              setStateLocal(() => saving = true);
              await onSave();
              setStateLocal(() => saving = false);
            },
            child: saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(actionLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  TextField _dialogField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? inputType,
  }) =>
      TextField(
        controller:   ctrl,
        keyboardType: inputType,
        decoration: InputDecoration(
          labelText: label,
          hintText:  hint,
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        floatingActionButton: FloatingActionButton.extended(
          onPressed:       _showAddEventDialog,
          backgroundColor: _indigo,
          icon:  const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('הוסף אירוע', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: _indigo.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: const Icon(Icons.stars_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('XP & מערכת רמות', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('הגדרת אירועים, נקודות וסף עליית רמה', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Level Thresholds Card ────────────────────────────────────
            _buildLevelsCard(),
            const SizedBox(height: 24),

            // ── Events section header ────────────────────────────────────
            Row(
              children: [
                Container(width: 4, height: 22, decoration: BoxDecoration(color: _indigo, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                const Text('אירועי XP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('settings_gamification').snapshots(),
                  builder: (_, snap) {
                    final count = (snap.data?.docs ?? []).where((d) => d.id != _levelsDocId).length;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: _indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text('$count אירועים', style: const TextStyle(color: _indigo, fontSize: 12, fontWeight: FontWeight.w600)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── XP Events Stream ─────────────────────────────────────────
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('settings_gamification')
                  .orderBy('points', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Center(child: Text('שגיאה: ${snap.error}', style: const TextStyle(color: Colors.red)));
                }
                final docs = (snap.data?.docs ?? [])
                    .where((d) => d.id != _levelsDocId)
                    .toList();

                if (docs.isEmpty) {
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text('אין אירועים עדיין.\nלחץ "הוסף אירוע" להתחלה.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ),
                  );
                }

                return Column(
                  children: docs.map((doc) {
                    return _buildEventTile(doc.id, doc.data() as Map<String, dynamic>);
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Level Thresholds Card ─────────────────────────────────────────────────
  Widget _buildLevelsCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _indigo.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.emoji_events_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('סף עליית רמה', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'הגדר את מינימום ה-XP הנדרש לכל רמה.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _levelField('🥉 ברונזה', null, isFixed: true)),
            const SizedBox(width: 10),
            Expanded(child: _levelField('🥈 כסף', _silverCtrl)),
            const SizedBox(width: 10),
            Expanded(child: _levelField('🥇 זהב', _goldCtrl)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _levelsLoaded ? _saveLevels : null,
              child: const Text('שמור סף רמות', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 10),
          // Live preview row
          _buildLevelPreviewRow(),
        ],
      ),
    );
  }

  Widget _levelField(String label, TextEditingController? ctrl, {bool isFixed = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 5),
        isFixed
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('0 XP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              )
            : TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white, width: 1.5),
                  ),
                  suffixText: 'XP',
                  suffixStyle: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
      ],
    );
  }

  Widget _buildLevelPreviewRow() {
    final silver = int.tryParse(_silverCtrl.text) ?? _silverThreshold;
    final gold   = int.tryParse(_goldCtrl.text)   ?? _goldThreshold;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _previewBadge('ברונזה', '0–${silver - 1}', const Color(0xFFCD7F32)),
        _previewBadge('כסף',    '$silver–${gold - 1}', const Color(0xFF9CA3AF)),
        _previewBadge('זהב',    '$gold+', const Color(0xFFF59E0B)),
      ],
    );
  }

  Widget _previewBadge(String name, String range, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(name, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(range, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  // ── Single Event Tile ─────────────────────────────────────────────────────
  Widget _buildEventTile(String docId, Map<String, dynamic> data) {
    final int  pts         = (data['points'] as num?)?.toInt() ?? 0;
    final bool isPositive  = pts >= 0;
    final Color ptsColor   = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final Color bgColor    = isPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2);
    final String name      = data['eventName']   as String? ?? docId;
    final String desc      = data['description'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        leading: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isPositive ? '+$pts' : '$pts',
                style: TextStyle(color: ptsColor, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text('XP', style: TextStyle(color: ptsColor.withValues(alpha: 0.7), fontSize: 10)),
            ],
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('id: $docId', style: TextStyle(fontSize: 10, color: Colors.grey[500], fontFamily: 'monospace')),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Edit
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: _indigo, size: 20),
              onPressed: () => _showEditEventDialog(docId, data),
              tooltip: 'ערוך',
            ),
            // Delete
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red[300], size: 20),
              onPressed: () => _confirmDeleteEvent(docId, name),
              tooltip: 'מחק',
            ),
          ],
        ),
        isThreeLine: desc.isNotEmpty,
      ),
    );
  }
}
