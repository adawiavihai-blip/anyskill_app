// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'chat_screen.dart';
import '../services/location_service.dart';
import '../services/gamification_service.dart';
import '../widgets/level_badge.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kIndigo   = Color(0xFF6366F1);
const _kUrgentOr = Color(0xFFF97316); // orange-500 — urgent border & CTA

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
      await db.runTransaction((tx) async {
        final snap = await tx.get(reqRef);
        if (!snap.exists) throw 'הבקשה כבר לא זמינה';
        final d         = snap.data()!;
        final count     = (d['interestedCount']    ?? 0) as int;
        final providers = List<String>.from(d['interestedProviders'] ?? []);
        if (d['status'] == 'closed') throw 'הבקשה סגורה — כבר נמצאו 3 מתעניינים';
        if (providers.contains(_uid)) throw 'כבר הבעת עניין בבקשה זו';
        if (count >= 3) throw 'הבקשה כבר קיבלה 3 מתעניינים';
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
          '💡 ${widget.providerName} הביע עניין בבקשת השירות שלך:\n"$description"';
      await chatRef.collection('messages').add({
        'senderId':  'system',
        'message':   msg,
        'type':      'text',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Notify client
      await db.collection('notifications').doc(clientId)
          .collection('userNotifications').add({
        'title':        'מתעניין חדש בבקשתך!',
        'body':         '${widget.providerName} מעוניין לבצע את השירות שביקשת',
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: _kUrgentOr,
            duration: Duration(seconds: 5),
            content: Text(
              '🚀 הפרופיל שלך זינק לראש תוצאות החיפוש ל-24 שעות!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ));
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(receiverId: clientId, receiverName: clientName),
          ));
          return;
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.green,
        content: Text("הבעת עניין! הצ'אט עם הלקוח נפתח"),
        duration: Duration(seconds: 3),
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
    var q = FirebaseFirestore.instance
        .collection('job_requests')
        .where('status', isEqualTo: 'open');
    if (!widget.isAdmin && widget.serviceType.isNotEmpty) {
      q = q.where('category', isEqualTo: widget.serviceType);
    }
    return q.orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  bool _isUrgentData(Map<String, dynamic> d) {
    final ts    = d['createdAt'] as Timestamp?;
    if (ts == null) return false;
    final age   = DateTime.now().difference(ts.toDate());
    final count = (d['interestedCount'] ?? 0) as int;
    return age.inHours < 3 && count >= 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Column(children: [
          const Text('לוח הזדמנויות',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text(
            widget.serviceType.isEmpty ? 'כל הקטגוריות' : widget.serviceType,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ]),
      ),
      body: Column(children: [
        _buildXpBanner(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildQuery(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('שגיאה: ${snapshot.error}'));
              }
              final docs     = snapshot.data?.docs ?? [];
              final filtered = List<QueryDocumentSnapshot>.from(docs);

              if (_currentPosition != null) {
                filtered.sort((a, b) {
                  final da   = a.data() as Map<String, dynamic>;
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

              if (filtered.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final doc         = filtered[index];
                  final d           = doc.data() as Map<String, dynamic>;
                  final clientId    = (d['clientId']    ?? '') as String;
                  final clientName  = (d['clientName']  ?? 'לקוח') as String;
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
                      customMessage:
                          'שלום $clientName! 👋\n'
                          'אני ${widget.providerName} ואני זמין לבצע את השירות שביקשת '
                          'מוקדם ככל האפשר.\nמה הזמינות שלך?',
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
              Text('עוד $xpToNext XP לרמת $nextName',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]))
            else
              const Text('הגעת לרמה הגבוהה ביותר! 🏆',
                  style: TextStyle(
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
                  ? Text('🚀 פרופיל מוגבר! עד ${_boostTimeLabel()}',
                      style: const TextStyle(
                          fontSize: 11, color: _kUrgentOr, fontWeight: FontWeight.w700))
                  : Text('AnySkill Boost: $_urgentCompleted/3 — השלם 3 משימות דחופות',
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
    final diff = _boostExpiry!.difference(DateTime.now());
    return diff.inHours >= 1 ? "${diff.inHours} שע'" : "${diff.inMinutes} ד'";
  }

  Widget _buildEmptyState() {
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
        Text(isCat ? 'אין הזדמנויות בתחום שלך כרגע' : 'אין בקשות פתוחות כרגע',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          isCat
              ? 'אין כרגע הזדמנויות חדשות בתחום שלך,\nנעדכן אותך כשיהיו 🔔'
              : 'בקשות חדשות מלקוחות יופיעו כאן בזמן אמת\nהישאר ערני!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.6),
        ),
      ]),
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
  // urgent pulse
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

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

    if (_isUrgent && widget.data['status'] != 'closed') {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_RequestCard old) {
    super.didUpdateWidget(old);
    final shouldPulse = _isUrgent && widget.data['status'] != 'closed';
    if (shouldPulse && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!shouldPulse && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Computed properties ───────────────────────────────────────────────────

  bool get _isUrgent {
    final ts    = widget.data['createdAt'] as Timestamp?;
    if (ts == null) return false;
    final age   = DateTime.now().difference(ts.toDate());
    final count = (widget.data['interestedCount'] ?? 0) as int;
    return age.inHours < 3 && count >= 1;
  }

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
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'הרגע';
    if (diff.inMinutes < 60) return "לפני ${diff.inMinutes} דק'";
    if (diff.inHours   < 24) return "לפני ${diff.inHours} שע'";
    return 'לפני ${diff.inDays} ימים';
  }

  @override
  Widget build(BuildContext context) {
    final d               = widget.data;
    final interestedCount = (d['interestedCount'] ?? 0) as int;
    final providers       = List<String>.from(d['interestedProviders'] ?? []);
    final alreadyInterested = providers.contains(widget.currentUid);
    final isClosed          = d['status'] == 'closed';
    final isUrgent          = _isUrgent && !isClosed;
    final viewers           = isUrgent ? _viewersNow() : 0;
    final netLabel          = _netEarningsLabel();
    final ts                = d['createdAt'] as Timestamp?;
    final timeAgo           = ts != null ? _timeAgo(ts.toDate()) : '';
    final location          = (d['location']    ?? '') as String;
    final category          = (d['category']    ?? '') as String;
    final description       = (d['description'] ?? '') as String;
    final clientName        = (d['clientName']  ?? 'לקוח') as String;
    final clientLat         = (d['clientLat'] as num?)?.toDouble();
    final clientLng         = (d['clientLng'] as num?)?.toDouble();

    final headerGradient = isClosed
        ? LinearGradient(colors: [Colors.grey[200]!, Colors.grey[200]!])
        : isUrgent
            ? const LinearGradient(
                colors: [Color(0xFFEA580C), Color(0xFFF97316)],
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: isUrgent
                  ? Border.all(
                      color: _kUrgentOr.withValues(alpha: _pulse.value),
                      width: 2.5)
                  : null,
              boxShadow: [BoxShadow(
                color: isUrgent
                    ? _kUrgentOr.withValues(alpha: _pulse.value * 0.22)
                    : isClosed
                        ? Colors.black.withValues(alpha: 0.04)
                        : _kIndigo.withValues(alpha: 0.10),
                blurRadius: isUrgent ? 22 : 18,
                spreadRadius: isUrgent ? 2 : 0,
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
                                Text(timeAgo,
                                    style: TextStyle(
                                        color: isClosed
                                            ? Colors.grey[400]
                                            : Colors.white70,
                                        fontSize: 11)),
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
                                  isClosed ? 'סגור' : '$interestedCount/3',
                                  style: TextStyle(
                                    color: isClosed ? Colors.grey[600] : Colors.white,
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ]),
                            ),
                            // "High Demand" badge — urgent only
                            if (isUrgent) ...[
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
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('🔥', style: TextStyle(fontSize: 10)),
                                    SizedBox(width: 3),
                                    Text('ביקוש גבוה',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),

                    // Social proof — viewers counter
                    if (isUrgent && viewers > 0) ...[
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
                            '$viewers מקצוענים צופים בהזדמנות זו כרגע',
                            style: const TextStyle(
                                color: Colors.white,
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

                      // Location + distance
                      Builder(builder: (_) {
                        final hasLoc    = location.isNotEmpty;
                        final distLabel = (widget.currentPosition != null &&
                                clientLat != null && clientLng != null)
                            ? LocationService.distanceLabel(
                                widget.currentPosition!.latitude,
                                widget.currentPosition!.longitude,
                                clientLat, clientLng)
                            : null;
                        if (!hasLoc && distLabel == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(children: [
                            const Icon(Icons.location_on_rounded,
                                size: 14, color: _kIndigo),
                            const SizedBox(width: 4),
                            if (hasLoc)
                              Text(location,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                            if (hasLoc && distLabel != null)
                              const Text(' · ',
                                  style: TextStyle(color: Colors.grey, fontSize: 13)),
                            if (distLabel != null)
                              Text(distLabel,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: _kIndigo,
                                      fontWeight: FontWeight.w700)),
                          ]),
                        );
                      }),

                      // Financial transparency — urgent + budget present
                      if (isUrgent && netLabel != null) ...[
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
                                const Text('רווח נקי משוער',
                                    style: TextStyle(
                                        fontSize: 10, color: Color(0xFF059669))),
                                Text(netLabel,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF065F46))),
                              ],
                            ),
                            const Spacer(),
                            Text('אחרי עמלת AnySkill',
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
                                    : isUrgent
                                        ? _kUrgentOr
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
                                              : isUrgent
                                                  ? Icons.bolt_rounded
                                                  : Icons.flash_on_rounded,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      alreadyInterested
                                          ? 'הבעת עניין ✓'
                                          : isClosed
                                              ? 'הבקשה סגורה'
                                              : isUrgent
                                                  ? 'קח את ההזדמנות!'
                                                  : 'אני מעוניין!',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      // ── One-Tap Quick Bid (urgent, not yet responded) ────────
                      if (isUrgent && !alreadyInterested && !isClosed) ...[
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
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, size: 16),
                                SizedBox(width: 7),
                                Text('מענה מהיר — שלח הצעה אוטומטית',
                                    style: TextStyle(
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
                          child: const Row(children: [
                            Icon(Icons.account_balance_wallet_rounded,
                                size: 14, color: _kIndigo),
                            SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'לאחר סיום העבודה — רווחך יועבר לארנק AnySkill שלך',
                                style: TextStyle(
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
