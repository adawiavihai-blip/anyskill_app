import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/vip_payment_model.dart';
import '../models/vip_subscription_model.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// VIP payment service — Phase 5 of Banners Studio.
///
/// All client-side flows go through here. **Phase 5 only writes via
/// the `purchaseVipWithCredits` Cloud Function** — never direct
/// Firestore writes from the client (Firestore rules block creates on
/// `vip_payments/`).
///
/// **Replacement plan (CLAUDE.md §2):** when the Israeli payment provider
/// lands (Tranzila / PayPlus / etc), this service grows a sibling
/// `purchaseVipWithCard()` method that calls a new CF
/// `purchaseVipWithCard`. The `vip_payments/` schema stays identical —
/// only `paymentMethod` flips from `'credits'` to `'visa'`/`'mc'`. The
/// admin Payments screen reads from the same collection unchanged.
/// ═══════════════════════════════════════════════════════════════════════════
class VipPaymentService {
  VipPaymentService._();
  static final VipPaymentService instance = VipPaymentService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('vip_payments');

  /// Standard tier price in credits (= ILS).
  static const int monthlyPriceCredits = 99;

  /// Hard ceiling for the [purchase] CF round-trip. Without this the spinner
  /// could hang up to the Functions client default (~70s) on flaky networks
  /// — long enough that the user assumes the app is frozen.
  static const Duration purchaseTimeout = Duration(seconds: 25);

  /// Read the caller's wallet balance ONCE, fresh from server (not cached).
  /// Used by the UI as a pre-flight check before calling [purchase] so we
  /// can surface "insufficient balance" instantly without a Functions call.
  ///
  /// Returns null if read fails — caller should treat that as "unknown,
  /// proceed to CF and let server validate".
  Future<double?> readBalance() async {
    final caller = FirebaseAuth.instance.currentUser;
    if (caller == null) return null;
    try {
      final doc = await _db
          .collection('users')
          .doc(caller.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      final raw = doc.data()?['balance'];
      if (raw is num) return raw.toDouble();
      return 0.0;
    } catch (_) {
      return null; // unknown — let the CF validate
    }
  }

  /// Buy VIP for the currently-authed provider.
  ///
  /// Calls the `purchaseVipWithCredits` Cloud Function which atomically:
  ///   1. Reads the caller's `users/{uid}.balance`
  ///   2. Confirms balance ≥ 99 (or fails with `failed-precondition`
  ///      and a Hebrew message — caller surfaces a top-up CTA)
  ///   3. Debits 99 from balance
  ///   4. Looks up active subscriptions count vs cap (30)
  ///   5. Creates a `vip_subscriptions/{id}` doc with status=active or
  ///      waitlist depending on cap
  ///   6. Creates a `vip_payments/{id}` doc with status=paid,
  ///      paymentMethod=credits
  ///   7. Returns `{subscriptionId, paymentId, status, position?}`
  ///
  /// On success, both [VipSubscriptionService] streams pick up the
  /// new subscription — the provider profile button auto-refreshes,
  /// the admin VIP screen sees the new slot, and (Phase 6) the
  /// rotation CF reconciles with the provider_carousel banner.
  Future<VipPurchaseResult> purchase() async {
    final caller = FirebaseAuth.instance.currentUser;
    if (caller == null) {
      throw const VipPaymentError(
        'not-authenticated',
        'יש להתחבר לפני רכישת VIP',
      );
    }

    // ── Pre-flight guard: existing active/waitlist subscription ───────────
    // Defensive belt-and-braces against the "user paid 99₪ and the active-sub
    // stream hasn't propagated yet → user taps VIP a second time" scenario.
    // Without this guard the second tap reaches the CF, the tx's `already-
    // exists` precondition rejects it, and the user sees a confusing dialog.
    // With this guard the user sees a friendly "you're already VIP" message
    // instantly with NO CF round-trip. Uses a single-where query (no
    // composite index needed) so it still works even if the
    // `(providerId, status)` index from firestore.indexes.json:21-28 isn't
    // deployed in this project yet.
    try {
      final existing = await _db
          .collection('vip_subscriptions')
          .where('providerId', isEqualTo: caller.uid)
          .limit(5)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      for (final doc in existing.docs) {
        final status = (doc.data()['status'] as String?) ?? '';
        if (status == 'active') {
          throw const VipPaymentError(
            'already-exists',
            'יש לך כבר מנוי VIP פעיל — הוא יחודש אוטומטית בתום החודש. אין צורך לשלם שוב.',
          );
        }
        if (status == 'waitlist') {
          throw const VipPaymentError(
            'already-exists',
            'אתה כבר ברשימת ההמתנה ל-VIP — תיכנס לקרוסלה אוטומטית כשיתפנה מקום.',
          );
        }
      }
    } on VipPaymentError {
      rethrow;
    } catch (_) {
      // Network blip / index missing / timeout → fall through to the CF
      // which has its own `already-exists` precondition inside the tx.
      // Worst case: user sees a CF-error dialog after a round-trip. Best
      // case (working network): user sees the friendly message above.
    }

    try {
      final fn = FirebaseFunctions.instance
          .httpsCallable('purchaseVipWithCredits');
      // §60: deterministic clientReqId from caller uid + day so two taps
      // within the same day return the same purchase result instead of
      // double-charging. Day-granularity is intentional — VIP is monthly
      // so a same-day retry is always the same intent.
      //
      // Audit caveat (post-§75): if a user CANCELS their subscription
      // and re-buys on the SAME day, the cached result from the original
      // purchase is returned. Currently safe because the CF's
      // `already-exists` precondition (purchaseVipWithCredits inside the
      // tx) blocks the second purchase before the cache check matters.
      // If that precondition is ever loosened, switch to a per-purchase
      // UUID so cancel-rebuy works.
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final res = await fn.call<Map<String, dynamic>>({
        'autoRenew':   true,
        'clientReqId': 'vip_${caller.uid}_$today',
      }).timeout(purchaseTimeout);
      final data = res.data;
      return VipPurchaseResult(
        subscriptionId: (data['subscriptionId'] as String?) ?? '',
        paymentId: (data['paymentId'] as String?) ?? '',
        status: VipSubscriptionStatus.fromDb(data['status'] as String?),
        waitlistPosition: (data['waitlistPosition'] as num?)?.toInt(),
        amountCharged: (data['amountCharged'] as num?)?.toInt() ?? 99,
        newBalance: (data['newBalance'] as num?)?.toInt() ?? 0,
      );
    } on TimeoutException {
      throw const VipPaymentError(
        'timeout',
        'הפעולה לוקחת יותר מדי זמן. בדוק את חיבור האינטרנט ונסה שוב.',
      );
    } on FirebaseFunctionsException catch (e) {
      // Re-throw as our domain error so the UI can show Hebrew text.
      throw VipPaymentError(
        e.code,
        _hebrewFor(e.code, e.message),
      );
    } on VipPaymentError {
      rethrow;
    } catch (e) {
      throw VipPaymentError(
        'unknown',
        'שגיאה לא צפויה. נסה שוב בעוד רגע.',
      );
    }
  }

  /// Stream all payments for one provider — used by Phase 5 provider-
  /// profile screen to show recent transactions.
  Stream<List<VipPayment>> watchForProvider(String providerId) {
    return _col
        .where('providerId', isEqualTo: providerId)
        .orderBy('paymentDate', descending: true)
        .limit(50)
        .snapshots()
        .map(_safeMap);
  }

  /// Stream all payments — admin Payments screen.
  Stream<List<VipPayment>> watchAll() {
    return _col
        .orderBy('paymentDate', descending: true)
        .limit(200)
        .snapshots()
        .map(_safeMap);
  }

  static List<VipPayment> _safeMap(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final out = <VipPayment>[];
    for (final doc in snap.docs) {
      try {
        out.add(VipPayment.fromDoc(doc));
      } catch (e) {
        // ignore: avoid_print
        print('[VipPaymentService] Skipped doc "${doc.id}": $e');
      }
    }
    return out;
  }

  static String _hebrewFor(String code, String? message) {
    switch (code) {
      case 'failed-precondition':
        if (message != null && message.contains('insufficient')) {
          return 'אין מספיק יתרה בארנק — נדרשים ₪$monthlyPriceCredits. הוסף יתרה ונסה שוב.';
        }
        return message ?? 'הפעולה לא ניתנת לביצוע כעת';
      case 'already-exists':
        return 'יש לך כבר מנוי VIP פעיל';
      case 'permission-denied':
        return 'אין הרשאה לפעולה זו';
      case 'unauthenticated':
        return 'יש להתחבר לפני רכישת VIP';
      case 'unavailable':
        return 'שירות התשלומים לא זמין כרגע. נסה שוב בעוד רגע.';
      case 'deadline-exceeded':
      case 'timeout':
        return 'הפעולה לוקחת יותר מדי זמן. בדוק את חיבור האינטרנט ונסה שוב.';
      case 'not-found':
        return 'שירות התשלום לא נמצא. ייתכן שהאפליקציה לא מעודכנת — נסה לרענן.';
      case 'internal':
        return 'שגיאה זמנית בשרת. נסה שוב בעוד רגע.';
      case 'cancelled':
        return 'הפעולה בוטלה';
      case 'resource-exhausted':
        return 'יותר מדי בקשות בזמן הקרוב. המתן רגע ונסה שוב.';
      case 'network-request-failed':
      case 'unknown':
        return 'בעיית רשת — בדוק את החיבור לאינטרנט ונסה שוב.';
      default:
        return message ?? 'שגיאה ($code) — נסה שוב או פנה לתמיכה.';
    }
  }
}

/// Result of `VipPaymentService.purchase()` — surfaced to the UI to
/// branch between "you're in the carousel" and "you're on the waitlist".
class VipPurchaseResult {
  final String subscriptionId;
  final String paymentId;
  final VipSubscriptionStatus status;
  final int? waitlistPosition;
  final int amountCharged;
  final int newBalance;

  const VipPurchaseResult({
    required this.subscriptionId,
    required this.paymentId,
    required this.status,
    required this.amountCharged,
    required this.newBalance,
    this.waitlistPosition,
  });

  bool get isActive => status == VipSubscriptionStatus.active;
  bool get isWaitlisted => status == VipSubscriptionStatus.waitlist;
}

/// Domain error thrown by [VipPaymentService.purchase].
class VipPaymentError implements Exception {
  final String code;
  final String hebrewMessage;
  const VipPaymentError(this.code, this.hebrewMessage);

  @override
  String toString() => 'VipPaymentError($code): $hebrewMessage';
}
