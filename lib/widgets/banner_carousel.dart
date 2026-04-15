// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/expert_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BannerCarousel
//
// Self-contained promotional banner PageView.
// Reads from the `banners` Firestore collection (same collection managed by
// the admin Banners tab).  Filters client-side for isActive + non-expired docs.
//
// Usage: const BannerCarousel()
// ─────────────────────────────────────────────────────────────────────────────

class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  // Fixed dimensions — never change, so there are no layout jumps
  static const double _cardH  = 118.0;
  static const double _totalH = 141.0; // cardH + 10 gap + 7 dots + 6 padding

  final PageController _ctrl = PageController();
  int   _currentPage = 0;
  bool  _loading     = true;
  Timer? _timer;
  StreamSubscription<QuerySnapshot>? _sub;

  List<Map<String, dynamic>> _liveBanners = [];
  String _memoKey = '';

  // ── Fallback shown while Firestore loads or collection is empty ─────────────
  static const _fallback = <Map<String, dynamic>>[
    {'title': 'מצא מומחים מובילים', 'subtitle': 'אלפי מומחים מחכים לך',       'color1': '667eea', 'color2': '764ba2', 'iconName': 'stars'},
    {'title': 'שיעורים פרטיים',      'subtitle': 'ממש מהמקום שאתה נמצא',     'color1': '11998e', 'color2': '38ef7d', 'iconName': 'school'},
    {'title': 'פתח את הפוטנציאל שלך','subtitle': 'עם המומחים הטובים ביותר', 'color1': 'f953c6', 'color2': 'b91d73', 'iconName': 'emoji_events'},
  ];

  static const _icons = <String, IconData>{
    'stars':             Icons.stars_rounded,
    'school':            Icons.school_rounded,
    'emoji_events':      Icons.emoji_events_rounded,
    'favorite':          Icons.favorite_rounded,
    'bolt':              Icons.bolt_rounded,
    'local_offer':       Icons.local_offer_rounded,
    'rocket_launch':     Icons.rocket_launch_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'celebration':       Icons.celebration_rounded,
    'trending_up':       Icons.trending_up_rounded,
  };

  static Color _hex(String h) {
    final c = h.replaceAll('#', '').replaceAll('0x', '');
    return Color(int.parse(c.length == 6 ? 'FF$c' : c, radix: 16));
  }

  List<Map<String, dynamic>> get _banners =>
      _liveBanners.isNotEmpty ? _liveBanners : _fallback;

  @override
  void initState() {
    super.initState();

    // Firestore subscription — no where() to avoid composite-index requirement;
    // filter isActive client-side.
    _sub = FirebaseFirestore.instance
        .collection('banners')
        .orderBy('order')
        .limit(50)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;

        final now     = DateTime.now();
        final newList = snap.docs
            .map((d) => {...d.data(), '_id': d.id})
            .where((b) {
              if (b['isActive'] != true) return false;
              final expires = (b['expiresAt'] as Timestamp?)?.toDate();
              return expires == null || expires.isAfter(now);
            })
            .toList();

        // Memoize by doc-ID string — skip setState if nothing changed
        final newKey = snap.docs.map((d) => d.id).join(',');
        if (!_loading && newKey == _memoKey) return;

        // Clamp the current page if the list shrank
        final clamped = (newList.isNotEmpty && _currentPage >= newList.length)
            ? 0
            : _currentPage;
        final needsJump = clamped != _currentPage;

        setState(() {
          _loading     = false;
          _liveBanners = newList;
          _currentPage = clamped;
          _memoKey     = newKey;
        });

        if (needsJump) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _ctrl.hasClients) _ctrl.jumpToPage(0);
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );

    // Auto-advance timer
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final count = _banners.length;
      if (count <= 1) return;
      final pos = _ctrl.page ?? 0.0;
      if ((pos - pos.round()).abs() > 0.01) return;
      _ctrl.animateToPage(
        (_currentPage + 1) % count,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _totalH,
      child: _loading ? _buildShimmer() : _buildCarousel(),
    );
  }

  Widget _buildShimmer() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _BannerShimmer(height: _cardH),
      );

  Widget _buildCarousel() {
    final banners = _banners;
    return Column(children: [
      SizedBox(
        height: _cardH,
        child: PageView.builder(
          controller: _ctrl,
          allowImplicitScrolling: true,
          physics: const PageScrollPhysics(),
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemCount: banners.length,
          itemBuilder: (context, i) => _BannerPage(
            key: ValueKey(banners[i]['title'] ?? i),
            data: banners[i],
            icons: _icons,
            hexToColor: _hex,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          banners.length,
          (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width:  _currentPage == i ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: _currentPage == i
                  ? const Color(0xFF007AFF)
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─── Individual banner page ───────────────────────────────────────────────────

class _BannerPage extends StatefulWidget {
  final Map<String, dynamic>   data;
  final Map<String, IconData>  icons;
  final Color Function(String) hexToColor;

  const _BannerPage({
    super.key,
    required this.data,
    required this.icons,
    required this.hexToColor,
  });

  @override
  State<_BannerPage> createState() => _BannerPageState();
}

class _BannerPageState extends State<_BannerPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final b            = widget.data;
    final color1       = widget.hexToColor(b['color1']       as String? ?? '667eea');
    final color2       = widget.hexToColor(b['color2']       as String? ?? '764ba2');
    final icon         = widget.icons[b['iconName'] as String? ?? 'stars'] ??
        Icons.stars_rounded;
    final title        = b['title']        as String? ?? '';
    final subtitle     = b['subtitle']     as String? ?? '';
    final providerId   = b['providerId']   as String?;
    final providerName = b['providerName'] as String? ?? '';

    void onTap() {
      if (providerId != null && providerId.isNotEmpty) {
        final bannerId = b['_id'] as String?;
        if (bannerId != null && bannerId.isNotEmpty) {
          FirebaseFirestore.instance
              .collection('banners')
              .doc(bannerId)
              .update({'clicks': FieldValue.increment(1)});
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExpertProfileScreen(
              expertId: providerId,
              expertName: providerName,
            ),
          ),
        );
      }
    }

    return GestureDetector(
      onTap: providerId != null ? onTap : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
            color: color2.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color1, color2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(children: [
              // Decorative circles
              Positioned(left: -25, top: -25,
                child: Container(width: 120, height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12)))),
              Positioned(left: 40, bottom: -35,
                child: Container(width: 90, height: 90,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08)))),
              Positioned(right: -15, top: -15,
                child: Container(width: 70, height: 70,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07)))),

              // "View profile" badge — featured-provider banners only
              if (providerId != null)
                Positioned(
                  bottom: 10, left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('לפרופיל', style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 10, color: Colors.white.withValues(alpha: 0.95)),
                    ]),
                  ),
                ),

              // Content row
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Glass icon box
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35), width: 1),
                            ),
                            child: Icon(icon, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Text block
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(title,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                height: 1.25,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            // Glass subtitle pill
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.28),
                                      width: 1),
                                  ),
                                  child: Text(subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Shimmer placeholder ──────────────────────────────────────────────────────

class _BannerShimmer extends StatefulWidget {
  final double height;
  const _BannerShimmer({required this.height});

  @override
  State<_BannerShimmer> createState() => _BannerShimmerState();
}

class _BannerShimmerState extends State<_BannerShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(children: [
            const SizedBox(width: 16),
            Container(width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(height: 16, width: double.infinity,
                      decoration: BoxDecoration(color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8))),
                  const SizedBox(height: 10),
                  Container(height: 12, width: 140,
                      decoration: BoxDecoration(color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8))),
                ],
              ),
            ),
            const SizedBox(width: 20),
          ]),
        ),
      ),
    );
  }
}
