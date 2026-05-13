// Cleaning types — 6 pre-defined services a provider can offer.
import 'package:flutter/material.dart';

class CleaningTypeDef {
  final String id;
  final String nameHe;
  final String icon;
  final String descriptionHe;
  final int avgDurationHours;
  final Color accent;

  const CleaningTypeDef({
    required this.id,
    required this.nameHe,
    required this.icon,
    required this.descriptionHe,
    required this.avgDurationHours,
    required this.accent,
  });
}

const List<CleaningTypeDef> kCleaningTypes = [
  CleaningTypeDef(
    id: 'regular_home',
    nameHe: 'בית רגיל',
    icon: '🏠',
    descriptionHe: '~3 שעות',
    avgDurationHours: 3,
    accent: Color(0xFF06B6D4),
  ),
  CleaningTypeDef(
    id: 'deep_renovation',
    nameHe: 'Deep / שיפוץ',
    icon: '✨',
    descriptionHe: '~5 שעות',
    avgDurationHours: 5,
    accent: Color(0xFF8B5CF6),
  ),
  CleaningTypeDef(
    id: 'airbnb',
    nameHe: 'Airbnb',
    icon: '🏨',
    descriptionHe: '~2 שעות',
    avgDurationHours: 2,
    accent: Color(0xFFF59E0B),
  ),
  CleaningTypeDef(
    id: 'office',
    nameHe: 'משרדים',
    icon: '🏢',
    descriptionHe: 'לפי גודל',
    avgDurationHours: 4,
    accent: Color(0xFF3B82F6),
  ),
  CleaningTypeDef(
    id: 'store',
    nameHe: 'חנויות',
    icon: '🏬',
    descriptionHe: 'לפי גודל',
    avgDurationHours: 3,
    accent: Color(0xFF10B981),
  ),
  CleaningTypeDef(
    id: 'event',
    nameHe: 'לפני אירוע',
    icon: '🧽',
    descriptionHe: '~4 שעות',
    avgDurationHours: 4,
    accent: Color(0xFFEC4899),
  ),
];

CleaningTypeDef? findCleaningType(String id) {
  for (final t in kCleaningTypes) {
    if (t.id == id) return t;
  }
  return null;
}
