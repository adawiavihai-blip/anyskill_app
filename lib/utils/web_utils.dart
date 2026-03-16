// Platform-agnostic web utilities.
// On web → delegates to dart:html (see web_utils_html.dart).
// On native (Android / iOS / desktop) → no-ops (see web_utils_stub.dart).
// Import THIS file everywhere.
export 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils_html.dart';
