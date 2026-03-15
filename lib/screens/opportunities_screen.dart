import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'chat_screen.dart';
import '../services/location_service.dart';
import '../services/gamification_service.dart';
import '../widgets/level_badge.dart';

class OpportunitiesScreen extends StatefulWidget {
  final String serviceType;
  final String providerName;

  const OpportunitiesScreen({
    super.key,
    required this.serviceType,
    required this.providerName,
  });

  @override
  State<OpportunitiesScreen> createState() => _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends State<OpportunitiesScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Set<String> _processingIds = {};
  Position? _currentPosition;
  int _xp = 0;

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
    _loadXp();
  }

  Future<void> _loadXp() async {
    if (_uid.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();
    if (snap.exists && mounted) {
      setState(() => _xp = (snap.data()?['xp'] as num? ?? 0).toInt());
    }
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
    String description,
  ) async {
    if (_processingIds.contains(requestId)) return;
    setState(() => _processingIds.add(requestId));

    final db = FirebaseFirestore.instance;
    final reqRef = db.collection('job_requests').doc(requestId);
    final chatRoomId = _getChatRoomId(_uid, clientId);

    try {
      await db.runTransaction((tx) async {
        final snap = await tx.get(reqRef);
        if (!snap.exists) throw 'הבקשה כבר לא זמינה';
        final d = snap.data()!;
        final count = (d['interestedCount'] ?? 0) as int;
        final providers = List<String>.from(d['interestedProviders'] ?? []);
        if (d['status'] == 'closed') throw 'הבקשה סגורה — כבר נמצאו 3 מתעניינים';
        if (providers.contains(_uid)) throw 'כבר הבעת עניין בבקשה זו';
        if (count >= 3) throw 'הבקשה כבר קיבלה 3 מתעניינים';
        final newCount = count + 1;
        tx.update(reqRef, {
          'interestedProviders': FieldValue.arrayUnion([_uid]),
          'interestedProviderNames': FieldValue.arrayUnion([widget.providerName]),
          'interestedCount': FieldValue.increment(1),
          if (newCount >= 3) 'status': 'closed',
        });
      });

      // Open/init chat channel
      final chatRef = db.collection('chats').doc(chatRoomId);
      await chatRef.set({'users': [_uid, clientId]}, SetOptions(merge: true));
      await chatRef.collection('messages').add({
        'senderId': 'system',
        'message': '💡 ${widget.providerName} הביע עניין בבקשת השירות שלך:\n"$description"',
        'type': 'text',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Notify the client
      await db
          .collection('notifications')
          .doc(clientId)
          .collection('userNotifications')
          .add({
        'title': 'מתעניין חדש בבקשתך!',
        'body': '${widget.providerName} מעוניין לבצע את השירות שביקשת',
        'type': 'interest',
        'requestId': requestId,
        'providerId': _uid,
        'providerName': widget.providerName,
        'chatRoomId': chatRoomId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text("הבעת עניין! הצ'אט עם הלקוח נפתח"),
          duration: Duration(seconds: 3),
        ));
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatScreen(receiverId: clientId, receiverName: clientName),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(requestId));
    }
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
        title: Column(
          children: [
            const Text('לוח הזדמנויות',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              widget.serviceType.isEmpty ? 'כל הקטגוריות' : widget.serviceType,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildXpBanner(),
          Expanded(child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('job_requests')
            .where('status', isEqualTo: 'open')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('שגיאה: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          // Show requests for this provider's category OR requests with no category
          final filtered = docs.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final cat = (d['category'] ?? '') as String;
            return cat.isEmpty ||
                cat == widget.serviceType ||
                widget.serviceType.isEmpty;
          }).toList();

          // Sort closest job first when provider location is known
          if (_currentPosition != null) {
            filtered.sort((a, b) {
              final da = a.data() as Map<String, dynamic>;
              final db = b.data() as Map<String, dynamic>;
              final distA = LocationService.distanceMeters(
                _currentPosition!.latitude, _currentPosition!.longitude,
                (da['clientLat'] as num?)?.toDouble(),
                (da['clientLng'] as num?)?.toDouble(),
              );
              final distB = LocationService.distanceMeters(
                _currentPosition!.latitude, _currentPosition!.longitude,
                (db['clientLat'] as num?)?.toDouble(),
                (db['clientLng'] as num?)?.toDouble(),
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
              final doc = filtered[index];
              final d = doc.data() as Map<String, dynamic>;
              return _RequestCard(
                key: ValueKey(doc.id),
                requestId: doc.id,
                data: d,
                currentUid: _uid,
                currentPosition: _currentPosition,
                isProcessing: _processingIds.contains(doc.id),
                onInterest: () => _expressInterest(
                  context,
                  doc.id,
                  (d['clientId'] ?? '') as String,
                  (d['clientName'] ?? 'לקוח') as String,
                  (d['description'] ?? '') as String,
                ),
              );
            },
          );
        },
      )),   // ← Expanded + StreamBuilder
        ],  // ← Column children
      ),    // ← Column
    );
  }

  Widget _buildXpBanner() {
    final level    = GamificationService.levelFor(_xp);
    final progress = GamificationService.levelProgress(_xp);
    final isGold   = level == ProviderLevel.gold;
    final xpToNext = GamificationService.xpToNextLevel(_xp);
    final nextName = GamificationService.nextLevelName(level);
    final barColor = GamificationService.levelProgressColor(level);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                if (_xp > 0) ...[
                  LevelBadge(xp: _xp, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  '$_xp XP',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87),
                ),
              ]),
              if (!isGold)
                Text(
                  'עוד $xpToNext XP לרמת $nextName',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                )
              else
                const Text(
                  'הגעת לרמה הגבוהה ביותר! 🏆',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              color: barColor,
              backgroundColor: Colors.grey[200],
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
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
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.work_outline_rounded,
                color: Colors.white, size: 46),
          ),
          const SizedBox(height: 28),
          const Text('אין בקשות פתוחות כרגע',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            'בקשות חדשות מלקוחות יופיעו כאן בזמן אמת\nהישאר ערני!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ─── Animated request card ────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final String currentUid;
  final Position? currentPosition;
  final bool isProcessing;
  final VoidCallback onInterest;

  const _RequestCard({
    super.key,
    required this.requestId,
    required this.data,
    required this.currentUid,
    this.currentPosition,
    required this.isProcessing,
    required this.onInterest,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'הרגע';
    if (diff.inMinutes < 60) return "לפני ${diff.inMinutes} דק'";
    if (diff.inHours < 24) return "לפני ${diff.inHours} שע'";
    return 'לפני ${diff.inDays} ימים';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final interestedCount = (d['interestedCount'] ?? 0) as int;
    final providers = List<String>.from(d['interestedProviders'] ?? []);
    final alreadyInterested = providers.contains(widget.currentUid);
    final isClosed = d['status'] == 'closed';
    final ts = d['createdAt'] as Timestamp?;
    final timeAgo = ts != null ? _timeAgo(ts.toDate()) : '';
    final location    = (d['location'] ?? '') as String;
    final category    = (d['category']  ?? '') as String;
    final description = (d['description'] ?? '') as String;
    final clientName  = (d['clientName']  ?? 'לקוח') as String;
    final clientLat   = (d['clientLat'] as num?)?.toDouble();
    final clientLng   = (d['clientLng'] as num?)?.toDouble();

    final headerGradient = isClosed
        ? LinearGradient(colors: [Colors.grey[200]!, Colors.grey[200]!])
        : const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: isClosed
                    ? Colors.black.withValues(alpha: 0.04)
                    : const Color(0xFF6366F1).withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Gradient header ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                decoration: BoxDecoration(
                  gradient: headerGradient,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Client avatar + name
                    Row(children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            Colors.white.withValues(alpha: isClosed ? 0.4 : 0.25),
                        child: Text(
                          clientName.isNotEmpty
                              ? clientName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: isClosed
                                ? Colors.grey[600]
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(clientName,
                              style: TextStyle(
                                  color: isClosed
                                      ? Colors.grey[600]
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
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
                    // Interest counter badge
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
                            isClosed
                                ? Icons.lock_outline_rounded
                                : Icons.people_outline_rounded,
                            size: 13,
                            color:
                                isClosed ? Colors.grey[600] : Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isClosed ? 'סגור' : '$interestedCount/3',
                            style: TextStyle(
                              color: isClosed
                                  ? Colors.grey[600]
                                  : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Body ────────────────────────────────────────────────────
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
                                color: Color(0xFF6366F1),
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
                      final hasLocation = location.isNotEmpty;
                      final distLabel = (widget.currentPosition != null &&
                              clientLat != null &&
                              clientLng != null)
                          ? LocationService.distanceLabel(
                              widget.currentPosition!.latitude,
                              widget.currentPosition!.longitude,
                              clientLat,
                              clientLng)
                          : null;
                      if (!hasLocation && distLabel == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(children: [
                          const Icon(Icons.location_on_rounded,
                              size: 14, color: Color(0xFF6366F1)),
                          const SizedBox(width: 4),
                          if (hasLocation)
                            Text(location,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.grey)),
                          if (hasLocation && distLabel != null)
                            const Text(' · ',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                          if (distLabel != null)
                            Text(distLabel,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.w700)),
                        ]),
                      );
                    }),

                    const SizedBox(height: 14),

                    // CTA button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: alreadyInterested
                              ? Colors.green[50]
                              : isClosed
                                  ? Colors.grey[100]
                                  : const Color(0xFF6366F1),
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
                        onPressed: (alreadyInterested ||
                                isClosed ||
                                widget.isProcessing)
                            ? null
                            : widget.onInterest,
                        child: widget.isProcessing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    alreadyInterested
                                        ? Icons.check_circle_outline_rounded
                                        : isClosed
                                            ? Icons.lock_outline_rounded
                                            : Icons.flash_on_rounded,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    alreadyInterested
                                        ? 'הבעת עניין ✓'
                                        : isClosed
                                            ? 'הבקשה סגורה'
                                            : 'אני מעוניין!',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                ],
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
    );
  }
}
