// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/vip_subscription_model.dart';
import '../../../services/vip_subscription_service.dart';
import '../../../utils/safe_image_provider.dart';
import 'design_tokens.dart';

/// Bottom-sheet modal for granting an admin-comp VIP slot.
///
/// Two-step flow:
///   1. **Pick provider** — search box + scrollable list of users where
///      isProvider==true. Already-active providers are shown but greyed.
///   2. **Configure** — duration radio (4 options), free-text reason.
///
/// On submit calls [VipSubscriptionService.grantAdminComp] which writes
/// the subscription doc + an audit log entry.
Future<void> showStudioAddVipModal(
  BuildContext context, {
  Set<String>? alreadyActiveProviderIds,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddVipModal(
      alreadyActiveProviderIds: alreadyActiveProviderIds ?? const {},
    ),
  );
}

class _AddVipModal extends StatefulWidget {
  const _AddVipModal({required this.alreadyActiveProviderIds});
  final Set<String> alreadyActiveProviderIds;

  @override
  State<_AddVipModal> createState() => _AddVipModalState();
}

class _AddVipModalState extends State<_AddVipModal> {
  // ── Step state ─────────────────────────────────────────────────────
  int _step = 0;

  // ── Step 1: provider selection ─────────────────────────────────────
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _pickedProviderId;
  String? _pickedProviderName;
  String? _pickedProviderPhoto;
  String? _pickedProviderCategory;

  // ── Step 2: configuration ──────────────────────────────────────────
  VipCompDuration _duration = VipCompDuration.oneMonth;
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) {
          return Container(
            decoration: const BoxDecoration(
              color: StudioColors.bgElevated,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(StudioRadius.xl)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _grabHandle(),
                _header(),
                const Divider(height: 1, color: StudioColors.line),
                Expanded(
                  child: _step == 0
                      ? _buildStep1(scrollCtrl)
                      : _buildStep2(scrollCtrl),
                ),
                const Divider(height: 1, color: StudioColors.line),
                _footer(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _grabHandle() => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: StudioColors.ink5,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: StudioColors.goldGradient,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            child: const Text('🎁',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _step == 0
                      ? 'בחר נותן שירות'
                      : 'הגדר את המענק',
                  style: StudioText.h3(),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 2),
                Text(
                  'הוספת ספק כ-VIP חינם · מענק מנהל',
                  style: StudioText.captionSm(),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: StudioColors.ink3,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ── Step 1 ────────────────────────────────────────────────────────────

  Widget _buildStep1(ScrollController scrollCtrl) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
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
                    controller: _searchCtrl,
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(
                          const Duration(milliseconds: 300), () {
                        if (mounted) {
                          setState(() => _query = v.trim().toLowerCase());
                        }
                      });
                    },
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'חפש לפי שם או קטגוריה...',
                    ),
                    style: StudioText.body(color: StudioColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isProvider', isEqualTo: true)
                .limit(150)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text('שגיאה: ${snap.error}',
                      textDirection: TextDirection.rtl),
                );
              }
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2));
              }
              var docs = snap.data!.docs;
              if (_query.isNotEmpty) {
                docs = docs.where((d) {
                  final m = d.data();
                  final name =
                      (m['name'] as String? ?? '').toLowerCase();
                  final cat = (m['serviceType'] as String? ?? '')
                      .toLowerCase();
                  return name.contains(_query) || cat.contains(_query);
                }).toList();
              }
              docs.sort((a, b) {
                final aActive =
                    widget.alreadyActiveProviderIds.contains(a.id);
                final bActive =
                    widget.alreadyActiveProviderIds.contains(b.id);
                if (aActive != bActive) return aActive ? 1 : -1;
                return ((a.data()['name'] as String?) ?? '')
                    .compareTo((b.data()['name'] as String?) ?? '');
              });
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'לא נמצאו תוצאות',
                    style: StudioText.captionSm(),
                    textDirection: TextDirection.rtl,
                  ),
                );
              }
              return ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final m = doc.data();
                  final isAlreadyActive =
                      widget.alreadyActiveProviderIds.contains(doc.id);
                  final isPicked = doc.id == _pickedProviderId;
                  return _ProviderRow(
                    name: (m['name'] as String?) ?? '(ללא שם)',
                    category: (m['serviceType'] as String?) ?? '',
                    photo: (m['profileImage'] as String?) ?? '',
                    rating: (m['rating'] as num?)?.toDouble() ?? 0,
                    verified: m['isVerified'] as bool? ?? false,
                    alreadyActive: isAlreadyActive,
                    selected: isPicked,
                    onTap: isAlreadyActive
                        ? null
                        : () {
                            setState(() {
                              _pickedProviderId = doc.id;
                              _pickedProviderName =
                                  (m['name'] as String?) ?? '(ללא שם)';
                              _pickedProviderPhoto =
                                  (m['profileImage'] as String?) ?? '';
                              _pickedProviderCategory =
                                  (m['serviceType'] as String?) ?? '';
                            });
                          },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Step 2 ────────────────────────────────────────────────────────────

  Widget _buildStep2(ScrollController scrollCtrl) {
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        // Picked provider card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StudioColors.goldSoft,
            borderRadius: BorderRadius.circular(StudioRadius.md),
            border: Border.all(color: StudioColors.gold),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: StudioColors.bgElevated,
                backgroundImage:
                    safeImageProvider(_pickedProviderPhoto ?? ''),
                child: safeImageProvider(_pickedProviderPhoto ?? '') ==
                        null
                    ? Text(
                        (_pickedProviderName ?? '?')
                            .characters
                            .firstOrNull ??
                            '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: StudioColors.ink2,
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
                    Text(
                      _pickedProviderName ?? '',
                      style: StudioText.bodyMedium(
                          color: StudioColors.goldDeep)
                          .copyWith(fontWeight: FontWeight.w600),
                      textDirection: TextDirection.rtl,
                    ),
                    if ((_pickedProviderCategory ?? '').isNotEmpty)
                      Text(
                        _pickedProviderCategory!,
                        style: StudioText.captionSm(
                            color: StudioColors.goldDeep),
                        textDirection: TextDirection.rtl,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('שנה'),
              ),
            ],
          ),
        ),

        const SizedBox(height: StudioSpacing.s5),

        // Duration radio
        Text(
          'משך המענק',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StudioColors.ink2),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 8),
        for (final d in VipCompDuration.values)
          _DurationRow(
            duration: d,
            selected: _duration == d,
            onTap: () => setState(() => _duration = d),
          ),

        const SizedBox(height: StudioSpacing.s5),

        // Reason
        Text(
          'סיבה למענק (יוצג ביומן הביקורת)',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StudioColors.ink2),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonCtrl,
          maxLines: 3,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: 'לדוגמה: ספק מובחן · השקה חינם, פיצוי על תקלה, פלוט VIP...',
            hintStyle: StudioText.captionSm(),
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            filled: true,
            fillColor: StudioColors.bgSubtle,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              borderSide: const BorderSide(color: StudioColors.line2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              borderSide: const BorderSide(color: StudioColors.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              borderSide: const BorderSide(
                  color: StudioColors.ink3, width: 1.4),
            ),
          ),
          style: StudioText.body(color: StudioColors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'מינימום 5 תווים · לא יוצג למשתמש',
          style: StudioText.captionSm(),
          textDirection: TextDirection.rtl,
        ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        children: [
          if (_step == 0) ...[
            Expanded(
              child: TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('בטל'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _pickedProviderId == null
                    ? null
                    : () => setState(() => _step = 1),
                style: FilledButton.styleFrom(
                  backgroundColor: StudioColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(StudioRadius.sm)),
                ),
                child: const Text('המשך'),
              ),
            ),
          ] else ...[
            Expanded(
              child: TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _step = 0),
                child: const Text('חזור'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : _onGrant,
                style: FilledButton.styleFrom(
                  backgroundColor: StudioColors.goldDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(StudioRadius.sm)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('הענק VIP'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onGrant() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לרשום סיבה (5 תווים לפחות)')),
      );
      return;
    }
    if (_pickedProviderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('בחר נותן שירות')),
      );
      setState(() => _step = 0);
      return;
    }
    setState(() => _saving = true);
    try {
      await VipSubscriptionService.instance.grantAdminComp(
        providerId: _pickedProviderId!,
        providerName: _pickedProviderName ?? '',
        duration: _duration,
        reason: reason,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'מענק VIP הוענק ל-${_pickedProviderName ?? "נותן שירות"}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e')),
      );
    }
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.name,
    required this.category,
    required this.photo,
    required this.rating,
    required this.verified,
    required this.alreadyActive,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final String category;
  final String photo;
  final double rating;
  final bool verified;
  final bool alreadyActive;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: InkWell(
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
              CircleAvatar(
                radius: 18,
                backgroundColor: StudioColors.bgSubtle,
                backgroundImage: safeImageProvider(photo),
                child: safeImageProvider(photo) == null
                    ? Text(
                        name.isEmpty ? '?' : name.characters.first,
                        style: const TextStyle(
                          color: StudioColors.ink2,
                          fontWeight: FontWeight.w600,
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
                          const Padding(
                            padding:
                                EdgeInsetsDirectional.only(start: 4),
                            child: Icon(Icons.verified_rounded,
                                size: 12, color: StudioColors.info),
                          ),
                      ],
                    ),
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
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded,
                              size: 11, color: StudioColors.gold),
                          const SizedBox(width: 1),
                          Text(rating.toStringAsFixed(1),
                              style: StudioText.captionSm(
                                  color: StudioColors.goldDeep)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (alreadyActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: StudioColors.successBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'כבר VIP',
                    style: TextStyle(
                      fontSize: 10,
                      color: StudioColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                )
              else if (selected)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: StudioColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationRow extends StatelessWidget {
  const _DurationRow({
    required this.duration,
    required this.selected,
    required this.onTap,
  });
  final VipCompDuration duration;
  final bool selected;
  final VoidCallback onTap;

  String get _hint => switch (duration) {
        VipCompDuration.trial30d =>
          'יסתיים אוטומטית כעבור 30 יום',
        VipCompDuration.oneMonth => 'יסתיים כעבור 30 יום',
        VipCompDuration.threeMonths => 'יסתיים כעבור 90 יום',
        VipCompDuration.permanent =>
          'ללא תאריך תפוגה · נותר עד הסרה ידנית',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? StudioColors.goldSoft : StudioColors.bgElevated,
            border: Border.all(
              color: selected ? StudioColors.gold : StudioColors.line2,
            ),
            borderRadius: BorderRadius.circular(StudioRadius.sm),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: selected ? StudioColors.gold : Colors.transparent,
                  border: Border.all(
                    color: selected ? StudioColors.gold : StudioColors.ink5,
                    width: 1.5,
                  ),
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Center(
                        child: Icon(Icons.check_rounded,
                            size: 11, color: Colors.white),
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
                      duration.hebrewLabel,
                      style: StudioText.bodyMedium(
                          color: StudioColors.ink),
                      textDirection: TextDirection.rtl,
                    ),
                    Text(
                      _hint,
                      style: StudioText.captionSm(),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
