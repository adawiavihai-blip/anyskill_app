// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  AdminBannersTab — full-featured banner management screen
// ═══════════════════════════════════════════════════════════════════════════

class AdminBannersTab extends StatefulWidget {
  const AdminBannersTab({super.key});

  @override
  State<AdminBannersTab> createState() => _AdminBannersTabState();
}

class _AdminBannersTabState extends State<AdminBannersTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Placement filter values (index matches tab)
  static const _placements = ['all', 'home_carousel', 'wallet'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Color _hex(String hex) {
    final c = hex.replaceAll('#', '').padLeft(6, '0');
    return Color(int.parse('FF$c', radix: 16));
  }

  static const _iconMap = <String, IconData>{
    'stars':             Icons.stars_rounded,
    'school':            Icons.school_rounded,
    'emoji_events':      Icons.emoji_events_rounded,
    'favorite':          Icons.favorite_rounded,
    'bolt':              Icons.bolt_rounded,
    'local_offer':       Icons.local_offer_rounded,
    'rocket_launch':     Icons.rocket_launch_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'celebration':       Icons.celebration_rounded,
    'trending_up':       Icons.trending_up_rounded,
    'handshake':         Icons.handshake_outlined,
    'monetization_on':   Icons.monetization_on_outlined,
    'diamond':           Icons.diamond_outlined,
    'auto_awesome':      Icons.auto_awesome_rounded,
    'people':            Icons.people_rounded,
    'verified':          Icons.verified_rounded,
    'flash_on':          Icons.flash_on_rounded,
    'loyalty':           Icons.loyalty_rounded,
    'whatshot':          Icons.whatshot_rounded,
    'military_tech':     Icons.military_tech_rounded,
  };

  // Preset gradient pairs — replaces free-form hex input
  static const _gradientPresets = <List<Color>>[
    [Color(0xFF667EEA), Color(0xFF764BA2)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFFF953C6), Color(0xFFB91D73)],
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF0EA5E9), Color(0xFF6366F1)],
    [Color(0xFFF97316), Color(0xFFEC4899)],
    [Color(0xFF10B981), Color(0xFF6366F1)],
    [Color(0xFFEF4444), Color(0xFFF97316)],
    [Color(0xFF1E1B4B), Color(0xFF6366F1)],
    [Color(0xFF059669), Color(0xFF34D399)],
    [Color(0xFFDC2626), Color(0xFFFB923C)],
    [Color(0xFF0F172A), Color(0xFF334155)],
  ];

  String _colorHex(Color c) =>
      c.toARGB32().toRadixString(16).substring(2).toUpperCase();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .orderBy('order')
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[Banners] Stream error: ${snap.error}');
          return const Center(child: Text('שגיאה בטעינת באנרים'));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all   = snap.data?.docs ?? [];
        final place = _placements[_tabs.index];
        final docs  = place == 'all'
            ? all
            : all.where((d) =>
                (d.data() as Map<String, dynamic>)['placement'] == place).toList();

        return Column(
          children: [
            // ── Tab bar ────────────────────────────────────────────────
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabs,
                indicatorColor: const Color(0xFF6366F1),
                labelColor: const Color(0xFF6366F1),
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(text: 'הכל (${all.length})'),
                  const Tab(text: '🏠 קרוסל'),
                  const Tab(text: '💰 ארנק'),
                ],
              ),
            ),

            // ── Action bar ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('הוסף באנר',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _openBannerDialog(existingCount: all.length),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Seed ברירת מחדל'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: all.any((d) =>
                            (d.data() as Map)['placement'] == 'home_carousel')
                        ? null
                        : _seedDefaults,
                  ),
                ],
              ),
            ),

            // ── Banner grid / list ─────────────────────────────────────
            Expanded(
              child: !snap.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : docs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_not_supported_outlined,
                                  size: 48, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('אין באנרים כאן עדיין',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 15)),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: docs.length,
                          onReorder: (oldIndex, newIndex) async {
                            if (newIndex > oldIndex) newIndex--;
                            final reordered = [...docs];
                            final moved = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, moved);
                            final batch = FirebaseFirestore.instance.batch();
                            for (int i = 0; i < reordered.length; i++) {
                              batch.update(reordered[i].reference, {'order': i});
                            }
                            await batch.commit();
                          },
                          itemBuilder: (context, index) {
                            final doc  = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            return _BannerPreviewCard(
                              key:       ValueKey(doc.id),
                              doc:       doc,
                              data:      data,
                              iconMap:   _iconMap,
                              hexToColor: _hex,
                              onEdit: () => _openBannerDialog(
                                  doc: doc,
                                  data: data,
                                  existingCount: all.length),
                              onDelete: () => _confirmDelete(doc.id),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  // ── Seed defaults ─────────────────────────────────────────────────────────

  Future<void> _seedDefaults() async {
    final existing = await FirebaseFirestore.instance
        .collection('banners')
        .where('placement', isEqualTo: 'home_carousel')
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('באנרי דף הבית כבר קיימים')));
      }
      return;
    }
    final defaults = [
      {'title': 'מצא מומחים מובילים',  'subtitle': 'אלפי מומחים מחכים לך',      'color1': '667eea', 'color2': '764ba2', 'iconName': 'stars',       'order': 0, 'isActive': true, 'placement': 'home_carousel', 'imageUrl': ''},
      {'title': 'שיעורים פרטיים',       'subtitle': 'ממש מהמקום שאתה נמצא',     'color1': '11998e', 'color2': '38ef7d', 'iconName': 'school',      'order': 1, 'isActive': true, 'placement': 'home_carousel', 'imageUrl': ''},
      {'title': 'פתח את הפוטנציאל שלך', 'subtitle': 'עם המומחים הטובים ביותר', 'color1': 'f953c6', 'color2': 'b91d73', 'iconName': 'emoji_events', 'order': 2, 'isActive': true, 'placement': 'home_carousel', 'imageUrl': ''},
    ];
    final batch = FirebaseFirestore.instance.batch();
    for (final b in defaults) {
      batch.set(FirebaseFirestore.instance.collection('banners').doc(), b);
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('3 באנרי ברירת מחדל נוצרו ✓')));
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('מחק באנר'),
        content: const Text('האם למחוק את הבאנר הזה לצמיתות?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ביטול')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('מחק', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('banners').doc(docId).delete();
    }
  }

  // ── Open dialog ───────────────────────────────────────────────────────────

  void _openBannerDialog({
    QueryDocumentSnapshot? doc,
    Map<String, dynamic>? data,
    int existingCount = 0,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BannerEditDialog(
        doc:            doc,
        data:           data,
        existingCount:  existingCount,
        iconMap:        _iconMap,
        gradientPresets: _gradientPresets,
        hexToColor:     _hex,
        colorToHex:     _colorHex,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _BannerPreviewCard — visual card shown in the grid
// ═══════════════════════════════════════════════════════════════════════════

class _BannerPreviewCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final Map<String, IconData> iconMap;
  final Color Function(String) hexToColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BannerPreviewCard({
    required super.key,
    required this.doc,
    required this.data,
    required this.iconMap,
    required this.hexToColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive   = data['isActive']   as bool?   ?? true;
    final title      = data['title']      as String? ?? '';
    final subtitle   = data['subtitle']   as String? ?? '';
    final placement  = data['placement']  as String? ?? 'home_carousel';
    final imageUrl   = data['imageUrl']   as String? ?? '';
    final color1Hex  = data['color1']     as String? ?? '6366F1';
    final color2Hex  = data['color2']     as String? ?? '8B5CF6';
    final iconName   = data['iconName']   as String? ?? 'stars';
    final expiresAt  = (data['expiresAt'] as Timestamp?)?.toDate();
    final now        = DateTime.now();
    final isExpired  = expiresAt != null && expiresAt.isBefore(now);
    final c1 = hexToColor(color1Hex);
    final c2 = hexToColor(color2Hex);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isExpired
              ? Colors.red.shade200
              : isActive
                  ? Colors.transparent
                  : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Visual preview (140px) ────────────────────────────────
          SizedBox(
            height: 140,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background
                if (imageUrl.isNotEmpty)
                  Image.network(imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _gradientBg(c1, c2))
                else
                  _gradientBg(c1, c2),

                // Dim overlay when inactive/expired
                if (!isActive || isExpired)
                  Container(color: Colors.black.withValues(alpha: 0.45)),

                // Icon + text overlay
                if (imageUrl.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(title,
                                  textAlign: TextAlign.right,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    shadows: [Shadow(blurRadius: 4, color: Colors.black38)],
                                  )),
                              if (subtitle.isNotEmpty)
                                Text(subtitle,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    )),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            iconMap[iconName] ?? Icons.stars_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Drag handle
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.drag_indicator_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),

                // Status chip
                Positioned(
                  bottom: 8,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? Colors.red.shade700
                          : isActive
                              ? const Color(0xFF10B981)
                              : Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isExpired ? 'פג תוקף' : isActive ? 'פעיל' : 'מושבת',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Info row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                // Placement chip
                _PlacementChip(placement: placement),
                const Spacer(),
                // Active toggle
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: isActive,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (v) =>
                        doc.reference.update({'isActive': v}),
                  ),
                ),
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18,
                      color: Color(0xFF6366F1)),
                  tooltip: 'ערוך',
                  onPressed: onEdit,
                ),
                // Delete button
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: Colors.red.shade400),
                  tooltip: 'מחק',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),

          // Expiry row
          if (expiresAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpired
                        ? Icons.event_busy_rounded
                        : Icons.schedule_rounded,
                    size: 12,
                    color: isExpired ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isExpired
                        ? 'פג תוקף ${DateFormat('dd/MM/yy', 'he').format(expiresAt)}'
                        : 'תוקף עד ${DateFormat('dd/MM/yy', 'he').format(expiresAt)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isExpired ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _gradientBg(Color c1, Color c2) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c1, c2],
              begin: Alignment.topRight, end: Alignment.bottomLeft),
        ),
      );
}

// ── Placement chip ────────────────────────────────────────────────────────

class _PlacementChip extends StatelessWidget {
  final String placement;
  const _PlacementChip({required this.placement});

  @override
  Widget build(BuildContext context) {
    final isHome = placement == 'home_carousel';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHome
            ? const Color(0xFFEEF2FF)
            : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHome ? const Color(0xFF6366F1) : Colors.amber.shade300,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHome ? Icons.home_outlined : Icons.account_balance_wallet_outlined,
            size: 11,
            color: isHome ? const Color(0xFF6366F1) : Colors.amber.shade700,
          ),
          const SizedBox(width: 3),
          Text(
            isHome ? 'דף הבית' : 'ארנק',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isHome ? const Color(0xFF6366F1) : Colors.amber.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _BannerEditDialog — premium create / edit dialog
// ═══════════════════════════════════════════════════════════════════════════

class _BannerEditDialog extends StatefulWidget {
  final QueryDocumentSnapshot? doc;
  final Map<String, dynamic>? data;
  final int existingCount;
  final Map<String, IconData> iconMap;
  final List<List<Color>> gradientPresets;
  final Color Function(String) hexToColor;
  final String Function(Color) colorToHex;

  const _BannerEditDialog({
    required this.doc,
    required this.data,
    required this.existingCount,
    required this.iconMap,
    required this.gradientPresets,
    required this.hexToColor,
    required this.colorToHex,
  });

  @override
  State<_BannerEditDialog> createState() => _BannerEditDialogState();
}

class _BannerEditDialogState extends State<_BannerEditDialog> {
  // Form controllers
  late TextEditingController _titleCtrl;
  late TextEditingController _subtitleCtrl;

  // Mode: 'image' or 'gradient'
  String _mode = 'gradient';

  // Gradient state
  late List<Color> _selectedGradient;
  late String _selectedIcon;

  // Placement
  late String _placement;
  late bool _isActive;
  DateTime? _expiresAt;

  // Image state
  String _imageUrl = '';
  bool _uploadingImage = false;

  // Provider link (preserved from existing)
  String? _providerId;
  String? _providerName;
  String? _providerPhoto;

  // Icon search
  String _iconSearch = '';

  // Save state
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _titleCtrl    = TextEditingController(text: d?['title']    as String? ?? '');
    _subtitleCtrl = TextEditingController(text: d?['subtitle'] as String? ?? '');
    _placement    = d?['placement'] as String? ?? 'home_carousel';
    _isActive     = d?['isActive']  as bool?   ?? true;
    _expiresAt    = (d?['expiresAt'] as Timestamp?)?.toDate();
    _imageUrl     = d?['imageUrl']  as String? ?? '';
    _providerId   = d?['providerId']   as String?;
    _providerName = d?['providerName'] as String?;
    _providerPhoto = d?['providerPhoto'] as String?;

    // Mode: image if imageUrl is non-empty
    _mode = _imageUrl.isNotEmpty ? 'image' : 'gradient';

    // Gradient
    final c1hex = d?['color1'] as String? ?? '667eea';
    final c2hex = d?['color2'] as String? ?? '764ba2';
    _selectedGradient = [
      widget.hexToColor(c1hex),
      widget.hexToColor(c2hex),
    ];
    _selectedIcon = d?['iconName'] as String? ?? 'stars';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  // ── Image upload ──────────────────────────────────────────────────────────

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 800, imageQuality: 75);
    if (picked == null) return;

    setState(() => _uploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext   = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final ref   = FirebaseStorage.instance
          .ref('banners/${DateTime.now().millisecondsSinceEpoch}.$ext');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      setState(() { _imageUrl = url; _uploadingImage = false; });
    } catch (e) {
      setState(() => _uploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאת העלאה: $e')));
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נא למלא כותרת')));
      return;
    }
    setState(() => _saving = true);

    final payload = <String, dynamic>{
      'title':     _titleCtrl.text.trim(),
      'subtitle':  _subtitleCtrl.text.trim(),
      'placement': _placement,
      'isActive':  _isActive,
      'order':     widget.data?['order'] ?? widget.existingCount,
      'imageUrl':  _mode == 'image' ? _imageUrl : '',
      'color1':    widget.colorToHex(_selectedGradient[0]),
      'color2':    widget.colorToHex(_selectedGradient[1]),
      'iconName':  _selectedIcon,
      'expiresAt': _expiresAt != null ? Timestamp.fromDate(_expiresAt!) : null,
      'providerId':    _providerId,
      'providerName':  _providerName,
      'providerPhoto': _providerPhoto,
    };

    try {
      if (widget.doc == null) {
        await FirebaseFirestore.instance.collection('banners').add(payload);
      } else {
        await widget.doc!.reference.update(payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאת שמירה: $e')));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNew = widget.doc == null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _mode == 'image' && _imageUrl.isNotEmpty
                      ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                      : [_selectedGradient[0], _selectedGradient[1]],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isNew ? 'באנר חדש' : 'עריכת באנר',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    _field(_titleCtrl, 'כותרת'),
                    const SizedBox(height: 12),
                    _field(_subtitleCtrl, 'תת כותרת'),
                    const SizedBox(height: 16),

                    // ── Mode toggle ────────────────────────────────
                    const _SectionLabel('מצב תצוגה'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'gradient',
                          label: Text('גרדיאנט'),
                          icon: Icon(Icons.gradient_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: 'image',
                          label: Text('תמונה'),
                          icon: Icon(Icons.image_outlined, size: 16),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 16),

                    // ── Gradient fields ────────────────────────────
                    if (_mode == 'gradient') ...[
                      const _SectionLabel('צבעי גרדיאנט'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.gradientPresets.map((pair) {
                          final selected = pair[0] == _selectedGradient[0] &&
                              pair[1] == _selectedGradient[1];
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedGradient = pair),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: selected ? 48 : 40,
                              height: selected ? 48 : 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [pair[0], pair[1]],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: selected
                                    ? Border.all(
                                        color: Colors.white, width: 2.5)
                                    : null,
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: pair[0].withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // ── Icon picker ────────────────────────────
                      const _SectionLabel('אייקון'),
                      const SizedBox(height: 8),
                      TextField(
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          hintText: 'חפש אייקון...',
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(10))),
                        ),
                        onChanged: (v) =>
                            setState(() => _iconSearch = v.toLowerCase()),
                      ),
                      const SizedBox(height: 10),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: widget.iconMap.entries
                            .where((e) =>
                                _iconSearch.isEmpty ||
                                e.key.contains(_iconSearch))
                            .map((e) {
                          final selected = e.key == _selectedIcon;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedIcon = e.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _selectedGradient[0]
                                        .withValues(alpha: 0.15)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: selected
                                    ? Border.all(
                                        color: _selectedGradient[0],
                                        width: 2)
                                    : null,
                              ),
                              child: Icon(
                                e.value,
                                size: 22,
                                color: selected
                                    ? _selectedGradient[0]
                                    : Colors.grey.shade500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // ── Image fields ───────────────────────────────
                    if (_mode == 'image') ...[
                      const _SectionLabel('תמונת באנר'),
                      const SizedBox(height: 8),

                      // Preview
                      if (_imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            _imageUrl,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 120,
                              color: Colors.grey.shade200,
                              child: const Center(
                                  child: Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                        ),

                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: _uploadingImage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.upload_rounded),
                          label: Text(_uploadingImage
                              ? 'מעלה...'
                              : _imageUrl.isEmpty
                                  ? 'העלה תמונה מהמכשיר'
                                  : 'החלף תמונה'),
                          onPressed:
                              _uploadingImage ? null : _pickAndUploadImage,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ── Placement ──────────────────────────────────
                    const _SectionLabel('מיקום הבאנר'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'home_carousel',
                          label: Text('🏠 דף הבית'),
                          icon: Icon(Icons.home_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 'wallet',
                          label: Text('💰 ארנק'),
                          icon: Icon(Icons.account_balance_wallet_outlined,
                              size: 16),
                        ),
                      ],
                      selected: {_placement},
                      onSelectionChanged: (s) =>
                          setState(() => _placement = s.first),
                    ),

                    const SizedBox(height: 16),

                    // ── Active + expiry ────────────────────────────
                    Row(
                      children: [
                        const Expanded(
                          child: Text('פעיל',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: _isActive,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (v) => setState(() => _isActive = v),
                        ),
                      ],
                    ),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _expiresAt != null
                                ? 'תוקף: ${DateFormat('dd/MM/yyyy', 'he').format(_expiresAt!)}'
                                : 'ללא תאריך תפוגה',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.date_range_rounded, size: 16),
                          label:
                              Text(_expiresAt != null ? 'שנה' : 'הגדר תפוגה'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _expiresAt ??
                                  DateTime.now()
                                      .add(const Duration(days: 30)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365 * 3)),
                              helpText: 'תאריך תפוגת הבאנר',
                              confirmText: 'אשר',
                              cancelText: 'ביטול',
                            );
                            if (picked != null) {
                              setState(() => _expiresAt = picked);
                            }
                          },
                        ),
                        if (_expiresAt != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: 'הסר תפוגה',
                            onPressed: () =>
                                setState(() => _expiresAt = null),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Footer buttons ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ביטול'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(isNew ? 'הוסף' : 'שמור',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  Widget _field(TextEditingController ctrl, String label) => TextField(
        controller: ctrl,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        ),
      );
}

// ── Small section label ───────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Color(0xFF374151),
        ),
      );
}
