import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/vip_subscription_model.dart';
import '../../../utils/safe_image_provider.dart';
import 'design_tokens.dart';

/// One slot in the VIP grid.
///
/// Mockup spec ([banners-mockup-v3.html:478-528](docs/ui-specs/Baner/banners-mockup-v3.html)):
///   - 280-wide card, 16px radius
///   - Variants:
///       paying        → cream gradient + soft gold border
///       admin-comp    → black "🎁 חינם · המנהל" tag in top-start corner
///       expired       → 60% opacity + dashed border
///   - Top-end rank badge (1, 2, 3...)
///   - Avatar 48 + name + verified + category + rating
///   - Time row: "X days left · until DD/MM" + auto/manual/permanent tag
///   - 3 stats: impressions / clicks / CTR
///   - 3 action buttons: details · edit · remove
///
/// Streams the provider's `users/{providerId}` doc itself so name +
/// avatar stay fresh without the parent screen needing to pre-resolve.
class StudioVipSlotCard extends StatelessWidget {
  const StudioVipSlotCard({
    super.key,
    required this.subscription,
    required this.rank,
    this.onDetails,
    this.onEdit,
    this.onRemove,
  });

  final VipSubscription subscription;
  final int rank;
  final VoidCallback? onDetails;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    final isAdminComp = s.type == VipSubscriptionType.adminComp;
    final isPaying = s.type == VipSubscriptionType.paid;
    final isExpired = s.status == VipSubscriptionStatus.expired ||
        (s.endDate != null && s.endDate!.isBefore(DateTime.now()));

    BoxDecoration deco;
    if (isExpired) {
      deco = BoxDecoration(
        color: StudioColors.bgElevated,
        borderRadius: BorderRadius.circular(StudioRadius.md),
        border: Border.all(
          color: StudioColors.line2,
          style: BorderStyle.solid, // dashed not natively supported — line2 + opacity is the closest
        ),
      );
    } else if (isPaying) {
      deco = BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFAF6EB), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(StudioRadius.md),
        border: Border.all(color: StudioColors.goldSoft),
        boxShadow: StudioShadows.sh1,
      );
    } else {
      deco = studioCard(radius: StudioRadius.md);
    }

    return Opacity(
      opacity: isExpired ? 0.6 : 1.0,
      child: Container(
        decoration: deco,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(StudioSpacing.s4 + 2),
        child: Stack(
          children: [
            if (isAdminComp)
              PositionedDirectional(
                top: 0,
                start: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: StudioColors.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '🎁 חינם · המנהל',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            // Rank badge (top-end)
            PositionedDirectional(
              top: 0,
              end: 0,
              child: _RankBadge(rank: rank, isPaying: isPaying),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: _Body(
                subscription: s,
                onDetails: onDetails,
                onEdit: onEdit,
                onRemove: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.isPaying});
  final int rank;
  final bool isPaying;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: isPaying ? StudioColors.goldGradient : null,
        color: isPaying ? null : StudioColors.bgSubtle,
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: isPaying ? Colors.white : StudioColors.ink3,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.subscription,
    required this.onDetails,
    required this.onEdit,
    required this.onRemove,
  });
  final VipSubscription subscription;
  final VoidCallback? onDetails;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(s.providerId)
          .snapshots(),
      builder: (context, snap) {
        final userData = snap.data?.data();
        final name = (userData?['name'] as String?) ?? 'נותן שירות';
        final category = (userData?['serviceType'] as String?) ?? '';
        final photo = (userData?['profileImage'] as String?) ?? '';
        final rating = (userData?['rating'] as num?)?.toDouble() ?? 0;
        final verified = userData?['isVerified'] as bool? ?? false;
        final missing = !snap.hasData || userData == null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Head(
              name: missing ? 'נותן שירות נמחק?' : name,
              category: category,
              rating: rating,
              photo: photo,
              verified: verified,
              missing: missing,
            ),
            const SizedBox(height: StudioSpacing.s3),
            _TimeRow(subscription: s),
            const SizedBox(height: StudioSpacing.s3),
            _StatsRow(subscription: s),
            const SizedBox(height: StudioSpacing.s3),
            const Divider(height: 1, color: StudioColors.line),
            const SizedBox(height: StudioSpacing.s3),
            _ActionsRow(
              onDetails: onDetails,
              onEdit: onEdit,
              onRemove: onRemove,
            ),
          ],
        );
      },
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({
    required this.name,
    required this.category,
    required this.rating,
    required this.photo,
    required this.verified,
    required this.missing,
  });
  final String name;
  final String category;
  final double rating;
  final String photo;
  final bool verified;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: missing ? null : StudioColors.goldGradient,
            color: missing ? StudioColors.bgTonal : null,
            borderRadius: BorderRadius.circular(StudioRadius.md),
            image: safeImageProvider(photo) != null
                ? DecorationImage(
                    image: safeImageProvider(photo)!,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: safeImageProvider(photo) == null && !missing
              ? Text(
                  name.isEmpty ? '?' : name.characters.first,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: StudioColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                  if (verified)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 4),
                      child: Icon(Icons.verified_rounded,
                          size: 14, color: StudioColors.info),
                    ),
                ],
              ),
              if (category.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    category,
                    style: StudioText.captionSm(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                ),
              if (rating > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 12, color: StudioColors.gold),
                      const SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: StudioText.captionSm(
                                color: StudioColors.goldDeep)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.subscription});
  final VipSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    final daysLeft = s.daysRemaining;
    final isExpired = s.isExpired;

    String timeLabel;
    Color timeColor;
    IconData timeIcon;
    if (s.endDate == null) {
      timeLabel = 'ללא פג תוקף · קבוע';
      timeColor = StudioColors.ink2;
      timeIcon = Icons.all_inclusive_rounded;
    } else if (isExpired) {
      timeLabel = 'פג ${_dmy(s.endDate!)}';
      timeColor = StudioColors.danger;
      timeIcon = Icons.event_busy_rounded;
    } else {
      timeLabel = 'נותרו $daysLeft ימים · עד ${_dmy(s.endDate!)}';
      timeColor = StudioColors.ink2;
      timeIcon = Icons.event_rounded;
    }

    final renewal = _renewalSpec(s);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isExpired
            ? StudioColors.dangerBg
            : StudioColors.bgSubtle,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isExpired
                  ? StudioColors.danger.withValues(alpha: 0.12)
                  : StudioColors.goldSoft,
              borderRadius: BorderRadius.circular(StudioRadius.xs),
            ),
            child: Icon(
              timeIcon,
              size: 13,
              color: isExpired
                  ? StudioColors.danger
                  : StudioColors.goldDeep,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isExpired ? 'הסתיים' : 'תוקף',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: StudioColors.ink4,
                    letterSpacing: 0.4,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: timeColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: renewal.bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              renewal.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: renewal.fg,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }

  static String _dmy(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}';
  }

  _RenewalSpec _renewalSpec(VipSubscription s) {
    if (s.type == VipSubscriptionType.adminComp) {
      if (s.endDate == null) {
        return const _RenewalSpec('קבוע', StudioColors.bgTonal,
            StudioColors.ink4);
      }
      return const _RenewalSpec(
          '⏱ זמני', StudioColors.bgTonal, StudioColors.ink4);
    }
    if (s.autoRenew) {
      return const _RenewalSpec(
          '↻ אוטו', StudioColors.successBg, StudioColors.success);
    }
    return const _RenewalSpec(
        '⚠ ידני', StudioColors.warnBg, StudioColors.warn);
  }
}

class _RenewalSpec {
  final String label;
  final Color bg;
  final Color fg;
  const _RenewalSpec(this.label, this.bg, this.fg);
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.subscription});
  final VipSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    final hasData = s.totalImpressions > 0 || s.totalClicks > 0;
    return Row(
      children: [
        Expanded(
          child: _Stat(
            label: 'חשיפות',
            value: hasData ? _compact(s.totalImpressions) : '—',
          ),
        ),
        Expanded(
          child: _Stat(
            label: 'הקלקות',
            value: hasData ? _compact(s.totalClicks) : '—',
          ),
        ),
        Expanded(
          child: _Stat(
            label: 'CTR',
            value: hasData ? '${s.ctr.toStringAsFixed(1)}%' : '—',
          ),
        ),
      ],
    );
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
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: StudioColors.ink4,
            letterSpacing: 0.4,
          ),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: StudioColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.onDetails,
    required this.onEdit,
    required this.onRemove,
  });
  final VoidCallback? onDetails;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Btn(
            icon: Icons.bar_chart_rounded,
            label: 'פרטים',
            onPressed: onDetails,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _Btn(
            icon: Icons.edit_outlined,
            label: 'ערוך',
            onPressed: onEdit,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _Btn(
            icon: Icons.delete_outline_rounded,
            label: 'הסר',
            onPressed: onRemove,
            danger: true,
          ),
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.xs),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: StudioColors.bgSubtle,
          borderRadius: BorderRadius.circular(StudioRadius.xs),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: disabled
                  ? StudioColors.ink4
                  : (danger
                      ? StudioColors.danger
                      : StudioColors.ink2),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: disabled
                    ? StudioColors.ink4
                    : (danger
                        ? StudioColors.danger
                        : StudioColors.ink2),
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-slot card — dashed surface with "+ הוסף ספק חינם" CTA.
class StudioVipEmptySlot extends StatelessWidget {
  const StudioVipEmptySlot({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.md),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 240),
        padding: const EdgeInsets.all(StudioSpacing.s5),
        decoration: BoxDecoration(
          color: StudioColors.bgSubtle,
          borderRadius: BorderRadius.circular(StudioRadius.md),
          border: Border.all(
            color: StudioColors.ink5,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(StudioRadius.md),
                border: Border.all(color: StudioColors.line),
              ),
              child: const Icon(Icons.add_rounded,
                  size: 22, color: StudioColors.ink3),
            ),
            const SizedBox(height: StudioSpacing.s3),
            Text(
              'הוסף ספק חינם',
              style: StudioText.h3(),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 4),
            Text(
              'מענק מנהל · ללא חיוב',
              style: StudioText.captionSm(),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }
}
