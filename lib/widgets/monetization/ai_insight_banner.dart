import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Section 2 — purple Gemini-branded banner carrying the latest
/// monetization insight. Stage 2 renders a placeholder; stage 5 streams
/// `ai_insights/monetization/latest` from Firestore.
class AiInsightBanner extends StatelessWidget {
  const AiInsightBanner({
    super.key,
    this.title = 'תובנת AI CEO',
    this.body = 'אין תובנה חדשה כרגע. ה-AI מנתח את הנתונים בכל 6 שעות.',
    this.model = 'Gemini 2.5',
    this.actionEnabled = false,
    this.onApply,
    this.onDismiss,
  });

  final String title;
  final String body;
  final String model;
  final bool actionEnabled;
  final VoidCallback? onApply;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: MonetizationTokens.primaryLight,
        border: Border.all(color: MonetizationTokens.primaryBorder, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: MonetizationTokens.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: MonetizationTokens.primaryDarker,
                        )),
                    const SizedBox(width: 6),
                    MonetizationPill(
                      label: model,
                      background: Colors.white,
                      foreground: MonetizationTokens.primaryDark,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: MonetizationTokens.primaryDark,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              ElevatedButton(
                onPressed: actionEnabled ? onApply : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MonetizationTokens.primaryDark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      MonetizationTokens.primaryDark.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('הפעל'),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed: actionEnabled ? onDismiss : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: MonetizationTokens.primaryDark,
                  side: const BorderSide(
                      color: MonetizationTokens.primaryBorder, width: 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('דחה'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
