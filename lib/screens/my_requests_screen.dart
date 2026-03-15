import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'expert_profile_screen.dart';
import 'chat_screen.dart';
import '../services/ai_analysis_service.dart';

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
        title: const Text('הבקשות שלי',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
            return _buildEmpty();
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

  Widget _buildEmpty() {
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
          const Text('אין בקשות פעילות',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            'שדר בקשה מהירה ותוך שניות\nספקים מקצועיים יפנו אליך!',
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

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'הרגע';
    if (diff.inMinutes < 60) return "לפני ${diff.inMinutes} דק'";
    if (diff.inHours < 24) return "לפני ${diff.inHours} שע'";
    return 'לפני ${diff.inDays} ימים';
  }

  @override
  Widget build(BuildContext context) {
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
                            ? '$count מתעניינים'
                            : 'ממתין למתעניינים...',
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
                  _timeAgo(ts),
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
                        'צפה ב-$count מתעניינים',
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
                        'ממתין לספקים מתעניינים...',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ],
                if (isClosed && count == 0)
                  Text('הבקשה נסגרה',
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
  int _topMatchIdx = 0;

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

    if (mounted) {
      setState(() {
        _providers = providers;
        _topMatchIdx = providers.isNotEmpty ? 0 : 0; // highest score is index 0 after sort
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
                  const Text('מתעניינים בבקשתך',
                      style: TextStyle(
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
                      ? const Center(child: Text('אין מתעניינים עדיין'))
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                          itemCount: _providers!.length,
                          itemBuilder: (ctx, index) =>
                              _ProviderMatchCard(
                                provider: _providers![index],
                                isTopMatch: index == _topMatchIdx,
                                score: AiAnalysisService.scoreProvider(
                                    _providers![index],
                                    widget.requestDescription),
                                requestDescription:
                                    widget.requestDescription,
                              ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Provider match card (with Top Match badge) ───────────────────────────────

class _ProviderMatchCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  final bool isTopMatch;
  final double score;
  final String requestDescription;

  const _ProviderMatchCard({
    required this.provider,
    required this.isTopMatch,
    required this.score,
    required this.requestDescription,
  });

  @override
  Widget build(BuildContext context) {
    final name = (provider['name'] ?? 'מומחה') as String;
    final rating = (provider['rating'] as num? ?? 5.0).toDouble();
    final reviewsCount = (provider['reviewsCount'] as num? ?? 0).toInt();
    final serviceType = (provider['serviceType'] ?? '') as String;
    final aboutMe = (provider['aboutMe'] ?? '') as String;
    final profileImage = (provider['profileImage'] ?? '') as String;
    final isVerified = (provider['isVerified'] ?? false) as bool;
    final orderCount = (provider['orderCount'] as num? ?? 0).toInt();
    final uid = (provider['uid'] ?? '') as String;
    final scorePercent = (score / 100.0).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isTopMatch
            ? Border.all(
                color: const Color(0xFFFFB800).withValues(alpha: 0.6),
                width: 2)
            : Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: isTopMatch
                ? const Color(0xFFFFB800).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, isTopMatch ? 42 : 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider info row
                Row(
                  children: [
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
                            Text(' $rating',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Text(' ($reviewsCount)',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            if (orderCount > 0) ...[
                              const SizedBox(width: 8),
                              const Text('🔥',
                                  style: TextStyle(fontSize: 12)),
                              Text(' $orderCount הזמנות',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFD4520A),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),

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

                // Match score bar
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('התאמה',
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
                            isTopMatch
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
                        color: isTopMatch
                            ? const Color(0xFFD97706)
                            : const Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Action buttons
                Row(
                  children: [
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
                        label: const Text('שלח הודעה',
                            style: TextStyle(
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
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.person_outline,
                            size: 16, color: Colors.white),
                        label: const Text('פרופיל',
                            style: TextStyle(
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
                  ],
                ),
              ],
            ),
          ),

          // ── Top Match badge (golden banner, top of card) ──────────────
          if (isTopMatch)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🏆', style: TextStyle(fontSize: 13)),
                    SizedBox(width: 6),
                    Text(
                      'התאמה הטובה ביותר',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.3,
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
