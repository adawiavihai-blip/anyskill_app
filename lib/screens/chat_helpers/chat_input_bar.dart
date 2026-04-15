import 'package:flutter/material.dart';

/// Bottom input area: quick action chips + text field + send button.
///
/// Extracted from chat_screen.dart (Phase 6 refactor).
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isUploading;
  final bool guardFlagged;
  final bool isProvider;
  final VoidCallback onSend;
  final VoidCallback onSendLocation;
  final VoidCallback onSendImage;
  final VoidCallback onIAmOnTheWay;
  final VoidCallback onIFinished;
  final VoidCallback onShowQuoteDialog;
  final VoidCallback onShowRequestPaymentDialog;
  final ValueChanged<String> onTextChanged;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isUploading,
    required this.guardFlagged,
    required this.isProvider,
    required this.onSend,
    required this.onSendLocation,
    required this.onSendImage,
    required this.onIAmOnTheWay,
    required this.onIFinished,
    required this.onShowQuoteDialog,
    required this.onShowRequestPaymentDialog,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildQuickActions(),
        _buildInputArea(),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Container(
      height: 44,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true, // RTL: first chip on the right
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _chip(Icons.location_on_rounded, 'שלח מיקום', onSendLocation,
              chipColor: Colors.redAccent),
          if (isProvider)
            _chip(Icons.receipt_long_rounded, 'הצעת מחיר 💰',
                onShowQuoteDialog,
                chipColor: const Color(0xFF6366F1))
          else
            _chip(Icons.payments_rounded, 'בקש תשלום',
                onShowRequestPaymentDialog,
                chipColor: const Color(0xFFD97706)),
          _chip(Icons.directions_car_rounded, 'אני בדרך 🚗', onIAmOnTheWay,
              chipColor: const Color(0xFF16A34A)),
          _chip(Icons.check_circle_outline_rounded, 'סיימתי ✅', onIFinished,
              chipColor: const Color(0xFF0EA5E9)),
          _chip(Icons.image_outlined, 'שלח תמונה', onSendImage,
              chipColor: const Color(0xFF6366F1)),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap,
      {Color chipColor = const Color(0xFF6366F1)}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipColor.withValues(alpha: 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: chipColor,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _buildInputArea() {
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
                  color: hasText
                      ? const Color(0xFF6366F1)
                      : Colors.grey[200],
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
