import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/favorites_service.dart';

/// Heart button that reflects the current user's favorites state for [providerId].
/// Streams the user's favorites list and renders a filled or outlined heart icon.
/// Tapping calls [FavoritesService.toggle] atomically.
class FavoriteButton extends StatelessWidget {
  final String providerId;
  final double size;
  final Color activeColor;

  const FavoriteButton({
    super.key,
    required this.providerId,
    this.size = 24,
    this.activeColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty || providerId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<String>>(
      stream: FavoritesService.streamIds(uid),
      builder: (context, snap) {
        final isFav = snap.data?.contains(providerId) ?? false;
        return GestureDetector(
          onTap: () => FavoritesService.toggle(providerId),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(isFav),
              color: isFav ? activeColor : Colors.white,
              size: size,
              shadows: const [
                Shadow(blurRadius: 6, color: Colors.black45),
              ],
            ),
          ),
        );
      },
    );
  }
}
