import 'package:flutter/material.dart';

const Color _kPurple = Color(0xFF6366F1);

/// A small ⓘ icon that shows an animated overlay tooltip on tap.
///
/// Renders nothing intrusive — just a faint purple info outline icon.
/// Tapping it opens a dark pill above the icon; tapping anywhere else
/// dismisses it.
///
/// Example:
/// ```dart
/// Row(
///   mainAxisSize: MainAxisSize.min,
///   children: [
///     Text('תשלום מאובטח'),
///     const SizedBox(width: 4),
///     InfoIcon(tooltip: 'הסכום נשמר אצלנו עד שאישרת קבלת השירות'),
///   ],
/// )
/// ```
class InfoIcon extends StatelessWidget {
  const InfoIcon({
    super.key,
    required this.tooltip,
    this.color = _kPurple,
    this.size   = 16.0,
  });

  final String tooltip;
  final Color  color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showTooltip(context),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.info_outline_rounded,
          size: size,
          color: color.withValues(alpha: 0.65),
        ),
      ),
    );
  }

  void _showTooltip(BuildContext context) {
    final overlay   = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final origin    = renderBox.localToGlobal(Offset.zero);
    final iconSize  = renderBox.size;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TooltipOverlay(
        anchorOrigin: origin,
        anchorSize:   iconSize,
        text:         tooltip,
        onDismiss:    () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

// ── Overlay widget ────────────────────────────────────────────────────────────

class _TooltipOverlay extends StatefulWidget {
  const _TooltipOverlay({
    required this.anchorOrigin,
    required this.anchorSize,
    required this.text,
    required this.onDismiss,
  });

  final Offset     anchorOrigin;
  final Size       anchorSize;
  final String     text;
  final VoidCallback onDismiss;

  @override
  State<_TooltipOverlay> createState() => _TooltipOverlayState();
}

class _TooltipOverlayState extends State<_TooltipOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    const tooltipWidth = 240.0;
    const tooltipGap   = 8.0;
    final screen       = MediaQuery.of(context).size;

    // Center tooltip above the icon, clamped within screen bounds.
    var left = widget.anchorOrigin.dx
        + widget.anchorSize.width / 2
        - tooltipWidth / 2;
    left = left.clamp(12.0, screen.width - tooltipWidth - 12);

    // Place above the anchor.
    final bottom = screen.height - widget.anchorOrigin.dy + tooltipGap;

    return Stack(
      children: [
        // Transparent full-screen dismiss area.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),

        // Tooltip card.
        Positioned(
          left:   left,
          bottom: bottom,
          width:  tooltipWidth,
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B4B),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.text,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
