import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/vip_subscription_model.dart';
import '../../../utils/safe_image_provider.dart';
import 'design_tokens.dart';

/// Waitlist card shown at the bottom of the VIP management screen.
///
/// Mockup spec ([banners-mockup-v3.html:531-545](docs/ui-specs/Baner/banners-mockup-v3.html)):
///   - Header: gold icon + title + counter
///   - Each row: position pill, avatar + meta, status, ETA, amount, "↑ קדם" btn
///
/// Phase 3 ships the layout but the waitlist is empty until Phase 5
/// brings paid subscriptions. The empty state is honest: "אין ספקים
/// ברשימת המתנה — תכונה זו תופעל כשמערכת התשלומים תעלה (פאזה 5)".
class StudioWaitlistCard extends StatelessWidget {
  const StudioWaitlistCard({
    super.key,
    required this.entries,
    required this.onPromote,
  });

  final List<VipSubscription> entries;
  final ValueChanged<VipSubscription> onPromote;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: studioCard(radius: StudioRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _Header(count: entries.length),
          if (entries.isEmpty)
            _EmptyState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: StudioColors.line),
              itemBuilder: (context, i) => _WaitlistRow(
                index: i + 1,
                entry: entries[i],
                onPromote: () => onPromote(entries[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          StudioSpacing.s6, StudioSpacing.s5, StudioSpacing.s6, StudioSpacing.s5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [
            StudioColors.gold.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
        border: const Border(
            bottom: BorderSide(color: StudioColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: StudioColors.goldSoft,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            child: const Text('⏳',
                style: TextStyle(fontSize: 20, color: StudioColors.goldDeep)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('רשימת המתנה',
                    style: StudioText.h3(),
                    textDirection: TextDirection.rtl),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'אין ספקים בהמתנה'
                      : '$count ספקים מחכים לכניסה לקרוסלה',
                  style: StudioText.captionSm(),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: StudioColors.goldDeep,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(StudioSpacing.s7),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: StudioColors.bgSubtle,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            child: const Icon(Icons.hourglass_empty_rounded,
                size: 26, color: StudioColors.ink4),
          ),
          const SizedBox(height: 12),
          Text(
            'אין ספקים ברשימת המתנה',
            style: StudioText.h3(),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 4),
          Text(
            'תכונה זו תופעל כשמערכת התשלומים תעלה (פאזה 5)',
            style: StudioText.captionSm(),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
}

class _WaitlistRow extends StatelessWidget {
  const _WaitlistRow({
    required this.index,
    required this.entry,
    required this.onPromote,
  });
  final int index;
  final VipSubscription entry;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(entry.providerId)
          .snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data();
        final name = (m?['name'] as String?) ?? 'נותן שירות';
        final photo = (m?['profileImage'] as String?) ?? '';
        final category = (m?['serviceType'] as String?) ?? '';

        return Padding(
          padding: const EdgeInsets.fromLTRB(
              StudioSpacing.s6, 12, StudioSpacing.s6, 12),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '#$index',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: StudioColors.ink3,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: StudioColors.bgSubtle,
                backgroundImage: safeImageProvider(photo),
                child: safeImageProvider(photo) == null
                    ? Text(name.characters.firstOrNull ?? '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: StudioColors.ink2,
                        ))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: StudioText.bodyMedium(
                            color: StudioColors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl),
                    if (category.isNotEmpty)
                      Text(category,
                          style: StudioText.captionSm(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: StudioColors.successBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('✓ שילם',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: StudioColors.success,
                    ),
                    textDirection: TextDirection.rtl),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: onPromote,
                style: FilledButton.styleFrom(
                  backgroundColor: StudioColors.goldSoft,
                  foregroundColor: StudioColors.goldDeep,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(StudioRadius.xs)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_upward_rounded, size: 13),
                    const SizedBox(width: 4),
                    Text('קדם',
                        style: StudioText.bodyMedium(
                            color: StudioColors.goldDeep)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
