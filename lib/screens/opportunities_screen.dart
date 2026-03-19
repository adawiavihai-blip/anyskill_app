// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';
import '../services/location_service.dart';
import '../services/gamification_service.dart';
import '../widgets/level_badge.dart';
import '../l10n/app_localizations.dart';

// ── Sort modes (user-selectable filter chips) ─────────────────────────────────
enum _SortMode { nearest, profitable, urgent }

// ── Palette ───────────────────────────────────────────────────────────────────
const _kIndigo   = Color(0xFF6366F1);
const _kUrgentOr = Color(0xFFF97316); // orange-500 — urgent border & CTA
const _kAmber    = Color(0xFFF59E0B); // amber-400 — warm state

// ── Temperature tiers (purely time-based) ─────────────────────────────────────
// HOT  : posted < 10 minutes ago — pulsing orange border + HOT 🔥 badge
// WARM : posted 10–60 minutes ago — solid amber border + ⏰ badge
// COOL : posted > 60 minutes ago — standard indigo styling
enum _CardTemperature { hot, warm, cool }

_CardTemperature _temperatureOf(Timestamp? ts) {
  if (ts == null) return _CardTemperature.cool;
  final ageMin = DateTime.now().difference(ts.toDate()).inMinutes;
  if (ageMin < 10) return _CardTemperature.hot;
  if (ageMin < 60) return _CardTemperature.warm;
  return _CardTemperature.cool;
}

// ── Entry widget ──────────────────────────────────────────────────────────────
class OpportunitiesScreen extends StatefulWidget {
  final String serviceType;
  final String providerName;
  final bool isAdmin;

  const OpportunitiesScreen({
    super.key,
    required this.serviceType,
    required this.providerName,
    this.isAdmin = false,
  });

  @override
  State<OpportunitiesScreen> createState() => _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends State<OpportunitiesScreen> {
  final String      _uid            = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Set<String> _processingIds  = {};
  Position?  _currentPosition;
  int        _xp               = 0;
  int        _urgentCompleted  = 0;   // progress toward AnySkill Boost
  DateTime?  _boostExpiry;            // non-null when boost is active
  double     _platformFee      = 0.15; // loaded from Firestore; 15 % default
  Timer?     _tickTimer;              // periodic rebuild so temperature cools in real-time
  _SortMode  _sortMode         = _SortMode.nearest;

  @override
  void initState() {
    super.initState();
    final cached = LocationService.cached;
    if (cached != null) {
      _currentPosition = cached;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final pos = await LocationService.requestAndGet(context);
        if (mounted && pos != null) setState(() => _currentPosition = pos);
      });
    }
    _loadUserData();
    _loadPlatformFee();
    // Rebuild every 60 s so "Posted X min ago" labels and card temperatures
    // update without waiting for a Firestore event.
    _tickTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (_uid.isEmpty) return;
    final snap = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    if (!snap.exists || !mounted) return;
    final d      = snap.data()!;
    final boostTs = d['boostedUntil'] as Timestamp?;
    setState(() {
      _xp             = (d['xp']                 as num? ?? 0).toInt();
      _urgentCompleted = (d['urgentJobsCompleted'] as num? ?? 0).toInt();
      _boostExpiry     = boostTs?.toDate();
    });
  }

  Future<void> _loadPlatformFee() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin').doc('admin')
          .collection('settings').doc('settings').get();
      final fee = (doc.data()?['feePercentage'] as num?)?.toDouble();
      if (fee != null && mounted) setState(() => _platformFee = fee / 100);
    } catch (_) {}
  }

  String _getChatRoomId(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  Future<void> _expressInterest(
    BuildContext context,
    String requestId,
    String clientId,
    String clientName,
    String description, {
    String? customMessage,
    bool isUrgent = false,
  }) async {
    if (_processingIds.contains(requestId)) return;
    setState(() => _processingIds.add(requestId));

    final db     = FirebaseFirestore.instance;
    final reqRef = db.collection('job_requests').doc(requestId);
    final chatRoomId = _getChatRoomId(_uid, clientId);

    try {
      final l10n = AppLocalizations.of(context);
      final msgRequestUnavailable = l10n.oppRequestUnavailable;
      final msgRequestClosed3     = l10n.oppRequestClosed3;
      final msgAlreadyExpressed   = l10n.oppAlreadyExpressed;
      final msgAlready3           = l10n.oppAlready3Interested;
      final msgBoostEarned        = l10n.oppBoostEarned;
      final msgInterestSuccess    = l10n.oppInterestSuccess;
      await db.runTransaction((tx) async {
        final snap = await tx.get(reqRef);
        if (!snap.exists) throw msgRequestUnavailable;
        final d         = snap.data()!;
        final count     = (d['interestedCount']    ?? 0) as int;
        final providers = List<String>.from(d['interestedProviders'] ?? []);
        if (d['status'] == 'closed') throw msgRequestClosed3;
        if (providers.contains(_uid)) throw msgAlreadyExpressed;
        if (count >= 3) throw msgAlready3;
        final newCount = count + 1;
        tx.update(reqRef, {
          'interestedProviders':     FieldValue.arrayUnion([_uid]),
          'interestedProviderNames': FieldValue.arrayUnion([widget.providerName]),
          'interestedCount':         FieldValue.increment(1),
          if (newCount >= 3) 'status': 'closed',
        });
      });

      // Open/init chat
      final chatRef = db.collection('chats').doc(chatRoomId);
      await chatRef.set({'users': [_uid, clientId]}, SetOptions(merge: true));
      final msg = customMessage ??
          AppLocalizations.of(context).oppInterestChatMessage(widget.providerName, description);
      await chatRef.collection('messages').add({
        'senderId':  'system',
        'message':   msg,
        'type':      'text',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Notify client
      final notifL10n = AppLocalizations.of(context);
      await db.collection('notifications').doc(clientId)
          .collection('userNotifications').add({
        'title':        notifL10n.oppNotifTitle,
        'body':         notifL10n.oppNotifBody(widget.providerName),
        'type':         'interest',
        'requestId':    requestId,
        'providerId':   _uid,
        'providerName': widget.providerName,
        'chatRoomId':   chatRoomId,
        'createdAt':    FieldValue.serverTimestamp(),
        'isRead':       false,
      });

      // AnySkill Boost — track urgent completions
      if (isUrgent) {
        final next        = _urgentCompleted + 1;
        final boostEarned = next >= 3;
        await db.collection('users').doc(_uid).update({
          'urgentJobsCompleted': boostEarned ? 0 : FieldValue.increment(1),
          if (boostEarned) 'boostedUntil': Timestamp.fromDate(
              DateTime.now().add(const Duration(hours: 24))),
        });
        if (mounted) {
          setState(() {
            if (boostEarned) {
              _urgentCompleted = 0;
              _boostExpiry     = DateTime.now().add(const Duration(hours: 24));
            } else {
              _urgentCompleted = next;
            }
          });
        }
        if (!context.mounted) return;
        if (boostEarned) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: _kUrgentOr,
            duration: const Duration(seconds: 5),
            content: Text(
              msgBoostEarned,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ));
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(receiverId: clientId, receiverName: clientName),
          ));
          return;
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(msgInterestSuccess),
        duration: const Duration(seconds: 3),
      ));
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(receiverId: clientId, receiverName: clientName),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _processingIds.remove(requestId));
    }
  }

  Stream<QuerySnapshot> _buildQuery() {
    // Only fetch documents from the last 24 hours — keeps the board fresh
    // and the Firestore read count low.
    final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 24)));
    var q = FirebaseFirestore.instance
        .collection('job_requests')
        .where('status',    isEqualTo: 'open')
        .where('createdAt', isGreaterThan: cutoff);
    if (!widget.isAdmin && widget.serviceType.isNotEmpty) {
      q = q.where('category', isEqualTo: widget.serviceType);
    }
    return q.orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  // Used only for the AnySkill Boost counter — "hot" = < 10 min old.
  bool _isUrgentData(Map<String, dynamic> d) =>
      _temperatureOf(d['createdAt'] as Timestamp?) == _CardTemperature.hot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Hard-lock: if this provider is not yet verified, show the review screen.
    if (!widget.isAdmin && _uid.isNotEmpty) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(_uid).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() as Map<String, dynamic>? ?? {};
          final isProvider         = data['isProvider']         as bool? ?? false;
          final isVerifiedProvider = data['isVerifiedProvider'] as bool? ?? true;

          // Show lock screen only for providers who haven't been approved yet.
          // Default true = existing users before this feature are unaffected.
          if (isProvider && !isVerifiedProvider) {
            return _buildUnderReviewScreen(AppLocalizations.of(context));
          }

          // Approved — show the normal screen
          return _buildNormalScaffold(AppLocalizations.of(context));
        },
      );
    }

    return _buildNormalScaffold(l10n);
  }

  Widget _buildUnderReviewScreen(AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(l10n.oppTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shield icon
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_outlined,
                    color: Color(0xFF6366F1), size: 52),
              ),
              const SizedBox(height: 28),

              Text(l10n.oppUnderReviewTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E1E2E))),
              const SizedBox(height: 8),
              Text(l10n.oppUnderReviewSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              Text(l10n.oppUnderReviewBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, height: 1.6, color: Colors.grey[700])),
              const SizedBox(height: 32),

              // Progress steps
              _buildReviewSteps(l10n),
              const SizedBox(height: 28),

              // Contact chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.email_outlined, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(l10n.oppUnderReviewContact,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewSteps(AppLocalizations l10n) {
    final steps = [
      {'label': l10n.oppUnderReviewStep1, 'done': true},
      {'label': l10n.oppUnderReviewStep2, 'done': false},
      {'label': l10n.oppUnderReviewStep3, 'done': false},
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          return Container(width: 28, height: 2, color: Colors.grey.shade300);
        }
        final step = steps[i ~/ 2];
        final done = step['done'] as bool;
        final active = i == 2; // step 2 = "Admin Review" = currently active
        return Column(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? const Color(0xFF10B981)
                    : active
                        ? const Color(0xFF6366F1)
                        : Colors.grey.shade200,
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                    : active
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.lock_outline_rounded,
                            color: Colors.grey.shade400, size: 14),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 70,
              child: Text(step['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      color: done || active ? Colors.black87 : Colors.grey,
                      fontWeight: done || active
                          ? FontWeight.w600
                          : FontWeight.normal)),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildNormalScaffold(AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Column(children: [
          Text(l10n.oppTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text(
            widget.serviceType.isEmpty ? l10n.oppAllCategories : widget.serviceType,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ]),
      ),
      body: Column(children: [
        _buildXpBanner(),
        _buildSortChips(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildQuery(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(l10n.oppError('${snapshot.error}')));
              }
              final docs = snapshot.data?.docs ?? [];
              final cutoff = DateTime.now().subtract(const Duration(hours: 24));
              var filtered = docs.where((doc) {
                final d   = doc.data() as Map<String, dynamic>;
                if (d['isActive'] == false) return false;
                final ts  = d['createdAt'] as Timestamp?;
                if (ts != null && ts.toDate().isBefore(cutoff)) return false;
                // "דחוף" filter: only HOT cards (< 10 min)
                if (_sortMode == _SortMode.urgent) {
                  return _temperatureOf(d['createdAt'] as Timestamp?) ==
                      _CardTemperature.hot;
                }
                return true;
              }).toList();

              // Sort based on selected mode
              switch (_sortMode) {
                case _SortMode.nearest:
                  if (_currentPosition != null) {
                    filtered.sort((a, b) {
                      final da    = a.data() as Map<String, dynamic>;
                      final dbMap = b.data() as Map<String, dynamic>;
                      final distA = LocationService.distanceMeters(
                        _currentPosition!.latitude, _currentPosition!.longitude,
                        (da['clientLat']    as num?)?.toDouble(),
                        (da['clientLng']    as num?)?.toDouble(),
                      );
                      final distB = LocationService.distanceMeters(
                        _currentPosition!.latitude, _currentPosition!.longitude,
                        (dbMap['clientLat'] as num?)?.toDouble(),
                        (dbMap['clientLng'] as num?)?.toDouble(),
                      );
                      if (distA == null && distB == null) return 0;
                      if (distA == null) return 1;
                      if (distB == null) return -1;
                      return distA.compareTo(distB);
                    });
                  }
                case _SortMode.profitable:
                  filtered.sort((a, b) {
                    final maxA = ((a.data() as Map)['budgetMax'] as num? ?? 0).toDouble();
                    final maxB = ((b.data() as Map)['budgetMax'] as num? ?? 0).toDouble();
                    return maxB.compareTo(maxA); // descending
                  });
                case _SortMode.urgent:
                  break; // already filtered to HOT, keep Firestore order
              }

              if (filtered.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final doc         = filtered[index];
                  final d           = doc.data() as Map<String, dynamic>;
                  final clientId    = (d['clientId']    ?? '') as String;
                  final clientName  = (d['clientName']  ?? l10n.oppDefaultClient) as String;
                  final description = (d['description'] ?? '') as String;
                  return _RequestCard(
                    key:             ValueKey(doc.id),
                    requestId:       doc.id,
                    data:            d,
                    currentUid:      _uid,
                    currentPosition: _currentPosition,
                    isProcessing:    _processingIds.contains(doc.id),
                    platformFee:     _platformFee,
                    providerName:    widget.providerName,
                    onInterest: () => _expressInterest(
                      context, doc.id, clientId, clientName, description,
                      isUrgent: _isUrgentData(d),
                    ),
                    onQuickBid: () => _expressInterest(
                      context, doc.id, clientId, clientName, description,
                      isUrgent: _isUrgentData(d),
                      customMessage: l10n.oppQuickBidMessage(clientName, widget.providerName),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── XP + AnySkill Boost banner ────────────────────────────────────────────
  Widget _buildXpBanner() {
    final l10n      = AppLocalizations.of(context);
    final level     = GamificationService.levelFor(_xp);
    final progress  = GamificationService.levelProgress(_xp);
    final isGold    = level == ProviderLevel.gold;
    final xpToNext  = GamificationService.xpToNextLevel(_xp);
    final nextName  = GamificationService.nextLevelName(level);
    final barColor  = GamificationService.levelProgressColor(level);
    final isBoosted = _boostExpiry != null && _boostExpiry!.isAfter(DateTime.now());
    final boostFrac = (_urgentCompleted / 3).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 3),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // XP row
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              if (_xp > 0) ...[LevelBadge(xp: _xp, size: 20), const SizedBox(width: 8)],
              Text('$_xp XP', style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
            ]),
            if (!isGold)
              Text(l10n.oppXpToNextLevel(xpToNext, nextName),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]))
            else
              Text(l10n.oppMaxLevel,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress, color: barColor,
              backgroundColor: Colors.grey[200], minHeight: 7,
            ),
          ),
          // AnySkill Boost row
          const SizedBox(height: 10),
          Row(children: [
            Icon(
              isBoosted ? Icons.rocket_launch_rounded : Icons.rocket_launch_outlined,
              size: 14,
              color: isBoosted ? _kUrgentOr : Colors.grey[500],
            ),
            const SizedBox(width: 6),
            Expanded(
              child: isBoosted
                  ? Text(l10n.oppProfileBoosted(_boostTimeLabel()),
                      style: const TextStyle(
                          fontSize: 11, color: _kUrgentOr, fontWeight: FontWeight.w700))
                  : Text(l10n.oppBoostProgress(_urgentCompleted),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ),
            if (!isBoosted) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: boostFrac, color: _kUrgentOr,
                    backgroundColor: Colors.grey[200], minHeight: 5,
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  String _boostTimeLabel() {
    if (_boostExpiry == null) return '';
    final l10n = AppLocalizations.of(context);
    final diff = _boostExpiry!.difference(DateTime.now());
    return diff.inHours >= 1
        ? l10n.oppTimeHours(diff.inHours)
        : l10n.oppTimeMinutes(diff.inMinutes);
  }

  Widget _buildEmptyState() {
    final l10n  = AppLocalizations.of(context);
    final isCat = !widget.isAdmin && widget.serviceType.isNotEmpty;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
              blurRadius: 24, offset: const Offset(0, 8),
            )],
          ),
          child: const Icon(Icons.work_outline_rounded, color: Colors.white, size: 46),
        ),
        const SizedBox(height: 28),
        Text(isCat ? l10n.oppEmptyCategory : l10n.oppEmptyAll,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          isCat ? l10n.oppEmptyCategorySubtitle : l10n.oppEmptyAllSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.6),
        ),
      ]),
    );
  }

  // ── Sort / filter chips ────────────────────────────────────────────────────
  Widget _buildSortChips() {
    const chips = [
      (_SortMode.nearest,    '📍 הכי קרוב'),
      (_SortMode.profitable, '💰 הכי רווחי'),
      (_SortMode.urgent,     '🔥 דחוף'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((e) {
            final selected = _sortMode == e.$1;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(e.$2),
                selected: selected,
                onSelected: (_) => setState(() => _sortMode = e.$1),
                selectedColor: _kIndigo,
                backgroundColor: const Color(0xFFF3F4F6),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Animated request card ─────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final String               requestId;
  final Map<String, dynamic> data;
  final String               currentUid;
  final Position?            currentPosition;
  final bool                 isProcessing;
  final double               platformFee;
  final String               providerName;
  final VoidCallback         onInterest;
  final VoidCallback         onQuickBid;

  const _RequestCard({
    super.key,
    required this.requestId,
    required this.data,
    required this.currentUid,
    this.currentPosition,
    required this.isProcessing,
    required this.platformFee,
    required this.providerName,
    required this.onInterest,
    required this.onQuickBid,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard>
    with TickerProviderStateMixin {
  // entrance
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;
  // HOT-state pulse (border + glow)
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;
  // local clock — updates timeAgo label + cools card without Firestore event
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _pulse = Tween<double>(begin: 0.3, end: 0.9)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    if (_temperature == _CardTemperature.hot &&
        widget.data['status'] != 'closed') {
      _pulseCtrl.repeat(reverse: true);
    }

    // Rebuild every 30 s so the time label refreshes and the card cools down
    // at the 10-minute and 60-minute boundaries without a Firestore event.
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_RequestCard old) {
    super.didUpdateWidget(old);
    final shouldPulse = _temperature == _CardTemperature.hot &&
        widget.data['status'] != 'closed';
    if (shouldPulse && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!shouldPulse && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _ctrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Computed properties ───────────────────────────────────────────────────

  _CardTemperature get _temperature =>
      _temperatureOf(widget.data['createdAt'] as Timestamp?);

  /// Simulated viewers: time-windowed seed so the number shifts every 5 min
  /// but stays stable within a window. Returns 0 for requests older than 2 h.
  int _viewersNow() {
    final ts = widget.data['createdAt'] as Timestamp?;
    if (ts == null) return 0;
    final age = DateTime.now().difference(ts.toDate());
    if (age.inHours >= 2) return 0;
    final window = DateTime.now().millisecondsSinceEpoch ~/ 300000; // 5-min bucket
    final seed   = widget.requestId.hashCode.abs() ^ window;
    return age.inMinutes < 30 ? 3 + (seed % 5) : 1 + (seed % 3);
  }

  /// Net earnings after platform fee, shown only when job has budget fields.
  String? _netEarningsLabel() {
    final minB = (widget.data['budgetMin'] as num?)?.toDouble();
    final maxB = (widget.data['budgetMax'] as num?)?.toDouble();
    if (minB == null || maxB == null || maxB <= 0) return null;
    final net = 1 - widget.platformFee;
    return '₪${(minB * net).round()} – ₪${(maxB * net).round()}';
  }

  String _timeAgo(DateTime dt) {
    final l10n = AppLocalizations.of(context);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return l10n.oppTimeJustNow;
    if (diff.inMinutes < 60) return l10n.oppTimeMinAgo(diff.inMinutes);
    if (diff.inHours   < 24) return l10n.oppTimeHourAgo(diff.inHours);
    return l10n.oppTimeDayAgo(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final l10n            = AppLocalizations.of(context);
    final d               = widget.data;
    final interestedCount = (d['interestedCount'] ?? 0) as int;
    final providers       = List<String>.from(d['interestedProviders'] ?? []);
    final alreadyInterested = providers.contains(widget.currentUid);
    final isClosed = d['status'] == 'closed';
    final temp     = _temperature;
    final isHot    = temp == _CardTemperature.hot  && !isClosed;
    final isWarm   = temp == _CardTemperature.warm && !isClosed;
    final ts                = d['createdAt'] as Timestamp?;
    final timeAgo           = ts != null ? _timeAgo(ts.toDate()) : '';
    final isUrgentFlag = d['isUrgent'] == true;
    final ageMin   = ts != null
        ? DateTime.now().difference(ts.toDate()).inMinutes
        : 999;
    // New-lead yellow glow: 10–15 min window (WARM but very fresh)
    final isNewLead = !isHot && !isClosed && ageMin < 15;
    final viewers  = _viewersNow();
    final netLabel = _netEarningsLabel();
    final location          = (d['location']    ?? '') as String;
    final category          = (d['category']    ?? '') as String;
    final description       = (d['description'] ?? '') as String;
    final clientName        = (d['clientName']  ?? l10n.oppDefaultClient) as String;
    final clientLat         = (d['clientLat'] as num?)?.toDouble();
    final clientLng         = (d['clientLng'] as num?)?.toDouble();

    final headerGradient = isClosed
        ? LinearGradient(colors: [Colors.grey[200]!, Colors.grey[200]!])
        : isHot
            ? const LinearGradient(
                colors: [Color(0xFFDC2626), Color(0xFFF97316)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)
            : isWarm
                ? const LinearGradient(
                    colors: [Color(0xFFB45309), Color(0xFFF59E0B)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)
                : const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isNewLead ? const Color(0xFFFFFBEB) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: isHot
                  ? Border.all(
                      color: _kUrgentOr.withValues(alpha: _pulse.value),
                      width: 2.5)
                  : isWarm
                      ? Border.all(color: _kAmber, width: 1.5)
                      : null,
              boxShadow: [BoxShadow(
                color: isHot
                    ? _kUrgentOr.withValues(alpha: _pulse.value * 0.22)
                    : isWarm
                        ? _kAmber.withValues(alpha: 0.18)
                        : isClosed
                            ? Colors.black.withValues(alpha: 0.04)
                            : _kIndigo.withValues(alpha: 0.10),
                blurRadius: isHot ? 24 : isWarm ? 16 : 18,
                spreadRadius: isHot ? 2 : 0,
                offset: const Offset(0, 5),
              )],
            ),
            child: child,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Gradient header ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  decoration: BoxDecoration(gradient: headerGradient),
                  child: Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Client avatar + name
                        Row(children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                Colors.white.withValues(alpha: isClosed ? 0.4 : 0.25),
                            child: Text(
                              clientName.isNotEmpty ? clientName[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: isClosed ? Colors.grey[600] : Colors.white,
                                fontWeight: FontWeight.bold, fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(clientName,
                                  style: TextStyle(
                                      color: isClosed ? Colors.grey[600] : Colors.white,
                                      fontWeight: FontWeight.bold, fontSize: 14)),
                              if (timeAgo.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isHot) ...[
                                      const Icon(Icons.circle,
                                          size: 7, color: Color(0xFF4ADE80)),
                                      const SizedBox(width: 4),
                                    ],
                                    if (isUrgentFlag) ...[
                                      AnimatedBuilder(
                                        animation: _pulse,
                                        builder: (_, __) => Icon(
                                          Icons.priority_high_rounded,
                                          size: 13,
                                          color: Colors.white
                                              .withValues(alpha: _pulse.value),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                    ],
                                    Text(timeAgo,
                                        style: TextStyle(
                                            color: isClosed
                                                ? Colors.grey[400]
                                                : Colors.white70,
                                            fontSize: 11,
                                            fontWeight: isHot
                                                ? FontWeight.w700
                                                : FontWeight.normal)),
                                  ],
                                ),
                            ],
                          ),
                        ]),

                        // Right: interest counter + urgent badge
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Interest counter
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isClosed
                                    ? Colors.grey[300]
                                    : Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  isClosed
                                      ? Icons.lock_outline_rounded
                                      : Icons.people_outline_rounded,
                                  size: 13,
                                  color: isClosed ? Colors.grey[600] : Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isClosed ? l10n.close : '$interestedCount/3',
                                  style: TextStyle(
                                    color: isClosed ? Colors.grey[600] : Colors.white,
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ]),
                            ),
                            // Temperature badge
                            if (isHot || isWarm) ...[
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isHot ? '🔥' : '⏰',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isHot ? 'HOT' : l10n.oppHighDemand,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),

                    // Social proof — viewers counter
                    if (!isClosed && viewers > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 7, height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80), // live green dot
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$viewers מומחים נוספים בוחנים את ההצעה',
                            style: TextStyle(
                                color: isClosed ? Colors.grey[600] : Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),

                // ── Body ─────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Category chip
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
                                  color: _kIndigo,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Description
                      Text(description,
                          style: const TextStyle(
                              fontSize: 15, height: 1.55, color: Colors.black87)),

                      // Location + distance + proximity badge + map button
                      Builder(builder: (_) {
                        final hasLoc    = location.isNotEmpty;
                        final distMeters = (widget.currentPosition != null &&
                                clientLat != null && clientLng != null)
                            ? LocationService.distanceMeters(
                                widget.currentPosition!.latitude,
                                widget.currentPosition!.longitude,
                                clientLat, clientLng)
                            : null;
                        final distLabel = distMeters != null
                            ? LocationService.distanceLabel(
                                widget.currentPosition!.latitude,
                                widget.currentPosition!.longitude,
                                clientLat!, clientLng!)
                            : null;
                        final isNearby  = distMeters != null && distMeters < 5000;
                        final hasMap    = clientLat != null && clientLng != null;
                        if (!hasLoc && distLabel == null && !hasMap) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.location_on_rounded,
                                    size: 14, color: _kIndigo),
                                const SizedBox(width: 4),
                                if (hasLoc)
                                  Text(location,
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.grey)),
                                if (hasLoc && distLabel != null)
                                  const Text(' · ',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 13)),
                                if (distLabel != null)
                                  Text(distLabel,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: _kIndigo,
                                          fontWeight: FontWeight.w700)),
                                if (isNearby) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0xFFFCA5A5),
                                          width: 1),
                                    ),
                                    child: const Text(
                                      '🔥 קרוב אליך',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFDC2626)),
                                    ),
                                  ),
                                ],
                              ]),
                              if (hasMap) ...[
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => launchUrl(
                                    Uri.parse(
                                        'https://maps.google.com/?q=$clientLat,$clientLng'),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.map_outlined,
                                        size: 13, color: _kIndigo),
                                    const SizedBox(width: 4),
                                    Text(
                                      'צפה במיקום על המפה',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _kIndigo.withValues(alpha: 0.8),
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline),
                                    ),
                                  ]),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),

                      // Financial transparency — shown for all cards with budget
                      if (netLabel != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFF6EE7B7), width: 1),
                          ),
                          child: Row(children: [
                            const Icon(Icons.account_balance_wallet_rounded,
                                size: 16, color: Color(0xFF059669)),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.oppEstimatedEarnings,
                                    style: const TextStyle(
                                        fontSize: 10, color: Color(0xFF059669))),
                                Text(netLabel,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF065F46))),
                              ],
                            ),
                            const Spacer(),
                            Text(l10n.oppAfterFee,
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[500])),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // ── Main CTA ────────────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: alreadyInterested
                                ? Colors.green[50]
                                : isClosed
                                    ? Colors.grey[100]
                                    : isHot
                                        ? _kUrgentOr
                                        : isWarm
                                            ? _kAmber
                                            : _kIndigo,
                            foregroundColor: alreadyInterested
                                ? Colors.green[700]
                                : isClosed
                                    ? Colors.grey[400]
                                    : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            disabledBackgroundColor: alreadyInterested
                                ? Colors.green[50]
                                : Colors.grey[100],
                            disabledForegroundColor: alreadyInterested
                                ? Colors.green[700]
                                : Colors.grey[400],
                          ),
                          onPressed:
                              (alreadyInterested || isClosed || widget.isProcessing)
                                  ? null
                                  : widget.onInterest,
                          child: widget.isProcessing
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      alreadyInterested
                                          ? Icons.check_circle_outline_rounded
                                          : isClosed
                                              ? Icons.lock_outline_rounded
                                              : isHot
                                                  ? Icons.bolt_rounded
                                                  : isWarm
                                                      ? Icons.local_fire_department_rounded
                                                      : Icons.flash_on_rounded,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      alreadyInterested
                                          ? l10n.oppAlreadyInterested
                                          : isClosed
                                              ? l10n.oppRequestClosedBtn
                                              : isHot
                                                  ? l10n.oppTakeOpportunity
                                                  : l10n.oppInterested,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      // ── One-Tap Quick Bid (HOT only, not yet responded) ─────
                      if (isHot && !alreadyInterested && !isClosed) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kUrgentOr,
                              side: BorderSide(
                                  color: _kUrgentOr.withValues(alpha: 0.6),
                                  width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed:
                                widget.isProcessing ? null : widget.onQuickBid,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send_rounded, size: 16),
                                const SizedBox(width: 7),
                                Text(l10n.oppQuickBid,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // ── Wallet hint chip (after expressing interest) ─────────
                      if (alreadyInterested) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.account_balance_wallet_rounded,
                                size: 14, color: _kIndigo),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                l10n.oppWalletHint,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: _kIndigo,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
