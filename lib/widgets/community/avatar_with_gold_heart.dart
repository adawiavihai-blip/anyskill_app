/// Avatar widget with the conditional gold-heart badge in the bottom-end
/// corner. Used everywhere a volunteer avatar is rendered (mockups 01,
/// 05, 06, 07, 09, 10, 11, 15, plus search cards + profile screens).
///
/// **Hard rules** (per CLAUDE.md §9b Law 11):
/// - All profile-image URLs route through [safeImageProvider] so base64
///   data URIs render correctly.
/// - The heart badge appears IFF [GoldHeartHelper.hasActiveGoldHeart].
/// - Heart anchor is `bottomEnd` so it mirrors correctly in RTL — same
///   visual position as the mockups in `dir="rtl"` HTML.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';
import '../../utils/gold_heart_helper.dart';
import '../../utils/safe_image_provider.dart';

class AvatarWithGoldHeart extends StatelessWidget {
  const AvatarWithGoldHeart({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 48,
    this.goldHeartExpiresAt,
    this.fallbackColor = const Color(0xFF4F46E5),
    this.heartHaloColor,
    this.onTap,
  });

  /// HTTPS URL or base64 data URI. Either is fine — [safeImageProvider]
  /// handles both. Pass `null` (or empty) to fall back to initials.
  final String? imageUrl;

  /// Used to derive 1-2 letter initials when [imageUrl] is missing or
  /// fails to decode. Pass the user's display name unchanged.
  final String name;

  /// Avatar diameter in logical pixels. The heart badge scales relative
  /// to this (see [_heartDiameter]).
  final double size;

  /// `users/{uid}.goldHeartExpiresAt`. Pass `null` to suppress the heart
  /// even if the user otherwise qualifies — useful for read-only contexts
  /// where the field hasn't been loaded yet.
  final Timestamp? goldHeartExpiresAt;

  /// Background color for the initials fallback.
  final Color fallbackColor;

  /// Color for the white halo behind the heart. Defaults to white on
  /// light backgrounds; pass [CommunityColors.darkSurface] when this
  /// avatar sits on the dark celebration background (mockups 06, 15).
  final Color? heartHaloColor;

  /// Optional tap handler — wraps the whole stack in [InkWell] so the
  /// heart is part of the tap target.
  final VoidCallback? onTap;

  // ── Sizing ──────────────────────────────────────────────────────────────

  /// Heart badge ≈ 36% of the avatar diameter, clamped so very small
  /// avatars (e.g., 24-32px in the social-proof bar) still get a visible
  /// heart and very large ones (the 88px hero in mockup 15) don't have
  /// an oversized one.
  double get _heartDiameter => (size * 0.36).clamp(12.0, 28.0);

  /// Inner heart icon ≈ 60% of the badge.
  double get _heartIconSize => _heartDiameter * 0.62;

  /// Initials font ≈ 32% of the avatar diameter.
  double get _initialsFont => size * 0.32;

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasHeart = GoldHeartHelper.hasActiveGoldHeart(goldHeartExpiresAt);

    final stack = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildAvatar(),
          if (hasHeart)
            PositionedDirectional(
              bottom: -2,
              end: -2,
              child: _buildHeartBadge(),
            ),
        ],
      ),
    );

    if (onTap == null) return stack;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: stack,
    );
  }

  Widget _buildAvatar() {
    final image = safeImageProvider(imageUrl);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: image == null ? fallbackColor : null,
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image == null
          ? Text(
              _initialsFor(name),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: _initialsFont,
                fontFamily: CommunityType.fontFamily,
              ),
            )
          : null,
    );
  }

  Widget _buildHeartBadge() {
    final halo = heartHaloColor ?? CommunityColors.primaryWhite;

    return Container(
      width: _heartDiameter,
      height: _heartDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: halo,
        boxShadow: const [
          BoxShadow(
            color: CommunityColors.goldHeartBorder,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.favorite,
        color: CommunityColors.goldHeart,
        size: _heartIconSize,
      ),
    );
  }

  /// Returns up to two initials from the name. Handles RTL strings.
  static String _initialsFor(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.characters.take(1).toString();
    }
    final first = parts.first.characters.take(1).toString();
    final last  = parts.last.characters.take(1).toString();
    return '$first$last';
  }
}
