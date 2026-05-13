import 'package:flutter/material.dart';

/// Delivery CSM — the 6 package types a courier can offer.
class DeliveryTypeDef {
  final String id;
  final String nameHe;
  final String shortHe;
  final String weightSpec;
  final IconData icon;
  final bool isOptional;

  const DeliveryTypeDef({
    required this.id,
    required this.nameHe,
    required this.shortHe,
    required this.weightSpec,
    required this.icon,
    this.isOptional = false,
  });
}

const kDeliveryTypes = <DeliveryTypeDef>[
  DeliveryTypeDef(
    id: 'documents',
    nameHe: 'מסמכים',
    shortHe: 'מסמכים',
    weightSpec: 'עד 1 ק"ג',
    icon: Icons.description_rounded,
  ),
  DeliveryTypeDef(
    id: 'small_package',
    nameHe: 'חבילה קטנה',
    shortHe: 'קטנה',
    weightSpec: 'עד 5 ק"ג',
    icon: Icons.inventory_2_outlined,
  ),
  DeliveryTypeDef(
    id: 'medium_package',
    nameHe: 'חבילה בינונית',
    shortHe: 'בינונית',
    weightSpec: '5-15 ק"ג',
    icon: Icons.markunread_mailbox_rounded,
  ),
  DeliveryTypeDef(
    id: 'large_package',
    nameHe: 'חבילה גדולה',
    shortHe: 'גדולה',
    weightSpec: '15-30 ק"ג',
    icon: Icons.card_giftcard_rounded,
  ),
  DeliveryTypeDef(
    id: 'flowers',
    nameHe: 'פרחים',
    shortHe: 'פרחים',
    weightSpec: 'עד 3 ק"ג',
    icon: Icons.local_florist_rounded,
    isOptional: true,
  ),
  DeliveryTypeDef(
    id: 'cakes',
    nameHe: 'עוגות',
    shortHe: 'עוגות',
    weightSpec: 'עד 5 ק"ג',
    icon: Icons.cake_rounded,
    isOptional: true,
  ),
];

DeliveryTypeDef? findDeliveryType(String id) {
  try {
    return kDeliveryTypes.firstWhere((d) => d.id == id);
  } catch (_) {
    return null;
  }
}
