/// AnySkill — Category-specific tag catalog entry.
///
/// Stored in `category_tags/{categoryName}.tags: [CategoryTag...]`.
/// Providers pick up to 5 tag IDs into `users/{uid}.categoryTags`.
/// This is ADDITIVE to the existing `quickTags` (max 3) — together they
/// give the provider up to 8 differentiators on their card.
library;

import 'package:flutter/material.dart';

class CategoryTag {
  final String id;
  final String label;
  final String iconName;

  const CategoryTag({
    required this.id,
    required this.label,
    required this.iconName,
  });

  factory CategoryTag.fromMap(Map<String, dynamic> m) => CategoryTag(
        id: m['id'] as String,
        label: m['label'] as String,
        iconName: (m['icon'] as String?) ?? 'label',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'icon': iconName,
      };

  IconData get icon => _iconFor(iconName);
}

/// Manual mapping from Material icon NAMES (as stored in Firestore) to
/// `IconData` instances. Needed because Flutter tree-shakes icons unless
/// referenced statically. Every name used across the seeded catalogs
/// MUST be listed here — unknown names fall back to [Icons.label].
IconData _iconFor(String name) {
  switch (name) {
    // general / shared
    case 'label':
      return Icons.label_rounded;
    case 'local_offer':
      return Icons.local_offer_rounded;
    case 'home':
      return Icons.home_rounded;
    case 'today':
      return Icons.today_rounded;
    case 'flash_on':
      return Icons.flash_on_rounded;
    case 'bolt':
      return Icons.bolt_rounded;
    case 'shield':
      return Icons.shield_rounded;
    case 'security':
      return Icons.security_rounded;
    case 'verified':
      return Icons.verified_rounded;
    case 'verified_user':
      return Icons.verified_user_rounded;
    case 'badge':
      return Icons.badge_rounded;
    case 'store':
      return Icons.store_rounded;
    case 'thumb_up':
      return Icons.thumb_up_rounded;
    case 'groups':
      return Icons.groups_rounded;
    case 'translate':
      return Icons.translate_rounded;
    case 'school':
      return Icons.school_rounded;
    case 'child_care':
      return Icons.child_care_rounded;
    case 'pets':
      return Icons.pets_rounded;
    case 'eco':
      return Icons.eco_rounded;
    case 'favorite':
      return Icons.favorite_rounded;
    case 'calendar_today':
      return Icons.calendar_today_rounded;
    case 'inventory':
      return Icons.inventory_2_rounded;
    case 'construction':
      return Icons.construction_rounded;
    case 'emergency':
      return Icons.emergency_rounded;
    case 'hardware':
      return Icons.hardware_rounded;
    case 'apartment':
      return Icons.apartment_rounded;
    case 'water_damage':
      return Icons.water_damage_rounded;
    case 'request_quote':
      return Icons.request_quote_rounded;
    case 'healing':
      return Icons.healing_rounded;
    case 'elderly':
      return Icons.elderly_rounded;
    case 'park':
      return Icons.park_rounded;
    case 'people':
      return Icons.people_rounded;
    case 'pregnant_woman':
      return Icons.pregnant_woman_rounded;
    case 'fitness_center':
      return Icons.fitness_center_rounded;
    case 'workspace_premium':
      return Icons.workspace_premium_rounded;
    case 'military_tech':
      return Icons.military_tech_rounded;
    case 'celebration':
      return Icons.celebration_rounded;
    case 'business':
      return Icons.business_rounded;
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'no_food':
      return Icons.no_food_rounded;
    case 'cleaning_services':
      return Icons.cleaning_services_rounded;
    case 'health_and_safety':
      return Icons.health_and_safety_rounded;
    case 'villa':
      return Icons.villa_rounded;
    case 'group_work':
      return Icons.group_work_rounded;
    case 'record_voice_over':
      return Icons.record_voice_over_rounded;
    case 'psychology':
      return Icons.psychology_rounded;
    case 'accessibility':
      return Icons.accessibility_rounded;
    case 'menu_book':
      return Icons.menu_book_rounded;
    case 'redeem':
      return Icons.redeem_rounded;
    case 'videocam':
      return Icons.videocam_rounded;
    // graphic-design custom tags
    case 'palette':
      return Icons.palette_rounded;
    case 'draw':
      return Icons.draw_rounded;
    case 'design_services':
      return Icons.design_services_rounded;
    case 'branding_watermark':
      return Icons.branding_watermark_rounded;
    case 'share':
      return Icons.share_rounded;
    case 'print':
      return Icons.print_rounded;
    case 'inventory_2':
      return Icons.inventory_2_outlined;
    case 'star':
      return Icons.star_rounded;
    default:
      return Icons.label_rounded;
  }
}
