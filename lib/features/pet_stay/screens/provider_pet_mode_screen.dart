/// AnySkill — Provider Pet Mode Screen (Pet Stay Tracker v13.0.0)
///
/// The provider's home base for an active pet booking. Shows:
///   1. A gold-bordered DogProfileCard with the frozen snapshot
///   2. Stay metadata (dates, status, counters)
///   3. (Pension only) A multi-day ScheduleChecklist
///
/// Walk tracking + daily proof controls stay on the existing
/// `PetServiceActions` widget mounted on `ExpertJobCard` — they're a
/// duplicate surface kept for quick access from the bookings list.
library;

import 'package:flutter/material.dart';

import '../models/pet_stay.dart';
import '../models/schedule_item.dart';
import '../services/pet_stay_service.dart';
import '../widgets/daily_report_form.dart';
import '../widgets/dog_profile_card.dart';
import '../widgets/feed_composer.dart';
import '../widgets/pet_feed_timeline.dart';
import '../widgets/schedule_checklist.dart';

class ProviderPetModeScreen extends StatelessWidget {
  final String jobId;

  const ProviderPetModeScreen({super.key, required this.jobId});

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
          'מצב מטפל 🐕',
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _statusHeader(stay),
              const SizedBox(height: 16),
              DogProfileCard(snapshot: stay.dogSnapshot),
              const SizedBox(height: 16),
              FeedComposer(
                jobId: jobId,
                customerId: stay.customerId,
                expertId: stay.expertId,
              ),
              if (stay.isPension) ...[
                const SizedBox(height: 20),
                _sectionTitle('לוח זמנים יומי'),
                const SizedBox(height: 10),
                StreamBuilder<List<ScheduleItem>>(
                  stream:
                      PetStayService.instance.streamSchedule(jobId),
                  builder: (context, sSnap) {
                    if (sSnap.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: CircularProgressIndicator()),
                      );
                    }
                    final items = sSnap.data ?? const [];
                    return ScheduleChecklist(
                      jobId: jobId,
                      items: items,
                      canToggle: true,
                    );
                  },
                ),
              ],
              if (stay.isDogWalker) ...[
                const SizedBox(height: 20),
                _dogWalkerTip(),
              ],

              if (stay.isPension) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFA855F7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.assignment_rounded),
                    label: const Text(
                      '📊 שלח דו"ח יומי',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => DailyReportForm.show(
                      context,
                      jobId: jobId,
                      customerId: stay.customerId,
                      expertId: stay.expertId,
                    ),
                  ),
                ),
              ],

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

  Widget _statusHeader(PetStay stay) {
    final isPension = stay.isPension;
    final dateRange = isPension
        ? '${_d(stay.startDate)} → ${_d(stay.endDate)} · ${stay.totalNights} לילות'
        : _d(stay.startDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPension ? Icons.home_rounded : Icons.directions_walk_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPension ? 'פנסיון ביתי' : 'דוגווקר',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateRange,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _statusPill(stay.status),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final label = switch (status) {
      'upcoming' => 'ממתין',
      'active' => 'פעיל',
      'completed' => 'הושלם',
      'cancelled' => 'בוטל',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF6366F1),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Color(0xFF1A1A2E),
      ),
    );
  }

  Widget _dogWalkerTip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF059669)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'השתמש בכפתור "התחל הליכון" בכרטיס ההזמנה כדי להתחיל את המעקב.',
              style: TextStyle(
                color: Color(0xFF065F46),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.pets_rounded,
                size: 64, color: Color(0xFF9CA3AF)),
            SizedBox(height: 16),
            Text(
              'לא נמצא מידע על השהות',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'הזמנה זו נוצרה לפני הפעלת מערכת המעקב',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
