// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../utils/safe_image_provider.dart';
import 'design_tokens.dart';

/// Section 3 of the banner edit screen — provider selection for a
/// `provider_carousel` banner.
///
/// Fresh implementation (NOT a port of v2's 600-line picker) optimised
/// for the inline edit-screen accordion: search-debounced 300ms list of
/// `users where isProvider == true` (capped 100), tappable rows, badge
/// at the top with the selected count, and a 2-20 soft limit enforced
/// with Hebrew snackbars.
class StudioProviderPickerSection extends StatefulWidget {
  const StudioProviderPickerSection({
    super.key,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  static const int minProviders = 2;
  static const int maxProviders = 20;

  @override
  State<StudioProviderPickerSection> createState() =>
      _StudioProviderPickerSectionState();
}

class _StudioProviderPickerSectionState
    extends State<StudioProviderPickerSection> {
  String _query = '';
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim().toLowerCase());
    });
  }

  void _toggle(String uid) {
    final ids = List<String>.from(widget.selectedIds);
    if (ids.contains(uid)) {
      ids.remove(uid);
    } else {
      if (ids.length >= StudioProviderPickerSection.maxProviders) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'הגעת לתקרה של ${StudioProviderPickerSection.maxProviders} נותני שירות',
            ),
          ),
        );
        return;
      }
      ids.add(uid);
    }
    widget.onChanged(ids);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = widget.selectedIds.length;
    final tooFew = selectedCount < StudioProviderPickerSection.minProviders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Counter banner
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: StudioSpacing.s4, vertical: 10),
          decoration: BoxDecoration(
            color: tooFew ? StudioColors.warnBg : StudioColors.successBg,
            borderRadius: BorderRadius.circular(StudioRadius.sm),
          ),
          child: Row(
            children: [
              Icon(
                tooFew
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 16,
                color: tooFew ? StudioColors.warn : StudioColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tooFew
                      ? 'בחר עוד ${StudioProviderPickerSection.minProviders - selectedCount} נותני שירות לפחות (נבחרו $selectedCount/${StudioProviderPickerSection.maxProviders})'
                      : 'נבחרו $selectedCount/${StudioProviderPickerSection.maxProviders} נותני שירות',
                  style: StudioText.bodyMedium(
                    color: tooFew ? StudioColors.warn : StudioColors.success,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
              if (selectedCount > 0)
                TextButton(
                  onPressed: () => widget.onChanged(const []),
                  style: TextButton.styleFrom(
                    foregroundColor: StudioColors.ink3,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('נקה הכל',
                      textDirection: TextDirection.rtl),
                ),
            ],
          ),
        ),

        const SizedBox(height: StudioSpacing.s3),

        // Search field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: StudioColors.bgSubtle,
            border: Border.all(color: StudioColors.line2),
            borderRadius: BorderRadius.circular(StudioRadius.sm),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded,
                  size: 16, color: StudioColors.ink3),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onChanged: _onSearchChanged,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'חפש לפי שם או קטגוריה...',
                    hintStyle: StudioText.body(color: StudioColors.ink4),
                  ),
                  style: StudioText.body(color: StudioColors.ink),
                ),
              ),
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  color: StudioColors.ink3,
                  onPressed: () {
                    _ctrl.clear();
                    setState(() => _query = '');
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),

        const SizedBox(height: StudioSpacing.s3),

        // Provider list
        SizedBox(
          height: 320,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isProvider', isEqualTo: true)
                .limit(100)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text('שגיאה: ${snap.error}',
                      style: StudioText.captionSm(),
                      textDirection: TextDirection.rtl),
                );
              }
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2));
              }
              final all = snap.data!.docs;
              final filtered = _query.isEmpty
                  ? all
                  : all.where((d) {
                      final m = d.data();
                      final name = (m['name'] as String? ?? '').toLowerCase();
                      final cat =
                          (m['serviceType'] as String? ?? '').toLowerCase();
                      return name.contains(_query) || cat.contains(_query);
                    }).toList();

              // Sort: selected first, then by name.
              filtered.sort((a, b) {
                final aSel = widget.selectedIds.contains(a.id);
                final bSel = widget.selectedIds.contains(b.id);
                if (aSel != bSel) return aSel ? -1 : 1;
                return ((a.data()['name'] as String?) ?? '')
                    .compareTo((b.data()['name'] as String?) ?? '');
              });

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(StudioSpacing.s5),
                    child: Text(
                      _query.isEmpty
                          ? 'אין ספקים פעילים במערכת'
                          : 'לא נמצאו תוצאות עבור "$_query"',
                      style: StudioText.captionSm(),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final doc = filtered[i];
                  final m = doc.data();
                  return _ProviderRow(
                    uid: doc.id,
                    name: (m['name'] as String?) ?? '(ללא שם)',
                    category: (m['serviceType'] as String?) ?? '',
                    photo: (m['profileImage'] as String?) ?? '',
                    rating: (m['rating'] as num?)?.toDouble() ?? 0,
                    reviewsCount:
                        (m['reviewsCount'] as num?)?.toInt() ?? 0,
                    verified: m['isVerified'] as bool? ?? false,
                    online: m['isOnline'] as bool? ?? false,
                    selected: widget.selectedIds.contains(doc.id),
                    onTap: () => _toggle(doc.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.uid,
    required this.name,
    required this.category,
    required this.photo,
    required this.rating,
    required this.reviewsCount,
    required this.verified,
    required this.online,
    required this.selected,
    required this.onTap,
  });

  // ignore: unused_element
  final String uid;
  final String name;
  final String category;
  final String photo;
  final double rating;
  final int reviewsCount;
  final bool verified;
  final bool online;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.sm),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? StudioColors.goldSoft
              : StudioColors.bgElevated,
          border: Border.all(
            color: selected ? StudioColors.gold : StudioColors.line,
          ),
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: StudioColors.bgSubtle,
                  backgroundImage: safeImageProvider(photo),
                  child: safeImageProvider(photo) == null
                      ? Text(
                          name.isEmpty ? '?' : name.characters.first,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: StudioColors.ink2,
                          ),
                        )
                      : null,
                ),
                if (online)
                  PositionedDirectional(
                    bottom: -1,
                    end: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: StudioColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
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
                          style: StudioText.bodyMedium(
                              color: StudioColors.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                      if (verified)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: Icon(
                            Icons.verified_rounded,
                            size: 13,
                            color: StudioColors.info,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (category.isNotEmpty)
                        Flexible(
                          child: Text(
                            category,
                            style: StudioText.captionSm(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                      if (rating > 0) ...[
                        if (category.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text('·',
                                style: StudioText.captionSm()),
                          ),
                        Icon(Icons.star_rounded,
                            size: 11, color: StudioColors.gold),
                        const SizedBox(width: 2),
                        Text(
                          rating.toStringAsFixed(1),
                          style: StudioText.captionSm(
                                  color: StudioColors.goldDeep)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (reviewsCount > 0) ...[
                          const SizedBox(width: 3),
                          Text('($reviewsCount)',
                              style: StudioText.captionSm()),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Add/Remove button
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? StudioColors.gold : StudioColors.ink,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                selected ? Icons.check_rounded : Icons.add_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
