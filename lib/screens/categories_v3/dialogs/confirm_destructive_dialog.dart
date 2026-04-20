import 'package:flutter/material.dart';

/// Reusable type-to-delete confirmation dialog. Used by every destructive
/// admin action that's NOT idempotent (i.e. delete; bulk hide/pin go through
/// a simpler confirm because they're reversible).
///
/// Returns `true` when the user typed [requiredText] AND tapped the red
/// confirm button. Returns `null` on cancel/dismiss.
class ConfirmDestructiveDialog extends StatefulWidget {
  const ConfirmDestructiveDialog({
    super.key,
    required this.title,
    required this.body,
    required this.requiredText,
    required this.confirmLabel,
    this.helperLabel,
    this.warning,
  });

  /// Dialog title (e.g. "מחיקת קטגוריה").
  final String title;

  /// Long-form explanation of consequences.
  final String body;

  /// The exact text the user must type to enable the confirm button.
  /// Usually the entity name they're about to delete.
  final String requiredText;

  /// Red button label (e.g. "מחק לצמיתות").
  final String confirmLabel;

  /// Hint above the text field (e.g. "כתוב 'אופה עוגות' כדי לאשר").
  final String? helperLabel;

  /// Optional yellow warning banner (e.g. "פעולה זו אינה הפיכה").
  final String? warning;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String body,
    required String requiredText,
    required String confirmLabel,
    String? helperLabel,
    String? warning,
  }) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ConfirmDestructiveDialog(
          title: title,
          body: body,
          requiredText: requiredText,
          confirmLabel: confirmLabel,
          helperLabel: helperLabel,
          warning: warning,
        ),
      );

  @override
  State<ConfirmDestructiveDialog> createState() =>
      _ConfirmDestructiveDialogState();
}

class _ConfirmDestructiveDialogState extends State<ConfirmDestructiveDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _typedCorrectly =>
      _ctrl.text.trim() == widget.requiredText.trim();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.body,
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
            if (widget.warning != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFBBF24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: Color(0xFFB45309)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.warning!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              widget.helperLabel ??
                  'כתוב "${widget.requiredText}" כדי לאשר',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textDirection: TextDirection.rtl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 12, vertical: 10),
                hintText: widget.requiredText,
                hintStyle: const TextStyle(color: Color(0xFFC0C7D2)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: Color(0xFFEF4444), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('ביטול',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton(
            onPressed:
                _typedCorrectly ? () => Navigator.pop(context, true) : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFCA5A5),
            ),
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
