import 'package:flutter/material.dart';

import '../../../models/babysitter_profile.dart';
import '../../../models/cleaning_profile.dart';
import '../../../models/delivery_profile.dart';
import '../../../models/fitness_trainer_profile.dart';
import '../../../models/handyman_profile.dart';
import '../../../models/massage_profile.dart';
import '../../../models/motorcycle_tow_profile.dart';
import '../../../models/pest_control_profile.dart';
import '../../babysitter/babysitter_booking_block.dart';
import '../../cleaning/cleaning_booking_block.dart';
import '../../delivery/delivery_booking_block.dart';
import '../../fitness_trainer/fitness_trainer_booking_block.dart';
import '../../handyman/handyman_booking_block.dart';
import '../../massage/build_your_treatment_block.dart';
import '../../motorcycle_tow/motorcycle_tow_booking_block.dart';
import '../../pest_control/pest_booking_block.dart';

/// Eight Category-Specific Module (CSM) booking-block adapters + their
/// "has X profile" detectors.
///
/// Extracted from `expert_profile_screen.dart` in §80. Each widget is a
/// tiny adapter: it parses the relevant profile model from the user data
/// Map and renders the underlying CSM block with the right callbacks.
/// The parent screen owns the state — these widgets just route callbacks.
///
/// Why a single file (vs. 8 files):
///   • Each adapter is ~20 LOC. 8 files would be noise.
///   • The 8 detector functions naturally live alongside their builders.
///   • The shared imports (8 profile models + 8 block widgets) are
///     justified once here, not 8 times.

// ═══════════════════════════════════════════════════════════════════════════════
// Detector functions — pure logic, no widgets. Called from the main screen's
// build method to decide which adapter (if any) to render.
// ═══════════════════════════════════════════════════════════════════════════════

bool hasMassageProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isMassageCategory(serviceType)) return false;
  final mp = data['massageProfile'] as Map?;
  return mp != null && (mp['specialties'] as List?)?.isNotEmpty == true;
}

bool hasPestControlProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isPestControlCategory(serviceType)) return false;
  final pp = data['pestControlProfile'] as Map?;
  return pp != null && (pp['pestTypes'] as List?)?.isNotEmpty == true;
}

bool hasDeliveryProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isDeliveryCategory(serviceType)) return false;
  final dp = data['deliveryProfile'] as Map?;
  return dp != null && (dp['vehicles'] as List?)?.isNotEmpty == true;
}

bool hasCleaningProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isCleaningCategory(serviceType)) return false;
  final cp = data['cleaningProfile'] as Map?;
  return cp != null && ((cp['cleaningTypes'] as List?)?.isNotEmpty == true);
}

bool hasHandymanProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isHandymanCategory(serviceType)) return false;
  final hp = data['handymanProfile'] as Map?;
  if (hp == null) return false;
  final specs = hp['specialties'] as List?;
  if (specs == null || specs.isEmpty) return false;
  return specs.whereType<Map>().any((m) => m['active'] == true);
}

bool hasFitnessTrainerProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isFitnessTrainerCategory(serviceType)) return false;
  final fp = data['fitnessTrainerProfile'] as Map?;
  if (fp == null) return false;
  final specs = fp['selectedSpecialties'] as List?;
  return specs != null && specs.isNotEmpty;
}

bool hasBabysitterProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isBabysitterCategory(serviceType)) return false;
  final bp = data['babysitterProfile'] as Map?;
  return bp != null;
}

bool hasMotorcycleTowProfileFor(Map<String, dynamic> data) {
  final serviceType = (data['serviceType'] as String? ?? '').trim();
  if (!isMotorcycleTowingCategory(serviceType)) return false;
  final mp = data['motorcycleTowProfile'] as Map?;
  if (mp == null) return false;
  final ids = mp['bikeTypeIds'] as List?;
  return ids != null && ids.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CSM booking-block adapters — one per category. Each parses its profile model
// from `data` and renders the underlying block widget with the right callbacks.
// Padded by 24px bottom to match the original inline rendering.
// ═══════════════════════════════════════════════════════════════════════════════

class MassageBookingAdapter extends StatelessWidget {
  const MassageBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onPreferencesChanged,
    required this.onTotalChanged,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final ValueChanged<MassageBookingPreferences?> onPreferencesChanged;
  final ValueChanged<double> onTotalChanged;

  @override
  Widget build(BuildContext context) {
    final mp = MassageProfile.fromMap(
        Map<String, dynamic>.from(data['massageProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: BuildYourTreatmentBlock(
        massageProfile: mp,
        providerName: providerName,
        providerId: expertId,
        onPreferencesChanged: onPreferencesChanged,
        onTotalChanged: onTotalChanged,
      ),
    );
  }
}

class PestBookingAdapter extends StatelessWidget {
  const PestBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onPreferencesChanged,
    required this.onTotalChanged,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final ValueChanged<PestControlBookingPreferences?> onPreferencesChanged;
  final ValueChanged<double> onTotalChanged;

  @override
  Widget build(BuildContext context) {
    final pp = PestControlProfile.fromMap(
        Map<String, dynamic>.from(data['pestControlProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: PestBookingBlock(
        pestProfile: pp,
        providerName: providerName,
        providerId: expertId,
        onPreferencesChanged: onPreferencesChanged,
        onTotalChanged: onTotalChanged,
      ),
    );
  }
}

class DeliveryBookingAdapter extends StatelessWidget {
  const DeliveryBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onChanged,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final void Function(DeliveryBookingPreferences? prefs, double total) onChanged;

  @override
  Widget build(BuildContext context) {
    final dp = DeliveryProfile.fromMap(
        Map<String, dynamic>.from(data['deliveryProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: DeliveryBookingBlock(
        expertId: expertId,
        expertName: providerName,
        deliveryProfile: dp,
        onChanged: onChanged,
      ),
    );
  }
}

class HandymanBookingAdapter extends StatelessWidget {
  const HandymanBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onChanged,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final void Function(HandymanBookingPreferences? prefs, double total) onChanged;

  @override
  Widget build(BuildContext context) {
    final hp = HandymanProfile.fromMap(
        Map<String, dynamic>.from(data['handymanProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    final providerAvatar = data['profileImage'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: HandymanBookingBlock(
        expertId: expertId,
        expertName: providerName,
        expertAvatarUrl: providerAvatar,
        handymanProfile: hp,
        onChanged: onChanged,
      ),
    );
  }
}

class BabysitterBookingAdapter extends StatelessWidget {
  const BabysitterBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onPreferencesChanged,
    required this.onTotalChanged,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final ValueChanged<BabysitterBookingPreferences?> onPreferencesChanged;
  final ValueChanged<double> onTotalChanged;

  @override
  Widget build(BuildContext context) {
    final bp = BabysitterProfile.fromMap(
        Map<String, dynamic>.from(data['babysitterProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: BabysitterBookingBlock(
        profile: bp,
        providerName: providerName,
        providerId: expertId,
        onPreferencesChanged: onPreferencesChanged,
        onTotalChanged: onTotalChanged,
      ),
    );
  }
}

class MotorcycleTowBookingAdapter extends StatelessWidget {
  const MotorcycleTowBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onChanged,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final void Function(MotorcycleTowBookingPreferences? prefs, double total)
      onChanged;

  @override
  Widget build(BuildContext context) {
    final mp = MotorcycleTowProfile.fromMap(
        Map<String, dynamic>.from(data['motorcycleTowProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    final providerInitial =
        providerName.isNotEmpty ? providerName.characters.first : '?';
    final rating = (data['rating'] as num?)?.toDouble();
    final reviewsCount = (data['reviewsCount'] as num?)?.toInt();
    final isOnline = data['isOnline'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: MotorcycleTowBookingBlock(
        expertId: expertId,
        expertName: providerName,
        expertAvatarInitial: providerInitial,
        profile: mp,
        rating: rating,
        reviewsCount: reviewsCount,
        isOnline: isOnline,
        onChanged: onChanged,
      ),
    );
  }
}

class FitnessTrainerBookingAdapter extends StatelessWidget {
  const FitnessTrainerBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onPackageSelected,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final ValueChanged<PricingPackage> onPackageSelected;

  @override
  Widget build(BuildContext context) {
    final fp = FitnessTrainerProfile.fromMap(
        Map<String, dynamic>.from(data['fitnessTrainerProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: FitnessTrainerBookingBlock(
        profile: fp,
        trainerId: expertId,
        trainerName: providerName,
        onPackageSelected: onPackageSelected,
      ),
    );
  }
}

class CleaningBookingAdapter extends StatelessWidget {
  const CleaningBookingAdapter({
    super.key,
    required this.data,
    required this.expertId,
    required this.onChanged,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final void Function(CleaningBookingPreferences? prefs, double total) onChanged;

  @override
  Widget build(BuildContext context) {
    final cp = CleaningProfile.fromMap(
        Map<String, dynamic>.from(data['cleaningProfile'] as Map));
    final providerName = data['name'] as String? ?? '';
    final providerAvatar = data['profileImage'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: CleaningBookingBlock(
        expertId: expertId,
        expertName: providerName,
        expertAvatarUrl: providerAvatar,
        cleaningProfile: cp,
        onChanged: onChanged,
      ),
    );
  }
}
