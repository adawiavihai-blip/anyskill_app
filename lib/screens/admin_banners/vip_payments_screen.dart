// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/vip_payment_model.dart';
import '../../services/vip_payment_service.dart';
import '../../utils/safe_image_provider.dart';
import '../../widgets/banners_admin/v3/design_tokens.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Banners Studio — Screen D (VIP Payments).
///
/// Per `docs/ui-specs/Baner/banners-mockup-v3.html` Screen D:
///   - 4 stat cards (revenue this month, active payments, renewals next
///     month, waitlist potential)
///   - Filter tabs (All / Paid / Pending / Failed) + month pill
///   - Payments table: provider · amount · status · date · method ·
///     renewal type · row menu
///
/// **Data source:** `vip_payments/` collection. All entries written
/// server-side by `purchaseVipWithCredits` (Phase 5) or the monthly
/// billing CF (Phase 6).
/// ═══════════════════════════════════════════════════════════════════════════

class VipPaymentsScreen extends StatefulWidget {
  const VipPaymentsScreen({super.key});

  @override
  State<VipPaymentsScreen> createState() => _VipPaymentsScreenState();
}

enum _Filter { all, paid, pending, failed }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'הכל',
        _Filter.paid => 'שולמו',
        _Filter.pending => 'בהמתנה',
        _Filter.failed => 'נכשלו',
      };
}

class _VipPaymentsScreenState extends State<VipPaymentsScreen> {
  _Filter _filter = _Filter.all;

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
        title: Text('תשלומי VIP',
            style: StudioText.h3(),
            textDirection: TextDirection.rtl),
      ),
      body: StreamBuilder<List<VipPayment>>(
        stream: VipPaymentService.instance.watchAll(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorState(error: snap.error.toString());
          }
          final payments = snap.data ?? const <VipPayment>[];
          return _buildBody(context, payments);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<VipPayment> payments) {
    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);

    // ── Stats ───────────────────────────────────────────────────────
    final paidThisMonth = payments.where((p) =>
        p.status == VipPaymentStatus.paid &&
        p.paymentDate != null &&
        p.paymentDate!.isAfter(thisMonthStart));
    final revenueThisMonth =
        paidThisMonth.fold<int>(0, (a, p) => a + p.amount);
    final activeCount = payments
        .where((p) => p.status == VipPaymentStatus.paid)
        .map((p) => p.subscriptionId)
        .toSet()
        .length;
    final renewalsNextMonth = payments
        .where((p) =>
            p.status == VipPaymentStatus.paid &&
            p.paymentDate != null &&
            p.paymentDate!
                .add(const Duration(days: 30))
                .isAfter(nextMonthStart) &&
            p.paymentDate!
                .add(const Duration(days: 30))
                .isBefore(nextMonthStart.add(const Duration(days: 31))))
        .length;

    final filtered = payments.where((p) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.paid:
          return p.status == VipPaymentStatus.paid;
        case _Filter.pending:
          return p.status == VipPaymentStatus.pending;
        case _Filter.failed:
          return p.status == VipPaymentStatus.failed;
      }
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: StudioSpacing.s7, vertical: StudioSpacing.s6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatsGrid(
                revenueThisMonth: revenueThisMonth,
                activeCount: activeCount,
                renewalsNextMonth: renewalsNextMonth,
                waitlistCount: 0, // populated in Phase 6
              ),

              const SizedBox(height: StudioSpacing.s7),

              // Tabs + month
              Row(
                children: [
                  _TabsBar(
                    selected: _filter,
                    counts: {
                      _Filter.all: payments.length,
                      _Filter.paid: payments
                          .where((p) =>
                              p.status == VipPaymentStatus.paid)
                          .length,
                      _Filter.pending: payments
                          .where((p) =>
                              p.status == VipPaymentStatus.pending)
                          .length,
                      _Filter.failed: payments
                          .where((p) =>
                              p.status == VipPaymentStatus.failed)
                          .length,
                    },
                    onChange: (f) => setState(() => _filter = f),
                  ),
                  const Spacer(),
                  // Static month pill (admin-side filtering by month is
                  // a Phase 6 enhancement).
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: StudioColors.bgElevated,
                      border: Border.all(color: StudioColors.line2),
                      borderRadius:
                          BorderRadius.circular(StudioRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_outlined,
                            size: 13, color: StudioColors.ink3),
                        const SizedBox(width: 6),
                        Text(
                          _hebrewMonth(now.month),
                          style: StudioText.bodyMedium(),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: StudioSpacing.s5),

              // Payments table
              if (filtered.isEmpty)
                _EmptyState(filter: _filter)
              else
                _PaymentsTable(payments: filtered),

              const SizedBox(height: StudioSpacing.s8),
            ],
          ),
        ),
      ),
    );
  }

  static String _hebrewMonth(int month) {
    const names = [
      '',
      'ינואר',
      'פברואר',
      'מרץ',
      'אפריל',
      'מאי',
      'יוני',
      'יולי',
      'אוגוסט',
      'ספטמבר',
      'אוקטובר',
      'נובמבר',
      'דצמבר',
    ];
    if (month < 1 || month > 12) return '';
    return names[month];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATS GRID
// ═══════════════════════════════════════════════════════════════════════════

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.revenueThisMonth,
    required this.activeCount,
    required this.renewalsNextMonth,
    required this.waitlistCount,
  });
  final int revenueThisMonth;
  final int activeCount;
  final int renewalsNextMonth;
  final int waitlistCount;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: StudioSpacing.s4,
      mainAxisSpacing: StudioSpacing.s4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: [
        _StatCard(
          label: 'הכנסה החודש',
          valueText: revenueThisMonth == 0
              ? '—'
              : '₪${_compactMoney(revenueThisMonth.toDouble())}',
          accent: true,
        ),
        _StatCard(
          label: 'תשלומים פעילים',
          valueText: activeCount == 0 ? '—' : '$activeCount',
        ),
        _StatCard(
          label: 'חידושים בחודש הבא',
          valueText:
              renewalsNextMonth == 0 ? '—' : '$renewalsNextMonth',
        ),
        _StatCard(
          label: 'פוטנציאל המתנה',
          valueText:
              waitlistCount == 0 ? '—' : '₪${waitlistCount * 99}',
        ),
      ],
    );
  }

  static String _compactMoney(double v) {
    if (v < 1000) return v.toStringAsFixed(0);
    if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '${(v / 1000000).toStringAsFixed(1)}M';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.valueText,
    this.accent = false,
  });
  final String label;
  final String valueText;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s5),
      decoration: studioCard(radius: StudioRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: StudioText.overline(),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: StudioSpacing.s3),
          Text(
            valueText,
            style: StudioText.metricLarge(
              color: accent ? StudioColors.gold : StudioColors.ink,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
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
  final _Filter selected;
  final Map<_Filter, int> counts;
  final ValueChanged<_Filter> onChange;

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
          for (final f in _Filter.values)
            _Tab(
              label: f.label,
              count: counts[f] ?? 0,
              active: f == selected,
              onTap: () => onChange(f),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? StudioColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 1),
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
// PAYMENTS TABLE
// ═══════════════════════════════════════════════════════════════════════════

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({required this.payments});
  final List<VipPayment> payments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(StudioRadius.lg),
      child: Container(
        decoration: studioCard(radius: StudioRadius.lg),
        child: Column(
          children: [
            const _TableHeader(),
            for (final p in payments)
              _PaymentRow(key: ValueKey(p.id), payment: p),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final labelStyle = StudioText.overline();
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: StudioSpacing.s5, vertical: 12),
      decoration: const BoxDecoration(
        color: StudioColors.bgSubtle,
        border: Border(bottom: BorderSide(color: StudioColors.line2)),
      ),
      child: Row(
        children: [
          Expanded(
              flex: 28,
              child: Text('ספק',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 100,
              child: Text('סכום',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 120,
              child: Text('סטטוס',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 120,
              child: Text('תאריך',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 130,
              child: Text('אמצעי תשלום',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 100,
              child: Text('חידוש',
                  style: labelStyle, textDirection: TextDirection.rtl)),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({super.key, required this.payment});
  final VipPayment payment;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: StudioSpacing.s5, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: StudioColors.line)),
      ),
      child: Row(
        children: [
          // Provider
          Expanded(
            flex: 28,
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(p.providerId)
                  .snapshots(),
              builder: (context, snap) {
                final m = snap.data?.data();
                final name = (m?['name'] as String?) ?? 'נותן שירות';
                final photo = (m?['profileImage'] as String?) ?? '';
                final cat = (m?['serviceType'] as String?) ?? '';
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: StudioColors.bgSubtle,
                      backgroundImage: safeImageProvider(photo),
                      child: safeImageProvider(photo) == null
                          ? Text(
                              name.characters.firstOrNull ?? '?',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: StudioColors.ink2,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: StudioText.bodyMedium(
                                color: StudioColors.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                          if (cat.isNotEmpty)
                            Text(
                              cat,
                              style: StudioText.captionSm(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Amount
          SizedBox(
            width: 100,
            child: Text(
              '₪${p.amount}',
              style: StudioText.metricMd(),
              textDirection: TextDirection.rtl,
            ),
          ),
          // Status pill
          SizedBox(
            width: 120,
            child: _StatusPill(status: p.status),
          ),
          // Date
          SizedBox(
            width: 120,
            child: Text(
              p.paymentDate != null ? _dmy(p.paymentDate!) : '—',
              style: StudioText.body(),
              textDirection: TextDirection.rtl,
            ),
          ),
          // Method
          SizedBox(
            width: 130,
            child: _MethodCell(payment: p),
          ),
          // Renewal type
          SizedBox(
            width: 100,
            child: _RenewalPill(type: p.renewalType),
          ),
        ],
      ),
    );
  }

  static String _dmy(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final VipPaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final spec = _spec(status);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: spec.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status.hebrewLabel,
          style: StudioText.chip(color: spec.fg),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  static _Spec _spec(VipPaymentStatus s) => switch (s) {
        VipPaymentStatus.paid =>
          const _Spec(StudioColors.successBg, StudioColors.success),
        VipPaymentStatus.pending =>
          const _Spec(StudioColors.warnBg, StudioColors.warn),
        VipPaymentStatus.failed =>
          const _Spec(StudioColors.dangerBg, StudioColors.danger),
        VipPaymentStatus.refunded =>
          const _Spec(StudioColors.bgTonal, StudioColors.ink3),
        VipPaymentStatus.comp =>
          const _Spec(StudioColors.goldSoft, StudioColors.goldDeep),
      };
}

class _RenewalPill extends StatelessWidget {
  const _RenewalPill({required this.type});
  final VipRenewalType type;

  @override
  Widget build(BuildContext context) {
    final spec = _spec(type);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: spec.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          type.hebrewLabel,
          style: StudioText.chip(color: spec.fg),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  static _Spec _spec(VipRenewalType t) => switch (t) {
        VipRenewalType.auto =>
          const _Spec(StudioColors.successBg, StudioColors.success),
        VipRenewalType.manual =>
          const _Spec(StudioColors.warnBg, StudioColors.warn),
        VipRenewalType.initial =>
          const _Spec(StudioColors.infoBg, StudioColors.info),
      };
}

class _Spec {
  final Color bg;
  final Color fg;
  const _Spec(this.bg, this.fg);
}

class _MethodCell extends StatelessWidget {
  const _MethodCell({required this.payment});
  final VipPayment payment;

  IconData _iconFor() {
    switch (payment.paymentMethod) {
      case 'visa':
        return Icons.credit_card_rounded;
      case 'mastercard':
      case 'mc':
        return Icons.credit_card_rounded;
      case 'comp':
        return Icons.card_giftcard_rounded;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _label() {
    switch (payment.paymentMethod) {
      case 'visa':
        return 'Visa${payment.cardLast4 != null ? ' ··· ${payment.cardLast4}' : ''}';
      case 'mastercard':
      case 'mc':
        return 'MC${payment.cardLast4 != null ? ' ··· ${payment.cardLast4}' : ''}';
      case 'comp':
        return 'חינם · מנהל';
      case 'credits':
      default:
        return 'יתרה פנימית';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_iconFor(), size: 14, color: StudioColors.ink3),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _label(),
            style: StudioText.bodyMedium(color: StudioColors.ink2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY / ERROR STATES
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final msg = switch (filter) {
      _Filter.all =>
        'אין עדיין תשלומי VIP — מנויים ראשונים יופיעו כאן ברגע שספקים יקנו דרך פרופיל הספק.',
      _Filter.paid => 'אין תשלומים שולמו עדיין',
      _Filter.pending => 'אין תשלומים בהמתנה',
      _Filter.failed => 'אין תשלומים נכשלו (טוב!)',
    };
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s7),
      decoration: studioCard(radius: StudioRadius.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.payments_outlined,
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
            Text('שגיאה בטעינת תשלומים', style: StudioText.h3()),
            const SizedBox(height: 4),
            Text(error, style: StudioText.captionSm()),
          ],
        ),
      ),
    );
  }
}
