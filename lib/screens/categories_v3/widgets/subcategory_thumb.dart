import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';

/// One sub-category thumb in the inline grid (spec §7.4).
/// Square aspect, image fills, edit pencil top-start, name + provider count below.
class SubcategoryThumb extends StatelessWidget {
  const SubcategoryThumb({
    super.key,
    required this.sub,
    this.onTap,
    this.onEdit,
  });

  final CategoryV3Model sub;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final hasImage = (sub.imageUrl ?? '').isNotEmpty || sub.iconUrl.isNotEmpty;
    final imageSrc = (sub.imageUrl?.isNotEmpty ?? false)
        ? sub.imageUrl!
        : sub.iconUrl;
    final providers = sub.analytics?.activeProviders ?? 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image area (1:1)
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10),
                      ),
                      child: hasImage
                          ? _SafeImage(url: imageSrc, fallbackName: sub.name)
                          : _NoImageBlock(name: sub.name),
                    ),
                  ),
                  if (onEdit != null)
                    PositionedDirectional(
                      top: 4,
                      start: 4,
                      child: _IconChip(
                        icon: Icons.edit_outlined,
                        onTap: onEdit!,
                      ),
                    ),
                  if (!hasImage)
                    const PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: _WarningDot(),
                    ),
                ],
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    providers > 0 ? '$providers ספקים' : 'אין ספקים',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: providers > 0
                          ? const Color(0xFF6B7280)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+ הוסף" placeholder card at the end of the sub-category grid.
class AddSubcategoryThumb extends StatelessWidget {
  const AddSubcategoryThumb({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: DottedBorderBox(
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 28, color: Color(0xFF6366F1)),
            SizedBox(height: 4),
            Text(
              'הוסף',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6366F1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Center(child: child),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final path = Path()..addRRect(rect);
    final dashPath = Path();
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        dashPath.addPath(
          metric.extractPath(dist, dist + dashWidth),
          Offset.zero,
        );
        dist += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

class _SafeImage extends StatelessWidget {
  const _SafeImage({required this.url, required this.fallbackName});
  final String url;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _NoImageBlock(name: fallbackName),
    );
  }
}

class _NoImageBlock extends StatelessWidget {
  const _NoImageBlock({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first : '?';
    return Container(
      color: const Color(0xFFEFF6FF),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Color(0xFF3B82F6),
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, size: 13, color: const Color(0xFF1A1A2E)),
      ),
    );
  }
}

class _WarningDot extends StatelessWidget {
  const _WarningDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: Color(0xFFF59E0B),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.priority_high_rounded,
          size: 10, color: Colors.white),
    );
  }
}
