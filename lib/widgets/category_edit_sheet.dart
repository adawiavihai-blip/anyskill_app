// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../services/category_service.dart';
import '../services/settings_service.dart';

/// Admin-only bottom sheet for editing a category document.
///
/// Shows:
///   • Title TextField (pre-populated)
///   • Horizontally scrollable icon picker (from CategoryService.iconMap)
///   • Image picker — uploads to Firebase Storage, stores download URL
///
/// Invisible to regular users — callers are responsible for only mounting
/// this when the authenticated user's email is the admin email.
class CategoryEditSheet extends StatefulWidget {
  final String  docId;
  final String  initialName;
  final String  initialIconName;
  final String  initialImageUrl;
  /// Per-category card scale override. null = use global setting (shows 1.0 as default).
  final double? initialCardScale;

  const CategoryEditSheet({
    super.key,
    required this.docId,
    required this.initialName,
    required this.initialIconName,
    required this.initialImageUrl,
    this.initialCardScale,
  });

  @override
  State<CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<CategoryEditSheet> {
  late final TextEditingController _nameCtrl;
  late String  _selectedIconName;
  String?      _newImageUrl;      // set after successful upload
  bool         _isUploading = false;
  bool         _isSaving    = false;
  bool         _isDeleting  = false;
  late double  _cardScale;        // per-category size override

  @override
  void initState() {
    super.initState();
    _nameCtrl         = TextEditingController(text: widget.initialName);
    _selectedIconName = widget.initialIconName.isNotEmpty
        ? widget.initialIconName
        : 'work_outline';
    _cardScale = widget.initialCardScale ?? 1.0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Image upload ─────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source:       ImageSource.gallery,
      maxWidth:     800,
      maxHeight:    600,
      imageQuality: 75,          // ~50-100 KB — well within Storage quotas
    );
    if (file == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await file.readAsBytes();
      final ref   = FirebaseStorage.instance
          .ref()
          .child('category_images/${widget.docId}.jpg');
      final snap = await ref.putData(
          bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await snap.ref.getDownloadURL();
      if (mounted) setState(() => _newImageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בהעלאת תמונה: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    // Capture context-dependents BEFORE the first await so they remain
    // valid even after the sheet is popped.
    final nav       = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSaving = true);
    try {
      await CategoryService.updateCategory(widget.docId, {
        'name':      name,
        'iconName':  _selectedIconName,
        'cardScale': _cardScale,
        if (_newImageUrl != null) 'img': _newImageUrl,
      });
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text('הקטגוריה "$name" עודכנה בהצלחה'),
        ]),
        backgroundColor: const Color(0xFF10B981),
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בשמירה: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    // Capture before any async gap
    final nav       = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name      = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : widget.initialName;

    // Check how many providers are in this category
    int providerCount = 0;
    try {
      providerCount = await CategoryService.activeProviderCount(name);
    } catch (_) {}

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('מחיקת קטגוריה',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'האם אתה בטוח שברצונך למחוק קטגוריה זו?\nפעולה זו אינה ניתנת לביטול.',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            if (providerCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people_outline,
                        color: Colors.orange[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ישנם $providerCount ספקים פעילים בקטגוריה זו. '
                        'הם לא יימחקו, אך הקטגוריה שלהם לא תהיה תקינה.',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever,
                color: Colors.white, size: 16),
            label: const Text('מחק',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final imageUrl = _newImageUrl ?? widget.initialImageUrl;
      await CategoryService.deleteCategory(widget.docId, imageUrl);
      nav.pop(); // close the sheet
      messenger.showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text('הקטגוריה "$name" נמחקה בהצלחה'),
        ]),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה במחיקה: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final previewUrl = _newImageUrl ?? widget.initialImageUrl;

    return Padding(
      // Shift sheet up when keyboard is visible
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Header row ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Delete button (left / trailing-edge in RTL)
                _isDeleting
                    ? const SizedBox(
                        width: 36, height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.red),
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: 'מחק קטגוריה',
                        onPressed:
                            (_isSaving || _isUploading) ? null : _confirmDelete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: Colors.red,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                const Text('ערוך קטגוריה',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                // Save button
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: (_isSaving || _isUploading || _isDeleting)
                        ? null
                        : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      disabledBackgroundColor:
                          const Color(0xFF6366F1).withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('שמור',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),

            const Divider(height: 20),

            // ── Category name ─────────────────────────────────────────────
            _label('שם הקטגוריה'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              textAlign:  TextAlign.right,
              decoration: InputDecoration(
                filled:      true,
                fillColor:   const Color(0xFFF5F6FA),
                hintText:    'שם הקטגוריה',
                border:      OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:   BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF6366F1))),
              ),
            ),
            const SizedBox(height: 18),

            // ── Background image ──────────────────────────────────────────
            _label('תמונת רקע'),
            const SizedBox(height: 8),
            Row(
              children: [
                // Thumbnail preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: previewUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: previewUrl,
                          width: 72, height: 60, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _imagePlaceholder())
                      : _imagePlaceholder(),
                ),
                const SizedBox(width: 12),
                // Upload button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_isUploading || _isSaving) ? null : _pickImage,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF6366F1)))
                        : const Icon(Icons.upload_rounded, size: 16),
                    label: Text(_isUploading ? 'מעלה תמונה...' : 'בחר תמונה חדשה',
                        style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Icon picker ───────────────────────────────────────────────
            _label('אייקון'),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                reverse: true,       // RTL: first icon on the right
                children: CategoryService.iconMap.entries.map((e) {
                  final selected = _selectedIconName == e.key;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIconName = e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44, height: 44,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFF5F6FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF6366F1)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(e.value,
                          size:  20,
                          color: selected
                              ? Colors.white
                              : Colors.grey.shade500),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // ── Per-category card scale override ──────────────────────────
            _label('גודל כרטיס (עקיפת גלובל)'),
            const SizedBox(height: 4),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: SettingsService.stream,
              builder: (context, settingsSnap) {
                final globalScale = SettingsService.cardScaleFrom(settingsSnap.data);
                final isDefault   = (_cardScale - 1.0).abs() < 0.01;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Text(
                          isDefault ? 'גלובל (${globalScale.toStringAsFixed(2)}x)' : '${_cardScale.toStringAsFixed(2)}x',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDefault ? Colors.grey : const Color(0xFF6366F1),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _cardScale,
                            min: 0.6,
                            max: 1.5,
                            divisions: 18,
                            activeColor: const Color(0xFF6366F1),
                            inactiveColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            onChanged: (v) => setState(() => _cardScale = v),
                          ),
                        ),
                      ],
                    ),
                    if (!isDefault)
                      GestureDetector(
                        onTap: () => setState(() => _cardScale = 1.0),
                        child: Text(
                          'אפס לגלובל',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              decoration: TextDecoration.underline),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String text) => Align(
        alignment: Alignment.centerRight,
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color:      Colors.grey[700],
                fontSize:   13)),
      );

  Widget _imagePlaceholder() => Container(
        width: 72, height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.image_outlined, color: Color(0xFF6366F1)),
      );
}
