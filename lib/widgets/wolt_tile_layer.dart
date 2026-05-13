import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/mapbox_config.dart';

/// Wolt-style raster tile layer for AnySkill.
///
/// Drop-in replacement for any direct `TileLayer(...)` call. Every map in
/// the app — discovery, booking, tracking, address pickers — routes
/// through here, so visual + reliability behaviour is controlled in
/// exactly one place.
///
/// ## Tile source priority (the "no grey box ever" contract)
///
/// 1. **Primary — CartoDB Voyager** (default).
///    * URL: `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png`
///    * Free, no API token, no URL allow-list, 4 sub-domains
///      (`a`/`b`/`c`/`d`) so we never hit a per-host browser
///      connection limit.
///    * Visual style is intentionally close to Wolt: soft cream land,
///      muted greens, no POI clutter at low zoom, retina @2x supported.
///    * CSP already allows `*.basemaps.cartocdn.com`
///      (web/index.html §connect-src).
///
/// 2. **Fallback — OpenStreetMap default tiles**.
///    * Used by flutter_map automatically when the primary URL returns
///      404 / 429 / other network error. The map keeps painting; only
///      the visual style briefly changes for that tile.
///
/// 3. **Skeleton — soft Wolt-cream underlay** (`#F4F1EC`).
///    * Painted under every tile via `tileBuilder` so the moment between
///      "tile requested" and "tile painted" reads as polished neutral,
///      never stark grey from the container background.
///
/// ## Mapbox opt-in
///
/// The Mapbox Studio Wolt-style raster is still wired up via
/// [MapboxConfig]. To use it instead of CartoDB, build with
/// `--dart-define=USE_MAPBOX=true`. We keep it as opt-in (not default)
/// because in practice the public token has periodically hit
/// URL-restriction / quota issues that rendered as blank tiles on some
/// domains — the exact symptom CartoDB's no-token setup avoids.
///
/// ## Attribution
///
/// CartoDB's free tier requires "© OpenStreetMap contributors © CARTO"
/// attribution. flutter_map renders a small `Attribution` control by
/// default; if a caller hides controls, add a `RichAttributionWidget`
/// (or static text) to the map's `children:` list.
///
/// ## Errors
///
/// Tile fetch errors are logged via [debugPrint] in debug mode only.
/// Production builds stay silent — transient tile flakiness is not a
/// Sentry-worthy event.
class WoltTileLayer {
  WoltTileLayer._();

  /// Compile-time opt-in to use Mapbox raster tiles instead of CartoDB.
  /// Build with `flutter build web --dart-define=USE_MAPBOX=true`.
  static const bool useMapbox = bool.fromEnvironment(
    'USE_MAPBOX',
    defaultValue: false,
  );

  /// CartoDB Voyager raster — primary tile source. Retina (`{r}` → `@2x`)
  /// is handled by `TileLayer` itself when `retinaMode: true`.
  static const String _voyagerUrlTemplate =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

  static const List<String> _voyagerSubdomains = ['a', 'b', 'c', 'd'];

  /// Plain OSM default — fallback when the primary URL fails.
  static const String _osmFallbackUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Build a `TileLayer` configured for the AnySkill Wolt look,
  /// auto-detecting retina from [context]. Call sites that already
  /// have `BuildContext` should prefer this overload.
  static TileLayer forContext(
    BuildContext context, {
    String? language,
    double maxZoom = 22,
  }) {
    final retina = MediaQuery.of(context).devicePixelRatio > 1.5;
    return _build(
      retinaMode: retina,
      language: language,
      maxZoom: maxZoom,
    );
  }

  /// Build a `TileLayer` with an explicit retina flag — for places
  /// where context isn't available or the caller already computed it.
  static TileLayer build({
    bool retinaMode = false,
    String? language,
    double maxZoom = 22,
  }) {
    return _build(
      retinaMode: retinaMode,
      language: language,
      maxZoom: maxZoom,
    );
  }

  static TileLayer _build({
    required bool retinaMode,
    required String? language,
    required double maxZoom,
  }) {
    if (useMapbox) {
      return _buildMapbox(
        retinaMode: retinaMode,
        language: language,
        maxZoom: maxZoom,
      );
    }
    return _buildCartoDb(retinaMode: retinaMode, maxZoom: maxZoom);
  }

  static TileLayer _buildCartoDb({
    required bool retinaMode,
    required double maxZoom,
  }) {
    return TileLayer(
      urlTemplate: _voyagerUrlTemplate,
      subdomains: _voyagerSubdomains,
      fallbackUrl: _osmFallbackUrl,
      retinaMode: retinaMode,
      userAgentPackageName: 'com.anyskill.app',
      maxZoom: maxZoom,
      tileBuilder: _tileSkeletonBuilder,
      errorTileCallback: _logTileError,
    );
  }

  static TileLayer _buildMapbox({
    required bool retinaMode,
    required String? language,
    required double maxZoom,
  }) {
    return TileLayer(
      urlTemplate: MapboxConfig.buildTileUrlTemplate(language: language),
      fallbackUrl: _osmFallbackUrl,
      retinaMode: retinaMode,
      userAgentPackageName: 'com.anyskill.app',
      maxZoom: maxZoom,
      tileBuilder: _tileSkeletonBuilder,
      errorTileCallback: _logTileError,
    );
  }

  /// Soft Wolt-cream underlay below every tile so brief loading frames
  /// look intentional, not broken. Once the tile image lands, it paints
  /// on top and the underlay disappears.
  static Widget _tileSkeletonBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFF4F1EC)),
        tileWidget,
      ],
    );
  }

  static void _logTileError(
    TileImage tile,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (kDebugMode) {
      debugPrint('[WoltTileLayer] tile error '
          'z=${tile.coordinates.z} x=${tile.coordinates.x} '
          'y=${tile.coordinates.y}: $error');
    }
  }
}
