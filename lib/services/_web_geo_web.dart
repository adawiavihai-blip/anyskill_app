// Web-only implementation. Calls `navigator.geolocation.getCurrentPosition`
// directly via JS interop, completely bypassing the geolocator package.
//
// Why bypass: geolocator on Flutter Web has known issues where
// `getCurrentPosition` silently returns null (or hangs past its own
// timeout) without a JS-level error surfacing back to Dart. When that
// happens, this fallback talks straight to the browser and lets us see
// the real `GeolocationPositionError` (PERMISSION_DENIED / POSITION_UNAVAILABLE
// / TIMEOUT) so we can both log it AND still get a position when the
// browser actually has it.
import 'dart:async';
import 'dart:js_interop';
import 'package:geolocator/geolocator.dart';
import 'package:web/web.dart' as web;

Future<Position?> webGetCurrentPositionDirect({
  Duration timeout = const Duration(seconds: 12),
}) async {
  // ignore: avoid_print
  print('[WebGeo] webGetCurrentPositionDirect: ENTRY (timeout ${timeout.inSeconds}s)');

  final geolocation = web.window.navigator.geolocation;

  final completer = Completer<Position?>();
  Timer? timeoutTimer;

  final successCb = ((web.GeolocationPosition pos) {
    if (completer.isCompleted) return;
    timeoutTimer?.cancel();
    try {
      final c = pos.coords;
      // ignore: avoid_print
      print('[WebGeo] success: lat=${c.latitude} lng=${c.longitude} acc=${c.accuracy}');
      completer.complete(Position(
        latitude:        c.latitude,
        longitude:       c.longitude,
        timestamp:       DateTime.fromMillisecondsSinceEpoch(pos.timestamp.toInt()),
        accuracy:        c.accuracy,
        altitude:        c.altitude ?? 0,
        altitudeAccuracy: c.altitudeAccuracy ?? 0,
        heading:         c.heading ?? 0,
        headingAccuracy: 0,
        speed:           c.speed ?? 0,
        speedAccuracy:   0,
      ));
    } catch (e) {
      // ignore: avoid_print
      print('[WebGeo] success-callback threw while building Position: $e');
      completer.complete(null);
    }
  }).toJS;

  final errorCb = ((web.GeolocationPositionError err) {
    if (completer.isCompleted) return;
    timeoutTimer?.cancel();
    final reason = switch (err.code) {
      1 => 'PERMISSION_DENIED',
      2 => 'POSITION_UNAVAILABLE',
      3 => 'TIMEOUT',
      _ => 'UNKNOWN(${err.code})',
    };
    // ignore: avoid_print
    print('[WebGeo] error: $reason — ${err.message}');
    completer.complete(null);
  }).toJS;

  timeoutTimer = Timer(timeout, () {
    if (completer.isCompleted) return;
    // ignore: avoid_print
    print('[WebGeo] watchdog timeout after ${timeout.inSeconds}s — completing null');
    completer.complete(null);
  });

  try {
    // PositionOptions: enableHighAccuracy off (battery + faster on web),
    // browser-side timeout slightly less than our watchdog so the browser
    // surfaces a TIMEOUT error before we cut it off.
    final options = web.PositionOptions(
      enableHighAccuracy: false,
      timeout: (timeout.inMilliseconds - 1000).clamp(2000, 30000),
      maximumAge: 60000, // accept a 60s-old cached fix
    );
    geolocation.getCurrentPosition(successCb, errorCb, options);
  } catch (e) {
    // ignore: avoid_print
    print('[WebGeo] getCurrentPosition call threw synchronously: $e');
    timeoutTimer.cancel();
    if (!completer.isCompleted) completer.complete(null);
  }

  return completer.future;
}
