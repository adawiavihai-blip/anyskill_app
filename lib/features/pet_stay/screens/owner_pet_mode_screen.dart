/// AnySkill — Owner Pet Mode Screen (Pet Stay Tracker v13.0.0, Step 8)
///
/// The customer's window into the ongoing stay: gradient hero with
/// progress + counters, live GPS map while the provider is walking,
/// dog card (read-only same snapshot the provider sees), the feed
/// timeline, and the end-of-stay rating prompt.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/dog_profile.dart';
import '../models/pet_stay.dart';
import '../services/dog_profile_service.dart';
import '../services/pet_stay_service.dart';
import '../widgets/dog_profile_card.dart';
import '../widgets/live_walk_map.dart';
import '../widgets/owner_hero_card.dart';
import '../widgets/pet_feed_timeline.dart';
import '../widgets/rating_sheet.dart';
import 'dog_profile_builder_screen.dart';

class OwnerPetModeScreen extends StatelessWidget {
  final String jobId;

  /// Current job status — used to decide whether to show the rating prompt.
  /// Accepts `paid_escrow`, `expert_completed`, `completed`, etc.
  final String jobStatus;

  /// True once the provider has tapped "התחל עבודה" (job.workStartedAt set).
  /// Controls whether the Live Walk Map is visible — customers see
  /// live tracking only AFTER the provider actually started working.
  final bool workStarted;

  const OwnerPetModeScreen({
    super.key,
    required this.jobId,
    required this.jobStatus,
    this.workStarted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        centerTitle: true,
        title: const Text(
          'מצב הכלב 🐕',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: StreamBuilder<PetStay?>(
        stream: PetStayService.instance.stream(jobId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('שגיאה: ${snap.error}'));
          }
          final stay = snap.data;
          if (stay == null) {
            return const _EmptyState();
          }

          // Rating prompt is gated on:
          //   1. job is completed / expert_completed (service done)
          //   2. stay doesn't have a rating yet
          //   3. stay wasn't cancelled
          final showRatingPrompt = (jobStatus == 'expert_completed' ||
                  jobStatus == 'completed') &&
              stay.rating == null &&
              stay.status != 'cancelled';

          final dogName =
              (stay.dogSnapshot['name'] ?? '') as String;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              OwnerHeroCardWithJobId(stay: stay, jobId: jobId),
              const SizedBox(height: 16),

              // Live GPS map — visible ONLY after the provider tapped
              // "התחל עבודה". Prevents customers from seeing tracking
              // before the service actually starts.
              if (workStarted) LiveWalkMap(jobId: jobId)
              else const _WaitingForWorkStart(),

              if (showRatingPrompt) ...[
                const SizedBox(height: 16),
                _RatePrompt(
                  dogName: dogName,
                  onRate: () => RatingSheet.show(
                    context,
                    jobId: jobId,
                    dogName: dogName,
                  ),
                ),
              ],

              if (stay.rating != null) ...[
                const SizedBox(height: 16),
                _RatingShown(
                    rating: stay.rating!, text: stay.reviewText ?? ''),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _sectionTitle('פרטי הכלב')),
                  TextButton.icon(
                    onPressed: () => _openDogEditor(context, stay),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('ערוך'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DogProfileCard(snapshot: stay.dogSnapshot),

              const SizedBox(height: 20),
              _sectionTitle('פיד עדכונים'),
              const SizedBox(height: 10),
              PetFeedTimeline(jobId: jobId),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A2E),
        ),
      );

  /// Opens the full dog profile editor pre-filled with the booking's
  /// frozen snapshot. Saves to the owner's master dog profile.
  /// Changes will apply to the live snapshot on this booking via the
  /// snapshot-sync callback inside DogProfileBuilderScreen.
  Future<void> _openDogEditor(BuildContext context, PetStay stay) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Reconstruct a DogProfile from the snapshot Map, tagged with the
    // original dog ID (if present) so the editor updates rather than creates.
    final snap = stay.dogSnapshot;
    final dogId = snap['id'] as String?;
    final existing = DogProfile.fromMap(dogId ?? '', snap);

    // Load the live master profile if available (more up-to-date fields).
    DogProfile live = existing;
    if (dogId != null && dogId.isNotEmpty) {
      try {
        final fresh = await DogProfileService.instance.get(uid, dogId);
        if (fresh != null) live = fresh;
      } catch (_) {}
    }

    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DogProfileBuilderScreen(existing: live),
      ),
    );

    // After returning, re-read the master profile and sync it into the
    // booking's frozen snapshot so the provider sees updates.
    if (dogId != null && dogId.isNotEmpty) {
      try {
        final fresh = await DogProfileService.instance.get(uid, dogId);
        if (fresh != null) {
          await PetStayService.instance.updateDogSnapshot(
            jobId: jobId,
            dogSnapshot: {...fresh.toMap(), 'id': dogId},
          );
        }
      } catch (_) {
        // Non-fatal — stream will show stale snapshot until next booking.
      }
    }
  }
}

/// Placeholder shown in place of LiveWalkMap before the provider starts
/// working. Keeps the layout consistent and sets user expectations.
class _WaitingForWorkStart extends StatelessWidget {
  const _WaitingForWorkStart();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_top_rounded, color: Color(0xFF856404)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'המעקב החי ייפתח ברגע שנותן השירות יתחיל את העבודה',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF856404),
                  fontWeight: FontWeight.w600,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatePrompt extends StatelessWidget {
  final String dogName;
  final VoidCallback onRate;

  const _RatePrompt({required this.dogName, required this.onRate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEF3C7), Color(0xFFFBBF24)],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('⭐', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'איך היה עם ${dogName.isEmpty ? "הכלב" : dogName}?',
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'הדירוג שלך עוזר לספקים הבאים',
                  style: TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF78350F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onRate,
            child: const Text('דרג'),
          ),
        ],
      ),
    );
  }
}

class _RatingShown extends StatelessWidget {
  final double rating;
  final String text;
  const _RatingShown({required this.rating, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF059669)),
              const SizedBox(width: 8),
              const Text(
                'הדירוג שלך נשלח',
                style: TextStyle(
                  color: Color(0xFF065F46),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Row(children: [
                for (int i = 1; i <= 5; i++)
                  Icon(
                    i <= rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFFBBF24),
                    size: 18,
                  ),
              ]),
            ],
          ),
          if (text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFF065F46),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pets_rounded,
                size: 64, color: Color(0xFF9CA3AF)),
            SizedBox(height: 16),
            Text(
              'המעקב על הכלב עוד לא התחיל',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'לאחר התחלת השהות יופיעו כאן עדכונים בזמן אמת',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
