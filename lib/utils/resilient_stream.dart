import 'dart:async';
import 'package:flutter/material.dart';

/// A StreamBuilder wrapper that self-heals on Firestore errors and timeouts.
///
/// Usage:
/// ```dart
/// ResilientStreamBuilder<QuerySnapshot>(
///   stream: FirebaseFirestore.instance.collection('banners').snapshots(),
///   timeoutSeconds: 4,
///   builder: (context, docs) => _buildBannerList(docs),
///   emptyBuilder: (context) => Text('No banners'),
/// )
/// ```
class ResilientStreamBuilder<T> extends StatefulWidget {
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context)? emptyBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final int timeoutSeconds;

  const ResilientStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.emptyBuilder,
    this.errorBuilder,
    this.timeoutSeconds = 6,
  });

  @override
  State<ResilientStreamBuilder<T>> createState() => _ResilientStreamBuilderState<T>();
}

class _ResilientStreamBuilderState<T> extends State<ResilientStreamBuilder<T>> {
  bool _timedOut = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(seconds: widget.timeoutSeconds), () {
      if (mounted && !_timedOut) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: widget.stream,
      builder: (context, snapshot) {
        // Error state — show error UI, never crash
        if (snapshot.hasError) {
          debugPrint('[ResilientStream] Error: ${snapshot.error}');
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, snapshot.error!);
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 40,
                      color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('שגיאה בטעינת הנתונים',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                ],
              ),
            ),
          );
        }

        // Waiting state — show shimmer unless timed out
        if (!snapshot.hasData && !_timedOut) {
          return const Center(child: CircularProgressIndicator());
        }

        // Timed out with no data — show empty state
        if (!snapshot.hasData) {
          _timer?.cancel();
          if (widget.emptyBuilder != null) {
            return widget.emptyBuilder!(context);
          }
          return const SizedBox.shrink();
        }

        // Data arrived — cancel timer and render
        _timer?.cancel();
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}
