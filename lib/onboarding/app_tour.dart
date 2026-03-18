import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Brand tokens ─────────────────────────────────────────────────────────────
const Color _kPurple = Color(0xFF6366F1);

// ── Client tour GlobalKeys ────────────────────────────────────────────────────
/// Search bar on the Discover screen.
final GlobalKey tourClientSearchKey      = GlobalKey();

/// Time-based suggested category chips.
final GlobalKey tourClientSuggestionsKey = GlobalKey();

/// The Inspiration Feed section.
final GlobalKey tourClientFeedKey        = GlobalKey();

// ── Provider tour GlobalKeys ─────────────────────────────────────────────────
/// Opportunities tab icon in bottom nav.
final GlobalKey tourProviderOppKey     = GlobalKey();

/// Wallet tab icon in bottom nav.
final GlobalKey tourProviderWalletKey  = GlobalKey();

/// Profile tab icon in bottom nav.
final GlobalKey tourProviderProfileKey = GlobalKey();

// ── AppTour service ───────────────────────────────────────────────────────────
class AppTour {
  AppTour._();

  static const _kPrefKey = 'tour_complete';

  /// True when the tour has NOT been completed yet.
  /// Checks local SharedPreferences first (instant, offline-safe), then
  /// falls back to Firestore so it works across devices too.
  static Future<bool> shouldShow() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    // Fast local check — survives app restarts without a network round-trip.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrefKey) == true) return false;

    // Firestore fallback — catches cross-device completions.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data() ?? {};
      if ((data['tourComplete'] as bool?) == true) {
        // Sync to local so future checks are instant.
        await prefs.setBool(_kPrefKey, true);
        return false;
      }
    } catch (_) {}

    return true;
  }

  /// Persists the tour-complete flag locally AND to Firestore.
  static Future<void> markComplete() async {
    // Local first — survives network failures, instant on next check.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefKey, true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'tourComplete': true});
    } catch (_) {}
  }

  /// Launches the 3-step client tour.
  /// [ctx] must be a BuildContext inside a [ShowCaseWidget].
  static void startClient(BuildContext ctx) {
    ShowCaseWidget.of(ctx).startShowCase([
      tourClientSearchKey,
      tourClientSuggestionsKey,
      tourClientFeedKey,
    ]);
  }

  /// Launches the 3-step provider tour.
  static void startProvider(BuildContext ctx) {
    ShowCaseWidget.of(ctx).startShowCase([
      tourProviderOppKey,
      tourProviderProfileKey,
    ]);
  }
}

// ── AnyShowcase ───────────────────────────────────────────────────────────────
/// Thin wrapper that applies the AnySkill brand style to every tour step.
///
/// Usage:
/// ```dart
/// AnyShowcase(
///   tourKey: tourClientSearchKey,
///   title: '🔍 חיפוש מומחים',
///   description: 'הקלידו שם, קטגוריה, או מיקום',
///   child: MySearchBar(),
/// )
/// ```
class AnyShowcase extends StatelessWidget {
  const AnyShowcase({
    super.key,
    required this.tourKey,
    required this.title,
    required this.description,
    required this.child,
    this.tooltipPosition = TooltipPosition.bottom,
  });

  final GlobalKey        tourKey;
  final String           title;
  final String           description;
  final Widget           child;
  final TooltipPosition  tooltipPosition;

  @override
  Widget build(BuildContext context) {
    return Showcase(
      key: tourKey,
      title: title,
      description: description,
      overlayColor: Colors.black,
      overlayOpacity: 0.72,
      tooltipBackgroundColor: _kPurple,
      textColor: Colors.white,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      descTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        height: 1.5,
      ),
      tooltipPosition: tooltipPosition,
      movingAnimationDuration: const Duration(milliseconds: 400),
      child: child,
    );
  }
}
