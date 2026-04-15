/// AnySkill — End-of-Stay Rating Sheet (Pet Stay Tracker v13.0.0, Step 8)
///
/// Modal bottom sheet for the customer to rate the pet stay AFTER
/// the provider marks the job as completed. Captures:
///   • 1-5 stars
///   • free-text review
///
/// **NO TIP.** Per product decision, no tip mechanic exists in any layer
/// of the pet-stay feature.
library;

import 'package:flutter/material.dart';

import '../services/pet_stay_service.dart';

class RatingSheet extends StatefulWidget {
  final String jobId;
  final String dogName;

  const RatingSheet({
    super.key,
    required this.jobId,
    required this.dogName,
  });

  /// Convenience — shows the sheet and returns true when the user submitted.
  static Future<bool> show(
    BuildContext context, {
    required String jobId,
    required String dogName,
  }) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RatingSheet(jobId: jobId, dogName: dogName),
    );
    return res == true;
  }

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  int _stars = 0;
  final _textCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) return;
    setState(() => _submitting = true);
    try {
      await PetStayService.instance.submitRating(
        jobId: widget.jobId,
        rating: _stars.toDouble(),
        reviewText: _textCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('תודה על הדירוג! 🐾'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grip
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('🐾',
                    style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'איך היה עם ${widget.dogName.isEmpty ? "הכלב" : widget.dogName}?',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'דרג את החוויה ואם תרצה/י הוסף/י הערה לספק',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // Stars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              final active = starIndex <= _stars;
              return IconButton(
                iconSize: 40,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: _submitting
                    ? null
                    : () => setState(() => _stars = starIndex),
                icon: Icon(
                  active ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: active
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFFD1D5DB),
                ),
              );
            }),
          ),

          if (_stars > 0) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                _labelForStars(_stars),
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),

          TextField(
            controller: _textCtrl,
            maxLines: 4,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            enabled: !_submitting,
            decoration: InputDecoration(
              hintText: 'הוסף/י ביקורת חופשית (אופציונלי)',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF6366F1), width: 2),
              ),
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _stars > 0
                    ? const Color(0xFF6366F1)
                    : const Color(0xFFD1D5DB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(
                _submitting ? 'שולח...' : 'שלח דירוג',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: (_stars == 0 || _submitting) ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }

  String _labelForStars(int n) {
    switch (n) {
      case 1:
        return 'לא מרוצה';
      case 2:
        return 'יכול להיות יותר טוב';
      case 3:
        return 'בסדר';
      case 4:
        return 'מרוצה';
      case 5:
        return 'מעולה!';
      default:
        return '';
    }
  }
}
