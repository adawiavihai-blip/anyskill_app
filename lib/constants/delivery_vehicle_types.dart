import 'package:flutter/material.dart';

/// Delivery CSM — only 2 vehicles per spec (no trucks, no fridges).
class DeliveryVehicleDef {
  final String id; // scooter | car
  final String nameHe;
  final IconData icon;
  final int defaultMaxWeightKg;
  final int avgMinutesFor5km;

  const DeliveryVehicleDef({
    required this.id,
    required this.nameHe,
    required this.icon,
    required this.defaultMaxWeightKg,
    required this.avgMinutesFor5km,
  });
}

const kDeliveryVehicles = <DeliveryVehicleDef>[
  DeliveryVehicleDef(
    id: 'scooter',
    nameHe: 'קטנוע',
    icon: Icons.two_wheeler_rounded,
    defaultMaxWeightKg: 30,
    avgMinutesFor5km: 8,
  ),
  DeliveryVehicleDef(
    id: 'car',
    nameHe: 'רכב',
    icon: Icons.directions_car_rounded,
    defaultMaxWeightKg: 60,
    avgMinutesFor5km: 15,
  ),
];

DeliveryVehicleDef? findDeliveryVehicle(String id) {
  try {
    return kDeliveryVehicles.firstWhere((v) => v.id == id);
  } catch (_) {
    return null;
  }
}
