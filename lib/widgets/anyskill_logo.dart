import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── AnySkill Branding Widgets ─────────────────────────────────────────────────
//
// AnySkillLoadingIndicator  — pulsing logo, replaces CircularProgressIndicator.
//                             Reads optional custom URL from system_settings/global.
// AnySkillBrandIcon         — small static icon for AppBar / search bar.
//                             Simple local asset, no Firestore dependency.
// ─────────────────────────────────────────────────────────────────────────────

/// Animated pulse logo shown during loading states.
/// Falls back to bundled GIF; can be overridden by setting `logoUrl`
/// in Firestore `system_settings/global` via the Admin Brand Assets tab.
class AnySkillLoadingIndicator extends StatefulWidget {
  final double size;
  const AnySkillLoadingIndicator({super.key, this.size = 100});

  @override
  State<AnySkillLoadingIndicator> createState() =>
      _AnySkillLoadingIndicatorState();
}

class _AnySkillLoadingIndicatorState extends State<AnySkillLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _stream = FirebaseFirestore.instance
        .collection('system_settings')
        .doc('global')
        .snapshots();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final data    = snap.data?.data() ?? {};
        final logoUrl = (data['logoUrl'] as String?) ?? '';
        return ScaleTransition(
          scale: _anim,
          child: logoUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl:    logoUrl,
                  width:       widget.size,
                  height:      widget.size,
                  fit:         BoxFit.contain,
                  placeholder: (_, __) => _localGif(),
                  errorWidget: (_, __, ___) => _localGif(),
                )
              : _localGif(),
        );
      },
    );
  }

  Widget _localGif() => Image.asset(
        'assets/images/NEW_LOGO1.png.png',
        width:  widget.size,
        height: widget.size,
        fit:    BoxFit.contain,
      );
}

/// Small static brand icon — used in AppBar, search bar, profile sub-screens.
/// Pure local asset; no network/Firestore dependency so it renders instantly.
class AnySkillBrandIcon extends StatelessWidget {
  final double size;
  const AnySkillBrandIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/NEW_LOGO1.png.png',
        width:  size,
        height: size,
        fit:    BoxFit.contain,
      );
}
