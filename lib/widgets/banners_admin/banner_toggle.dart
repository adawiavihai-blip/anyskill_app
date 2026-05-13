import 'package:flutter/material.dart';

import 'design_tokens.dart';

typedef BannerToggleAsyncCallback = Future<void> Function(bool newValue);

/// A compact 26×14 toggle switch with optimistic-update semantics.
///
/// On tap:
///  1. The visual state flips **immediately** (optimistic).
///  2. [onChanged] is awaited in the background.
///  3. On success → the visual stays and defers to the next parent
///     rebuild (which should pass the new [value]).
///  4. On failure → the visual reverts + a Hebrew SnackBar is shown.
///
/// This matches the spec's "feels instant, no spinner" table behaviour.
/// If the caller needs explicit feedback, they should return a Future
/// that throws on failure — the default SnackBar message is
/// "לא הצלחנו לעדכן. נסה שוב." but a [onErrorMessage] builder can
/// customize it per call site.
class BannerToggle extends StatefulWidget {
  const BannerToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.onErrorMessage,
  });

  final bool value;
  final BannerToggleAsyncCallback onChanged;
  final bool enabled;
  final String Function(Object error)? onErrorMessage;

  @override
  State<BannerToggle> createState() => _BannerToggleState();
}

class _BannerToggleState extends State<BannerToggle> {
  /// Non-null while an optimistic update is in flight.
  bool? _optimistic;

  /// True once a failure has rolled us back — used to suppress further
  /// rapid-fire taps until the user acknowledges the snackbar.
  bool _inFlight = false;

  bool get _displayValue => _optimistic ?? widget.value;

  Future<void> _handleTap() async {
    if (!widget.enabled || _inFlight) return;
    final next = !_displayValue;

    setState(() {
      _optimistic = next;
      _inFlight = true;
    });

    try {
      await widget.onChanged(next);
      // Success — clear the optimistic override, next rebuild from
      // parent will reflect the persisted [value].
      if (!mounted) return;
      setState(() {
        _optimistic = null;
        _inFlight = false;
      });
    } catch (err) {
      if (!mounted) return;
      // Failure — roll back.
      setState(() {
        _optimistic = null;
        _inFlight = false;
      });
      final msg = widget.onErrorMessage?.call(err) ??
          'לא הצלחנו לעדכן. נסה שוב.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _displayValue;
    final trackColor = on
        ? BannersTokens.accent
        : const Color(0xFFE4E4E7); // gray-200
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        child: AnimatedContainer(
          duration: BannersTokens.toggleDuration,
          curve: Curves.easeOut,
          width: 26,
          height: 14,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: widget.enabled
                ? trackColor
                : trackColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: BannersTokens.toggleDuration,
                curve: Curves.easeOut,
                left: on ? 12 : 0,
                top: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
