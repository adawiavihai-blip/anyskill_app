// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Drop-in AppBar action widget that renders a contextual help icon (?) for
/// any screen.  The icon and its content are driven entirely by the Firestore
/// `app_hints/{screenKey}` document so the admin can toggle / edit it live.
///
/// Usage:
///   actions: [HintIcon(screenKey: 'opportunities')],
class HintIcon extends StatelessWidget {
  final String screenKey;
  const HintIcon({super.key, required this.screenKey});

  static const _adminEmail = 'adawiavihai@gmail.com';

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        FirebaseAuth.instance.currentUser?.email == _adminEmail;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_hints')
          .doc(screenKey)
          .snapshots(),
      builder: (_, snap) {
        final data      = snap.data?.data() as Map<String, dynamic>? ?? {};
        final isVisible = data['isVisible'] as bool?   ?? false;
        final title     = data['title']     as String? ?? '';
        final content   = data['content']   as String? ?? '';

        // Regular users see nothing when the hint is hidden
        if (!isVisible && !isAdmin) return const SizedBox.shrink();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Admin: edit pencil ──────────────────────────────────
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: Colors.orange,
                tooltip: 'ערוך רמז',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      _HintEditDialog(screenKey: screenKey, data: data),
                ),
              ),

            // ── Help (?) icon ───────────────────────────────────────
            if (isVisible)
              IconButton(
                icon: const Icon(Icons.help_outline_rounded, size: 22),
                color: const Color(0xFF6366F1),
                tooltip: 'עזרה',
                onPressed: () =>
                    _showHelpModal(context, title, content),
              )
            else if (isAdmin)
              // Disabled hint — greyed icon so admin knows it's off
              Tooltip(
                message: 'רמז מוסתר — לחץ עריכה להפעלה',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.help_outline_rounded,
                      size: 22, color: Colors.grey.shade400),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── User-facing help modal ────────────────────────────────────────────────
  static void _showHelpModal(
      BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HelpModal(title: title, content: content),
    );
  }
}

// ── Help bottom sheet (user view) ─────────────────────────────────────────
class _HelpModal extends StatelessWidget {
  final String title;
  final String content;
  const _HelpModal({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header row: close + badge
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.help_outline_rounded,
                        size: 14, color: Color(0xFF6366F1)),
                    SizedBox(width: 4),
                    Text('עזרה',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (title.isNotEmpty) ...[
            Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
          ],
          if (content.isNotEmpty)
            Text(
              content,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.6),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Hint edit dialog (admin only) ─────────────────────────────────────────
class _HintEditDialog extends StatefulWidget {
  final String screenKey;
  final Map<String, dynamic> data;
  const _HintEditDialog({required this.screenKey, required this.data});

  @override
  State<_HintEditDialog> createState() => _HintEditDialogState();
}

class _HintEditDialogState extends State<_HintEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late bool _isVisible;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl   = TextEditingController(
        text: widget.data['title']   as String? ?? '');
    _contentCtrl = TextEditingController(
        text: widget.data['content'] as String? ?? '');
    _isVisible   = widget.data['isVisible'] as bool? ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_hints')
          .doc(widget.screenKey)
          .set({
        'title':     _titleCtrl.text.trim(),
        'content':   _contentCtrl.text.trim(),
        'isVisible': _isVisible,
        'screenKey': widget.screenKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('שגיאה: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ערוך רמז',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(width: 6),
                  Icon(Icons.edit_outlined,
                      size: 18, color: Colors.orange),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                widget.screenKey,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.normal),
              ),
            ],
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // isVisible toggle
            SwitchListTile.adaptive(
              value: _isVisible,
              onChanged: (v) => setState(() => _isVisible = v),
              title: const Text('הצג אייקון (?)',
                  textAlign: TextAlign.right),
              activeColor: const Color(0xFF6366F1),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            // Title field
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text('כותרת',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: 'כותרת הרמז',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            // Content field
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text('תוכן',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _contentCtrl,
              textAlign: TextAlign.right,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'הסבר מפורט...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('שמור',
                  style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
