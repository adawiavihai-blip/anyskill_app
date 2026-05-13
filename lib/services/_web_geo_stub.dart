// Non-web stub. The real implementation lives in `_web_geo_web.dart` and
// is selected via conditional import in `location_service.dart`.
import 'package:geolocator/geolocator.dart';

/// On non-web platforms there is no JS `navigator.geolocation` to call,
/// so this stub returns null immediately. The geolocator package handles
/// native platforms correctly via the OS APIs.
Future<Position?> webGetCurrentPositionDirect({
  Duration timeout = const Duration(seconds: 12),
}) async {
  return null;
}
