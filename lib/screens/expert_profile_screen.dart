// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'chat_screen.dart';
import '../constants/quick_tags.dart';
import '../services/cancellation_policy_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/anyskill_logo.dart';

// Brand tokens
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);
const _kGold       = Color(0xFFFBBF24);

// Trait tag catalog — keys stored in reviews/{id}.traitTags
// Labels are resolved at runtime via _traitLabel() for i18n.
const _kTraitTags = [
  {'key': 'punctual',      'emoji': '⏰'},
  {'key': 'professional',  'emoji': '💼'},
  {'key': 'communicative', 'emoji': '💬'},
  {'key': 'patient',       'emoji': '🤗'},
  {'key': 'knowledgeable', 'emoji': '🎓'},
  {'key': 'friendly',      'emoji': '😊'},
  {'key': 'creative',      'emoji': '🎨'},
  {'key': 'flexible',      'emoji': '🔄'},
];

/// Returns the i18n label for a trait key. Falls back to the key itself.
String _traitLabel(String key, AppLocalizations l10n) {
  switch (key) {
    case 'punctual':      return l10n.traitPunctual;
    case 'professional':  return l10n.traitProfessional;
    case 'communicative': return l10n.traitCommunicative;
    case 'patient':       return l10n.traitPatient;
    case 'knowledgeable': return l10n.traitKnowledgeable;
    case 'friendly':      return l10n.traitFriendly;
    case 'creative':      return l10n.traitCreative;
    case 'flexible':      return l10n.traitFlexible;
    default:              return key;
  }
}

class ExpertProfileScreen extends StatefulWidget {
  final String expertId;
  final String expertName;

  const ExpertProfileScreen(
      {super.key, required this.expertId, required this.expertName});

  @override
  State<ExpertProfileScreen> createState() => _ExpertProfileScreenState();
}

class _ExpertProfileScreenState extends State<ExpertProfileScreen> {
  // ── Booking state ──────────────────────────────────────────────────────────
  bool _isProcessing = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedTimeSlot;
  int _refreshTrigger = 0;
  int _selectedServiceIndex = 0;

  // ── Hero carousel state ────────────────────────────────────────────────────
  final PageController _pageController = PageController();
  int _heroPage = 0;

  // ── Bio expand state ───────────────────────────────────────────────────────
  bool _bioExpanded = false;

  final List<String> _timeSlots = [
    "08:00", "09:00", "10:00", "11:00",
    "14:00", "15:00", "16:00", "17:00", "18:00", "19:00",
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('he_IL', null);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Derived service tiers (no separate Firestore collection needed)
  // ─────────────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _deriveServices(
      double pricePerHour, AppLocalizations l10n) => [
        {
          'title':    l10n.serviceSingleLesson,
          'subtitle': l10n.serviceSingleSubtitle,
          'duration': l10n.serviceSingle60min,
          'price':    pricePerHour,
        },
        {
          'title':    l10n.serviceExtendedLesson,
          'subtitle': l10n.serviceExtendedSubtitle,
          'duration': l10n.serviceExtended90min,
          'price':    (pricePerHour * 1.4).roundToDouble(),
        },
        {
          'title':    l10n.serviceFullSession,
          'subtitle': l10n.serviceFullSubtitle,
          'duration': l10n.serviceFullSession120min,
          'price':    (pricePerHour * 1.8).roundToDouble(),
        },
      ];

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _getChatRoomId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join("_");
  }

  /// Render a gallery image that may be an HTTP URL or a raw base64 string.
  Widget _buildGalleryImage(String src, {BoxFit fit = BoxFit.cover}) {
    if (src.startsWith('http')) {
      return CachedNetworkImage(
          imageUrl: src, fit: fit, errorWidget: (_, __, ___) => _imagePH());
    }
    try {
      final bytes = base64Decode(src.contains(',') ? src.split(',').last : src);
      return Image.memory(bytes, fit: fit);
    } catch (_) {
      return _imagePH();
    }
  }

  Widget _imagePH() => Container(
        color: _kPurpleSoft,
        child: Icon(Icons.image_outlined,
            size: 40, color: _kPurple.withValues(alpha: 0.3)),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Payment / booking (UNCHANGED LOGIC)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _processEscrowPayment(
      BuildContext context, double totalPrice, String cancellationPolicy,
      {bool isDemo = false}) async {
    // ── Demo expert: show success illusion, log demand signal, no real writes ──
    if (isDemo) {
      await _handleDemoBooking(context);
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Capture l10n strings before any await (context may be gone after await)
    final l10n = AppLocalizations.of(context);
    final msgInsufficientBalance = l10n.expertInsufficientBalance;
    final msgEscrowSuccess       = l10n.expertEscrowSuccess;
    final msgTransactionTitle    = l10n.expertTransactionTitle(widget.expertName);
    final dateStr = _selectedDay != null
        ? '${_selectedDay!.day}/${_selectedDay!.month}'
        : '';

    final firestore = FirebaseFirestore.instance;
    final String currentUserId =
        FirebaseAuth.instance.currentUser?.uid ?? "";
    final String chatRoomId =
        _getChatRoomId(currentUserId, widget.expertId);
    final adminSettingsRef = firestore
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings');

    double expertNetEarnings = totalPrice * 0.90;
    final navigator  = Navigator.of(context);
    final messenger  = ScaffoldMessenger.of(context);

    try {
      await firestore.runTransaction((transaction) async {
        final adminSnap = await transaction.get(adminSettingsRef);
        final double feePercentage =
            ((adminSnap.exists ? adminSnap.get('feePercentage') : null) ??
                    0.10)
                .toDouble();
        final double commission    = totalPrice * feePercentage;
        expertNetEarnings          = totalPrice - commission;

        final customerRef  = firestore.collection('users').doc(currentUserId);
        final customerSnap = await transaction.get(customerRef);
        final double currentBalance =
            (customerSnap['balance'] ?? 0.0).toDouble();

        if (currentBalance < totalPrice) {
          throw msgInsufficientBalance;
        }

        // Calculate cancellation deadline based on provider's policy
        final cancelDeadline = CancellationPolicyService.deadline(
          policy:          cancellationPolicy,
          appointmentDate: _selectedDay,
          timeSlot:        _selectedTimeSlot,
        );

        final jobRef = firestore.collection('jobs').doc();
        transaction.set(jobRef, {
          'jobId':                 jobRef.id,
          'chatRoomId':            chatRoomId,
          'customerId':            currentUserId,
          'customerName':          customerSnap['name'] ?? "",
          'expertId':              widget.expertId,
          'expertName':            widget.expertName,
          'totalPaidByCustomer':   totalPrice,
          'totalAmount':           totalPrice,
          'commissionAmount':      commission,
          'netAmountForExpert':    expertNetEarnings,
          'appointmentDate':       _selectedDay,
          'appointmentTime':       _selectedTimeSlot,
          'status':                'paid_escrow',
          'createdAt':             FieldValue.serverTimestamp(),
          'cancellationPolicy':    cancellationPolicy,
          if (cancelDeadline != null)
            'cancellationDeadline': Timestamp.fromDate(cancelDeadline),
        });

        transaction.update(
            customerRef, {'balance': FieldValue.increment(-totalPrice)});

        transaction.set(firestore.collection('platform_earnings').doc(), {
          'jobId':          jobRef.id,
          'amount':         commission,
          'sourceExpertId': widget.expertId,
          'timestamp':      FieldValue.serverTimestamp(),
          'status':         'pending_escrow',
        });

        transaction.set(firestore.collection('transactions').doc(), {
          'userId':    currentUserId,
          'amount':    -totalPrice,
          'title':     msgTransactionTitle,
          'timestamp': FieldValue.serverTimestamp(),
          'status':    'escrow',
        });
      });

      await _sendSystemNotification(
          chatRoomId, totalPrice, expertNetEarnings, currentUserId,
          systemMsg: l10n.expertSystemMessage(
              dateStr, _selectedTimeSlot ?? '', expertNetEarnings.toStringAsFixed(0)));

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(msgEscrowSuccess),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Demo booking: fake success + admin demand signal ──────────────────────
  // No real Firestore transaction, no wallet change, no job document.
  // Closes the booking sheet, shows a success overlay, and silently logs
  // the demand event to activity_log so the admin Live Feed picks it up.
  Future<void> _handleDemoBooking(BuildContext context) async {
    final navigator     = Navigator.of(context);
    // Capture the root context (profile screen) BEFORE any awaits so we can
    // show the success dialog after the sheet closes.
    final rootContext   = this.context;

    // 1. Close the booking summary sheet
    navigator.pop();

    // 2. Log demand signal to activity_log (admin Live Feed)
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await FirebaseFirestore.instance.collection('activity_log').add({
        'type':       'demo_booking_attempt',
        'expertId':   widget.expertId,
        'expertName': widget.expertName,
        'userId':     uid,
        'timestamp':  FieldValue.serverTimestamp(),
        'priority':   'high',
        'message':    'משתמש ניסה להזמין מומחה דמו: ${widget.expertName}',
      });
    } catch (_) {
      // Non-blocking — if logging fails the UX is unaffected
    }

    // 3. Show success dialog on the profile screen
    if (!mounted) return;
    await showDialog(
      context: rootContext,
      barrierDismissible: false,
      builder: (_) => const _DemoBookingSuccessDialog(),
    );
  }

  Future<void> _sendSystemNotification(
      String chatRoomId, double total, double net, String currentUserId,
      {required String systemMsg}) async {
    final chatRef =
        FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
    await chatRef.collection('messages').add({
      'senderId': 'system',
      'message':  systemMsg,
      'type':      'text',
      'timestamp': FieldValue.serverTimestamp(),
    });
    await chatRef.set(
        {'users': [currentUserId, widget.expertId]},
        SetOptions(merge: true));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Hero gallery carousel
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeroBackground(Map<String, dynamic> data, AppLocalizations l10n) {
    final gallery      = (data['gallery'] as List? ?? []).cast<String>();
    final profileImage = data['profileImage'] as String? ?? '';
    final images       = [...gallery];
    if (images.isEmpty && profileImage.isNotEmpty) images.add(profileImage);

    final isVerified = data['isVerified'] as bool? ?? false;
    final isPromoted = data['isPromoted'] as bool? ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Image / carousel ─────────────────────────────────────────────
        images.isEmpty
            ? Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_kPurple, _kPurple.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(Icons.person_outlined,
                    size: 100, color: Colors.white.withValues(alpha: 0.3)),
              )
            : PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _heroPage = i),
                itemBuilder: (_, i) =>
                    _buildGalleryImage(images[i], fit: BoxFit.cover),
              ),

        // ── Bottom gradient ───────────────────────────────────────────────
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.72),
                ],
                stops: const [0.45, 1.0],
              ),
            ),
          ),
        ),

        // ── Name + badges overlay (bottom) ────────────────────────────────
        Positioned(
          bottom: 50,
          left: 16,
          right: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isPromoted)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _kGold,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 11, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(l10n.expertRecommendedBadge,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        if (isVerified)
                          const Icon(Icons.verified_rounded,
                              color: Color(0xFF60A5FA), size: 20),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.expertName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                      ),
                    ),
                    if ((data['serviceType'] as String? ?? '').isNotEmpty)
                      Text(
                        data['serviceType'] as String,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 14),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Page indicator dots ────────────────────────────────────────────
        if ((data['gallery'] as List? ?? []).length > 1)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                (data['gallery'] as List).length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width:  _heroPage == i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _heroPage == i
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Power Row (trust stats horizontal scroll)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPowerRow(Map<String, dynamic> data, AppLocalizations l10n) {
    final rating       = (data['rating']       as num? ?? 5.0).toDouble();
    final reviewsCount = (data['reviewsCount'] as num? ?? 0).toInt();
    final orderCount   = (data['orderCount']   as num? ?? 0).toInt();
    final respTime     = (data['responseTimeMinutes'] as num? ?? 0).toInt();
    final xp           = (data['xp']           as num? ?? 0).toInt();

    // Repeat rate: shown when orderCount > 3 (approximated — no real data)
    final repeatRate   = orderCount > 3 ? 75 : null;

    final stats = <Map<String, dynamic>>[
      {
        'value': rating.toStringAsFixed(1),
        'label': l10n.expertStatRating,
        'icon':  Icons.star_rounded,
        'color': _kGold,
      },
      if (reviewsCount > 0)
        {
          'value': '$reviewsCount',
          'label': l10n.expertStatReviews,
          'icon':  Icons.chat_bubble_outline_rounded,
          'color': Colors.blue,
        },
      if (repeatRate != null)
        {
          'value': '$repeatRate%',
          'label': l10n.expertStatRepeatClients,
          'icon':  Icons.repeat_rounded,
          'color': Colors.green,
        },
      if (respTime > 0)
        {
          'value': l10n.expertResponseTimeFormat(respTime),
          'label': l10n.expertStatResponseTime,
          'icon':  Icons.bolt_rounded,
          'color': _kPurple,
        },
      if (orderCount > 0)
        {
          'value': '$orderCount',
          'label': l10n.expertStatOrders,
          'icon':  Icons.local_fire_department_rounded,
          'color': Colors.orange,
        },
      if (xp > 0)
        {
          'value': '$xp XP',
          'label': l10n.expertStatXp,
          'icon':  Icons.emoji_events_rounded,
          'color': const Color(0xFF8B5CF6),
        },
    ];

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final s = stats[i];
          final color = s['color'] as Color;
          return Container(
            width: 88,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(s['icon'] as IconData, color: color, size: 20),
                const SizedBox(height: 3),
                Text(s['value'] as String,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
                Text(s['label'] as String,
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 10)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Quick Tags
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildQuickTagsSection(Map<String, dynamic> data) {
    final tagKeys = ((data['quickTags'] as List?) ?? []).cast<String>();
    final resolved = tagKeys
        .map(quickTagByKey)
        .whereType<Map<String, String>>()
        .toList();
    if (resolved.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: resolved.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: _kPurpleSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kPurple.withValues(alpha: 0.2)),
        ),
        child: Text(
          '${t['emoji']} ${t['label']}',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kPurple),
        ),
      )).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Bio section
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBioSection(Map<String, dynamic> data, AppLocalizations l10n) {
    final bio = data['aboutMe'] as String? ?? l10n.expertBioPlaceholder;
    const maxLines = 3;
    final isLong   = bio.split('\n').length > maxLines || bio.length > 160;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          bio,
          textAlign: TextAlign.right,
          maxLines: _bioExpanded ? null : maxLines,
          overflow: _bioExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 15, height: 1.6, color: Colors.grey[800]),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _bioExpanded = !_bioExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _bioExpanded ? l10n.expertBioShowLess : l10n.expertBioReadMore,
                style: const TextStyle(
                    color: _kPurple,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Service menu
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildServiceMenu(Map<String, dynamic> data, AppLocalizations l10n) {
    final price    = (data['pricePerHour'] as num? ?? 100).toDouble();
    final services = _deriveServices(price, l10n);

    return Column(
      children: List.generate(services.length, (i) {
        final svc      = services[i];
        final selected = i == _selectedServiceIndex;
        final svcPrice = svc['price'] as double;

        return GestureDetector(
          onTap: () => setState(() => _selectedServiceIndex = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        selected ? _kPurpleSoft : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:  selected ? _kPurple : Colors.grey.shade200,
                width:  selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: _kPurple.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ]
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6)
                    ],
            ),
            child: Row(
              children: [
                // ── Selection indicator ────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:  selected ? _kPurple : Colors.transparent,
                    border: Border.all(
                        color:  selected ? _kPurple : Colors.grey.shade300,
                        width:  2),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 14),
                // ── Details ────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Duration pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _kPurple.withValues(alpha: 0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule_rounded,
                                    size: 12,
                                    color: selected
                                        ? _kPurple
                                        : Colors.grey[600]),
                                const SizedBox(width: 3),
                                Text(svc['duration'] as String,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: selected
                                            ? _kPurple
                                            : Colors.grey[700],
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          // Title
                          Text(svc['title'] as String,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: selected
                                      ? _kPurple
                                      : Colors.black87)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('₪${svcPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: _kPurple,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18)),
                          Text(svc['subtitle'] as String,
                              style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Interactive Portfolio grid
  // ─────────────────────────────────────────────────────────────────────────

  void _expandPortfolioImage(
      BuildContext context, List<String> images, int startIndex) {
    final ctrl = PageController(initialPage: startIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            PageView.builder(
              controller: ctrl,
              itemCount: images.length,
              itemBuilder: (_, i) => Center(
                child: InteractiveViewer(
                  child: _buildGalleryImage(images[i], fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortfolioGrid(Map<String, dynamic> data) {
    final gallery = (data['gallery'] as List? ?? []).cast<String>();
    if (gallery.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:  3,
        crossAxisSpacing: 4,
        mainAxisSpacing:  4,
      ),
      itemCount: gallery.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => _expandPortfolioImage(context, gallery, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildGalleryImage(gallery[i]),
              // Hover-hint overlay
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.black38, shape: BoxShape.circle),
                  child: const Icon(Icons.zoom_in_rounded,
                      color: Colors.white, size: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Calendar (unchanged logic, updated style)
  // ─────────────────────────────────────────────────────────────────────────

  Set<DateTime> _parseUnavailableDates(Map<String, dynamic> data) {
    final raw = data['unavailableDates'] as List<dynamic>? ?? [];
    return raw
        .map((d) => DateTime.tryParse(d.toString()))
        .whereType<DateTime>()
        .map((d) => DateTime.utc(d.year, d.month, d.day))
        .toSet();
  }

  Widget _buildCalendar(Set<DateTime> unavailableDates) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: TableCalendar(
        locale: 'he_IL',
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: _focusedDay,
        headerStyle:
            const HeaderStyle(formatButtonVisible: false, titleCentered: true),
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        enabledDayPredicate: (day) {
          final n = DateTime.utc(day.year, day.month, day.day);
          return !unavailableDates.contains(n);
        },
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay     = selectedDay;
            _focusedDay      = focusedDay;
            _selectedTimeSlot = null;
          });
        },
        calendarBuilders: CalendarBuilders(
          disabledBuilder: (context, day, _) {
            final n = DateTime.utc(day.year, day.month, day.day);
            if (!unavailableDates.contains(n)) return null;
            return Center(
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: Colors.red.shade50, shape: BoxShape.circle),
                child: Center(
                  child: Text('${day.day}',
                      style: TextStyle(
                          color: Colors.red.shade300,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        ),
        calendarStyle: const CalendarStyle(
          selectedDecoration:
              BoxDecoration(color: _kPurple, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(
              color: Color(0xFFE0E7FF), shape: BoxShape.circle),
          todayTextStyle: TextStyle(
              color: _kPurple, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Time slots
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimeSlots(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(l10n.expertSelectTime,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: _timeSlots.length,
            itemBuilder: (context, index) {
              final slot       = _timeSlots[index];
              final isSelected = _selectedTimeSlot == slot;
              return GestureDetector(
                onTap: () => setState(() => _selectedTimeSlot = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: isSelected ? _kPurple : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected ? _kPurple : Colors.grey.shade300),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: _kPurple.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ]
                        : [],
                  ),
                  child: Center(
                    child: Text(slot,
                        style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Reviews — Advanced Social Proof System
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReviewsSection(AppLocalizations l10n) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isProvider = currentUid == widget.expertId;

    return FutureBuilder<QuerySnapshot>(
      key: ValueKey('reviews_$_refreshTrigger'),
      future: FirebaseFirestore.instance
          .collection('reviews')
          .where('expertId', isEqualTo: widget.expertId)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get(),
      builder: (context, snapshot) {
        // Show spinner while Firestore is loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs    = snapshot.data?.docs ?? [];
        final reviews = docs.map((d) => d.data() as Map<String, dynamic>).toList();

        // ── Rating distribution ─────────────────────────────────────────────
        final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
        for (final r in reviews) {
          final star = (r['rating'] as num? ?? 5).round().clamp(1, 5);
          dist[star] = (dist[star] ?? 0) + 1;
        }
        final maxCount = dist.values.fold(0, (a, b) => a > b ? a : b);

        // ── Trait tag aggregation ───────────────────────────────────────────
        final traitCounts = <String, int>{};
        for (final r in reviews) {
          for (final t in (r['traitTags'] as List? ?? []).cast<String>()) {
            traitCounts[t] = (traitCounts[t] ?? 0) + 1;
          }
        }
        final sortedTraits = traitCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (docs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kPurpleSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l10n.expertReviewsCount(docs.length),
                      style: const TextStyle(
                          color: _kPurple,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                Text(l10n.expertReviewsHeader,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),

            // ── Empty state ──────────────────────────────────────────────────
            if (docs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.star_border_rounded, size: 40, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(l10n.expertNoReviews,
                        style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              )
            else ...[
              // ── Rating Distribution bar chart ─────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: List.generate(5, (i) {
                    final star  = 5 - i;
                    final count = dist[star] ?? 0;
                    final frac  = maxCount > 0 ? count / maxCount : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            child: Text('$count',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: count > 0
                                        ? Colors.grey[700]
                                        : Colors.grey[300])),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: frac,
                                minHeight: 8,
                                backgroundColor: Colors.grey[100],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  star >= 4
                                      ? _kGold
                                      : star == 3
                                          ? Colors.orange.shade300
                                          : Colors.red.shade300,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$star',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const Icon(Icons.star_rounded,
                                  size: 12, color: _kGold),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),

              // ── Trait Tags (AI-style highlights) ─────────────────────────
              if (sortedTraits.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: sortedTraits.take(6).map((entry) {
                    final meta = _kTraitTags.firstWhere(
                        (t) => t['key'] == entry.key,
                        orElse: () => {'emoji': '✓'});
                    final metaLabel = _traitLabel(entry.key, l10n);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _kPurpleSoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _kPurple.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _kPurple,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${entry.value}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${meta['emoji']} $metaLabel',
                            style: const TextStyle(
                                color: _kPurple,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // ── Review cards ──────────────────────────────────────────────
              ...List.generate(docs.length, (idx) {
                final doc      = docs[idx];
                final r        = doc.data() as Map<String, dynamic>;
                final rating   = (r['rating'] as num? ?? 5).toDouble();
                final name     = r['reviewerName'] as String? ?? l10n.expertDefaultReviewer;
                final comment  = (r['comment'] ?? '').toString().trim();
                final ts       = r['timestamp'] as Timestamp?;
                final date     = ts != null
                    ? DateFormat('dd/MM/yy').format(ts.toDate())
                    : '';
                final photos   = (r['photos']    as List? ?? []).cast<String>();
                final tags     = (r['traitTags'] as List? ?? []).cast<String>();
                final response = r['providerResponse'] as String?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // ── Card header ────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left: stars + verified + date
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: List.generate(
                                      5,
                                      (i) => Icon(
                                            i < rating
                                                ? Icons.star_rounded
                                                : Icons.star_border_rounded,
                                            color: _kGold,
                                            size: 16,
                                          )),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Icon(Icons.verified_rounded,
                                        color: Colors.green, size: 12),
                                    const SizedBox(width: 3),
                                    Text(l10n.expertVerifiedBooking,
                                        style: TextStyle(
                                            color: Colors.green[700],
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600)),
                                    if (date.isNotEmpty)
                                      Text('  ·  $date',
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 10)),
                                  ],
                                ),
                              ],
                            ),
                            // Right: name + avatar
                            Row(
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: _kPurpleSoft,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: _kPurple,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // ── Comment ────────────────────────────────────────
                      if (comment.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: Text(comment,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.55,
                                  color: Colors.grey[800])),
                        ),

                      // ── Trait chips ────────────────────────────────────
                      if (tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            children: tags.map((key) {
                              final meta = _kTraitTags.firstWhere(
                                  (t) => t['key'] == key,
                                  orElse: () => {'emoji': '✓'});
                              final tagLabel = _traitLabel(key, l10n);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.green.shade200),
                                ),
                                child: Text(
                                  '${meta['emoji']} $tagLabel',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green[800],
                                      fontWeight: FontWeight.w600),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      // ── Review photos ──────────────────────────────────
                      if (photos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: SizedBox(
                            height: 76,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              itemCount: photos.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () =>
                                    _expandPortfolioImage(context, photos, i),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 76,
                                    height: 76,
                                    child: _buildGalleryImage(photos[i]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // ── Provider response ──────────────────────────────
                      if (response != null && response.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kPurpleSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _kPurple.withValues(alpha: 0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Icon(Icons.verified_user_rounded,
                                      color: _kPurple, size: 14),
                                  Text(l10n.expertProviderResponse,
                                      style: const TextStyle(
                                          color: _kPurple,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(response,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                      color: Colors.grey[700])),
                            ],
                          ),
                        )
                      else if (isProvider)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                  foregroundColor: _kPurple,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2)),
                              icon: const Icon(Icons.reply_rounded, size: 15),
                              label: Text(l10n.expertAddReply,
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: () =>
                                  _showProviderReplyDialog(context, doc.id),
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),
                    ],
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  // ── Provider reply bottom sheet ───────────────────────────────────────────
  void _showProviderReplyDialog(BuildContext context, String reviewDocId) {
    final ctrl = TextEditingController();
    // Dispose the controller when the sheet is dismissed (success or cancel).
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Drag handle
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 16),
              Text(l10n.expertAddReplyTitle,
                  style: const
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 4,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: l10n.expertReplyHint,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: _kPurple, width: 1.5)),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                onPressed: () async {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  // Capture l10n error formatter before await
                  final replyErrorFn = l10n.expertReplyError; // ignore: prefer_function_declarations_over_variables
                  try {
                    await FirebaseFirestore.instance
                        .collection('reviews')
                        .doc(reviewDocId)
                        .update({'providerResponse': text});
                    if (ctx.mounted) Navigator.pop(ctx);
                    // Check parent state — ctx may be mounted while parent disposed
                    if (mounted) setState(() => _refreshTrigger++);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        backgroundColor: Colors.red,
                        content: Text(replyErrorFn('$e')),
                      ));
                    }
                  }
                },
                child: Text(l10n.expertPublishReply,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        );
      },
    ).whenComplete(() => ctrl.dispose());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Sticky bottom bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context, Map<String, dynamic> data) {
    final l10n       = AppLocalizations.of(context);
    final price      = (data['pricePerHour'] as num? ?? 100).toDouble();
    final services   = _deriveServices(price, l10n);
    final svcPrice   = services[_selectedServiceIndex]['price'] as double;
    final isReady    = _selectedDay != null && _selectedTimeSlot != null;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              border: Border(
                  top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, -5)),
              ],
            ),
            child: Row(
              children: [
                // ── Chat button ──────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _kPurple.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: _kPurple),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(
                                receiverId: widget.expertId,
                                receiverName: widget.expertName))),
                  ),
                ),
                const SizedBox(width: 12),

                // ── Book Now ──────────────────────────────────────────
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      // When onPressed is null Flutter uses disabledBackgroundColor —
                      // explicit values keep the "idle state" look consistent.
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed:
                        isReady ? () => _showBookingSummary(context, data, svcPrice) : null,
                    child: _isProcessing
                        ? const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5)
                        : isReady
                            ? Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white,
                                      size: 14),
                                  Text(
                                    l10n.expertBookForTime(_selectedTimeSlot ?? ''),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  Text(
                                    '₪${svcPrice.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    l10n.expertStartingFrom(price.toStringAsFixed(0)),
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11),
                                  ),
                                  Text(
                                    l10n.expertSelectDateTime,
                                    style: const TextStyle(
                                        color: Colors.white,
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
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Booking summary sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showBookingSummary(
      BuildContext context, Map<String, dynamic> data, double price) {
    final l10n    = AppLocalizations.of(context);
    final isDemo  = data['isDemo'] == true;
    final dateStr = _selectedDay != null
        ? "${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}"
        : "";
    // Use l10n title list — avoids calling _deriveServices with the already-
    // computed tier price (which would re-derive tiers from the wrong base).
    final svcTitles = [l10n.serviceSingleLesson, l10n.serviceExtendedLesson, l10n.serviceFullSession];
    final svcTitle  = svcTitles[_selectedServiceIndex.clamp(0, 2)];

    final policy = data['cancellationPolicy'] as String? ?? 'flexible';

    // Human-readable deadline string for the notice
    final dlDt = CancellationPolicyService.deadline(
      policy:          policy,
      appointmentDate: _selectedDay,
      timeSlot:        _selectedTimeSlot,
    );
    final dlStr = dlDt != null
        ? "${dlDt.day}/${dlDt.month} ${dlDt.hour.toString().padLeft(2,'0')}:${dlDt.minute.toString().padLeft(2,'0')}"
        : null;
    final penaltyPct = (CancellationPolicyService.penaltyFraction(policy) * 100).toInt();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(l10n.expertBookingSummaryTitle,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text("$svcTitle • $dateStr $_selectedTimeSlot",
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kPurpleSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: _kPurple, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _summaryRow(l10n.expertSummaryRowService, svcTitle),
                  _summaryRow(l10n.expertSummaryRowDate, dateStr),
                  _summaryRow(l10n.expertSummaryRowTime, _selectedTimeSlot ?? '—'),
                  _summaryRow(l10n.expertSummaryRowPrice, "₪${price.toStringAsFixed(0)}"),
                  _summaryRow(l10n.expertSummaryRowProtection, l10n.expertSummaryRowIncluded,
                      isGreen: true),
                  const Divider(height: 16),
                  _summaryRow(l10n.expertSummaryRowTotal,
                      "₪${price.toStringAsFixed(0)}",
                      isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Cancellation policy notice ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC02),
                    width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF856404)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dlStr != null
                          ? l10n.expertCancellationNotice(
                              CancellationPolicyService.label(policy),
                              dlStr,
                              penaltyPct)
                          : l10n.expertCancellationNoDeadline(
                              CancellationPolicyService.label(policy),
                              CancellationPolicyService.description(policy)),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF856404)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurple,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
              icon: const Icon(Icons.lock_rounded,
                  color: Colors.white, size: 18),
              label: Text(l10n.expertConfirmPaymentButton,
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              onPressed: () =>
                  _processEscrowPayment(context, price, policy, isDemo: isDemo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isBold ? FontWeight.bold : FontWeight.normal,
                  color: Colors.grey[700])),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  color: isGreen
                      ? Colors.green
                      : isBold
                          ? Colors.black
                          : Colors.black87,
                  fontWeight:
                      isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section header helper
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (trailing != null) trailing,
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: FutureBuilder<DocumentSnapshot>(
        key: ValueKey(_refreshTrigger),
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.expertId)
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final l10n    = AppLocalizations.of(context);
          final data    = snapshot.data!.data() as Map<String, dynamic>;
          final unavail = _parseUnavailableDates(data);

          return Stack(
            children: [
              // ── Main scrollable content ──────────────────────────────────
              RefreshIndicator(
                onRefresh: () async => setState(() => _refreshTrigger++),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Hero ────────────────────────────────────────────────
                    SliverAppBar(
                      expandedHeight: 320,
                      pinned: true,
                      stretch: true,
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      actions: const [
                        Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Center(child: AnySkillBrandIcon(size: 26)),
                        ),
                      ],
                      title: Text(widget.expertName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, shadows: [
                            Shadow(blurRadius: 10, color: Colors.black45)
                          ])),
                      flexibleSpace: FlexibleSpaceBar(
                        stretchModes: const [
                          StretchMode.zoomBackground,
                          StretchMode.blurBackground,
                        ],
                        background: _buildHeroBackground(data, l10n),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          // ── Power Row ──────────────────────────────────────
                          const SizedBox(height: 16),
                          _buildPowerRow(data, l10n),
                          const SizedBox(height: 24),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // ── About ──────────────────────────────────
                                _sectionHeader(l10n.expertSectionAbout),
                                _buildBioSection(data, l10n),
                                const SizedBox(height: 16),

                                // ── Quick Tags ─────────────────────────────
                                _buildQuickTagsSection(data),
                                if ((data['quickTags'] as List? ?? [])
                                    .isNotEmpty)
                                  const SizedBox(height: 24),

                                // ── Service Menu ───────────────────────────
                                _sectionHeader(l10n.expertSectionService),
                                _buildServiceMenu(data, l10n),
                                const SizedBox(height: 24),

                                // ── Portfolio ──────────────────────────────
                                if ((data['gallery'] as List? ?? []).isNotEmpty) ...[
                                  _sectionHeader(l10n.expertSectionGallery),
                                  _buildPortfolioGrid(data),
                                  const SizedBox(height: 24),
                                ],

                                // ── Booking calendar ──────────────────────
                                const Divider(height: 1),
                                const SizedBox(height: 24),
                                _sectionHeader(l10n.expertSectionSchedule),
                                _buildCalendar(unavail),
                                if (_selectedDay != null) ...[
                                  const SizedBox(height: 16),
                                  _buildTimeSlots(l10n),
                                ],
                                const SizedBox(height: 24),

                                // ── Reviews ────────────────────────────────
                                const Divider(height: 1),
                                const SizedBox(height: 24),
                                _buildReviewsSection(l10n),

                                // Space for sticky bar
                                const SizedBox(height: 120),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Sticky bottom bar ─────────────────────────────────────────
              _buildBottomBar(context, data),
            ],
          );
        },
      ),
    );
  }
}

// ─── Demo booking success dialog ─────────────────────────────────────────────
// Shown instead of a real escrow flow when the expert has isDemo: true.
// Auto-dismisses after 3 seconds or on tap.

class _DemoBookingSuccessDialog extends StatefulWidget {
  const _DemoBookingSuccessDialog();

  @override
  State<_DemoBookingSuccessDialog> createState() =>
      _DemoBookingSuccessDialogState();
}

class _DemoBookingSuccessDialogState extends State<_DemoBookingSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>    _scale;
  late final Animation<double>    _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();

    // Auto-dismiss after 3 s
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: FadeTransition(
        opacity: _fade,
        child: Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success circle
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF6366F1).withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '✅ ההזמנה נשלחה בהצלחה!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'המומחה יאשר את המועד בקרוב.\nתקבל עדכון בהודעה.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('סגור',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
