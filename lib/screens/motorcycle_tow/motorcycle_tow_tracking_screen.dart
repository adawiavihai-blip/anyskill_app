// Motorcycle Towing CSM — Live tracking screen.
//
// Customer-side view of an active tow. Streams `motorcycle_tows/{towId}` and
// renders: status bar (current stage + ETA), live map (provider pin +
// pickup pin + dropoff pin + path polyline), driver card, 6-stage timeline,
// locked price breakdown, safety actions (share + SOS), cancel + help.
//
// The provider drives stage transitions via [MotorcycleTowService.advanceStage].
// Customer can cancel only before the provider starts driving (stage
// `driver_assigned` or earlier — checked via `_isCancellable`).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../constants/motorcycle_tracking_stages.dart';
import '../../models/motorcycle_tow_profile.dart';
import '../../services/motorcycle_tow_service.dart';
import '../../widgets/wolt_tile_layer.dart';
import '../chat_screen.dart';
import 'motorcycle_tow_palette.dart';

typedef _MTP = MotorcycleTowPalette;

class MotorcycleTowTrackingScreen extends StatefulWidget {
  /// The `motorcycle_tows/{towId}` document id. The screen streams this doc.
  final String towId;

  const MotorcycleTowTrackingScreen({super.key, required this.towId});

  @override
  State<MotorcycleTowTrackingScreen> createState() =>
      _MotorcycleTowTrackingScreenState();
}

class _MotorcycleTowTrackingScreenState
    extends State<MotorcycleTowTrackingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  StreamSubscription? _tickSub;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    // 30s tick to refresh the "X minutes ago" labels in the timeline.
    _tickSub = Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _tickSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _MTP.bgSecondary,
        appBar: AppBar(
          backgroundColor: _MTP.bgPrimary,
          surfaceTintColor: _MTP.bgPrimary,
          elevation: 0,
          centerTitle: false,
          title: const Text(
            'מעקב גרירה',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _MTP.textPrimary,
            ),
          ),
          iconTheme: const IconThemeData(color: _MTP.textPrimary),
        ),
        body: StreamBuilder<Map<String, dynamic>?>(
          stream: MotorcycleTowService.watchTow(widget.towId),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorState(
                  message: 'שגיאה בטעינת הגרירה: ${snap.error}');
            }
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _MTP.purple500),
              );
            }
            final data = snap.data;
            if (data == null) {
              return const _ErrorState(message: 'הגרירה לא נמצאה');
            }
            return _buildBody(data);
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BODY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBody(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'order_confirmed';
    final providerName = data['providerName'] as String? ?? '';
    final providerLoc = data['providerLocation'] as Map<String, dynamic>?;
    final booking =
        (data['bookingSnapshot'] as Map<String, dynamic>?) ?? const {};
    final priceBreakdown = MotorcycleTowPriceBreakdown.fromMap(
      booking['priceBreakdown'] as Map<String, dynamic>?,
    );
    final pickupLat = (booking['pickupLat'] as num?)?.toDouble();
    final pickupLng = (booking['pickupLng'] as num?)?.toDouble();
    final dropoffLat = (booking['dropoffLat'] as num?)?.toDouble();
    final dropoffLng = (booking['dropoffLng'] as num?)?.toDouble();
    final pathRaw = (data['path'] as List?) ?? const [];
    final stageHistory = (data['stageHistory'] as List?) ?? const [];

    final pathPoints = pathRaw
        .whereType<Map<String, dynamic>>()
        .map((m) => LatLng(
              (m['lat'] as num).toDouble(),
              (m['lng'] as num).toDouble(),
            ))
        .toList();

    final providerPoint = providerLoc != null
        ? LatLng(
            (providerLoc['lat'] as num).toDouble(),
            (providerLoc['lng'] as num).toDouble(),
          )
        : (pathPoints.isNotEmpty ? pathPoints.last : null);

    // Provider-side prompts: photo reminders gated on the smart-feature
    // flag stamped onto the tow doc at startTow time (§55). Customer
    // never sees these — they only matter to the courier.
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final providerId = data['providerId'] as String? ?? '';
    final isProviderViewer = viewerUid != null && viewerUid == providerId;
    final beforeAfterEnabled = data['flagBeforeAfterPhotos'] == true;
    final beforePhotos =
        (data['beforePhotos'] as List?)?.cast<dynamic>() ?? const [];
    final afterPhotos =
        (data['afterPhotos'] as List?)?.cast<dynamic>() ?? const [];

    Widget? photoPrompt;
    if (isProviderViewer && beforeAfterEnabled) {
      if (status == 'arrived_pickup' && beforePhotos.isEmpty) {
        photoPrompt = _buildPhotoPromptCard(phase: 'before');
      } else if (status == 'arrived_destination' && afterPhotos.isEmpty) {
        photoPrompt = _buildPhotoPromptCard(phase: 'after');
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        _buildStatusBar(status: status, providerLoc: providerLoc),
        const SizedBox(height: 10),
        if (photoPrompt != null) ...[
          photoPrompt,
          const SizedBox(height: 10),
        ],
        _buildMap(
          providerPoint: providerPoint,
          pickup: (pickupLat != null && pickupLng != null)
              ? LatLng(pickupLat, pickupLng)
              : null,
          dropoff: (dropoffLat != null && dropoffLng != null)
              ? LatLng(dropoffLat, dropoffLng)
              : null,
          pathPoints: pathPoints,
        ),
        const SizedBox(height: 10),
        _buildDriverCard(
          providerId: providerId,
          providerName: providerName,
          customerId: data['customerId'] as String? ?? '',
          customerName: data['customerName'] as String? ?? '',
          rating: (booking['providerRating'] as num?)?.toDouble(),
        ),
        const SizedBox(height: 10),
        _buildTimeline(status: status, stageHistory: stageHistory),
        const SizedBox(height: 10),
        _buildCostCard(priceBreakdown),
        const SizedBox(height: 10),
        _buildSectionLabel('בטיחות וסיוע'),
        _buildSafetyRow(),
        const SizedBox(height: 10),
        _buildBottomActions(status: status),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PHOTO PROMPT (provider-side, gated on flagBeforeAfterPhotos + stage)
  // ─────────────────────────────────────────────────────────────────────────

  /// Prominent orange card shown to the provider when the tow reaches a
  /// photo-documentation stage. Tap → camera → Storage upload → addPhoto.
  /// Auto-dismisses once the photos array is non-empty.
  Widget _buildPhotoPromptCard({required String phase}) {
    final isBefore = phase == 'before';
    final label = isBefore ? 'תיעוד "לפני"' : 'תיעוד "אחרי"';
    final hint = isBefore
        ? 'צלם 2-4 תמונות של האופנוע לפני העמסה — מגן עליך מתלונות נזק'
        : 'צלם 2-4 תמונות של האופנוע אחרי הפריקה — מאשר מסירה תקינה';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        // Amber/orange accent — distinct from the purple status bar so
        // the provider can't miss it.
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.photo_camera_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.95),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => _capturePhoto(phase: phase),
            icon: const Icon(Icons.camera_alt_rounded, size: 14),
            label: const Text('צלם'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFD97706),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _capturePhoto({required String phase}) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 78,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      // Show a quick "uploading…" snackbar so the user sees feedback
      // during the Storage round-trip.
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('מעלה תמונה…'),
          duration: Duration(seconds: 2),
        ),
      );
      final towId = widget.towId;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref('motorcycle_tows/$towId/${phase}_$ts.jpg');
      final bytes = await picked.readAsBytes();
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      await MotorcycleTowService.addPhoto(url: url, phase: phase);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            phase == 'before'
                ? '✓ תמונת "לפני" נוספה'
                : '✓ תמונת "אחרי" נוספה',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בהעלאת התמונה: $e')),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATUS BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatusBar({
    required String status,
    required Map<String, dynamic>? providerLoc,
  }) {
    final stage = findMotorcycleStage(status);
    final speed = providerLoc != null
        ? (providerLoc['speedKph'] as num?)?.toDouble()
        : null;
    final eta = _estimateEtaMin(status);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_MTP.purple700, _MTP.purple500],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                    alpha: 0.18 + 0.08 * _pulseCtrl.value),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.local_shipping_outlined,
                  size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage?.name ?? 'בעדכון…',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  speed != null && speed > 1
                      ? '~${speed.round()} קמ"ש · בנסיעה'
                      : (stage?.detail ?? ''),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (eta != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    '$eta',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'דקות',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFFCECBF6),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Naive ETA — coarse proxy by stage. When real route ETA is wired
  /// (future PR with a routing API), feed `speedKph` + remaining distance
  /// here.
  int? _estimateEtaMin(String status) {
    switch (status) {
      case 'order_confirmed':
      case 'driver_assigned':
        return 28;
      case 'en_route_pickup':
        return 12;
      case 'arrived_pickup':
        return 5;
      case 'loaded_in_transit':
        return 15;
      case 'arrived_destination':
        return null;
      default:
        return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAP
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMap({
    required LatLng? providerPoint,
    required LatLng? pickup,
    required LatLng? dropoff,
    required List<LatLng> pathPoints,
  }) {
    // Default centre to Tel Aviv if nothing yet.
    final centre = providerPoint ??
        pickup ??
        dropoff ??
        const LatLng(32.0853, 34.7818);
    return Container(
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _MTP.borderTertiary, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: centre,
          initialZoom: 12.5,
          minZoom: 6,
          maxZoom: 18,
        ),
        children: [
          WoltTileLayer.build(maxZoom: 19),
          if (pathPoints.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: pathPoints,
                  strokeWidth: 3.5,
                  color: _MTP.purple500,
                  pattern: StrokePattern.dashed(segments: const [6, 4]),
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              if (providerPoint != null)
                Marker(
                  point: providerPoint,
                  width: 36,
                  height: 36,
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 28 + 12 * _pulseCtrl.value,
                          height: 28 + 12 * _pulseCtrl.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _MTP.purple500.withValues(
                                alpha: 0.2 - 0.15 * _pulseCtrl.value),
                          ),
                        ),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _MTP.purple500,
                            border: Border.all(
                                color: Colors.white, width: 2.5),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.two_wheeler_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              if (pickup != null)
                Marker(
                  point: pickup,
                  width: 28,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _MTP.green500,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.flag_outlined,
                        size: 13, color: Colors.white),
                  ),
                ),
              if (dropoff != null)
                Marker(
                  point: dropoff,
                  width: 28,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _MTP.amber600,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.place_rounded,
                        size: 13, color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DRIVER CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDriverCard({
    required String providerId,
    required String providerName,
    required String customerId,
    required String customerName,
    required double? rating,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _MTP.bgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _MTP.borderTertiary, width: 0.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _MTP.purple50,
            child: Text(
              providerName.isEmpty ? '?' : providerName.characters.first,
              style: const TextStyle(
                color: _MTP.purple700,
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  providerName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _MTP.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (rating != null) ...[
                      const Text('★',
                          style: TextStyle(
                              fontSize: 12, color: _MTP.amber600)),
                      const SizedBox(width: 3),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _MTP.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('·',
                          style: TextStyle(
                              fontSize: 11, color: _MTP.textTertiary)),
                      const SizedBox(width: 6),
                    ],
                    const Text(
                      'מאומת',
                      style: TextStyle(
                        fontSize: 11,
                        color: _MTP.green500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'צ\'אט',
            onPressed: providerId.isEmpty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          receiverId: providerId,
                          receiverName: providerName,
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.chat_bubble_outline_rounded,
                size: 18, color: _MTP.purple500),
            style: IconButton.styleFrom(
              backgroundColor: _MTP.purple50,
              minimumSize: const Size(36, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TIMELINE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimeline({
    required String status,
    required List stageHistory,
  }) {
    final currentIdx = motorcycleStageIndex(status);
    DateTime? historyTimeFor(String stageId) {
      for (final entry in stageHistory) {
        if (entry is Map &&
            (entry['stage'] as String?) == stageId &&
            entry['at'] is Timestamp) {
          return (entry['at'] as Timestamp).toDate();
        }
      }
      return null;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: _MTP.bgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _MTP.borderTertiary, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'סטטוס הנסיעה',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _MTP.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < kMotorcycleTrackingStages.length; i++)
            _TimelineRow(
              stage: kMotorcycleTrackingStages[i],
              done: i < currentIdx,
              active: i == currentIdx,
              isLast: i == kMotorcycleTrackingStages.length - 1,
              when: historyTimeFor(kMotorcycleTrackingStages[i].id),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COST CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCostCard(MotorcycleTowPriceBreakdown b) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _MTP.bgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _MTP.borderTertiary, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'פירוט תשלום',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _MTP.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _MTP.green50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock_outline_rounded,
                        size: 11, color: _MTP.green700),
                    SizedBox(width: 4),
                    Text(
                      'מחיר נעול',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: _MTP.green700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CostRow(label: 'מחיר בסיס', value: '₪${b.basePrice.round()}'),
          if (b.kmFee > 0)
            _CostRow(
              label:
                  'תוספת מרחק (${b.extraKm.toStringAsFixed(1)} ק"מ)',
              value: '₪${b.kmFee.round()}',
            ),
          if (b.nightSurcharge > 0)
            _CostRow(
              label: 'תוספת לילה / שבת',
              value: '₪${b.nightSurcharge.round()}',
            ),
          if (b.emergencySurcharge > 0)
            _CostRow(
              label: 'תוספת חירום מיידי',
              value: '₪${b.emergencySurcharge.round()}',
            ),
          const Divider(
              height: 16, thickness: 0.5, color: _MTP.borderTertiary),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'סה"כ לתשלום',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _MTP.textPrimary,
                  ),
                ),
              ),
              Text(
                '₪${b.total.round()}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: _MTP.purple900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SAFETY ROW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: _MTP.textTertiary,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSafetyRow() {
    return Row(
      children: [
        Expanded(
          child: _SafetyCard(
            icon: Icons.share_outlined,
            title: 'שתף מעקב',
            sub: 'לבן/בת זוג, חבר, משפחה',
            onTap: _shareTracking,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SafetyCard(
            icon: Icons.warning_amber_rounded,
            title: 'קריאת SOS',
            sub: 'משטרה + מוקד אסונות',
            danger: true,
            onTap: _confirmSos,
          ),
        ),
      ],
    );
  }

  Future<void> _shareTracking() async {
    final url =
        'https://anyskill.app/tow/${widget.towId}'; // stable share link
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הקישור הועתק — שלח/י ל-WhatsApp או ל-SMS')),
    );
  }

  Future<void> _confirmSos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('קריאת SOS'),
          content: const Text(
              'פעולה זו תפנה את צוות התמיכה ותתעד את המיקום שלך. להמשיך?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _MTP.red500),
              child: const Text('קרא SOS'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('קריאה נשלחה לצוות התמיכה — נחזור אליך מיידית'),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  bool _isCancellable(String status) =>
      status == 'order_confirmed' || status == 'driver_assigned';

  Widget _buildBottomActions({required String status}) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed:
                _isCancellable(status) ? _confirmCancel : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: _MTP.textSecondary,
              side: const BorderSide(color: _MTP.borderSecondary),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(
              _isCancellable(status)
                  ? 'ביטול הזמנה (חינם עד הגעת הגורר)'
                  : 'לא ניתן לבטל בשלב זה',
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _openHelp,
          icon: const Icon(Icons.help_outline_rounded, size: 14),
          label: const Text('תמיכה'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _MTP.textPrimary,
            side: const BorderSide(color: _MTP.borderSecondary),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ביטול הזמנה'),
          content: const Text(
              'הביטול חינם עד שהגורר יוצא לדרך. האם להמשיך?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('חזור'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _MTP.red500),
              child: const Text('בטל הזמנה'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await MotorcycleTowService.cancelTow(reason: 'customer_cancel');
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בביטול: $e')),
      );
    }
  }

  void _openHelp() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('פותח תמיכה...')),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _TimelineRow extends StatelessWidget {
  final MotorcycleTrackingStage stage;
  final bool done;
  final bool active;
  final bool isLast;
  final DateTime? when;

  const _TimelineRow({
    required this.stage,
    required this.done,
    required this.active,
    required this.isLast,
    this.when,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? _MTP.purple500
        : (done ? _MTP.green500 : _MTP.borderSecondary);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: active
                      ? Border.all(
                          color: _MTP.purple500.withValues(alpha: 0.25),
                          width: 4)
                      : null,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: _MTP.borderTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: active || done
                          ? _MTP.textPrimary
                          : _MTP.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _detailLine(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: _MTP.textTertiary,
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

  String _detailLine() {
    if (when != null) {
      return _formatHm(when!) + (active ? '' : ' · בוצע');
    }
    if (active) {
      return stage.detail.isEmpty
          ? 'מתבצע כעת'
          : '${stage.detail} · מתבצע';
    }
    return stage.detail;
  }

  String _formatHm(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final String value;
  const _CostRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: _MTP.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _MTP.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final bool danger;
  final VoidCallback onTap;

  const _SafetyCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = danger ? _MTP.red500 : _MTP.purple500;
    final titleColor = danger ? _MTP.red500 : _MTP.textPrimary;
    final bg = danger ? _MTP.red50 : _MTP.bgSecondary;
    final border = danger
        ? const Color(0xFFF09595)
        : _MTP.borderTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 10,
                      color: danger
                          ? _MTP.red700.withValues(alpha: 0.7)
                          : _MTP.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 36, color: _MTP.amber600),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: _MTP.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
