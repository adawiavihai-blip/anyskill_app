// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'expert_profile_screen.dart';
import 'chat_screen.dart';
import '../services/ai_analysis_service.dart';
import '../l10n/app_localizations.dart';

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text(AppLocalizations.of(context).requestsTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('job_requests')
            .where('clientId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _buildEmpty(context);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return _RequestStatusCard(
                key: ValueKey(docs[index].id),
                requestId: docs[index].id,
                data: docs[index].data() as Map<String, dynamic>,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.campaign_rounded,
                color: Colors.white, size: 42),
          ),
          const SizedBox(height: 26),
          Text(l10n.requestsEmpty,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            l10n.requestsEmptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: Colors.grey[500], height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ─── Request status card ──────────────────────────────────────────────────────

class _RequestStatusCard extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;

  const _RequestStatusCard(
      {super.key, required this.requestId, required this.data});

  String _timeAgo(Timestamp? ts, AppLocalizations l10n) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return l10n.requestsJustNow;
    if (diff.inMinutes < 60) return l10n.requestsMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.requestsHoursAgo(diff.inHours);
    return l10n.requestsDaysAgo(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final description =
        (data['description'] ?? '') as String;
    final category = (data['category'] ?? '') as String;
    final status = (data['status'] ?? 'open') as String;
    final isClosed = status == 'closed';
    final interestedProviders =
        List<String>.from(data['interestedProviders'] ?? []);
    final count = interestedProviders.length;
    final ts = data['createdAt'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: isClosed
                ? Colors.black.withValues(alpha: 0.04)
                : const Color(0xFF6366F1).withValues(alpha: 0.09),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gradient header ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              gradient: isClosed
                  ? LinearGradient(
                      colors: [Colors.grey[200]!, Colors.grey[100]!])
                  : const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Interest count pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isClosed
                        ? Colors.grey[300]
                        : Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        count > 0
                            ? Icons.people_rounded
                            : Icons.people_outline_rounded,
                        size: 13,
                        color: isClosed
                            ? Colors.grey[600]
                            : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        count > 0
                            ? l10n.requestsInterested(count)
                            : l10n.requestsWaiting,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isClosed
                              ? Colors.grey[600]
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _timeAgo(ts, l10n),
                  style: TextStyle(
                    fontSize: 11,
                    color: isClosed ? Colors.grey[400] : Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (category.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(category,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  description,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 15, height: 1.5, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                if (count > 0)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.people_rounded,
                          color: Colors.white, size: 18),
                      label: Text(
                        l10n.requestsViewInterested(count),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      onPressed: () => _showInterestedProviders(
                          context, interestedProviders, description),
                    ),
                  ),
                if (count == 0 && !isClosed) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.grey[300],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.requestsWaitingProviders,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ],
                if (isClosed && count == 0)
                  Text(l10n.requestsClosed,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[400])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInterestedProviders(BuildContext context,
      List<String> providerIds, String requestDescription) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InterestedProvidersSheet(
        providerIds: providerIds,
        requestDescription: requestDescription,
      ),
    );
  }
}

// ─── Interested providers bottom sheet ───────────────────────────────────────

class _InterestedProvidersSheet extends StatefulWidget {
  final List<String> providerIds;
  final String requestDescription;

  const _InterestedProvidersSheet({
    required this.providerIds,
    required this.requestDescription,
  });

  @override
  State<_InterestedProvidersSheet> createState() =>
      _InterestedProvidersSheetState();
}

class _InterestedProvidersSheetState
    extends State<_InterestedProvidersSheet> {
  List<Map<String, dynamic>>? _providers;
  int _bestValueIdx = -1;
  int _fastestResponseIdx = -1;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    if (widget.providerIds.isEmpty) {
      if (mounted) setState(() => _providers = []);
      return;
    }
    final db = FirebaseFirestore.instance;
    final snaps = await Future.wait(
      widget.providerIds
          .map((id) => db.collection('users').doc(id).get()),
    );
    final providers = snaps
        .where((s) => s.exists)
        .map((s) {
          final d = Map<String, dynamic>.from(s.data()!);
          d['uid'] = s.id;
          return d;
        })
        .toList();

    // Sort by AI match score (highest first)
    providers.sort((a, b) =>
        AiAnalysisService.scoreProvider(b, widget.requestDescription)
            .compareTo(AiAnalysisService.scoreProvider(
                a, widget.requestDescription)));

    // Best Value = lowest pricePerHour (among providers with a set price)
    int bestValueIdx = -1;
    int lowestPrice = 999999;
    for (int i = 0; i < providers.length; i++) {
      final price = (providers[i]['pricePerHour'] as num? ?? 0).toInt();
      if (price > 0 && price < lowestPrice) {
        lowestPrice = price;
        bestValueIdx = i;
      }
    }

    // Fastest Response = highest orderCount (proxy), excluding bestValue slot
    int fastestResponseIdx = -1;
    int highestOrders = -1;
    for (int i = 0; i < providers.length; i++) {
      if (i == bestValueIdx) continue;
      final orders = (providers[i]['orderCount'] as num? ?? 0).toInt();
      if (orders > highestOrders) {
        highestOrders = orders;
        fastestResponseIdx = i;
      }
    }

    if (mounted) {
      setState(() {
        _providers = providers;
        _bestValueIdx = bestValueIdx;
        _fastestResponseIdx = fastestResponseIdx;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(AppLocalizations.of(ctx).requestsInterestedTitle,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold)),
                  if (_providers != null && _providers!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_providers!.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Provider list
            Expanded(
              child: _providers == null
                  ? const Center(child: CircularProgressIndicator())
                  : _providers!.isEmpty
                      ? Center(child: Text(AppLocalizations.of(context).requestsNoInterested))
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                          itemCount: _providers!.length,
                          itemBuilder: (ctx, index) => _ProviderMatchCard(
                            key: ValueKey(_providers![index]['uid']),
                            provider: _providers![index],
                            isTopMatch: index == 0,
                            score: AiAnalysisService.scoreProvider(
                                _providers![index],
                                widget.requestDescription),
                            requestDescription: widget.requestDescription,
                            badge: index == _bestValueIdx
                                ? _ComparisonBadge.bestValue
                                : index == _fastestResponseIdx
                                    ? _ComparisonBadge.fastestResponse
                                    : _ComparisonBadge.none,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Comparison badge type ────────────────────────────────────────────────────

enum _ComparisonBadge { none, bestValue, fastestResponse }

// ─── Provider match card ──────────────────────────────────────────────────────

class _ProviderMatchCard extends StatefulWidget {
  final Map<String, dynamic> provider;
  final bool isTopMatch;
  final double score;
  final String requestDescription;
  final _ComparisonBadge badge;

  const _ProviderMatchCard({
    super.key,
    required this.provider,
    required this.isTopMatch,
    required this.score,
    required this.requestDescription,
    this.badge = _ComparisonBadge.none,
  });

  @override
  State<_ProviderMatchCard> createState() => _ProviderMatchCardState();
}

class _ProviderMatchCardState extends State<_ProviderMatchCard> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  String? _lastHiredAgo;

  @override
  void initState() {
    super.initState();
    _loadVideoUrl();
    _loadLastHired();
  }

  Future<void> _loadVideoUrl() async {
    final uid = widget.provider['uid'] as String? ?? '';
    if (uid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('stories')
          .doc(uid)
          .get();
      final videoUrl =
          ((doc.data() ?? {})['videoUrl'] as String?) ?? '';
      if (videoUrl.isEmpty || !mounted) return;
      final ctrl =
          VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await ctrl.initialize();
      ctrl.setVolume(0);
      ctrl.setLooping(true);
      ctrl.play();
      if (mounted) {
        setState(() {
          _videoCtrl = ctrl;
          _videoReady = true;
        });
      } else {
        ctrl.dispose();
      }
    } catch (_) {}
  }

  Future<void> _loadLastHired() async {
    final uid = widget.provider['uid'] as String? ?? '';
    if (uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .where('expertId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty || !mounted) return;
      final ts =
          snap.docs.first.data()['createdAt'] as Timestamp?;
      if (ts == null) return;
      final diff = DateTime.now().difference(ts.toDate());
      // Store raw duration — format with l10n in build()
      final String label;
      if (diff.inMinutes < 60) {
        label = 'minutes:${diff.inMinutes}';
      } else if (diff.inHours < 24) {
        label = 'hours:${diff.inHours}';
      } else {
        label = 'days:${diff.inDays}';
      }
      if (mounted) setState(() => _lastHiredAgo = label);
    } catch (_) {}
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  // ── Decode raw duration label stored by _loadLastHired ───────────────────────
  String _hiredAgoLabel(String raw, AppLocalizations l10n) {
    if (raw.startsWith('minutes:')) {
      return l10n.requestsMinutesAgo(int.parse(raw.substring(8)));
    } else if (raw.startsWith('hours:')) {
      return l10n.requestsHoursAgo(int.parse(raw.substring(6)));
    } else if (raw.startsWith('days:')) {
      return l10n.requestsDaysAgo(int.parse(raw.substring(5)));
    }
    return raw;
  }

  // ── Confidence score label ──────────────────────────────────────────────────
  String _confidenceLabel() {
    final rating =
        (widget.provider['rating'] as num? ?? 5.0).toDouble();
    final orders =
        (widget.provider['orderCount'] as num? ?? 0).toInt();
    final xp = (widget.provider['xp'] as num? ?? 0).toInt();
    final composite = (rating / 5.0) * 40.0 +
        (orders.clamp(0, 50) / 50.0) * 40.0 +
        (xp.clamp(0, 500) / 500.0) * 20.0;
    if (composite >= 85) return 'Top 5% באזורך';
    if (composite >= 65) return 'Top 10% באזורך';
    final successRate =
        ((rating / 5.0) * 100).toInt().clamp(0, 100);
    return '$successRate% שיעור הצלחה';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = widget.provider;
    final name = (p['name'] ?? l10n.requestsDefaultExpert) as String;
    final rating = (p['rating'] as num? ?? 5.0).toDouble();
    final reviewsCount = (p['reviewsCount'] as num? ?? 0).toInt();
    final serviceType = (p['serviceType'] ?? '') as String;
    final aboutMe = (p['aboutMe'] ?? '') as String;
    final profileImage = (p['profileImage'] ?? '') as String;
    final isVerified = (p['isVerified'] ?? false) as bool;
    final orderCount = (p['orderCount'] as num? ?? 0).toInt();
    final pricePerHour = (p['pricePerHour'] as num? ?? 0).toInt();
    final uid = (p['uid'] ?? '') as String;
    final scorePercent = (widget.score / 100.0).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: widget.isTopMatch
            ? Border.all(
                color: const Color(0xFFFFB800).withValues(alpha: 0.6),
                width: 2)
            : Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: widget.isTopMatch
                ? const Color(0xFFFFB800).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Match golden banner ────────────────────────────────────
          if (widget.isTopMatch)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    l10n.requestsTopMatch,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Provider info row ──────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with video indicator
                    Stack(children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.blue[50],
                        backgroundImage: profileImage.isNotEmpty
                            ? NetworkImage(profileImage)
                            : null,
                        child: profileImage.isEmpty
                            ? const Icon(Icons.person, size: 28)
                            : null,
                      ),
                      if (_videoReady)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6366F1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                size: 12, color: Colors.white),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            if (isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified,
                                  color: Color(0xFF1877F2), size: 16),
                            ],
                          ]),
                          Text(serviceType,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 14),
                            Text(' ${rating.toStringAsFixed(1)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Text(' ($reviewsCount)',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            if (orderCount > 0) ...[
                              const SizedBox(width: 8),
                              Text(l10n.requestsOrderCount(orderCount),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFD4520A),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── Confidence Score badge ─────────────────────────
                    _buildConfidenceBadge(),
                  ],
                ),

                // ── Video Intro Preview ────────────────────────────────
                if (_videoReady && _videoCtrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 140,
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoCtrl!.value.size.width,
                            height: _videoCtrl!.value.size.height,
                            child: VideoPlayer(_videoCtrl!),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Bio ───────────────────────────────────────────────
                if (aboutMe.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    aboutMe,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        height: 1.4),
                  ),
                ],

                // ── Social proof + price + comparison badges ───────────
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_lastHiredAgo != null)
                      _chip(
                        icon: Icons.circle,
                        iconColor: Colors.green,
                        iconSize: 7,
                        label: l10n.requestsHiredAgo(_hiredAgoLabel(_lastHiredAgo!, l10n)),
                        bg: Colors.green[50]!,
                        fg: Colors.green[700]!,
                      ),
                    if (pricePerHour > 0)
                      _chip(
                        icon: Icons.attach_money_rounded,
                        iconColor: const Color(0xFF6366F1),
                        label: l10n.requestsPricePerHour(pricePerHour.toString()),
                        bg: const Color(0xFFF0F0FF),
                        fg: const Color(0xFF6366F1),
                      ),
                    if (widget.badge != _ComparisonBadge.none)
                      _buildComparisonBadge(),
                  ],
                ),

                // ── AnySkill Verified + Escrow badge ──────────────────
                const SizedBox(height: 10),
                Tooltip(
                  triggerMode: TooltipTriggerMode.tap,
                  message: l10n.requestsEscrowTooltip,
                  preferBelow: false,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                      color: Colors.white, fontSize: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FFF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF22C55E)
                              .withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_rounded,
                            size: 14, color: Color(0xFF16A34A)),
                        const SizedBox(width: 6),
                        Text(
                          l10n.requestsVerifiedBadge,
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.info_outline_rounded,
                            size: 12,
                            color: const Color(0xFF16A34A)
                                .withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),

                // ── Match score bar ────────────────────────────────────
                const SizedBox(height: 12),
                Row(children: [
                  Text(l10n.requestsMatchLabel,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: scorePercent,
                        minHeight: 5,
                        backgroundColor: Colors.grey[100],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isTopMatch
                              ? const Color(0xFFFFB800)
                              : const Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(scorePercent * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: widget.isTopMatch
                          ? const Color(0xFFD97706)
                          : const Color(0xFF6366F1),
                    ),
                  ),
                ]),

                const SizedBox(height: 14),

                // ── Action bar ─────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFF6366F1)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline,
                          size: 16, color: Color(0xFF6366F1)),
                      label: Text(l10n.requestsChatNow,
                          style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              receiverId: uid,
                              receiverName: name,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.lock_rounded,
                          size: 16, color: Colors.white),
                      label: Text(l10n.requestsConfirmPay,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExpertProfileScreen(
                              expertId: uid,
                              expertName: name,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ]),

                // Escrow caption
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(l10n.requestsMoneyProtected,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[400])),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _buildConfidenceBadge() {
    final label = _confidenceLabel();
    final isTop = label.startsWith('Top');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: isTop
            ? const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])
            : const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildComparisonBadge() {
    final isBestValue = widget.badge == _ComparisonBadge.bestValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isBestValue
            ? Colors.green[600]
            : const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isBestValue
              ? Icons.savings_rounded
              : Icons.bolt_rounded,
          size: 11,
          color: Colors.white,
        ),
        const SizedBox(width: 3),
        Text(
          isBestValue ? AppLocalizations.of(context).requestsBestValue : AppLocalizations.of(context).requestsFastResponse,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold),
        ),
      ]),
    );
  }

  static Widget _chip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color bg,
    required Color fg,
    double iconSize = 13,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: iconSize, color: iconColor),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: fg,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
