import 'package:flutter/material.dart';

/// Bottom input area: text field + send button.
///
/// Quick-reply chips were removed in v15.x (PR-1 of the messages-upgrade)
/// in favor of an attachment menu wired in PR-2. The underlying handlers
/// (`_sendLocation`, `_sendImage`, `_showQuoteDialog`,
/// `_showRequestPaymentDialog`) still live on `_ChatScreenState` and will
/// be re-wired through that menu.
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isUploading;
  final bool guardFlagged;
  final VoidCallback onSend;
  final ValueChanged<String> onTextChanged;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isUploading,
    required this.guardFlagged,
    required this.onSend,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUploading) ...[
            const LinearProgressIndicator(color: Color(0xFF6366F1)),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 44, maxHeight: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: guardFlagged
                          ? const Color(0xFFDC2626)
                          : Colors.grey.shade200,
                      width: guardFlagged ? 1.5 : 1.0,
                    ),
                  ),
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    onChanged: onTextChanged,
                    decoration: InputDecoration(
                      hintText: 'הקלד הודעה...',
                      hintStyle: TextStyle(
                          color: Colors.grey[400], fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      hasText ? const Color(0xFF6366F1) : Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: hasText ? Colors.white : Colors.grey[400],
                  ),
                  onPressed: onSend,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
