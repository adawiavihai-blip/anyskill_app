import 'package:flutter/material.dart';
import '../../services/location_service.dart';

/// Wraps the production-grade [LocationService] (branded pre-prompt +
/// web JS-interop fallback when geolocator silently returns null) and
/// returns a Google Maps URL that can be sent as a chat message.
///
/// Returns `null` when the user declines permission OR the browser can't
/// resolve a position. Callers should surface a snackbar in that case.
class LocationModule {
  static Future<String?> getMapUrl(BuildContext context) async {
    try {
      final pos = await LocationService.requestAndGet(context);
      if (pos == null) return null;
      return 'https://www.google.com/maps?q=${pos.latitude},${pos.longitude}';
    } catch (e) {
      debugPrint('[LocationModule] getMapUrl failed: $e');
      return null;
    }
  }
}
