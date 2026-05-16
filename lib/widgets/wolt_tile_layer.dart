import 'dart:async';

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
/// ## The "map is grey until you touch it" fix (web)
///
/// On Flutter web, `flutter_map` frequently leaves the map a flat grey/
/// cream box until the user's FIRST pointer interaction — the tiles are
/// fetched + decoded but the completion repaint is never composited, so
/// nothing shows until a gesture forces a frame. To make the map the
/// first thing the user sees WITHOUT touching anything, the tile layer is
/// wrapped in [_WoltTileHost]: a tiny stateful host that fires a handful
/// of `setState` "kicks" across the first few seconds after mount. Each
/// kick re-runs the `TileLayer` build → re-evaluates visible tiles and
/// repaints already-cached ones (no re-download — `flutter_map` caches
/// `TileImage`s by coordinate). It also uses [TileDisplay.instantaneous]
/// so a decoded tile paints immediately instead of fading in.
///
/// `forContext` / `build` therefore return `Widget` (not `TileLayer`).
/// Every call site drops the result straight into a `FlutterMap.children`
/// list, so the wider return type is transparent.
///
/// ## Tile source priority (the "no grey box ever" contract)
///
/// 1. **Primary — CartoDB Voyager** (default).
///    * URL: `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png`
///    * Free, no API token, no URL allow-list, 4 sub-domains
///      (`a`/`b`/`c`/`d`) so we never hit a per-host browser
///      connection limit.
///    * CSP already allows `*.basemaps.cartocdn.com`
///      (web/index.html §connect-src).
///
/// 2. **Fallback — OpenStreetMap default tiles**.
///    * Used by flutter_map automatically when the primary URL returns
///      404 / 429 / other network error.
///
/// 3. **Skeleton — soft Wolt-cream underlay** (`#F4F1EC`).
///    * Painted under every tile via `tileBuilder` so the moment between
///      "tile requested" and "tile painted" reads as polished neutral.
///
/// ## Mapbox opt-in
///
/// The Mapbox Studio Wolt-style raster is still wired up via
/// [MapboxConfig]. Build with `--dart-define=USE_MAPBOX=true` to use it.
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

  /// Map tile layer widget for the AnySkill Wolt look, auto-detecting
  /// retina from [context]. Returns a [Widget] (see class docs) — use it
  /// directly inside a `FlutterMap.children` list.
  static Widget forContext(
    BuildContext context, {
    String? language,
    double maxZoom = 22,
  }) {
    final retina = MediaQuery.of(context).devicePixelRatio > 1.5;
    return _WoltTileHost(
      retinaMode: retina,
      language: language,
      maxZoom: maxZoom,
    );
  }

  /// Map tile layer widget with an explicit retina flag — for places
  /// where context isn't available or the caller already computed it.
  static Widget build({
    bool retinaMode = false,
    String? language,
    double maxZoom = 22,
  }) {
    return _WoltTileHost(
      retinaMode: retinaMode,
      language: language,
      maxZoom: maxZoom,
    );
  }

  /// Builds the raw [TileLayer]. Internal — call [forContext] / [build].
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
      // Paint each tile the instant it decodes — no fade-in. The fade
      // animation depends on a ticker that web sometimes never advances,
      // which is one of the ways the map ended up looking grey.
      tileDisplay: const TileDisplay.instantaneous(),
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
      tileDisplay: const TileDisplay.instantaneous(),
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

/// Stateful host that wraps the raw [TileLayer] and — on web — nudges
/// `flutter_map` to actually paint the tiles without waiting for a user
/// gesture. See [WoltTileLayer] class docs for the why.
class _WoltTileHost extends StatefulWidget {
  const _WoltTileHost({
    required this.retinaMode,
    required this.language,
    required this.maxZoom,
  });

  final bool retinaMode;
  final String? language;
  final double maxZoom;

  @override
  State<_WoltTileHost> createState() => _WoltTileHostState();
}

class _WoltTileHostState extends State<_WoltTileHost> {
  // Staged "kick" schedule (ms after mount). Each kick fires an empty
  // setState → the child TileLayer rebuilds → `_TileLayerState.build`
  // re-evaluates visible tiles and repaints already-cached ones, forcing
  // a real composite. The window is generous enough to cover slow tile
  // fetches; after the last kick the map is fully painted.
  static const List<int> _kickScheduleMs = [150, 400, 800, 1500, 2500, 4000];

  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    // Native (iOS/Android) flutter_map paints tiles fine on first frame —
    // the grey-until-touch bug is web-only, so only kick there.
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
      for (final ms in _kickScheduleMs) {
        _timers.add(Timer(Duration(milliseconds: ms), _kick));
      }
    }
  }

  void _kick() {
    if (!mounted) return;
    // Empty setState — the goal is purely to dirty this element so the
    // TileLayer subtree below rebuilds + repaints. No key change, so
    // flutter_map keeps its tile cache (no re-download, no flicker).
    setState(() {});
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WoltTileLayer._build(
      retinaMode: widget.retinaMode,
      language: widget.language,
      maxZoom: widget.maxZoom,
    );
  }
}
