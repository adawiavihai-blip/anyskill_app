import 'package:flutter/material.dart';

class BabysitterAgeGroup {
  final String id;
  final String labelHe;
  final String emoji;
  final String hint;
  final Color color;

  const BabysitterAgeGroup({
    required this.id,
    required this.labelHe,
    required this.emoji,
    required this.hint,
    required this.color,
  });
}

/// 5 age buckets — used by both provider settings (which I cover) and client
/// booking (how old are your children).
const List<BabysitterAgeGroup> kBabysitterAgeGroups = [
  BabysitterAgeGroup(
    id: 'infant',
    labelHe: 'תינוקות',
    emoji: '👶',
    hint: '0-12 חודשים',
    color: Color(0xFFEC4899),
  ),
  BabysitterAgeGroup(
    id: 'toddler',
    labelHe: 'פעוטות',
    emoji: '🧒',
    hint: '1-3 שנים',
    color: Color(0xFFF59E0B),
  ),
  BabysitterAgeGroup(
    id: 'preschool',
    labelHe: 'גיל גן',
    emoji: '🎨',
    hint: '3-6 שנים',
    color: Color(0xFF10B981),
  ),
  BabysitterAgeGroup(
    id: 'school_age',
    labelHe: 'גיל בית-ספר',
    emoji: '📚',
    hint: '6-12 שנים',
    color: Color(0xFF6366F1),
  ),
  BabysitterAgeGroup(
    id: 'teen',
    labelHe: 'נוער',
    emoji: '👩‍🎓',
    hint: '12+',
    color: Color(0xFF8B5CF6),
  ),
];

BabysitterAgeGroup? babysitterAgeGroupById(String id) {
  for (final g in kBabysitterAgeGroups) {
    if (g.id == id) return g;
  }
  return null;
}
