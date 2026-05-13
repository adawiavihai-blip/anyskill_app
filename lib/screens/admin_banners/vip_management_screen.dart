// ignore_for_file: use_build_context_synchronously
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../models/vip_subscription_model.dart';
import '../../services/vip_subscription_service.dart';
import '../../widgets/banners_admin/v3/add_vip_modal.dart';
import '../../widgets/banners_admin/v3/capacity_ring.dart';
import 'vip_payments_screen.dart';
import '../../widgets/banners_admin/v3/design_tokens.dart';
import '../../widgets/banners_admin/v3/vip_slot_card.dart';
import '../../widgets/banners_admin/v3/waitlist_card.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Banners Studio — Screen C (VIP Management).
///
/// Per `docs/ui-specs/Baner/banners-mockup-v3.html` Screen C:
///   - VIP Hero: dark gradient + 3 stats (revenue, paying, waitlist) +
///     capacity ring (160px gold)
///   - Capacity Bar: paying gold + admin-comp black + free grey
///   - Filter tabs: הכל / משלמים / חינם / פג בקרוב + "הוסף ספק חינם" CTA
///   - Slot grid: paying first → admin-comp → 1 empty slot
///   - Waitlist card at the bottom (empty state until Phase 5)
///
/// **Phase 3 surface:**
///   - Admin can grant admin-comp VIPs end-to-end (modal → service →
///     audit log → live grid).
///   - Paying VIPs render correctly when present (none until Phase 5).
///   - Revoke any active VIP via the slot card's "הסר" button.
///   - Tabs + filter all live-driven.
///   - Waitlist card surfaces — empty state explains Phase 5 dependency.
///
/// **Sync note (CLAUDE.md §49 + Phase 5):** the customer-facing rail is
/// still driven by `banners/{id}.providerCarousel.providerIds`, NOT by
/// `vip_subscriptions/`. Phase 5's `purchaseVipWithCredits` CF reconciles
/// them. Until then, this screen and the Studio dashboard are the
/// admin-side ground truth, but the home tab keeps reading the banner.
///
/// We surface this to the admin with an info banner at the top of the
/// hero — full transparency.
/// ═══════════════════════════════════════════════════════════════════════════

class VipManagementScreen extends StatefulWidget {
  const VipManagementScreen({super.key});

  @override
  State<VipManagementScreen> createState() => _VipManagementScreenState();
}

enum _Tab { all, paying, adminComp, expiringSoon }

extension on _Tab {
  String get label => switch (this) {
        _Tab.all => 'הכל',
        _Tab.paying => 'משלמים',
        _Tab.adminComp => 'חינם · מנהל',
        _Tab.expiringSoon => 'פג בקרוב',
      };
}

class _VipManagementScreenState extends State<VipManagementScreen> {
  _Tab _tab = _Tab.all;
  bool _isSyncing = false;

  /// Calls `forceSyncVipCarousel` CF. Used after a stale state (e.g. a
  /// legacy `activateVipSubscription` payment that never wrote to
  /// `vip_subscriptions/`, or a missed trigger fire) so the admin can
  /// fix the carousel without redeploying anything.
  Future<void> _onForceSync() async {
    setState(() => _isSyncing = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('forceSyncVipCarousel')
          .call();
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      final action = (data['action'] as String?) ?? 'unknown';
      final count = (data['providerCount'] as num?)?.toInt() ?? 0;
      final written = (data['bannersWritten'] as num?)?.toInt();
      if (!mounted) return;
      final label = switch (action) {
        'no-op' => 'אין מנויים פעילים לסנכרון',
        'created' => '✅ באנר VIP נוצר עם $count נותני שירות',
        'already-synced' => '✅ הקרוסלה כבר מסונכרנת ($count)',
        'updated' => '✅ עודכנו $count נותני שירות'
            '${written != null ? ' ב-$written באנרים' : ''}',
        _ => '✅ סנכרון הסתיים',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('שגיאה בסנכרון: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioColors.bg,
      appBar: AppBar(
        backgroundColor: StudioColors.bgElevated,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: StudioColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('ניהול VIP',
            style: StudioText.h3(), textDirection: TextDirection.rtl),
        actions: [
          // ── "סנכרן עכשיו" — restored after a real production incident ──
          //
          // Auto-sync runs in two layers (inline in `purchaseVipWithCredits`
          // + the `syncVipCarouselOnSubscriptionChange` trigger), but a
          // production case where a provider paid via the LEGACY
          // `activateVipSubscription` CF (now disabled) left him with
          // `isPromoted: true` but no `vip_subscriptions/` doc → never
          // appeared in the carousel until an admin clicked sync.
          // _runVipCarouselSync now merges legacy + new-system, but
          // the manual button stays as the operator's emergency lever.
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton.icon(
              onPressed: _isSyncing ? null : _onForceSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('סנכרן עכשיו'),
              style: TextButton.styleFrom(
                foregroundColor: StudioColors.goldDeep,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VipPaymentsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.payments_outlined, size: 16),
              label: const Text('תשלומים'),
              style: TextButton.styleFrom(
                foregroundColor: StudioColors.ink2,
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<VipSubscription>>(
        stream: VipSubscriptionService.instance.watchActive(),
        builder: (context, activeSnap) {
          if (activeSnap.hasError) {
            return _ErrorState(error: activeSnap.error.toString());
          }
          final active = activeSnap.data ?? const <VipSubscription>[];

          return StreamBuilder<List<VipSubscription>>(
            stream: VipSubscriptionService.instance.watchWaitlist(),
            builder: (context, waitSnap) {
              final waitlist =
                  waitSnap.data ?? const <VipSubscription>[];
              return _buildBody(context, active, waitlist);
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<VipSubscription> active,
      List<VipSubscription> waitlist) {
    final paying = active
        .where((s) => s.type == VipSubscriptionType.paid)
        .toList();
    final adminComp = active
        .where((s) => s.type == VipSubscriptionType.adminComp)
        .toList();
    final expiringSoon = active.where((s) {
      final left = s.daysRemaining;
      return left != null && left <= 3;
    }).toList();

    final filtered = switch (_tab) {
      _Tab.all => active,
      _Tab.paying => paying,
      _Tab.adminComp => adminComp,
      _Tab.expiringSoon => expiringSoon,
    };

    final monthlyRevenue =
        paying.fold<int>(0, (a, s) => a + s.pricePerMonth);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: StudioSpacing.s7,
        vertical: StudioSpacing.s6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VipHero(
                paying: paying.length,
                adminComp: adminComp.length,
                waitlist: waitlist.length,
                monthlyRevenue: monthlyRevenue,
              ),
              const SizedBox(height: StudioSpacing.s5),

              StudioCapacityBar(
                paying: paying.length,
                adminComp: adminComp.length,
                max: VipSubscriptionService.maxSlots,
              ),
              const SizedBox(height: StudioSpacing.s7),

              // Tabs + Add button
              Row(
                children: [
                  _TabsBar(
                    selected: _tab,
                    counts: {
                      _Tab.all: active.length,
                      _Tab.paying: paying.length,
                      _Tab.adminComp: adminComp.length,
                      _Tab.expiringSoon: expiringSoon.length,
                    },
                    onChange: (t) => setState(() => _tab = t),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _onAddVip(active),
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('הוסף ספק חינם'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioColors.goldDeep,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(StudioRadius.sm)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: StudioSpacing.s5),

              // Slot grid
              if (filtered.isEmpty && _tab != _Tab.all)
                _EmptyTabState(tab: _tab)
              else
                _SlotGrid(
                  paying: paying,
                  adminComp: adminComp,
                  filtered: filtered,
                  onAdd: () => _onAddVip(active),
                  onDetails: _onDetails,
                  onEdit: _onEdit,
                  onRemove: _onRevoke,
                ),

              const SizedBox(height: StudioSpacing.s8),

              // Waitlist
              StudioWaitlistCard(
                entries: waitlist,
                onPromote: _onPromote,
              ),

              const SizedBox(height: StudioSpacing.s8),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Action handlers ────────────────────────────────────────────────────

  Future<void> _onAddVip(List<VipSubscription> active) async {
    final ids = active.map((s) => s.providerId).toSet();
    await showStudioAddVipModal(context, alreadyActiveProviderIds: ids);
  }

  // `_onForceSync` removed — sync is now fully automatic (see actions[]
  // comment in the AppBar build). The `forceSyncVipCarousel` Cloud
  // Function stays deployed as an emergency operator tool callable via
  // `firebase functions:shell`, but no longer has a UI entry point.

  void _onDetails(VipSubscription s) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('מסך פרטי VIP מורחב — יבנה בפאזה 5'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _onEdit(VipSubscription s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.type == VipSubscriptionType.adminComp
            ? 'עריכת מענק (משך, סיבה) — יבנה בפאזה 6'
            : 'עריכת מנוי משלם — תפתח בפאזה 5'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onRevoke(VipSubscription s) async {
    // ignore: avoid_print
    print('[Revoke] called for subscription ${s.id} (${s.type.dbValue})');
    final reasonCtrl = TextEditingController(
      // Pre-fill with a sensible default so the admin can just hit
      // "הסר" without typing if they have no specific reason. Was the
      // root cause of the "nothing happens" report — the validation
      // snackbar was hidden behind the dialog.
      text: s.type == VipSubscriptionType.adminComp
          ? 'הוסר ע״י המנהל'
          : 'הוסר ע״י המנהל · ביטול מנוי משלם',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final reasonOk = reasonCtrl.text.trim().length >= 5;
            return AlertDialog(
              title: const Text('הסרת VIP'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.type == VipSubscriptionType.adminComp
                          ? 'הספק יוסר מקרוסלת ה-VIP מיידית. הפעולה תיכתב ביומן הביקורת.'
                          : 'הסרה תפסיק את המנוי המשלם. ייתכן שיהיו השלכות על תהליך החיוב — יש לוודא טרם הסרה.',
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      autofocus: false,
                      textDirection: TextDirection.rtl,
                      onChanged: (_) => setStateDialog(() {}),
                      decoration: InputDecoration(
                        labelText: 'סיבה להסרה',
                        helperText: reasonOk
                            ? null
                            : '⚠ מינימום 5 תווים נדרשים',
                        helperStyle: TextStyle(
                          color: reasonOk
                              ? null
                              : StudioColors.warn,
                          fontWeight: FontWeight.w500,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('בטל'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: reasonOk
                        ? StudioColors.danger
                        : StudioColors.ink5,
                  ),
                  onPressed: reasonOk
                      ? () => Navigator.of(dialogCtx).pop(true)
                      : null,
                  child: const Text('הסר'),
                ),
              ],
            );
          },
        );
      },
    );

    // ignore: avoid_print
    print('[Revoke] confirm dialog returned: $confirmed');
    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
    );

    try {
      // ignore: avoid_print
      print('[Revoke] calling VipSubscriptionService.revoke');
      await VipSubscriptionService.instance.revoke(
        subscriptionId: s.id,
        reason: reasonCtrl.text.trim(),
      );
      // ignore: avoid_print
      print('[Revoke] success — sub ${s.id} marked expired');
      if (rootNav.canPop()) rootNav.pop(); // dismiss spinner
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: StudioColors.success,
        content: const Text('✓ הספק הוסר מהקרוסלה'),
      ));
    } catch (e, st) {
      // ignore: avoid_print
      print('[Revoke] FAILED: $e\n$st');
      if (rootNav.canPop()) rootNav.pop();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: StudioColors.danger,
        content: Text('הסרה נכשלה: $e'),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  Future<void> _onPromote(VipSubscription s) async {
    try {
      await VipSubscriptionService.instance.promoteFromWaitlist(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הספק קודם לקרוסלה')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('הקידום נכשל: $e')),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VIP HERO
// ═══════════════════════════════════════════════════════════════════════════

class _VipHero extends StatelessWidget {
  const _VipHero({
    required this.paying,
    required this.adminComp,
    required this.waitlist,
    required this.monthlyRevenue,
  });
  final int paying;
  final int adminComp;
  final int waitlist;
  final int monthlyRevenue;

  String _money(int amount) {
    if (amount < 1000) return '₪$amount';
    if (amount < 1000000) {
      return '₪${(amount / 1000).toStringAsFixed(amount < 10000 ? 1 : 0)}k';
    }
    return '₪${(amount / 1000000).toStringAsFixed(1)}M';
  }

  @override
  Widget build(BuildContext context) {
    final total = paying + adminComp;
    return Container(
      decoration: BoxDecoration(
        gradient: StudioColors.vipGradient,
        borderRadius: BorderRadius.circular(StudioRadius.xl),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(StudioSpacing.s7),
      child: Stack(
        children: [
          const Positioned.fill(child: _GoldHaloPaint()),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 700;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _heroLeft(monthlyRevenue, paying, waitlist),
                    ),
                    const SizedBox(width: StudioSpacing.s7),
                    StudioCapacityRing(
                      current: total,
                      max: VipSubscriptionService.maxSlots,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heroLeft(monthlyRevenue, paying, waitlist),
                  const SizedBox(height: StudioSpacing.s5),
                  Center(
                    child: StudioCapacityRing(
                      current: total,
                      max: VipSubscriptionService.maxSlots,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _heroLeft(int revenue, int payingCount, int waitlistCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tag
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: StudioColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '⭐ VIP · קרוסלת ספקים',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.32,
              fontWeight: FontWeight.w700,
              color: StudioColors.gold,
            ),
            textDirection: TextDirection.rtl,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'הקרוסלה היוקרתית של AnySkill',
          style: StudioText.display(color: Colors.white).copyWith(
            fontSize: 30,
            letterSpacing: -0.6,
          ),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 6),
        Text(
          'שלושים מקומות בלבד. ₪99 לחודש בקרדיטים פנימיים. רשימת המתנה אוטומטית.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.7),
            height: 1.5,
          ),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: StudioSpacing.s6),
        Row(
          children: [
            _heroStat(
              label: 'הכנסה / חודש',
              value: revenue == 0 ? '—' : _money(revenue),
              color: StudioColors.gold,
            ),
            const SizedBox(width: StudioSpacing.s7),
            _heroStat(
              label: 'משלמים פעילים',
              value: '$payingCount',
              color: StudioColors.gold,
            ),
            const SizedBox(width: StudioSpacing.s7),
            _heroStat(
              label: 'בהמתנה',
              value: '$waitlistCount',
              color: StudioColors.gold,
            ),
          ],
        ),
        if (revenue == 0) ...[
          const SizedBox(height: StudioSpacing.s5),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: Color(0xCCFFFFFF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'מנויים משלמים יחלו להגיע אחרי שמערכת התשלומים תעלה (פאזה 5). כרגע פעילים רק מענקי מנהל חינם.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _heroStat(
      {required String label, required String value, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _GoldHaloPaint extends StatelessWidget {
  const _GoldHaloPaint();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GoldHaloPainter(),
      size: Size.infinite,
    );
  }
}

class _GoldHaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width * 1.05, -size.height * 0.4);
    final radius = size.width * 0.6;
    if (radius <= 0) return;
    final paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x40B89855), Color(0x00B89855)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _GoldHaloPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// TABS
// ═══════════════════════════════════════════════════════════════════════════

class _TabsBar extends StatelessWidget {
  const _TabsBar({
    required this.selected,
    required this.counts,
    required this.onChange,
  });
  final _Tab selected;
  final Map<_Tab, int> counts;
  final ValueChanged<_Tab> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: StudioColors.bgElevated,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        border: Border.all(color: StudioColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in _Tab.values)
            _TabBtn(
              label: t.label,
              count: counts[t] ?? 0,
              active: t == selected,
              onTap: () => onChange(t),
            ),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? StudioColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active ? StudioShadows.sh1 : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : StudioColors.ink3,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.18)
                    : StudioColors.bgSubtle,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : StudioColors.ink3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT GRID
// ═══════════════════════════════════════════════════════════════════════════

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.paying,
    required this.adminComp,
    required this.filtered,
    required this.onAdd,
    required this.onDetails,
    required this.onEdit,
    required this.onRemove,
  });
  final List<VipSubscription> paying;
  final List<VipSubscription> adminComp;
  final List<VipSubscription> filtered;
  final VoidCallback onAdd;
  final ValueChanged<VipSubscription> onDetails;
  final ValueChanged<VipSubscription> onEdit;
  final ValueChanged<VipSubscription> onRemove;

  @override
  Widget build(BuildContext context) {
    // Sort: paying first, then admin-comp. Within each: by createdAt DESC.
    final sorted = [...filtered]..sort((a, b) {
        if (a.type != b.type) {
          if (a.type == VipSubscriptionType.paid) return -1;
          return 1;
        }
        final at = a.createdAt ?? DateTime(0);
        final bt = b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      });

    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 280).floor().clamp(1, 4);
      return Wrap(
        spacing: StudioSpacing.s4,
        runSpacing: StudioSpacing.s4,
        children: [
          for (int i = 0; i < sorted.length; i++)
            SizedBox(
              width: (c.maxWidth -
                      (cols - 1) * StudioSpacing.s4) /
                  cols,
              child: StudioVipSlotCard(
                subscription: sorted[i],
                rank: i + 1,
                onDetails: () => onDetails(sorted[i]),
                onEdit: () => onEdit(sorted[i]),
                onRemove: () => onRemove(sorted[i]),
              ),
            ),
          // Empty slot CTA — shown when total < cap.
          if (paying.length + adminComp.length <
              VipSubscriptionService.maxSlots)
            SizedBox(
              width: (c.maxWidth -
                      (cols - 1) * StudioSpacing.s4) /
                  cols,
              child: StudioVipEmptySlot(onTap: onAdd),
            ),
        ],
      );
    });
  }
}

class _EmptyTabState extends StatelessWidget {
  const _EmptyTabState({required this.tab});
  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    final msg = switch (tab) {
      _Tab.paying =>
        'אין מנויים משלמים — מערכת התשלומים תעלה בפאזה 5',
      _Tab.adminComp => 'לא הוענקו עדיין מענקי VIP חינם',
      _Tab.expiringSoon => 'אין VIP-ים קרובים לפג תוקף',
      _Tab.all => 'אין VIP-ים פעילים',
    };
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s7),
      decoration: studioCard(radius: StudioRadius.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 32, color: StudioColors.ink4),
            const SizedBox(height: 12),
            Text(
              msg,
              style: StudioText.body(color: StudioColors.ink3),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudioSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 32, color: StudioColors.ink4),
            const SizedBox(height: StudioSpacing.s3),
            Text('שגיאה בטעינת VIP', style: StudioText.h3()),
            const SizedBox(height: 4),
            Text(error, style: StudioText.captionSm()),
          ],
        ),
      ),
    );
  }
}
