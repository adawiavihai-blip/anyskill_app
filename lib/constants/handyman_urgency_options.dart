// Handyman urgency catalog — 4 options on the client booking block.
// Matches spec docs/ui-specs/Handyman/03_CLIENT_BOOKING_HANDYMAN.md Section 9.
import 'package:flutter/material.dart';

class HandymanUrgencyOption {
  final String id; // emergency | today | scheduled | maintenance_contract
  final String labelHe;
  final String subtitleHe;
  final String emoji;
  final Color gradientStart;
  final Color gradientEnd;
  final bool hasSurcharge;

  const HandymanUrgencyOption({
    required this.id,
    required this.labelHe,
    required this.subtitleHe,
    required this.emoji,
    required this.gradientStart,
    required this.gradientEnd,
    this.hasSurcharge = false,
  });
}

const List<HandymanUrgencyOption> kHandymanUrgencyOptions = [
  HandymanUrgencyOption(
    id: 'emergency',
    labelHe: 'עכשיו',
    subtitleHe: '25 דק\' · +תוספת',
    emoji: '🚨',
    gradientStart: Color(0xFFDC2626),
    gradientEnd: Color(0xFF991B1B),
    hasSurcharge: true,
  ),
  HandymanUrgencyOption(
    id: 'today',
    labelHe: 'היום',
    subtitleHe: 'חלון 2 שעות',
    emoji: '⚡',
    gradientStart: Color(0xFFF97316),
    gradientEnd: Color(0xFFEA580C),
  ),
  HandymanUrgencyOption(
    id: 'scheduled',
    labelHe: 'תאריך אחר',
    subtitleHe: 'בחר מתי',
    emoji: '📅',
    gradientStart: Color(0xFF3B82F6),
    gradientEnd: Color(0xFF2563EB),
  ),
  HandymanUrgencyOption(
    id: 'maintenance_contract',
    labelHe: 'תחזוקה',
    subtitleHe: 'חוזה שנתי',
    emoji: '🔁',
    gradientStart: Color(0xFF6366F1),
    gradientEnd: Color(0xFF4F46E5),
  ),
];
