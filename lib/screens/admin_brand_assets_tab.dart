import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/anyskill_logo.dart';

// ── Preset brand colours the CEO can choose from ─────────────────────────────
const _kPresetColors = <String, Color>{
  'Indigo (Default)': Color(0xFF6366F1),
  'Purple':           Color(0xFF9333EA),
  'Blue':             Color(0xFF3B82F6),
  'Teal':             Color(0xFF14B8A6),
  'Rose':             Color(0xFFF43F5E),
  'Amber':            Color(0xFFF59E0B),
  'Emerald':          Color(0xFF10B981),
  'Slate':            Color(0xFF475569),
};

class AdminBrandAssetsTab extends StatefulWidget {
  const AdminBrandAssetsTab({super.key});

  @override
  State<AdminBrandAssetsTab> createState() => _AdminBrandAssetsTabState();
}

class _AdminBrandAssetsTabState extends State<AdminBrandAssetsTab> {
  final _logoUrlCtrl  = TextEditingController();
  final _iconUrlCtrl  = TextEditingController();
  bool  _saving       = false;
  String _selectedColorHex = '6366F1';

  // Firestore ref
  final _ref = FirebaseFirestore.instance.collection('system_settings').doc('global');

  @override
  void dispose() {
    _logoUrlCtrl.dispose();
    _iconUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyGlobally() async {
    setState(() => _saving = true);
    try {
      final updates = <String, dynamic>{
        'brandColorHex': _selectedColorHex,
      };
      final logoUrl = _logoUrlCtrl.text.trim();
      final iconUrl = _iconUrlCtrl.text.trim();
      if (logoUrl.isNotEmpty) updates['logoUrl']     = logoUrl;
      if (iconUrl.isNotEmpty) updates['logoIconUrl'] = iconUrl;

      await _ref.set(updates, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ נכסי המותג עודכנו בהצלחה!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('איפוס לברירת מחדל'),
        content: const Text('זה ימחק את ה-URL המותאם אישית ויחזיר את הלוגו הבנוי.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('אפס', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _ref.set({
      'logoUrl':      FieldValue.delete(),
      'logoIconUrl':  FieldValue.delete(),
      'brandColorHex': '6366F1',
    }, SetOptions(merge: true));

    _logoUrlCtrl.clear();
    _iconUrlCtrl.clear();
    setState(() => _selectedColorHex = '6366F1');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('♻️ הנכסים אופסו לברירת מחדל.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        final data         = snap.data?.data() ?? {};
        final currentLogo  = (data['logoUrl']     as String?) ?? '';
        final currentIcon  = (data['logoIconUrl'] as String?) ?? '';
        final currentColor = (data['brandColorHex'] as String?) ?? '6366F1';

        // Pre-fill text fields once when Firestore data first arrives
        if (snap.connectionState == ConnectionState.active &&
            _logoUrlCtrl.text.isEmpty &&
            currentLogo.isNotEmpty) {
          _logoUrlCtrl.text = currentLogo;
        }
        if (snap.connectionState == ConnectionState.active &&
            _iconUrlCtrl.text.isEmpty &&
            currentIcon.isNotEmpty) {
          _iconUrlCtrl.text = currentIcon;
        }
        if (_selectedColorHex == '6366F1' && currentColor != '6366F1') {
          // Sync once
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedColorHex = currentColor);
          });
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Live Preview ───────────────────────────────────────────────────
            _SectionHeader('תצוגה מקדימה חיה'),
            const SizedBox(height: 12),
            _buildPreviewCard(currentLogo, currentIcon, currentColor),
            const SizedBox(height: 24),

            // ── Full Logo URL ──────────────────────────────────────────────────
            _SectionHeader('לוגו מלא (כתובת URL)'),
            const SizedBox(height: 8),
            TextField(
              controller: _logoUrlCtrl,
              decoration: InputDecoration(
                hintText: 'https://...לוגו מלא.gif/png',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: const Icon(Icons.image_outlined),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'מוצג במסך הטעינה ובסביבת הטעינה. השאר ריק לשימוש בנכס המוטמע.',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const SizedBox(height: 20),

            // ── Icon URL ────────────────────────────────────────────────────────
            _SectionHeader('אייקון מותג (כתובת URL)'),
            const SizedBox(height: 8),
            TextField(
              controller: _iconUrlCtrl,
              decoration: InputDecoration(
                hintText: 'https://...אייקון.png',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: const Icon(Icons.crop_square_outlined),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'מוצג בשורת החיפוש, בכותרת ובמסכי ה-AppBar. השאר ריק לשימוש בנכס המוטמע.',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const SizedBox(height: 24),

            // ── Brand Colour ────────────────────────────────────────────────────
            _SectionHeader('צבע מותג ראשי'),
            const SizedBox(height: 12),
            _buildColorPicker(),
            const SizedBox(height: 28),

            // ── Action Buttons ──────────────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _saving ? null : _applyGlobally,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(_saving ? 'מחיל...' : '🚀 החל גלובלית'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _resetToDefaults,
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('♻️ אפס לברירת מחדל'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildPreviewCard(String logoUrl, String iconUrl, String colorHex) {
    Color previewColor;
    try {
      previewColor = Color(int.parse('FF$colorHex', radix: 16));
    } catch (_) {
      previewColor = const Color(0xFF6366F1);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [previewColor.withValues(alpha: 0.08), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: previewColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Loading indicator preview
          Text('מסך טעינה', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: Center(
              child: logoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl:    logoUrl,
                      width:       80,
                      height:      80,
                      fit:         BoxFit.contain,
                      placeholder: (_, __) => const AnySkillLoadingIndicator(size: 80),
                      errorWidget: (_, __, ___) => const AnySkillLoadingIndicator(size: 80),
                    )
                  : const AnySkillLoadingIndicator(size: 80),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          // AppBar / search bar preview
          Text('שורת חיפוש', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          const SizedBox(height: 8),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                iconUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl:    iconUrl,
                        width:       20,
                        height:      20,
                        fit:         BoxFit.contain,
                        errorWidget: (_, __, ___) => const AnySkillBrandIcon(size: 20),
                      )
                    : const AnySkillBrandIcon(size: 20),
                const SizedBox(width: 10),
                Text('חפש מומחה...', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Brand color swatch
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: previewColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('#$colorHex', style: TextStyle(
                fontWeight: FontWeight.bold, color: previewColor, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _kPresetColors.entries.map((e) {
        final hex = (e.value.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
        final selected = _selectedColorHex.toUpperCase() == hex;
        return GestureDetector(
          onTap: () => setState(() => _selectedColorHex = hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width:  44,
            height: 44,
            decoration: BoxDecoration(
              color:  e.value,
              shape:  BoxShape.circle,
              border: Border.all(
                color:  selected ? Colors.white : Colors.transparent,
                width:  3,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: e.value.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)]
                  : [],
            ),
            child: selected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      );
}
