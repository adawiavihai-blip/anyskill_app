/// AnySkill — Engagement & Gamification Service
///
/// Three interconnected systems:
///   1. **Daily Drop** — 20% chance of a prize on first login of the day
///      (requires activity in last 72h).
///   2. **Provider Streaks** — consecutive days with response time < 10 min.
///   3. **Variable XP** — 2X multiplier for off-peak hours (nights/weekends).
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gamification_service.dart';

// ── Reward Types ─────────────────────────────────────────────────────────────

enum RewardType {
  zeroCommissionDay,
  profileBoostCard,
  temporaryRecommendedBadge,
}

class RewardConfig {
  final RewardType type;
  final String nameHe;
  final String descriptionHe;
  final IconData icon;
  final Color color;
  final Duration duration;

  const RewardConfig({
    required this.type,
    required this.nameHe,
    required this.descriptionHe,
    required this.icon,
    required this.color,
    required this.duration,
  });

  String get typeId => type.name;
}

// ═══════════════════════════════════════════════════════════════════════════════

class EngagementService {
  EngagementService._();

  static final _db = FirebaseFirestore.instance;
  static final _rng = Random();

  // ── Constants ──────────────────────────────────────────────────────────────

  /// Probability of winning a Daily Drop prize (20%).
  static const double dailyDropProbability = 0.20;

  /// Activity window: user must have been active in the last 72 hours.
  static const int activityWindowHours = 72;

  /// Streak response time threshold (minutes).
  static const int streakResponseThreshold = 10;

  /// Streak milestone that awards a free profile boost.
  static const int streakBoostMilestone = 7;

  /// Off-peak hours (20:00-08:00 local time, or any Saturday).
  static bool isOffPeak() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday) return true;
    return now.hour >= 20 || now.hour < 8;
  }

  // ── Reward Pool ────────────────────────────────────────────────────────────

  static const List<RewardConfig> rewardPool = [
    RewardConfig(
      type: RewardType.zeroCommissionDay,
      nameHe: 'יום ללא עמלה!',
      descriptionHe: 'כל העבודות היום — 0% עמלה. הכל שלך.',
      icon: Icons.money_off_rounded,
      color: Color(0xFF10B981),
      duration: Duration(hours: 24),
    ),
    RewardConfig(
      type: RewardType.profileBoostCard,
      nameHe: 'כרטיס דחיפת פרופיל',
      descriptionHe: 'הפרופיל שלך יופיע בראש תוצאות החיפוש ב-12 השעות הקרובות.',
      icon: Icons.rocket_launch_rounded,
      color: Color(0xFF6366F1),
      duration: Duration(hours: 12),
    ),
    RewardConfig(
      type: RewardType.temporaryRecommendedBadge,
      nameHe: 'תג "מומלץ" זמני',
      descriptionHe: 'תג מומלץ בולט על הפרופיל שלך למשך 24 שעות.',
      icon: Icons.star_rounded,
      color: Color(0xFFF59E0B),
      duration: Duration(hours: 24),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. DAILY DROP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Checks if the user is eligible for a Daily Drop and rolls the dice.
  ///
  /// Returns the [RewardConfig] if the user wins, or null if:
  ///   - Already rolled today
  ///   - Not active in last 72h
  ///   - Lost the 20% roll
  ///
  /// Also writes the reward to `user_rewards` if won.
  static Future<RewardConfig?> calculateRandomReward(String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    final userData = userDoc.data() ?? {};

    // ── Already rolled today? ────────────────────────────────────────────
    final today = _todayKey();
    final lastDrop = userData['lastDailyDropDate'] as String?;
    if (lastDrop == today) return null;

    // ── Activity check (72h window) ──────────────────────────────────────
    final lastActive = userData['lastActiveAt'] as Timestamp?;
    if (lastActive == null) return null;
    final hoursSinceActive =
        DateTime.now().difference(lastActive.toDate()).inHours;
    if (hoursSinceActive > activityWindowHours) return null;

    // ── Mark today's roll (even before the dice) ─────────────────────────
    await _db.collection('users').doc(userId).update({
      'lastDailyDropDate': today,
    });

    // ── Roll the dice (20% probability) ──────────────────────────────────
    if (_rng.nextDouble() > dailyDropProbability) return null;

    // ── Won! Pick a random reward ────────────────────────────────────────
    final reward = rewardPool[_rng.nextInt(rewardPool.length)];
    final expiresAt = DateTime.now().add(reward.duration);

    await _db.collection('user_rewards').add({
      'userId': userId,
      'type': reward.typeId,
      'status': 'active',
      'awardedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    // Denormalize boost card expiry onto user doc for O(1) search ranking
    if (reward.type == RewardType.profileBoostCard) {
      await _db.collection('users').doc(userId).update({
        'profileBoostUntil': Timestamp.fromDate(expiresAt),
      });
    }

    return reward;
  }

  /// Returns active, non-expired rewards for a user.
  static Future<List<Map<String, dynamic>>> getActiveRewards(
      String userId) async {
    final now = Timestamp.now();
    final snap = await _db
        .collection('user_rewards')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .where('expiresAt', isGreaterThan: now)
        .limit(10)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Checks if a user has a specific active reward type right now.
  static Future<bool> hasActiveReward(
      String userId, RewardType type) async {
    final rewards = await getActiveRewards(userId);
    return rewards.any((r) => r['type'] == type.name);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. PROVIDER STREAKS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Call daily (e.g., on app open) to check and update the streak.
  ///
  /// A streak day is counted when:
  ///   - The provider's `avgResponseMinutes` <= [streakResponseThreshold]
  ///   - The provider was online at some point during the day
  ///
  /// Returns the updated streak count.
  static Future<int> checkAndUpdateStreak(String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    final data = userDoc.data() ?? {};
    final today = _todayKey();
    final lastStreakDate = data['lastStreakDate'] as String? ?? '';
    final currentStreak = (data['streak'] as num? ?? 0).toInt();
    final bestStreak = (data['streakBestEver'] as num? ?? 0).toInt();

    // Already counted today
    if (lastStreakDate == today) return currentStreak;

    // Check if yesterday was the last streak day (consecutive)
    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    final isConsecutive = lastStreakDate == yesterday;

    // Check qualification: response time threshold
    final avgResponse = (data['avgResponseMinutes'] as num? ?? 0).toInt();
    final qualifies = avgResponse > 0 && avgResponse <= streakResponseThreshold;

    int newStreak;
    if (qualifies) {
      newStreak = isConsecutive ? currentStreak + 1 : 1;
    } else {
      newStreak = 0; // Streak broken
    }

    final newBest = max(bestStreak, newStreak);

    await _db.collection('users').doc(userId).update({
      'streak': newStreak,
      'lastStreakDate': today,
      'streakBestEver': newBest,
    });

    // ── Milestone check: 7-day streak → free profile boost ───────────────
    if (newStreak > 0 && newStreak % streakBoostMilestone == 0) {
      await _awardStreakMilestone(userId, newStreak);
    }

    return newStreak;
  }

  static Future<void> _awardStreakMilestone(
      String userId, int streakCount) async {
    final boost = rewardPool.firstWhere(
        (r) => r.type == RewardType.profileBoostCard);
    final expiresAt = DateTime.now().add(boost.duration);

    await _db.collection('user_rewards').add({
      'userId': userId,
      'type': boost.typeId,
      'status': 'active',
      'awardedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'source': 'streak_milestone_$streakCount',
    });

    // Denormalize for O(1) search ranking
    await _db.collection('users').doc(userId).update({
      'profileBoostUntil': Timestamp.fromDate(expiresAt),
    });

    await _db.collection('notifications').add({
      'userId': userId,
      'title': '🔥 רצף $streakCount ימים!',
      'body': 'כל הכבוד! קיבלת כרטיס דחיפת פרופיל חינם ל-12 שעות!',
      'type': 'streak_milestone',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Checks if a streak is about to break (last streak was yesterday
  /// but the user hasn't qualified yet today).
  static bool isStreakAtRisk(Map<String, dynamic> userData) {
    final lastStreakDate = userData['lastStreakDate'] as String? ?? '';
    final streak = (userData['streak'] as num? ?? 0).toInt();
    if (streak == 0) return false;

    final today = _todayKey();
    if (lastStreakDate == today) return false; // Already extended today

    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    return lastStreakDate == yesterday; // Will break if not extended today
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. VARIABLE XP (2X OFF-PEAK MULTIPLIER)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Awards XP for an event, with a chance of 2X during off-peak hours.
  /// Returns `{newXp: int, multiplier: int}` or null on failure.
  static Future<Map<String, int>?> awardVariableXp(
      String userId, String eventId) async {
    final multiplier = isOffPeak() ? 2 : 1;

    if (multiplier == 1) {
      // Standard award
      final newXp = await GamificationService.awardXP(userId, eventId);
      if (newXp == null) return null;
      return {'newXp': newXp, 'multiplier': 1};
    }

    // Off-peak: award twice (Cloud Function handles individual XP amounts)
    final first = await GamificationService.awardXP(userId, eventId);
    final second = await GamificationService.awardXP(userId, eventId);
    final newXp = second ?? first;
    if (newXp == null) return null;
    return {'newXp': newXp, 'multiplier': 2};
  }

  /// Detects if the user just crossed a level boundary.
  /// Compare [oldXp] (before award) with [newXp] (after award).
  static bool didLevelUp(int oldXp, int newXp) {
    return GamificationService.levelFor(oldXp) !=
        GamificationService.levelFor(newXp);
  }

  // ── Level display names (extended beyond Bronze/Silver/Gold) ────────────

  /// Extended level names for gamification display.
  static String levelDisplayName(int xp) {
    if (xp >= 5000) return 'אגדי';     // Legendary
    if (xp >= 2000) return 'זהב';      // Gold
    if (xp >= 500)  return 'מקצוען';   // Pro
    return 'טירון';                     // Rookie
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _todayKey() => _dayKey(DateTime.now());

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
