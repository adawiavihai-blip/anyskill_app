// Mapbox configuration for AnySkill — single source of truth for the
// Wolt-style raster tile renderer used everywhere via [WoltTileLayer].
//
// CLAUDE.md path: `Path B` integration (raster tiles via flutter_map),
// chosen because mapbox_maps_flutter v2.5 has no Flutter Web support
// and AnySkill is a web-first PWA.
//
// The Mapbox access token is NOT committed to git. A `pk.*` token is
// PUBLIC by design (it ships inside the client bundle), but GitHub
// push-protection blocks it and keeping it out of the repo is cleaner.
// It is injected at build time:
//
//   flutter build web --release --dart-define-from-file=mapbox_env.json
//
// `mapbox_env.json` is gitignored — copy `mapbox_env.example.json` and
// paste the real `pk.*` token. For actual abuse protection, restrict the
// token by URL pattern (web) + bundle ID (native) in Mapbox Studio.
class MapboxConfig {
  MapboxConfig._();

  static const String _defaultUsername = 'anyskill';
  static const String _defaultStyleId = 'cmoy53o3u000901qvcalw8k3f';

  /// Public access token — injected at build time via
  /// `--dart-define-from-file=mapbox_env.json` (see the class comment).
  /// Empty if the build forgot the flag, which fails loudly (blank map)
  /// rather than silently.
  static const String accessToken = String.fromEnvironment('MAPBOX_TOKEN');

  /// Mapbox username that owns the style.
  static const String username = String.fromEnvironment(
    'MAPBOX_USERNAME',
    defaultValue: _defaultUsername,
  );

  /// Style ID published in Mapbox Studio (Wolt-style faded look,
  /// hidden POIs).
  static const String styleId = String.fromEnvironment(
    'MAPBOX_STYLE_ID',
    defaultValue: _defaultStyleId,
  );

  /// Default label language. Israeli market = Hebrew.
  ///
  /// The `language` query parameter is honoured by Mapbox vector tiles
  /// natively. For raster tiles (what we render here), labels are
  /// primarily controlled by the style configuration in Mapbox Studio
  /// — but the parameter is harmless when ignored. Keeping it ensures
  /// future-compat if the style is republished with localization-on.
  static const String defaultLanguage = 'he';

  /// Build a flutter_map-compatible tile URL template.
  ///
  /// `{z}/{x}/{y}` and `{r}` (retina suffix → `''` or `'@2x'`) are
  /// resolved by `TileLayer` itself. Everything else (token, style,
  /// language) is baked in at build time by this method.
  static String buildTileUrlTemplate({String? language}) {
    final lang = language ?? defaultLanguage;
    return 'https://api.mapbox.com/styles/v1/$username/$styleId'
        '/tiles/256/{z}/{x}/{y}{r}'
        '?access_token=$accessToken'
        '&language=$lang';
  }
}
