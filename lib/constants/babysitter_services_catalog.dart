import 'package:flutter/material.dart';

class BabysitterServiceItem {
  final String id;
  final String labelHe;
  final String emoji;
  final IconData icon;

  const BabysitterServiceItem({
    required this.id,
    required this.labelHe,
    required this.emoji,
    required this.icon,
  });
}

/// What can the babysitter offer beyond pure supervision?
/// Used by provider settings (multi-select) and client booking (read-only display).
const List<BabysitterServiceItem> kBabysitterServices = [
  BabysitterServiceItem(
    id: 'feeding',
    labelHe: 'הכנת ארוחות',
    emoji: '🍽️',
    icon: Icons.restaurant_rounded,
  ),
  BabysitterServiceItem(
    id: 'bath',
    labelHe: 'אמבטיה',
    emoji: '🛁',
    icon: Icons.bathtub_rounded,
  ),
  BabysitterServiceItem(
    id: 'bedtime',
    labelHe: 'השכבה לישון',
    emoji: '🌙',
    icon: Icons.bedtime_rounded,
  ),
  BabysitterServiceItem(
    id: 'homework',
    labelHe: 'עזרה בשיעורי בית',
    emoji: '📝',
    icon: Icons.menu_book_rounded,
  ),
  BabysitterServiceItem(
    id: 'play_activities',
    labelHe: 'פעילויות יצירה ומשחק',
    emoji: '🎨',
    icon: Icons.palette_rounded,
  ),
  BabysitterServiceItem(
    id: 'outdoor',
    labelHe: 'יציאות לפארק',
    emoji: '🌳',
    icon: Icons.park_rounded,
  ),
  BabysitterServiceItem(
    id: 'pickup_school',
    labelHe: 'איסוף מבית-ספר/גן',
    emoji: '🚗',
    icon: Icons.directions_car_rounded,
  ),
  BabysitterServiceItem(
    id: 'light_housework',
    labelHe: 'סדר קל בבית',
    emoji: '🧹',
    icon: Icons.cleaning_services_rounded,
  ),
  BabysitterServiceItem(
    id: 'pet_friendly',
    labelHe: 'בית עם חיות מחמד',
    emoji: '🐶',
    icon: Icons.pets_rounded,
  ),
  BabysitterServiceItem(
    id: 'special_needs',
    labelHe: 'ילדים עם צרכים מיוחדים',
    emoji: '💙',
    icon: Icons.favorite_rounded,
  ),
];

BabysitterServiceItem? babysitterServiceById(String id) {
  for (final s in kBabysitterServices) {
    if (s.id == id) return s;
  }
  return null;
}
