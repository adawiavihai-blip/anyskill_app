import 'package:flutter/material.dart';

/// AnySkill — AnyTasks Module Palette (v14.1.0 — UI Overhaul)
///
/// Scoped palette for the AnyTasks micro-task marketplace module ONLY.
/// Mirrors the design-system spec dropped by product. Same structure as
/// `MapPalette` (v12.9.0) — keeps the rest of the app on `Brand.*`.
abstract final class TasksPalette {
  // ── Primary (v14.2.0 spec) — green CTA / active status ─────────
  static const primaryGreen       = Color(0xFF10B981);
  static const primaryGreenDark   = Color(0xFF059669);

  // ── Dark navy (headers + primary text) ─────────────────────────
  static const darkNavy           = Color(0xFF0F172A);
  static const darkNavy2          = Color(0xFF1E293B);

  // ── Client (purple) — kept for backwards-compat w/ older widgets
  static const clientPrimary      = Color(0xFF6C63FF);
  static const clientLight        = Color(0xFFEEEDFE);
  static const clientDark         = Color(0xFF3C3489);
  static const clientPrimaryDark  = clientDark;
  static const clientPrimarySoft  = clientLight;

  // ── Provider (green) — Accept CTA ──────────────────────────────
  static const providerPrimary    = Color(0xFF2D6A4F);
  static const providerLight      = Color(0xFFE1F5EE);
  static const providerDark       = Color(0xFF085041);
  // Back-compat
  static const providerPrimaryDk  = providerDark;
  static const providerPrimarySft = providerLight;

  // ── Amber (prices, earnings, streaks) ──────────────────────────
  static const amber              = Color(0xFFB5651D);
  static const amberLight         = Color(0xFFFAEEDA);
  static const amberSoft          = amberLight; // back-compat

  // ── Coral (urgency, deadlines) ─────────────────────────────────
  static const coral              = Color(0xFFD85A30);
  static const coralLight         = Color(0xFFFAECE7);
  static const coralSoft          = coralLight; // back-compat

  // ── Escrow blue (info, security) ───────────────────────────────
  static const escrowBlue         = Color(0xFF185FA5);
  static const escrowBlueLight    = Color(0xFFE6F1FB);
  static const escrowBlueSoft     = escrowBlueLight; // back-compat

  // ── Pink ──────────────────────────────────────────────────────
  static const pink               = Color(0xFFD4537E);
  static const pinkLight          = Color(0xFFFBEAF0);

  // ── Semantic ───────────────────────────────────────────────────
  static const successGreen       = Color(0xFF0F6E56);
  static const success            = successGreen; // back-compat
  static const dangerRed          = Color(0xFFE24B4A);
  static const danger             = dangerRed; // back-compat

  // ── Text ───────────────────────────────────────────────────────
  static const textPrimary        = Color(0xFF1B1B1B);
  static const textSecondary      = Color(0xFF6B7280);
  static const textHint           = Color(0xFF9CA3AF);

  // ── Surfaces (v14.2.0 spec) ─────────────────────────────────────
  static const bgPrimary          = Color(0xFFFAFBFC);
  static const scaffoldBg         = bgPrimary; // back-compat
  static const cardWhite          = Color(0xFFFFFFFF);
  static const cardBg             = cardWhite; // back-compat
  static const borderLight        = Color(0xFFE2E8F0);
  static const border             = borderLight; // back-compat
  static const borderSoft         = Color(0xFFF0F0F0);
  // v14.2.0 text aliases
  static const textMuted          = Color(0xFF94A3B8);

  // ── Shadow (consistent across cards) ───────────────────────────
  static const cardShadow = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 2)),
  ];

  // ── Radii (v14.2.0 spec) ───────────────────────────────────────
  static const rCard    = 20.0;
  static const rButton  = 14.0;
  static const rInput   = 14.0;
  static const rPill    = 24.0;
  static const rChip    = 20.0;
  static const rAvatar  = 16.0;

  // ── Avatar palette — pick consistent color per uid via hash ────
  static const _avatarBgs = <Color>[
    clientLight,
    providerLight,
    escrowBlueLight,
    pinkLight,
    amberLight,
  ];
  static const _avatarFgs = <Color>[
    clientPrimary,
    successGreen,
    escrowBlue,
    pink,
    amber,
  ];

  /// Returns a (bg, fg) pair stable for a given key (e.g. uid or name).
  static (Color bg, Color fg) avatarColors(String key) {
    if (key.isEmpty) return (_avatarBgs[0], _avatarFgs[0]);
    final hash = key.codeUnits.fold<int>(0, (s, c) => s + c);
    final i = hash % _avatarBgs.length;
    return (_avatarBgs[i], _avatarFgs[i]);
  }
}

/// Reusable initial-circle avatar for AnyTasks screens.
class TasksAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;

  const TasksAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = TasksPalette.avatarColors(name);
    final initial = name.isEmpty ? '?' : name.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        image: (imageUrl != null && imageUrl!.startsWith('http'))
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: (imageUrl != null && imageUrl!.startsWith('http'))
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: fg,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }
}
