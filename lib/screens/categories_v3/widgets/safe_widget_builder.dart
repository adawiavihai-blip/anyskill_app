// ignore_for_file: avoid_print
import 'package:flutter/material.dart';

/// Catches synchronous exceptions thrown inside a widget's build closure and
/// renders a small amber warning chip instead of letting the framework
/// substitute the default grey ErrorWidget (which on Flutter Web release
/// builds appears as a "big grey block" with no useful info).
///
/// Usage:
/// ```dart
/// SafeWidgetBuilder(
///   label: 'category-row',
///   builder: () => CategoryRowCard(...),
/// )
/// ```
///
/// **Important:** this only catches errors inside the immediate `builder()`
/// closure. It does NOT catch errors in the deeper widget subtree's build
/// methods — those are caught by Flutter's framework and surfaced via
/// `FlutterError.onError`. To protect a deep subtree, place SafeWidgetBuilder
/// at each leaf you want to isolate.
class SafeWidgetBuilder extends StatelessWidget {
  const SafeWidgetBuilder({
    super.key,
    required this.label,
    required this.builder,
    this.compact = false,
  });

  /// Diagnostic name for the wrapped widget (logged on failure).
  final String label;

  /// Returns the widget to render. Any synchronous exception here is caught.
  final Widget Function() builder;

  /// When true, renders a small inline pill instead of a full-width banner.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    try {
      return builder();
    } catch (e, st) {
      // ALWAYS print (also in release) — we're diagnosing a production bug.
      print('═══ [SafeWidgetBuilder FAIL] ══════════════════════════════════');
      print('  label: $label');
      print('  exception: ${e.runtimeType}: $e');
      print('  stack:\n$st');
      print('═════════════════════════════════════════════════════════════');
      return _FallbackBanner(label: label, error: '$e', compact: compact);
    }
  }
}

class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner({
    required this.label,
    required this.error,
    required this.compact,
  });
  final String label;
  final String error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final amber = const Color(0xFFB45309);
    final amberBg = const Color(0xFFFEF3C7);
    final amberBorder = const Color(0xFFFBBF24);

    if (compact) {
      return Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: amberBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: amberBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 11, color: amber),
            const SizedBox(width: 4),
            Text(
              '—',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: amber,
              ),
            ),
          ],
        ),
      );
    }

    // Full-width banner — show the actual error text so the user can see
    // what failed without opening DevTools. Selectable so they can copy-paste.
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding:
          const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amberBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '⚠ שגיאה ברינדור',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: amber,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  '$label\n$error',
                  style: TextStyle(
                    fontSize: 11,
                    color: amber.withValues(alpha: 0.85),
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
