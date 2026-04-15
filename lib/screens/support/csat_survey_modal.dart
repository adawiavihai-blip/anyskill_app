// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/support_agent_service.dart';

/// Customer Satisfaction (CSAT) survey modal.
///
/// Triggered automatically by `SupportAgentService.closeTicket()` which
/// writes a notification with `type: 'csat_survey'`. The customer taps the
/// notification → `notifications_screen.dart` calls [showCsatSurveyModal]
/// with the ticketId from `notification.data.ticketId`.
///
/// The customer rates 1-5 stars + optional comment, and the result is
/// written back to the ticket via `SupportAgentService.submitCsatRating`.
Future<void> showCsatSurveyModal({
  required BuildContext context,
  required String ticketId,
}) async {
  // First check if the ticket exists and isn't already rated
  try {
    final snap = await FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(ticketId)
        .get();
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    if (data['csatRating'] != null) {
      // Already rated — show a brief thank-you instead
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('כבר דירגת את הפנייה הזו. תודה!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
      return;
    }
  } catch (_) {
    // Continue to show the modal anyway — user can still rate
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    builder: (_) => _CsatSurveySheet(ticketId: ticketId),
  );
}

class _CsatSurveySheet extends StatefulWidget {
  final String ticketId;
  const _CsatSurveySheet({required this.ticketId});

  @override
  State<_CsatSurveySheet> createState() => _CsatSurveySheetState();
}

class _CsatSurveySheetState extends State<_CsatSurveySheet> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      await SupportAgentService.submitCsatRating(
        ticketId: widget.ticketId,
        rating: _rating,
        comment: _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🙏 תודה על הדירוג! זה עוזר לנו להשתפר.'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירת הדירוג: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          18,
          24,
          MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // Animated icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rate_rounded,
                  size: 48,
                  color: Color(0xFFF59E0B),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Title
            const Text(
              'איך הייתה התמיכה?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'הדירוג שלך עוזר לנו להעניק לך שירות טוב יותר',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 5-star rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return GestureDetector(
                  onTap: () => setState(() => _rating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedScale(
                      scale: filled ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        filled
                            ? Icons.star_rate_rounded
                            : Icons.star_border_rounded,
                        size: 44,
                        color: filled
                            ? const Color(0xFFF59E0B)
                            : Colors.grey[400],
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            // Rating label
            if (_rating > 0)
              Text(
                _ratingLabel(_rating),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ratingColor(_rating),
                ),
              )
            else
              Text(
                'בחר דירוג',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),

            const SizedBox(height: 20),

            // Comment field
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              maxLength: 300,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'משוב נוסף (אופציונלי)...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 16),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _rating == 0 || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'שלח דירוג',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: Text(
                'אולי בפעם אחרת',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ratingLabel(int rating) {
    return switch (rating) {
      1 => '😞 לא מרוצה',
      2 => '😐 בסדר',
      3 => '🙂 טוב',
      4 => '😊 טוב מאוד',
      5 => '🤩 מצוין',
      _ => '',
    };
  }

  Color _ratingColor(int rating) {
    return switch (rating) {
      1 => const Color(0xFFEF4444),
      2 => const Color(0xFFF59E0B),
      3 => const Color(0xFFF59E0B),
      4 => const Color(0xFF10B981),
      5 => const Color(0xFF10B981),
      _ => Colors.grey,
    };
  }
}
