/// AnySkill — Active Booking Detail Screen
///
/// Full-screen view opened when the customer taps the short booking card
/// on the "הזמנות פעילות" tab. Matches the mockup in
/// `docs/ui-specs/active-booking/anyskill_booking_mockup.html`.
///
/// Live pieces:
///   * Banner at the top mirroring the current status (purple "בדרך" /
///     green "כמעט אצלך" when the provider is within 300m / green
///     "בעבודה" once work has started).
///   * flutter_map with a live-moving provider marker — stream comes
///     from `provider_live_location/{expertId}` via [LiveLocationService].
///     Falls back to a static destination marker when the provider isn't
///     broadcasting.
///   * 4-step stepper (התקבלה → בדרך → בעבודה → הושלם).
///   * Provider identity card, expandable with recent reviews + tags.
///   * Cancellation policy card — translated from
///     `users/{expertId}.cancellationPolicy`.
///   * Swipe-to-cancel slider that triggers the existing cancel flow.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/cancellation_policy_service.dart';
import '../../services/live_location_service.dart';
import '../../utils/safe_image_provider.dart';
import '../chat_screen.dart';

class ActiveBookingDetailScreen extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic> initialJob;

  /// Called when the swipe-to-cancel gesture completes.
  /// Owner (customer_bookings_tab) already has the cancel dialog + CF
  /// wiring, so we just delegate.
  final Future<void> Function(Map<String, dynamic> job, double amount)
      onCancelRequested;

  const ActiveBookingDetailScreen({
    super.key,
    required this.jobId,
    required this.initialJob,
    required this.onCancelRequested,
  });

  @override
  State<ActiveBookingDetailScreen> createState() =>
      _ActiveBookingDetailScreenState();
}

class _ActiveBookingDetailScreenState
    extends State<ActiveBookingDetailScreen> {
  bool _providerExpanded = false;

  // Palette from the mockup — scoped to this screen only.
  static const _p  = Color(0xFF6C5CE7);
  static const _pd = Color(0xFF5A4BD1);
  static const _pl = Color(0xFFA29BFE);
  static const _pbg  = Color(0xFFF3F1FF);
  static const _pbg2 = Color(0xFFEBE8FF);
  static const _g    = Color(0xFF00B894);
  static const _gbg  = Color(0xFFE6FAF3);
  static const _o    = Color(0xFFE17055);
  static const _obg  = Color(0xFFFFF0EC);
  static const _ambg = Color(0xFFFFF8E7);
  static const _dk   = Color(0xFF2D3436);
  static const _gr   = Color(0xFF636E72);
  static const _grl  = Color(0xFFB2BEC3);
  static const _grbg = Color(0xFFF8F9FA);
  static const _bd   = Color(0xFFEEEDF5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: _grbg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          iconTheme: const IconThemeData(color: _dk),
          title: const Text('ההזמנה הפעילה',
              style: TextStyle(
                  color: _dk,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          centerTitle: true,
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('jobs')
              .doc(widget.jobId)
              .snapshots(),
          builder: (context, jobSnap) {
            final job = jobSnap.hasData && jobSnap.data!.exists
                ? (jobSnap.data!.data() ?? widget.initialJob)
                : widget.initialJob;
            return _buildBody(context, job);
          },
        ));
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> job) {
    final expertId   = job['expertId']   as String? ?? '';
    final expertName = job['expertName'] as String? ?? 'נותן שירות';
    final expertPhone = job['expertPhone'] as String? ?? '';
    final chatRoomId = job['chatRoomId'] as String? ?? '';
    final category   = job['category'] as String? ?? 'שירות';
    final totalAmount = (job['totalAmount']  ??
            job['totalPaidByCustomer'] ??
            0.0)
        .toDouble();

    DateTime? apptDate;
    if (job['appointmentDate'] is Timestamp) {
      apptDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    final apptStr  = apptDate != null
        ? DateFormat('dd/MM/yy', 'he').format(apptDate)
        : '—';
    final apptTime = job['appointmentTime'] as String? ?? '—';
    final durationStr =
        (job['estimatedDurationHours'] as num?) != null
            ? '${job['estimatedDurationHours']} שעות'
            : '—';

    final status = job['status'] as String? ?? '';
    final expertOnWay   = job['expertOnWay']   == true;
    final workStartedTs = job['workStartedAt'] as Timestamp?;
    final clientLat = (job['clientLat'] as num?)?.toDouble();
    final clientLng = (job['clientLng'] as num?)?.toDouble();
    final expertLat = (job['expertLat'] as num?)?.toDouble();
    final expertLng = (job['expertLng'] as num?)?.toDouble();

    int step;
    if (status == 'completed' || status == 'expert_completed') {
      step = 3;
    } else if (workStartedTs != null) {
      step = 2;
    } else if (expertOnWay) {
      step = 1;
    } else {
      step = 0;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: [
        // ─── Card container ─────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _p.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LiveBanner(
                expertId: expertId,
                clientLat: clientLat,
                clientLng: clientLng,
                workStarted: workStartedTs != null,
                expertOnWay: expertOnWay,
              ),
              SizedBox(
                height: 220,
                child: _LiveMap(
                  expertId: expertId,
                  expertName: expertName,
                  expertImage: job['expertImage'] as String?,
                  clientLat: clientLat,
                  clientLng: clientLng,
                  fallbackExpertLat: expertLat,
                  fallbackExpertLng: expertLng,
                ),
              ),
              _ProviderHeader(
                expertId: expertId,
                expertName: expertName,
                expertImage: job['expertImage'] as String?,
                expanded: _providerExpanded,
                onTap: () => setState(
                    () => _providerExpanded = !_providerExpanded),
              ),
              if (_providerExpanded)
                _ProviderDetail(expertId: expertId, category: category),
              _Stepper(step: step),
              _InfoGrid(
                  date: apptStr,
                  time: apptTime,
                  serviceType: category,
                  duration: durationStr,
                  total: totalAmount),
              _SafetyCard(job: job),
              _ActionsRow(
                expertPhone: expertPhone,
                expertId: expertId,
                expertName: expertName,
                expertImage: job['expertImage'] as String?,
                chatRoomId: chatRoomId,
              ),
              _CancellationPolicyCard(expertId: expertId,
                  expertName: expertName),
              _SwipeToCancel(
                enabled: status == 'paid_escrow',
                onCancelled: () =>
                    widget.onCancelRequested(job, totalAmount),
              ),
              const _TrustBar(),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// LIVE BANNER
// ══════════════════════════════════════════════════════════════════════

class _LiveBanner extends StatelessWidget {
  final String expertId;
  final double? clientLat;
  final double? clientLng;
  final bool workStarted;
  final bool expertOnWay;

  const _LiveBanner({
    required this.expertId,
    required this.clientLat,
    required this.clientLng,
    required this.workStarted,
    required this.expertOnWay,
  });

  @override
  Widget build(BuildContext context) {
    if (workStarted) {
      return _banner(
        bg: _ActiveBookingDetailScreenState._gbg,
        textColor: const Color(0xFF1A7A5A),
        message: 'נותן השירות בעבודה',
        pillColor: _ActiveBookingDetailScreenState._g,
        pillText: 'בעבודה',
        pillIcon: Icons.build_rounded,
      );
    }

    if (!expertOnWay) {
      return _banner(
        bg: _ActiveBookingDetailScreenState._pbg,
        textColor: _ActiveBookingDetailScreenState._pd,
        message: 'ההזמנה התקבלה — ממתין ליציאה',
        pillColor: _ActiveBookingDetailScreenState._p,
        pillText: 'התקבלה',
        pillIcon: Icons.check_circle_outline_rounded,
      );
    }

    // expertOnWay — listen to live GPS to switch the banner to "close".
    return StreamBuilder<LiveLocation?>(
      stream: LiveLocationService.streamLocation(expertId),
      builder: (context, snap) {
        final loc = snap.data;
        final close = _isClose(loc);
        final bg = close
            ? _ActiveBookingDetailScreenState._gbg
            : _ActiveBookingDetailScreenState._pbg;
        final textColor = close
            ? const Color(0xFF1A7A5A)
            : _ActiveBookingDetailScreenState._pd;
        final pillColor = close
            ? _ActiveBookingDetailScreenState._g
            : _ActiveBookingDetailScreenState._p;
        final pillText = close ? 'כמעט אצלך' : 'בדרך';
        final message =
            close ? 'כמעט אצלך!' : 'נותן השירות בדרך אלייך';
        return _banner(
          bg: bg,
          textColor: textColor,
          message: message,
          pillColor: pillColor,
          pillText: pillText,
          pillIcon: Icons.location_on_rounded,
        );
      },
    );
  }

  bool _isClose(LiveLocation? loc) {
    if (loc == null || clientLat == null || clientLng == null) return false;
    final d = Geolocator.distanceBetween(
        loc.lat, loc.lng, clientLat!, clientLng!);
    return d < 300;
  }

  Widget _banner({
    required Color bg,
    required Color textColor,
    required String message,
    required Color pillColor,
    required String pillText,
    required IconData pillIcon,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
            bottom:
                BorderSide(color: _ActiveBookingDetailScreenState._bd)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(pillIcon, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(pillText,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ]),
          ),
          const Spacer(),
          Text(message,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(width: 8),
          _PulsingDot(color: pillColor),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value;
        return SizedBox(
          width: 18,
          height: 18,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 18 * (0.6 + v * 0.4),
              height: 18 * (0.6 + v * 0.4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.2 * (1 - v)),
              ),
            ),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// LIVE MAP
// ══════════════════════════════════════════════════════════════════════

class _LiveMap extends StatefulWidget {
  final String expertId;
  final String expertName;
  final String? expertImage;
  final double? clientLat;
  final double? clientLng;
  final double? fallbackExpertLat;
  final double? fallbackExpertLng;

  const _LiveMap({
    required this.expertId,
    required this.expertName,
    required this.expertImage,
    required this.clientLat,
    required this.clientLng,
    required this.fallbackExpertLat,
    required this.fallbackExpertLng,
  });

  @override
  State<_LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<_LiveMap> {
  final _mapCtrl = MapController();

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LiveLocation?>(
      stream: LiveLocationService.streamLocation(widget.expertId),
      builder: (context, snap) {
        final live = snap.data;
        final providerLat = live?.lat ?? widget.fallbackExpertLat;
        final providerLng = live?.lng ?? widget.fallbackExpertLng;

        final markers = <Marker>[];
        LatLng center;

        // Client destination marker (red pin)
        if (widget.clientLat != null && widget.clientLng != null) {
          markers.add(Marker(
            point: LatLng(widget.clientLat!, widget.clientLng!),
            width: 40,
            height: 40,
            child: const _ClientPin(),
          ));
        }

        // Provider live marker
        if (providerLat != null && providerLng != null) {
          markers.add(Marker(
            point: LatLng(providerLat, providerLng),
            width: 56,
            height: 56,
            child: _ProviderPin(
              image: widget.expertImage,
              name: widget.expertName,
              isLive: live != null,
            ),
          ));
        }

        // Pick center — midpoint if both, else whichever exists.
        if (providerLat != null &&
            providerLng != null &&
            widget.clientLat != null &&
            widget.clientLng != null) {
          center = LatLng(
            (providerLat + widget.clientLat!) / 2,
            (providerLng + widget.clientLng!) / 2,
          );
        } else if (providerLat != null && providerLng != null) {
          center = LatLng(providerLat, providerLng);
        } else if (widget.clientLat != null && widget.clientLng != null) {
          center = LatLng(widget.clientLat!, widget.clientLng!);
        } else {
          // No coordinates anywhere — show Israel default
          return const _MapPlaceholder();
        }

        final polyline = (providerLat != null &&
                providerLng != null &&
                widget.clientLat != null &&
                widget.clientLng != null)
            ? [
                LatLng(providerLat, providerLng),
                LatLng(widget.clientLat!, widget.clientLng!)
              ]
            : null;

        return FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13.5,
            interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.anyskill.app',
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
            ),
            if (polyline != null)
              PolylineLayer(polylines: [
                Polyline(
                    points: polyline,
                    strokeWidth: 3,
                    color: _ActiveBookingDetailScreenState._p),
              ]),
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0EEF8),
      alignment: Alignment.center,
      child: const Text(
        'מפה לא זמינה — לא נקבע מיקום',
        style: TextStyle(
            color: _ActiveBookingDetailScreenState._gr, fontSize: 13),
      ),
    );
  }
}

class _ProviderPin extends StatelessWidget {
  final String? image;
  final String name;
  final bool isLive;

  const _ProviderPin(
      {required this.image, required this.name, required this.isLive});

  @override
  Widget build(BuildContext context) {
    final img = safeImageProvider(image);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
            color: isLive
                ? _ActiveBookingDetailScreenState._p
                : _ActiveBookingDetailScreenState._grl,
            width: 3),
        boxShadow: [
          BoxShadow(
            color: (isLive
                    ? _ActiveBookingDetailScreenState._p
                    : Colors.black)
                .withValues(alpha: 0.25),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipOval(
        child: img != null
            ? Image(image: img, fit: BoxFit.cover)
            : Container(
                color: _ActiveBookingDetailScreenState._pbg,
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name.characters.first : '?',
                  style: const TextStyle(
                      color: _ActiveBookingDetailScreenState._pd,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
      ),
    );
  }
}

class _ClientPin extends StatelessWidget {
  const _ClientPin();

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _ActiveBookingDetailScreenState._o.withValues(alpha: 0.15),
        ),
      ),
      Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _ActiveBookingDetailScreenState._o,
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// PROVIDER HEADER + DETAIL
// ══════════════════════════════════════════════════════════════════════

class _ProviderHeader extends StatelessWidget {
  final String expertId;
  final String expertName;
  final String? expertImage;
  final bool expanded;
  final VoidCallback onTap;

  const _ProviderHeader({
    required this.expertId,
    required this.expertName,
    required this.expertImage,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(expertId)
          .get(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const {};
        final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final reviewsCount = (data['reviewsCount'] as num?)?.toInt() ?? 0;
        final responseStr =
            (data['avgResponseMinutes'] as num?) != null
                ? 'תגובה: ${data['avgResponseMinutes']} דק\''
                : 'תגובה: מהיר';
        final isVerified = data['isVerified'] == true;
        final img = safeImageProvider(expertImage ??
            data['profileImage'] as String?);

        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _ActiveBookingDetailScreenState._p, width: 3),
                ),
                child: ClipOval(
                  child: img != null
                      ? Image(image: img, fit: BoxFit.cover)
                      : Container(
                          color: _ActiveBookingDetailScreenState._pbg,
                          alignment: Alignment.center,
                          child: Text(
                            expertName.isNotEmpty
                                ? expertName.characters.first
                                : '?',
                            style: const TextStyle(
                                color: _ActiveBookingDetailScreenState._pd,
                                fontWeight: FontWeight.w700,
                                fontSize: 18),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(expertName,
                        style: const TextStyle(
                            color: _ActiveBookingDetailScreenState._dk,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded,
                              size: 16,
                              color: Color(0xFFFDCB6E)),
                          const SizedBox(width: 2),
                          Text(rating.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Color(0xFFE17055),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ]),
                        Text('$reviewsCount עבודות',
                            style: const TextStyle(
                                color: _ActiveBookingDetailScreenState._gr,
                                fontSize: 12)),
                        Text(responseStr,
                            style: const TextStyle(
                                color: _ActiveBookingDetailScreenState._grl,
                                fontSize: 11)),
                      ],
                    ),
                    if (isVerified) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: _ActiveBookingDetailScreenState._pbg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.shield_rounded,
                              size: 12,
                              color: _ActiveBookingDetailScreenState._p),
                          SizedBox(width: 4),
                          Text('נותן שירות מאומת',
                              style: TextStyle(
                                  color: _ActiveBookingDetailScreenState._pd,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500)),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _ActiveBookingDetailScreenState._pl),
            ]),
          ),
        );
      },
    );
  }
}

class _ProviderDetail extends StatelessWidget {
  final String expertId;
  final String category;

  const _ProviderDetail({required this.expertId, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      decoration: const BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: _ActiveBookingDetailScreenState._bd)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('התמחויות',
              style: TextStyle(
                  color: _ActiveBookingDetailScreenState._grl,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _tag(category),
          ]),
          const SizedBox(height: 12),
          const Text('ביקורות אחרונות',
              style: TextStyle(
                  color: _ActiveBookingDetailScreenState._grl,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('reviews')
                .where('revieweeId', isEqualTo: expertId)
                .limit(10)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('טוען…',
                      style: TextStyle(fontSize: 12,
                          color: _ActiveBookingDetailScreenState._gr)),
                );
              }
              final published = snap.data!.docs
                  .where((d) {
                    final v = d.data()['isPublished'];
                    return v == null || v == true;
                  })
                  .take(2)
                  .toList();
              if (published.isEmpty) {
                return const Text('עדיין אין ביקורות זמינות',
                    style: TextStyle(fontSize: 12,
                        color: _ActiveBookingDetailScreenState._gr));
              }
              return Column(
                children: [
                  for (final d in published) _review(d.data()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: _ActiveBookingDetailScreenState._pbg,
            borderRadius: BorderRadius.circular(10)),
        child: Text(t,
            style: const TextStyle(
                color: _ActiveBookingDetailScreenState._pd,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      );

  Widget _review(Map<String, dynamic> r) {
    final rating = (r['overallRating'] as num?)?.toDouble() ??
        (r['rating'] as num?)?.toDouble() ??
        5.0;
    final text = r['publicComment'] as String? ??
        r['comment'] as String? ??
        '';
    final name = r['reviewerName'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _ActiveBookingDetailScreenState._grbg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (int i = 0; i < 5; i++)
                Icon(
                  i < rating.round()
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 12,
                  color: const Color(0xFFFDCB6E),
                ),
            ]),
            const Spacer(),
            Text(name,
                style: const TextStyle(
                    color: _ActiveBookingDetailScreenState._dk,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ]),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(text,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: _ActiveBookingDetailScreenState._gr,
                    height: 1.5)),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// STEPPER
// ══════════════════════════════════════════════════════════════════════

class _Stepper extends StatelessWidget {
  final int step;
  const _Stepper({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['התקבלה', 'בדרך', 'בעבודה', 'הושלם'];
    final progressPct =
        (step <= 0 ? 0 : (step / (labels.length - 1))).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: _ActiveBookingDetailScreenState._bd)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(children: [
            // Background line
            Positioned(
              right: 22,
              left: 22,
              top: 15,
              child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                      color: _ActiveBookingDetailScreenState._bd,
                      borderRadius: BorderRadius.circular(2))),
            ),
            // Progress line (RTL — grows from right)
            Positioned(
              right: 22,
              top: 15,
              child: Container(
                width: (w - 44) * progressPct,
                height: 3,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    _ActiveBookingDetailScreenState._p,
                    _ActiveBookingDetailScreenState._pl,
                  ]),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(labels.length, (i) {
                final isOk = i < step;
                final isCurrent = i == step;
                return Column(children: [
                  _circle(isOk, isCurrent),
                  const SizedBox(height: 6),
                  Text(labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: (isOk || isCurrent)
                            ? _ActiveBookingDetailScreenState._p
                            : _ActiveBookingDetailScreenState._grl,
                        fontWeight: (isOk || isCurrent)
                            ? FontWeight.w600
                            : FontWeight.normal,
                      )),
                ]);
              }),
            ),
          ]);
        },
      ),
    );
  }

  Widget _circle(bool ok, bool current) {
    if (ok) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _ActiveBookingDetailScreenState._p),
        child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
      );
    }
    if (current) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
              color: _ActiveBookingDetailScreenState._p, width: 2.5),
          boxShadow: [
            BoxShadow(
                color: _ActiveBookingDetailScreenState._p
                    .withValues(alpha: 0.15),
                blurRadius: 6,
                spreadRadius: 2),
          ],
        ),
        child: const Icon(Icons.location_on_rounded,
            size: 16, color: _ActiveBookingDetailScreenState._p),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF0EEF8),
        border: Border.all(color: const Color(0xFFDDD8EF), width: 1.5),
      ),
      child: const Icon(Icons.schedule_rounded,
          size: 14, color: _ActiveBookingDetailScreenState._grl),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// INFO GRID + ESCROW
// ══════════════════════════════════════════════════════════════════════

class _InfoGrid extends StatelessWidget {
  final String date;
  final String time;
  final String serviceType;
  final String duration;
  final double total;

  const _InfoGrid({
    required this.date,
    required this.time,
    required this.serviceType,
    required this.duration,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: _ActiveBookingDetailScreenState._bd)),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: _cell('תאריך', date)),
          const SizedBox(width: 8),
          Expanded(child: _cell('שעה', time)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _cell('סוג שירות', serviceType)),
          const SizedBox(width: 8),
          Expanded(child: _cell('משך משוער', duration)),
        ]),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _ActiveBookingDetailScreenState._pbg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _ActiveBookingDetailScreenState._pbg2),
          ),
          child: Row(children: [
            Text('${total.toStringAsFixed(0)}₪',
                style: const TextStyle(
                    color: _ActiveBookingDetailScreenState._pd,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            const Icon(Icons.lock_outline_rounded,
                color: _ActiveBookingDetailScreenState._pl, size: 17),
            const Spacer(),
            const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('תשלום בנאמנות',
                      style: TextStyle(
                          color: _ActiveBookingDetailScreenState._pd,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('הכסף מוגן — ישוחרר רק לאחר אישורך',
                      style: TextStyle(
                          color: _ActiveBookingDetailScreenState._pl,
                          fontSize: 10.5)),
                ]),
          ]),
        ),
      ]),
    );
  }

  Widget _cell(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _ActiveBookingDetailScreenState._grbg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: _ActiveBookingDetailScreenState._grl,
                    fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: _ActiveBookingDetailScreenState._dk,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
// SAFETY + ACTIONS
// ══════════════════════════════════════════════════════════════════════

class _SafetyCard extends StatelessWidget {
  final Map<String, dynamic> job;
  const _SafetyCard({required this.job});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: () => _shareLocation(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _ActiveBookingDetailScreenState._gbg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    _ActiveBookingDetailScreenState._g.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.location_on_outlined,
                  color: _ActiveBookingDetailScreenState._g, size: 17),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: 'שיתוף מיקום חי',
                        style: TextStyle(
                            color: Color(0xFF1A7A5A),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5)),
                    TextSpan(
                        text:
                            ' — שתף עם מישהו קרוב כדי שידע שנותן השירות בדרך',
                        style: TextStyle(
                            color: Color(0xFF2D8A6E),
                            fontSize: 12.5,
                            height: 1.5)),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_left_rounded,
                color: Color(0xFF81D4BB)),
          ]),
        ),
      ),
    );
  }

  void _shareLocation(BuildContext context) {
    final lat = (job['clientLat'] as num?)?.toDouble();
    final lng = (job['clientLng'] as num?)?.toDouble();
    final url = (lat != null && lng != null)
        ? 'https://maps.google.com/?q=$lat,$lng'
        : 'https://anyskill.co.il';
    final text =
        'נותן שירות בדרך אליי דרך AnySkill. מיקום: $url';
    launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
  }
}

class _ActionsRow extends StatelessWidget {
  final String expertPhone;
  final String expertId;
  final String expertName;
  final String? expertImage;
  final String chatRoomId;

  const _ActionsRow({
    required this.expertPhone,
    required this.expertId,
    required this.expertName,
    required this.expertImage,
    required this.chatRoomId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      child: Row(children: [
        Expanded(
          child: _btn(
            icon: Icons.call_rounded,
            label: 'התקשר',
            bg: _ActiveBookingDetailScreenState._pbg,
            fg: _ActiveBookingDetailScreenState._pd,
            onTap: expertPhone.isEmpty
                ? null
                : () => launchUrl(Uri.parse('tel:$expertPhone')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _btn(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'שלח הודעה',
            bg: _ActiveBookingDetailScreenState._gbg,
            fg: const Color(0xFF1A7A5A),
            onTap: expertId.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        receiverId: expertId,
                        receiverName: expertName,
                      ),
                    )),
          ),
        ),
      ]),
    );
  }

  Widget _btn({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// CANCELLATION POLICY
// ══════════════════════════════════════════════════════════════════════

class _CancellationPolicyCard extends StatelessWidget {
  final String expertId;
  final String expertName;

  const _CancellationPolicyCard(
      {required this.expertId, required this.expertName});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(expertId)
          .get(),
      builder: (context, snap) {
        final policy = snap.data?.data()?['cancellationPolicy']
                as String? ??
            'flexible';
        final freeHours = CancellationPolicyService.freeHours(policy);
        final penaltyPct =
            (CancellationPolicyService.penaltyFraction(policy) * 100)
                .round();
        final penaltyLabel =
            penaltyPct == 100 ? '100% חיוב' : '$penaltyPct% חיוב';

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _ActiveBookingDetailScreenState._ambg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF5E6B8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline_rounded,
                    size: 15, color: Color(0xFFD4930A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'מדיניות ביטול של $expertName',
                    style: const TextStyle(
                        color: Color(0xFF8B6914),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (policy == 'nonRefundable') ...[
                _row('100% חיוב', 'שירות חירום — ללא החזר בכל ביטול',
                    isWarn: true),
                _row('החזר מלא אוטומטי', 'אם נותן השירות לא הגיע'),
              ] else ...[
                _row('ביטול חינם',
                    'עד $freeHours שעות לפני מועד ההגעה',
                    isFree: true),
                _row(penaltyLabel,
                    'ביטול בפחות מ-$freeHours שעות לפני ההגעה',
                    isWarn: true),
                if (penaltyPct < 100)
                  _row('100% חיוב',
                      'לאחר שנותן השירות הגיע למיקום',
                      isWarn: true),
                _row('החזר מלא אוטומטי',
                    'אי-הגעה של נותן השירות'),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String description,
      {bool isFree = false, bool isWarn = false}) {
    final labelColor = isFree
        ? _ActiveBookingDetailScreenState._g
        : isWarn
            ? _ActiveBookingDetailScreenState._o
            : const Color(0xFF6B5A20);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 7, left: 7),
            decoration: const BoxDecoration(
              color: Color(0xFFD4A84A),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                      text: label,
                      style: TextStyle(
                          color: labelColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5)),
                  const TextSpan(
                      text: ' — ',
                      style: TextStyle(
                          color: Color(0xFF6B5A20), fontSize: 11.5)),
                  TextSpan(
                      text: description,
                      style: const TextStyle(
                          color: Color(0xFF6B5A20),
                          fontSize: 11.5,
                          height: 1.8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// SWIPE TO CANCEL
// ══════════════════════════════════════════════════════════════════════

class _SwipeToCancel extends StatefulWidget {
  final bool enabled;
  final Future<void> Function() onCancelled;

  const _SwipeToCancel(
      {required this.enabled, required this.onCancelled});

  @override
  State<_SwipeToCancel> createState() => _SwipeToCancelState();
}

class _SwipeToCancelState extends State<_SwipeToCancel> {
  double _dragPx = 0;
  bool _triggered = false;

  static const _thumbSize = 44.0;
  static const _trackHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: LayoutBuilder(builder: (context, c) {
        final maxDrag = c.maxWidth - _thumbSize - 8;
        final pct = maxDrag <= 0 ? 0.0 : (_dragPx / maxDrag).clamp(0.0, 1.0);
        return Stack(children: [
          Container(
            height: _trackHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFD5CF)),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: pct > 0.85
                    ? const [Color(0xFFFCEBEB), Color(0xFFFFD5CF)]
                    : [_ActiveBookingDetailScreenState._obg.withValues(alpha: 0.5),
                        _ActiveBookingDetailScreenState._obg],
              ),
            ),
            alignment: Alignment.center,
            child: _triggered
                ? const Text('ההזמנה בוטלה',
                    style: TextStyle(
                        color: Color(0xFFA32D2D),
                        fontWeight: FontWeight.w600,
                        fontSize: 14))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded,
                          size: 14,
                          color: _ActiveBookingDetailScreenState._o),
                      const SizedBox(width: 2),
                      Text('החלק לביטול הזמנה',
                          style: TextStyle(
                            color: _ActiveBookingDetailScreenState._o
                                .withValues(alpha: 0.85),
                            fontSize: 13,
                          )),
                    ],
                  ),
          ),
          if (!_triggered)
            PositionedDirectional(
              top: 4,
              start: 4 + _dragPx,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) {
                  // RTL: primary direction for cancel is visually → left.
                  // The delta from the gesture is already in screen pixels;
                  // dragging "toward left" == negative dx. We flip for RTL
                  // so we measure progress as we drag away from the start.
                  setState(() {
                    _dragPx = (_dragPx - d.delta.dx).clamp(0.0, maxDrag);
                  });
                },
                onHorizontalDragEnd: (_) {
                  if (_dragPx / maxDrag >= 0.85) {
                    setState(() => _triggered = true);
                    Future.microtask(() async {
                      await widget.onCancelled();
                      if (mounted) {
                        setState(() {
                          _triggered = false;
                          _dragPx = 0;
                        });
                      }
                    });
                  } else {
                    setState(() => _dragPx = 0);
                  }
                },
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    color: _ActiveBookingDetailScreenState._o,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: _ActiveBookingDetailScreenState._o
                              .withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// TRUST BAR
// ══════════════════════════════════════════════════════════════════════

class _TrustBar extends StatelessWidget {
  const _TrustBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 8,
        children: const [
          _TrustItem(icon: Icons.shield_rounded, label: 'תשלום מאובטח'),
          _TrustItem(
              icon: Icons.verified_rounded, label: 'נותני שירות מאומתים'),
          _TrustItem(
              icon: Icons.support_agent_rounded, label: 'תמיכה 24/7'),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: _ActiveBookingDetailScreenState._pl),
      const SizedBox(width: 5),
      Text(label,
          style: const TextStyle(
              fontSize: 11,
              color: _ActiveBookingDetailScreenState._grl)),
    ]);
  }
}
