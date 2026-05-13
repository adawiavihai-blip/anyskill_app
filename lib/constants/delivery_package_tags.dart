import 'package:flutter/material.dart';

/// Delivery CSM — package tags the client can attach to the booking.
class PackageTagDef {
  final String id;
  final String icon;
  final String titleHe;
  final Color color;

  const PackageTagDef({
    required this.id,
    required this.icon,
    required this.titleHe,
    required this.color,
  });
}

const kPackageTags = <PackageTagDef>[
  PackageTagDef(
    id: 'fragile',
    icon: '⚠️',
    titleHe: 'שביר',
    color: Color(0xFFDC2626),
  ),
  PackageTagDef(
    id: 'sensitive',
    icon: '🤐',
    titleHe: 'רגיש',
    color: Color(0xFFD97706),
  ),
  PackageTagDef(
    id: 'photo_documentation',
    icon: '📸',
    titleHe: 'לתעד',
    color: Color(0xFF1E40AF),
  ),
  PackageTagDef(
    id: 'signature_required',
    icon: '🆔',
    titleHe: 'חתימה',
    color: Color(0xFF6366F1),
  ),
];

PackageTagDef? findPackageTag(String id) {
  try {
    return kPackageTags.firstWhere((t) => t.id == id);
  } catch (_) {
    return null;
  }
}
