/// Mockup 13 — Interactive map of open community requests.
///
/// **Implementation:** uses `flutter_map` (already in pubspec) with the
/// CartoDB Voyager tiles same as
/// `lib/widgets/providers_map_view.dart`. No new dependencies.
///
/// **Pins:** each open `community_requests` doc with a `location`
/// (GeoPoint) renders as a small white pill showing the category +
/// optional urgency dot. Tapping a pin opens a bottom card with the
/// request preview + a "הצג פרטים" CTA that pushes
/// [RequestDetailScreen].
///
/// **Header:** back arrow + "בקשות באזור" + "רשימה" toggle (pops back
/// to [CommunityHubScreenV2]).
///
/// **Phase E scope:** no real geo filter yet (the "קרוב אליי" pill is
/// purely informational). Phase F may wire it to the user's location
/// via the existing [LocationService]. For now we center on Tel Aviv
/// and show all open requests with a non-null location.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/community_hub_service.dart';
import '../../services/location_service.dart';
import '../../theme/community_theme.dart';
import '../../widgets/community/pill_chip.dart';
import '../../widgets/wolt_tile_layer.dart';
import 'request_detail_screen.dart';

class CommunityMapViewScreen extends StatefulWidget {
  const CommunityMapViewScreen({super.key});

  @override
  State<CommunityMapViewScreen> createState() => _CommunityMapViewScreenState();
}

class _CommunityMapViewScreenState extends State<CommunityMapViewScreen> {
  static const LatLng _defaultCenter = LatLng(32.0853, 34.7818); // Tel Aviv

  final _mapCtrl = MapController();
  String? _selectedRequestId;
  Map<String, dynamic>? _selectedRequestData;

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  /// Phase H QA fix: the my-location FAB now actually goes to the
  /// user's real location (via [LocationService.requestAndGet]) instead
  /// of just resetting the map to Tel Aviv. Falls back to the default
  /// center if permission is denied or geolocation fails.
  Future<void> _goToMyLocation() async {
    final pos = await LocationService.requestAndGet(context);
    if (!mounted) return;
    if (pos == null) {
      _mapCtrl.move(_defaultCenter, 13);
      return;
    }
    _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 14);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.primaryWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onListPressed: () => Navigator.of(context).maybePop()),
            Expanded(child: _buildMap()),
            if (_selectedRequestId != null && _selectedRequestData != null)
              _BottomCard(
                requestId: _selectedRequestId!,
                data: _selectedRequestData!,
                onClear: () => setState(() {
                  _selectedRequestId = null;
                  _selectedRequestData = null;
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('community_requests')
          .where('status', isEqualTo: 'open')
          .limit(80)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const _MapError();
        final docs = snap.data?.docs ?? [];
        // Filter to docs with a real location.
        final withLoc = docs.where((d) {
          final m = (d.data() as Map<String, dynamic>?) ?? const {};
          return m['location'] is GeoPoint;
        }).toList();

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: const MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: 13,
                minZoom: 6,
                maxZoom: 18,
              ),
              children: [
                WoltTileLayer.forContext(context, maxZoom: 18),
                MarkerLayer(
                  markers: [
                    for (final d in withLoc)
                      _markerFor(d.id,
                          (d.data() as Map<String, dynamic>?) ?? const {}),
                  ],
                ),
              ],
            ),

            // Top filter chips (overlay)
            const Positioned(
              top: 12, left: 12, right: 12,
              child: _FilterChips(),
            ),

            // Bottom-end my-location FAB
            PositionedDirectional(
              bottom: 16, end: 14,
              child: _MyLocationButton(onTap: _goToMyLocation),
            ),

            // Empty state when feed has no geo-tagged requests.
            // Phase H QA fix: also gate on `snap.hasData` so we don't
            // flash "no requests" during the initial connecting frame.
            if (snap.hasData && withLoc.isEmpty)
              const Positioned(
                bottom: 84, left: 0, right: 0,
                child: Center(child: _EmptyHint()),
              ),
          ],
        );
      },
    );
  }

  Marker _markerFor(String id, Map<String, dynamic> data) {
    final loc = data['location'] as GeoPoint;
    final urgency = data['urgency'] as String? ?? 'normal';
    final cat = data['category'] as String? ?? '';
    final isHigh = urgency == 'high';
    final isSelected = id == _selectedRequestId;
    return Marker(
      point: LatLng(loc.latitude, loc.longitude),
      width: 130,
      height: 30,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedRequestId = id;
          _selectedRequestData = data;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? CommunityColors.primaryBlack
                : CommunityColors.primaryWhite,
            border: Border.all(
              color: isSelected
                  ? CommunityColors.primaryBlack
                  : const Color(0x1A000000),
              width: 0.5,
            ),
            borderRadius: const BorderRadius.all(CommunityRadius.pill),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isHigh)
                Container(
                  width: 6, height: 6,
                  margin: const EdgeInsetsDirectional.only(end: 5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: CommunityColors.danger,
                  ),
                ),
              Flexible(
                child: Text(
                  isHigh
                      ? '${_categoryLabel(cat)} · דחוף'
                      : _categoryLabel(cat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    fontWeight: isHigh
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: isSelected
                        ? CommunityColors.primaryWhite
                        : CommunityColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _categoryLabel(String id) {
    final found = CommunityHubService.helpCategories.firstWhere(
      (c) => c['id'] == id,
      orElse: () => const {'label': 'בקשה'},
    );
    return found['label'] as String;
  }
}

// ── Header ────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.onListPressed});
  final VoidCallback onListPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
      decoration: const BoxDecoration(
        color: CommunityColors.primaryWhite,
        border: Border(
          bottom: BorderSide(color: CommunityColors.borderSofter, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            color: CommunityColors.textPrimary,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'בקשות באזור',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  color: CommunityColors.textPrimary,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onListPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: CommunityColors.surface,
                border: Border.all(
                    color: const Color(0x14000000), width: 0.5),
                borderRadius:
                    const BorderRadius.all(CommunityRadius.pill),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_rounded,
                      size: 12, color: CommunityColors.textPrimary),
                  SizedBox(width: 4),
                  Text(
                    'רשימה',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 11,
                      color: CommunityColors.textPrimary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top filter chips (placeholder — Phase F may wire) ─────────────────────
class _FilterChips extends StatelessWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _shadowedPill(child: const CommunityPillChip(
            label: 'בקשות באזור',
            selected: true,
          )),
          const SizedBox(width: 6),
          _shadowedPill(child: const CommunityPillChip(label: 'קטגוריה')),
          const SizedBox(width: 6),
          _shadowedPill(child: const CommunityPillChip(label: 'דחיפות')),
        ],
      ),
    );
  }

  Widget _shadowedPill({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        borderRadius: BorderRadius.all(CommunityRadius.pill),
      ),
      child: ColoredBox(
        color: CommunityColors.primaryWhite,
        child: child,
      ),
    );
  }
}

// ── My-location FAB ───────────────────────────────────────────────────────
class _MyLocationButton extends StatelessWidget {
  const _MyLocationButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CommunityColors.primaryWhite,
      elevation: 0,
      borderRadius: const BorderRadius.all(CommunityRadius.field),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(CommunityRadius.field),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            border:
                Border.all(color: const Color(0x14000000), width: 0.5),
            borderRadius:
                const BorderRadius.all(CommunityRadius.field),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.my_location_rounded,
            size: 18,
            color: CommunityColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Bottom sticky card showing the selected request ──────────────────────
class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.requestId,
    required this.data,
    required this.onClear,
  });
  final String requestId;
  final Map<String, dynamic> data;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'בקשת התנדבות';
    final desc = data['description'] as String? ?? '';
    final urgency = data['urgency'] as String? ?? 'normal';
    final reqType = data['requesterType'] as String? ?? '';
    final reqName = data['isAnonymous'] == true
        ? 'אנונימי'
        : (data['requesterName'] as String? ?? 'הפונה');

    return Container(
      decoration: const BoxDecoration(
        color: CommunityColors.primaryWhite,
        border: Border(
          top: BorderSide(color: CommunityColors.borderSubtle, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (urgency == 'high') ...[
                _UrgencyBadge(),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: CommunityColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: CommunityType.title15),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CommunityType.body13,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$reqName${reqType.isEmpty ? '' : ' · ${_typeLabel(reqType)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 12,
                    color: CommunityColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RequestDetailScreen(requestId: requestId),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: CommunityColors.primaryBlack,
                foregroundColor: CommunityColors.primaryWhite,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(CommunityRadius.pill),
                ),
              ),
              child: const Text(
                'הצג פרטים',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(String id) {
    switch (id) {
      case 'elderly':           return 'קשישים';
      case 'lone_soldier':      return 'חייל בודד';
      case 'struggling_family': return 'משפחה';
      case 'general':           return 'כללי';
      default:                  return id;
    }
  }
}

class _UrgencyBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CommunityColors.dangerBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'דחוף',
        style: TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: CommunityColors.danger,
        ),
      ),
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────────────────
class _MapError extends StatelessWidget {
  const _MapError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'שגיאה בטעינת המפה',
          style: TextStyle(
            fontFamily: CommunityType.fontFamily,
            fontSize: 13,
            color: CommunityColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CommunityColors.primaryWhite,
        border: Border.all(color: CommunityColors.borderSubtle, width: 0.5),
        borderRadius: const BorderRadius.all(CommunityRadius.pill),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Text(
        'אין כרגע בקשות עם מיקום באזור זה',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 12,
          color: CommunityColors.textSecondary,
        ),
      ),
    );
  }
}
