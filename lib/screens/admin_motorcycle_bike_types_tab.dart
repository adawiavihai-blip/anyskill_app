// Admin tab for managing the motorcycle bike-types catalog.
//
// Live-edited Firestore collection `motorcycle_bike_types/{id}`. Admin can:
//  • Replace the image (upload OR paste an external URL)
//  • Toggle a type active/inactive
//  • Rename
//  • Delete
//  • Add a brand-new type
//
// Idempotent seed runs once per session via `ensureSeeded()` so the
// fallback list (kMotorcycleBikeTypesFallback) lands in Firestore the
// first time an admin opens this tab.
//
// Light tab (per CLAUDE.md §54 / spec instruction "Admin tab קל לתמונות
// סוגי-אופנועים — לא דשבורד שלם נפרד"). Not in a separate section.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/motorcycle_bike_types_catalog.dart';
import '../services/motorcycle_bike_types_service.dart';

class AdminMotorcycleBikeTypesTab extends StatefulWidget {
  const AdminMotorcycleBikeTypesTab({super.key});

  @override
  State<AdminMotorcycleBikeTypesTab> createState() =>
      _AdminMotorcycleBikeTypesTabState();
}

class _AdminMotorcycleBikeTypesTabState
    extends State<AdminMotorcycleBikeTypesTab> {
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _runSeedOnce();
  }

  Future<void> _runSeedOnce() async {
    if (_seeded) return;
    _seeded = true;
    await MotorcycleBikeTypesService.ensureSeeded();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F4EE),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(child: _buildList()),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openEditDialog(context, null),
          backgroundColor: const Color(0xFF534AB7),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('הוסף סוג אופנוע'),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: const Row(
        children: [
          Icon(Icons.two_wheeler_rounded, color: Color(0xFF534AB7), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ניהול קטגוריה: גרר אופנועים',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF2C2C2A),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'תמונות וסוגי אופנועים שיוצגו לכל נותני השירות בקטגוריה זו',
                  style: TextStyle(fontSize: 11, color: Color(0xFF888780)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<List<MotorcycleBikeType>>(
      stream: MotorcycleBikeTypesService.streamBikeTypes(),
      initialData: kMotorcycleBikeTypesFallback,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'שגיאה: ${snap.error}',
                style: const TextStyle(color: Color(0xFFA32D2D)),
              ),
            ),
          );
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF534AB7)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) =>
              _BikeTypeRow(type: list[i], onEdit: _openEditDialog),
        );
      },
    );
  }

  Future<void> _openEditDialog(
    BuildContext context,
    MotorcycleBikeType? existing,
  ) async {
    await showDialog(
      context: context,
      builder: (_) => _EditBikeTypeDialog(existing: existing),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROW
// ═══════════════════════════════════════════════════════════════════════════

class _BikeTypeRow extends StatefulWidget {
  final MotorcycleBikeType type;
  final Future<void> Function(BuildContext, MotorcycleBikeType?) onEdit;

  const _BikeTypeRow({
    required this.type,
    required this.onEdit,
  });

  @override
  State<_BikeTypeRow> createState() => _BikeTypeRowState();
}

class _BikeTypeRowState extends State<_BikeTypeRow> {
  int? _providerCount;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final c = await MotorcycleBikeTypesService.countProvidersForBikeType(
        widget.type.id);
    if (!mounted) return;
    setState(() => _providerCount = c);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFE8E6DD), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFFF5F4EE)),
                if (t.imageUrl.isNotEmpty)
                  Image.network(
                    t.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Color(0xFF888780)),
                    ),
                  )
                else
                  const Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        color: Color(0xFF888780)),
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.active
                          ? const Color(0xFFE1F5EE)
                          : const Color(0xFFFAEEDA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: t.active
                                ? const Color(0xFF1D9E75)
                                : const Color(0xFFBA7517),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          t.active ? 'פעיל' : 'מוסתר',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: t.active
                                ? const Color(0xFF0F6E56)
                                : const Color(0xFF854F0B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2C2C2A),
                        ),
                      ),
                    ),
                    if (t.nameEn.isNotEmpty)
                      Text(
                        t.nameEn,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF888780),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _providerCount == null
                      ? 'בודק…'
                      : '$_providerCount נותני שירות מסמנים את הסוג הזה',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5F5E5A),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onEdit(context, t),
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text('ערוך'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF534AB7),
                          side: const BorderSide(
                              color: Color(0xFFD3D1C7), width: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _confirmDelete(t),
                      icon: const Icon(Icons.delete_outline_rounded, size: 14),
                      label: const Text('מחק'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA32D2D),
                        side: const BorderSide(
                            color: Color(0xFFD3D1C7), width: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(MotorcycleBikeType t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת סוג אופנוע'),
          content: Text(
              'מחיקת "${t.name}" תסיר אותו לכל נותני השירות. להמשיך?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFA32D2D)),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await MotorcycleBikeTypesService.delete(t.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה במחיקה: $e')),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EDIT DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _EditBikeTypeDialog extends StatefulWidget {
  final MotorcycleBikeType? existing;

  const _EditBikeTypeDialog({this.existing});

  @override
  State<_EditBikeTypeDialog> createState() => _EditBikeTypeDialogState();
}

class _EditBikeTypeDialogState extends State<_EditBikeTypeDialog> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameEnCtrl;
  late final TextEditingController _imageUrlCtrl;
  late bool _active;
  bool _saving = false;
  bool _uploading = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _idCtrl = TextEditingController(text: e?.id ?? '');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _nameEnCtrl = TextEditingController(text: e?.nameEn ?? '');
    _imageUrlCtrl = TextEditingController(text: e?.imageUrl ?? '');
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _nameEnCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      final id = _resolveId();
      if (id.isEmpty) {
        throw 'יש להזין שם תחילה';
      }
      final ext = file.name.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      final url = await MotorcycleBikeTypesService.uploadImage(
        id: id,
        bytes: bytes,
        contentType: mime,
      );
      if (!mounted) return;
      setState(() {
        _imageUrlCtrl.text = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בהעלאה: $e')),
      );
    }
  }

  String _resolveId() {
    if (!_isNew) return widget.existing!.id;
    final manual = _idCtrl.text.trim();
    if (manual.isNotEmpty) return _slug(manual);
    final fromEn = _slug(_nameEnCtrl.text);
    if (fromEn.isNotEmpty) return fromEn;
    final fromHe = _nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), '_');
    return fromHe;
  }

  String _slug(String s) {
    final lower = s.trim().toLowerCase();
    return lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('שם בעברית הוא שדה חובה')),
      );
      return;
    }
    final id = _resolveId();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להזין מזהה או שם באנגלית')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // Compute order: append at the end for new entries.
      int order = widget.existing == null ? 999 : 999;
      if (widget.existing == null) {
        try {
          final agg = await FirebaseFirestore.instance
              .collection('motorcycle_bike_types')
              .count()
              .get();
          order = agg.count ?? 999;
        } catch (_) {}
      }
      await MotorcycleBikeTypesService.upsert(
        id: id,
        name: name,
        nameEn: _nameEnCtrl.text.trim(),
        imageUrl: _imageUrlCtrl.text.trim(),
        active: _active,
        order: order,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בשמירה: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(_isNew ? 'הוסף סוג אופנוע' : 'ערוך סוג אופנוע'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_imageUrlCtrl.text.isNotEmpty)
                  Container(
                    height: 140,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F4EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.network(
                      _imageUrlCtrl.text,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Color(0xFF888780)),
                      ),
                    ),
                  ),
                if (_isNew)
                  _DialogField(
                    label: 'מזהה (אופציונלי, ייווצר אוטומטית)',
                    controller: _idCtrl,
                    hint: 'sport, cruiser, ...',
                  ),
                _DialogField(
                  label: 'שם בעברית',
                  controller: _nameCtrl,
                  hint: 'ספורט',
                ),
                _DialogField(
                  label: 'שם באנגלית',
                  controller: _nameEnCtrl,
                  hint: 'Sport',
                ),
                _DialogField(
                  label: 'קישור לתמונה',
                  controller: _imageUrlCtrl,
                  hint: 'https://...',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickAndUpload,
                      icon: _uploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF534AB7),
                              ),
                            )
                          : const Icon(Icons.upload_outlined, size: 14),
                      label: const Text('העלה תמונה'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF534AB7),
                        side: const BorderSide(color: Color(0xFFD3D1C7)),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'פעיל',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2C2C2A),
                    ),
                  ),
                  subtitle: const Text(
                    'בכבוי, הסוג לא ייראה לנותני השירות וללקוחות',
                    style: TextStyle(fontSize: 11, color: Color(0xFF888780)),
                  ),
                  activeColor: const Color(0xFF534AB7),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _saving ? null : () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF534AB7)),
            child: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(_isNew ? 'הוסף' : 'שמור'),
          ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _DialogField({
    required this.label,
    required this.controller,
    this.hint = '',
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2C2C2A),
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB6B5AC),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: Color(0xFFD3D1C7), width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: Color(0xFFD3D1C7), width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF534AB7), width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
