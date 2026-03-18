import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../utils/price_formatter.dart';
import '../../expert_profile_screen.dart';
import '../../../l10n/app_localizations.dart'; // ignore: unused_import — partial i18n pass

class ExpertCard extends StatelessWidget {
  final String  expertId;
  final String  name;
  final String  bio;
  final double  rating;
  final dynamic price;          // int | double | String | null
  final String  imageUrl;
  final bool    hasActiveStory; // shows a gradient ring when true

  const ExpertCard({
    super.key,
    required this.expertId,
    required this.name,
    required this.bio,
    required this.rating,
    required this.price,
    required this.imageUrl,
    this.hasActiveStory = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExpertProfileScreen(expertId: expertId, expertName: name),
        ),
      ),
      child: Padding(
      padding: const EdgeInsets.only(bottom: 28), // רווח מעט גדול יותר לנשימה
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. תמונה עם הגנות ועיצוב Airbnb
          Stack(
            children: [
              // Story ring — wraps the entire card image with a gradient border
              if (hasActiveStory)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        painter: _StoryRingPainter(),
                      ),
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imageUrl.isEmpty
                    ? _ProfilePlaceholder(height: 240)
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 240,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: 240,
                          width: double.infinity,
                          color: Colors.grey[50],
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) =>
                            _ProfilePlaceholder(height: 240),
                      ),
              ),
              // Story badge chip
              if (hasActiveStory)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 12),
                        SizedBox(width: 3),
                        Text('סיפור חי',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              // Wishlist button
              const Positioned(
                top: 12,
                right: 12,
                child: Icon(Icons.favorite_border, color: Colors.white, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. שורת כותרת ודירוג
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(
                    rating.toStringAsFixed(1), // QA: מוודא ספרה אחת אחרי הנקודה
                    style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),

          // 3. תיאור (Bio)
          Text(
            bio,
            style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.4),
            maxLines: 1,
            overflow: TextOverflow.ellipsis, // QA: מונע מהטקסט לגלוש ולשבור את העיצוב
          ),

          const SizedBox(height: 6),

          // 4. מחיר מודגש — מעוצב על-ידי formatPriceDisplay
          Text(
            formatPriceDisplay(price),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ── Profile image placeholder ─────────────────────────────────────────────────
class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        color: Colors.grey[100],
        child: Icon(Icons.person, size: 50, color: Colors.grey[400]),
      );
}

// ── Story ring painter — gradient border on top of the card image ─────────────
class _StoryRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const strokeW = 3.5;
    final rect  = Rect.fromLTWH(strokeW / 2, strokeW / 2,
        size.width - strokeW, size.height - strokeW);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    final paint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..shader      = const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFFF59E0B)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_StoryRingPainter old) => false;
}