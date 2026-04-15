/// AnySkill — Owner Hero Card (Pet Stay Tracker v13.0.0, Step 8)
///
/// Top-of-screen hero on the owner's Pet Mode. Purple gradient, dog
/// photo, name + provider, date range. For pension shows a progress bar
/// "יום X מתוך Y" and stats derived from the live updates feed (walks,
/// distance, photos, reports). Counters are computed client-side, NOT
/// from `petStay.totalWalks` etc — those are denormalised cache fields
/// used only by rules enforcement. Single source of truth = the feed.
library;

import 'package:flutter/material.dart';

import '../../../utils/safe_image_provider.dart';
import '../models/pet_stay.dart';
import '../models/pet_update.dart';
import '../services/pet_update_service.dart';

/// The only public class in this file. Takes the PetStay + jobId so the
/// inner stats stream can attach to `updates`.
class OwnerHeroCardWithJobId extends StatelessWidget {
  final PetStay stay;
  final String jobId;

  const OwnerHeroCardWithJobId({
    super.key,
    required this.stay,
    required this.jobId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PetUpdate>>(
      stream: PetUpdateService.instance.stream(jobId),
      builder: (context, snap) {
        final updates = snap.data ?? const [];
        return _HeroBody(stay: stay, updates: updates);
      },
    );
  }
}

class _HeroBody extends StatelessWidget {
  final PetStay stay;
  final List<PetUpdate> updates;

  const _HeroBody({required this.stay, required this.updates});

  @override
  Widget build(BuildContext context) {
    final dogName = (stay.dogSnapshot['name'] ?? '') as String;
    final breed = (stay.dogSnapshot['breed'] ?? '') as String;
    final photo = safeImageProvider(stay.dogSnapshot['photoUrl'] as String?);

    final walks = updates.where((u) => u.type == 'walk_completed').length;
    final photos = updates.where((u) => u.type == 'photo').length;
    final videos = updates.where((u) => u.type == 'video').length;
    final reports = updates.where((u) => u.type == 'daily_report').length;
    final totalKm = updates
        .where((u) => u.type == 'walk_completed')
        .fold<double>(
            0, (sum, u) => sum + (u.distanceKm?.toDouble() ?? 0.0));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  backgroundImage: photo,
                  child: photo == null
                      ? const Icon(Icons.pets_rounded,
                          color: Colors.white, size: 32)
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dogName.isEmpty ? 'הכלב שלך' : dogName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (breed.isNotEmpty)
                      Text(
                        breed,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      stay.isPension
                          ? '${_d(stay.startDate)} → ${_d(stay.endDate)} · ${stay.totalNights} לילות'
                          : 'הליכון ב-${_d(stay.startDate)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(stay.status),
            ],
          ),
          if (stay.isPension && stay.totalNights > 0) ...[
            const SizedBox(height: 14),
            _ProgressBar(stay: stay),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                    child: _Stat(
                        Icons.directions_walk_rounded, walks, 'הליכונים')),
                Expanded(
                    child: _Stat(Icons.straighten_rounded, totalKm, 'ק"מ')),
                Expanded(
                    child: _Stat(Icons.camera_alt_rounded,
                        photos + videos, 'מדיה')),
                Expanded(
                    child:
                        _Stat(Icons.assignment_rounded, reports, 'דו"חות')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}';
}

class _ProgressBar extends StatelessWidget {
  final PetStay stay;
  const _ProgressBar({required this.stay});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final total = stay.endDate.difference(stay.startDate).inDays;
    final elapsed =
        now.difference(stay.startDate).inDays.clamp(0, total).toInt();
    final pct = total == 0 ? 0.0 : (elapsed / total).clamp(0.0, 1.0);
    final dayNumber = (elapsed + 1).clamp(1, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'יום $dayNumber מתוך $total',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            Text(
              '${(pct * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final num value;
  final String label;
  const _Stat(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final display = value is double ? value.toStringAsFixed(1) : '$value';
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(height: 4),
        Text(display,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14)),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
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
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
