/// AnySkill — Pet Feed Timeline (Pet Stay Tracker v13.0.0, Step 7)
///
/// Streams [PetUpdate]s from `jobs/{jobId}/petStay/data/updates` and
/// renders them as a list of [FeedItemCard]s. Empty state is built-in.
library;

import 'package:flutter/material.dart';

import '../models/pet_update.dart';
import '../services/pet_update_service.dart';
import 'feed_item_card.dart';

class PetFeedTimeline extends StatelessWidget {
  final String jobId;
  final int maxItems;

  const PetFeedTimeline({
    super.key,
    required this.jobId,
    this.maxItems = 100,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PetUpdate>>(
      stream: PetUpdateService.instance.stream(jobId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _errorBox(snap.error.toString());
        }
        final updates = (snap.data ?? const []).take(maxItems).toList();
        if (updates.isEmpty) return const _EmptyFeed();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final u in updates)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FeedItemCard(update: u, jobId: jobId),
              ),
          ],
        );
      },
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text('שגיאה בטעינת הפיד: $msg',
          style: const TextStyle(color: Color(0xFF991B1B))),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Column(
        children: [
          Icon(Icons.photo_library_outlined,
              size: 40, color: Color(0xFF9CA3AF)),
          SizedBox(height: 8),
          Text(
            'אין עדיין עדכונים',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              fontSize: 14,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'שלח תמונה, וידאו או הערה כדי לעדכן את הבעלים',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
