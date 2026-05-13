// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../models/vip_subscription_model.dart';
import '../../../services/vip_payment_service.dart';
import '../../../services/vip_subscription_service.dart';
import 'design_tokens.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Provider-facing VIP upgrade card. 3 states based on the provider's
/// own `vip_subscriptions/` doc:
///
///   ▸ NO subscription          → "הצטרף ל-VIP · ₪99/חודש" gold CTA
///   ▸ status: 'active'         → green status card with days-left +
///                                 auto-renew toggle + cancel button
///   ▸ status: 'waitlist'       → indigo status card with position +
///                                 ETA + cancel button
///
/// Pulls all state from a single per-provider stream of
/// `vip_subscriptions where providerId==uid AND status in [active,
/// waitlist]`. Uses [VipPaymentService.purchase] for the buy flow.
///
/// **Mount point (Phase 5.8):** in the provider's own profile screen.
/// Visible only to the logged-in provider when viewing themselves.
/// Other users (customers, other providers) never see this widget.
/// ═══════════════════════════════════════════════════════════════════════════

class VipUpgradeButton extends StatefulWidget {
  const VipUpgradeButton({super.key});

  @override
  State<VipUpgradeButton> createState() => _VipUpgradeButtonState();
}

class _VipUpgradeButtonState extends State<VipUpgradeButton> {
  bool _purchasing = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<VipSubscription?> _watchActiveSub() {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return FirebaseFirestore.instance
        .collection('vip_subscriptions')
        .where('providerId', isEqualTo: uid)
        .where('status', whereIn: const ['active', 'waitlist'])
        .limit(1)
        .snapshots()
        .map<VipSubscription?>((snap) {
      if (snap.docs.isEmpty) return null;
      try {
        return VipSubscription.fromDoc(snap.docs.first);
      } catch (_) {
        return null;
      }
    }).handleError((Object e) {
      // Missing composite index OR transient permission error. Don't
      // crash the widget tree — log + fall through to "Not VIP" card.
      // The pre-flight balance check + CF will still work for purchase.
      // ignore: avoid_print
      print('[VipUpgradeButton] subscription stream error (treated as no sub): $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return const SizedBox.shrink();

    return StreamBuilder<VipSubscription?>(
      stream: _watchActiveSub(),
      builder: (context, snap) {
        // Loading guard — during the initial waiting window (cold start /
        // missing composite index / transient permission blip), `snap.data`
        // is null and the StreamBuilder is still in `waiting`. Without this
        // guard the button renders the active gold CTA, which lets the user
        // tap purchase BEFORE we know whether they already have a sub. That
        // was the root cause of the "I tapped twice and got charged again"
        // report (CLAUDE.md §51 follow-up). Render a disabled clone of the
        // CTA so the user sees the button is there but can't tap it yet.
        final isWaiting =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        if (isWaiting) {
          return _NotVipCard(
            purchasing: true, // shows spinner + onPressed gets nulled out
            onPurchase: () {}, // never called because purchasing=true blocks
          );
        }
        final sub = snap.data;
        if (sub == null) {
          return _NotVipCard(
            purchasing: _purchasing,
            onPurchase: _onPurchase,
          );
        }
        if (sub.status == VipSubscriptionStatus.active) {
          return _ActiveVipCard(subscription: sub);
        }
        if (sub.status == VipSubscriptionStatus.waitlist) {
          return _WaitlistCard(subscription: sub);
        }
        return _NotVipCard(
          purchasing: _purchasing,
          onPurchase: _onPurchase,
        );
      },
    );
  }

  Future<void> _onPurchase() async {
    // ── Step 1: Pre-flight wallet balance check ───────────────────────────
    // Read the user's `balance` BEFORE showing the confirm dialog so we can
    // surface "insufficient balance" instantly without a Cloud Function
    // round-trip. Failing this read (network blip) returns null → fall
    // through to the CF and let the server validate (idempotent + atomic).
    setState(() => _purchasing = true);
    final balance = await VipPaymentService.instance.readBalance();
    if (!mounted) return;
    setState(() => _purchasing = false);

    if (balance != null &&
        balance < VipPaymentService.monthlyPriceCredits) {
      await _showInsufficientBalanceDialog(balance);
      return;
    }

    // ── Step 2: Confirm intent ────────────────────────────────────────────
    // Same nested-vs-root navigator issue as the 3 dialogs below — capture
    // the dialog's own context (dialogCtx) so Navigator.pop closes the
    // dialog (root navigator) rather than the page underneath (nested).
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('הצטרפות ל-VIP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ייחויבו ₪${VipPaymentService.monthlyPriceCredits} מהיתרה הפנימית שלך.',
              textDirection: TextDirection.rtl,
            ),
            if (balance != null) ...[
              const SizedBox(height: 6),
              Text(
                'יתרה נוכחית: ₪${balance.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 12, color: StudioColors.ink3),
                textDirection: TextDirection.rtl,
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'אם הקרוסלה מלאה — תיכנס לרשימת המתנה ותכנס אוטומטית כשיתפנה מקום. החיוב מתבצע מיידית.',
              style: TextStyle(fontSize: 12),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('בטל'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StudioColors.goldDeep,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
                'אישור · ₪${VipPaymentService.monthlyPriceCredits}'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    // ── Step 3: Call CF (timeout-guarded via VipPaymentService) ──────────
    setState(() => _purchasing = true);
    try {
      final res = await VipPaymentService.instance.purchase();
      if (!mounted) return;
      await _showSuccessDialog(res);
    } on VipPaymentError catch (e) {
      if (!mounted) return;
      // Edge case: balance dropped between pre-check and CF call. Show
      // the friendly insufficient-balance dialog (not a fleeting snackbar)
      // so the user knows exactly what to do.
      if (e.code == 'failed-precondition' &&
          e.hebrewMessage.contains('יתרה')) {
        final freshBalance = await VipPaymentService.instance.readBalance();
        if (!mounted) return;
        await _showInsufficientBalanceDialog(freshBalance ?? 0);
      } else {
        await _showErrorDialog(e.hebrewMessage);
      }
    } catch (_) {
      if (!mounted) return;
      await _showErrorDialog(
          'שגיאה לא צפויה. נסה שוב בעוד רגע או פנה לתמיכה.');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _showInsufficientBalanceDialog(double balance) async {
    final shortfall =
        VipPaymentService.monthlyPriceCredits - balance;
    // CRITICAL: capture the dialog's own context via the builder param
    // (`dialogCtx`). `showDialog` pushes onto the ROOT navigator by
    // default, but the widget-level `context` resolves to the NESTED
    // HomeScreen navigator. Popping with the wrong context closes the
    // page underneath the dialog instead of the dialog itself — that's
    // why "הבנתי" was leaving users staring at a frozen-looking screen.
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('אין מספיק יתרה'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'יתרה נוכחית בארנק: ₪${balance.toStringAsFixed(0)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 4),
            Text(
              'נדרשים ₪${VipPaymentService.monthlyPriceCredits} לרכישת מנוי VIP',
              textDirection: TextDirection.rtl,
            ),
            if (shortfall > 0) ...[
              const SizedBox(height: 4),
              Text(
                'חסר: ₪${shortfall.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: StudioColors.danger,
                    fontWeight: FontWeight.w600),
                textDirection: TextDirection.rtl,
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'הוסף יתרה דרך תפריט "הכספים שלי" וחזור לכאן.',
              style: TextStyle(fontSize: 12, color: StudioColors.ink3),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('הבנתי'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSuccessDialog(VipPurchaseResult res) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(res.isActive ? '🎉 ברוכים הבאים ל-VIP!' : '⏳ ברשימת המתנה'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              res.isActive
                  ? 'המנוי שלך פעיל. הופעת בקרוסלה היוקרתית בלשונית הבית.'
                  : 'נכנסת לרשימת המתנה במקום #${res.waitlistPosition}. תיכנס לקרוסלה אוטומטית ברגע שיתפנה מקום.',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: StudioColors.bgSubtle,
                borderRadius: BorderRadius.circular(StudioRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'חויב: ₪${res.amountCharged}',
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'יתרה לאחר חיוב: ₪${res.newBalance}',
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                        fontSize: 12, color: StudioColors.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StudioColors.gold,
              foregroundColor: const Color(0xFF1A1A1A),
            ),
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('יופי!'),
          ),
        ],
      ),
    );
  }

  Future<void> _showErrorDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('הפעולה נכשלה'),
        content: Text(message, textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATE 1: NOT VIP — gold CTA
// ═══════════════════════════════════════════════════════════════════════════

class _NotVipCard extends StatelessWidget {
  const _NotVipCard({required this.purchasing, required this.onPurchase});
  final bool purchasing;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1F1B14), Color(0xFF2A2317), Color(0xFF1A1A1A)],
        ),
        borderRadius: BorderRadius.circular(StudioRadius.lg),
        boxShadow: [
          BoxShadow(
            color: StudioColors.gold.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(StudioSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: StudioColors.goldGradient,
                  borderRadius: BorderRadius.circular(StudioRadius.md),
                ),
                child: const Text('⭐',
                    style: TextStyle(fontSize: 22, color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'הצטרף ל-VIP',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: StudioColors.gold,
                        height: 1.1,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'הופע בקרוסלת נותני השירות בלשונית הבית',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Bullet benefits
          _Bullet(text: 'חשיפה למאות לקוחות מדי יום'),
          _Bullet(text: 'מקום מובטח בקרוסלה היוקרתית'),
          _Bullet(text: 'תג ⭐ זהב על הפרופיל'),
          const SizedBox(height: 14),
          // Price + CTA
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₪${VipPaymentService.monthlyPriceCredits}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: StudioColors.gold,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'לחודש · מהיתרה הפנימית',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: purchasing ? null : onPurchase,
                style: FilledButton.styleFrom(
                  backgroundColor: StudioColors.gold,
                  foregroundColor: const Color(0xFF1A1A1A),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(StudioRadius.sm)),
                ),
                child: purchasing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Color(0xFF1A1A1A)),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'הצטרף עכשיו',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 14, color: StudioColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATE 2: ACTIVE VIP — green status card
// ═══════════════════════════════════════════════════════════════════════════

class _ActiveVipCard extends StatefulWidget {
  const _ActiveVipCard({required this.subscription});
  final VipSubscription subscription;

  @override
  State<_ActiveVipCard> createState() => _ActiveVipCardState();
}

class _ActiveVipCardState extends State<_ActiveVipCard> {
  bool _toggling = false;

  Future<void> _toggleAutoRenew(bool next) async {
    setState(() => _toggling = true);
    try {
      await VipSubscriptionService.instance
          .setAutoRenew(widget.subscription.id, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next
              ? '↻ חידוש אוטומטי הופעל'
              : '⚠️ חידוש אוטומטי כבוי — תצטרך לחדש ידנית'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e')),
      );
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subscription;
    final daysLeft = s.daysRemaining ?? 0;
    final urgent = daysLeft > 0 && daysLeft <= 3;

    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFAF6EB), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: StudioColors.gold, width: 1.5),
        borderRadius: BorderRadius.circular(StudioRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: StudioColors.goldGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_rounded,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '⭐ חבר VIP פעיל',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: StudioColors.goldDeep,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.endDate == null
                          ? 'מנוי קבוע · ללא פג תוקף'
                          : urgent
                              ? '⚠️ נותרו $daysLeft ימים'
                              : 'נותרו $daysLeft ימים · עד ${_dmy(s.endDate!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: urgent
                            ? StudioColors.warn
                            : StudioColors.ink3,
                        fontWeight: urgent
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Auto-renew toggle (only for paid)
          if (s.type == VipSubscriptionType.paid) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: StudioColors.line2),
                borderRadius: BorderRadius.circular(StudioRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'חידוש אוטומטי',
                          style: StudioText.bodyMedium(
                              color: StudioColors.ink),
                          textDirection: TextDirection.rtl,
                        ),
                        Text(
                          s.autoRenew
                              ? 'יחויב ₪${s.pricePerMonth} בחודש הבא מהיתרה הפנימית'
                              : 'לא יחויב — המנוי יפוג בסוף התקופה',
                          style: StudioText.captionSm(),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  if (_toggling)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Switch(
                      value: s.autoRenew,
                      onChanged: _toggleAutoRenew,
                      activeColor: Colors.white,
                      activeTrackColor: StudioColors.gold,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Compatibility info if admin-comp
          if (s.type == VipSubscriptionType.adminComp) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: StudioColors.bgSubtle,
                borderRadius: BorderRadius.circular(StudioRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded,
                      size: 14, color: StudioColors.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'מענק מנהל · לא יחויב חידוש אוטומטי',
                      style: StudioText.captionSm(),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Stats
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'חשיפות',
                  value: s.totalImpressions == 0
                      ? '—'
                      : _compact(s.totalImpressions),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'הקלקות',
                  value: s.totalClicks == 0
                      ? '—'
                      : _compact(s.totalClicks),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'CTR',
                  value: s.totalImpressions == 0
                      ? '—'
                      : '${s.ctr.toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _dmy(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: StudioText.overline(),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: StudioText.metricMd(color: StudioColors.goldDeep),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATE 3: WAITLIST — info card
// ═══════════════════════════════════════════════════════════════════════════

class _WaitlistCard extends StatelessWidget {
  const _WaitlistCard({required this.subscription});
  final VipSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final pos = subscription.waitlistPosition;
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s6),
      decoration: BoxDecoration(
        color: StudioColors.infoBg,
        border: Border.all(color: StudioColors.info.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(StudioRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: StudioColors.info,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '⏳ ברשימת המתנה ל-VIP',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: StudioColors.info,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  pos != null
                      ? 'מקום מספר $pos · תיכנס לקרוסלה אוטומטית כשיתפנה מקום'
                      : 'תיכנס לקרוסלה כשיתפנה מקום',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: StudioColors.ink2,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  '✓ התשלום בוצע · המקום שמור',
                  style: TextStyle(
                    fontSize: 11,
                    color: StudioColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
