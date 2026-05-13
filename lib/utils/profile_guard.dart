import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/edit_profile_screen.dart';

/// Profile-completeness gate.
///
/// Before any service-booking action (Pay & Secure on a provider profile,
/// Flash Auction order, AnyTask publish, etc.) the customer MUST have a
/// fully populated profile:
///
///   • Full name (≥ 2 chars)
///   • Phone — `phone` non-empty. The phone may come from the OTP-link
///     flow (`phoneVerifiedAt` set) OR from an admin manually entering
///     it in the admin user-detail screen (§15a). Both count — once a
///     phone sits on the profile we trust it. The OTP-verified timestamp
///     is still preferred for new signups (post-§21 onboarding flow),
///     but legacy + admin-assisted accounts pass this gate without it.
///   • Email
///   • Profile photo
///
/// If any field is missing, [ensureComplete] shows a Hebrew dialog
/// listing the gaps and offers to open Edit Profile. Returns `true` only
/// when the profile passes — the caller can then proceed with the order.
class ProfileCompleteness {
  final bool isComplete;
  final List<String> missingHebrewLabels;

  const ProfileCompleteness({
    required this.isComplete,
    required this.missingHebrewLabels,
  });

  static ProfileCompleteness check(Map<String, dynamic> userData) {
    final missing = <String>[];

    final name = (userData['name'] as String? ?? '').trim();
    if (name.length < 2) {
      missing.add('שם מלא');
    }

    // Trust any phone on the profile — OTP-verified OR admin-set
    // (the admin user-detail screen §15a writes `phone` directly).
    // Don't require `phoneVerifiedAt` here; that's a strict signup-flow
    // signal, not a hard precondition for booking.
    final phone = (userData['phone'] as String? ?? '').trim();
    if (phone.isEmpty) {
      missing.add('מספר טלפון');
    }

    final email = (userData['email'] as String? ?? '').trim();
    if (email.isEmpty || !email.contains('@')) {
      missing.add('כתובת אימייל');
    }

    final image = (userData['profileImage'] as String? ?? '').trim();
    if (image.isEmpty) {
      missing.add('תמונת פרופיל');
    }

    return ProfileCompleteness(
      isComplete: missing.isEmpty,
      missingHebrewLabels: missing,
    );
  }
}

class ProfileGuard {
  /// Reads `users/{uid}` and runs [check]. Returns `true` if the profile is
  /// complete OR the user accepts our blocking dialog and we let them
  /// proceed (we never let them — the dialog only offers "השלם פרופיל" or
  /// "ביטול"). Always returns `false` when blocking.
  ///
  /// Usage:
  /// ```dart
  /// if (!await ProfileGuard.ensureComplete(context)) return;
  /// // proceed with the order...
  /// ```
  static Future<bool> ensureComplete(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false; // not signed in — let caller handle.

    Map<String, dynamic> data;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      data = snap.data() ?? const {};
    } catch (e) {
      // On read failure, fail-open — don't block the order on a flaky
      // network read. The booking write will hit its own rules and any
      // missing fields surface there.
      return true;
    }

    final result = ProfileCompleteness.check(data);
    if (result.isComplete) return true;

    if (!context.mounted) return false;
    await _showBlockingDialog(context, result, data);
    return false; // caller does NOT proceed; user must complete & retry.
  }

  static Future<void> _showBlockingDialog(
    BuildContext context,
    ProfileCompleteness result,
    Map<String, dynamic> userData,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: const [
                Icon(Icons.account_circle_rounded,
                    color: Color(0xFF6366F1), size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'השלם את הפרופיל שלך',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'כדי להזמין שירות יש צורך להשלים את כל פרטי הפרופיל:',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 12),
                ...result.missingHebrewLabels.map(
                  (label) => Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.cancel_rounded,
                            size: 18, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: Color(0xFF6366F1)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'מספר הטלפון יאומת בקוד SMS ולאחר השמירה לא ניתן יהיה לשנות אותו.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF1A1A2E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'ביטול',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(userData: userData),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                child: const Text(
                  'השלם פרופיל',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
