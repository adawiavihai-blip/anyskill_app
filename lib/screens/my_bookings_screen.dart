// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/bookings/booking_shared_widgets.dart';
import '../widgets/hint_icon.dart';
import 'bookings/booking_actions.dart';
import 'bookings/calendar_tab.dart';
import 'bookings/provider_tasks_tab.dart';
import 'bookings/provider_history_tab.dart';
import 'bookings/customer_bookings_tab.dart';

/// Orchestrator shell for the My Bookings / My Tasks screen.
///
/// Creates Firestore streams (once in initState) and passes them to child
/// tab widgets via constructor. All business logic (complete, cancel, dispute)
/// lives in [BookingActions]. All card/list UI lives in extracted widget files.
class MyBookingsScreen extends StatefulWidget {
  final VoidCallback? onGoToSearch;
  const MyBookingsScreen({super.key, this.onGoToSearch});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _isProvider     = false;
  bool _providerLoaded = false;
  bool _isAdmin        = false;

  StreamSubscription<DocumentSnapshot>? _userDocSub;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── Stable streams (created once, shared across tabs) ──────────────────
  late final Stream<QuerySnapshot> _expertStream;
  late final Stream<QuerySnapshot> _customerStream;

  @override
  void initState() {
    super.initState();
    _expertStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('expertId', isEqualTo: currentUserId)
        .limit(200)
        .snapshots();
    _customerStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('customerId', isEqualTo: currentUserId)
        .limit(200)
        .snapshots();
    _subscribeProviderStatus();
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    super.dispose();
  }

  void _subscribeProviderStatus() {
    if (currentUserId.isEmpty) {
      setState(() => _providerLoaded = true);
      return;
    }
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .snapshots()
        .listen(
      (doc) {
        if (!mounted) return;
        final data = doc.data() ?? {};
        final isProvider = data['isProvider'] == true;
        final isAdmin    = data['isAdmin']    == true;
        setState(() {
          _isProvider     = isProvider;
          _isAdmin        = isAdmin;
          _providerLoaded = true;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _providerLoaded = true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_providerLoaded) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: _isProvider ? 3 : 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 20,
          title: Text(
            _isProvider ? 'העבודות שלי' : 'ההזמנות שלי',
            style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 20),
          ),
          actions: [
            HintIcon(
                screenKey: _isProvider
                    ? 'my_tasks_expert'
                    : 'my_bookings_client'),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                    bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
              ),
              child: TabBar(
                indicatorColor: const Color(0xFF6366F1),
                indicatorWeight: 3,
                labelColor: const Color(0xFF6366F1),
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                tabs: _isProvider
                    ? const [Tab(text: 'משימות שלי'), Tab(text: 'יומן'), Tab(text: 'היסטוריה')]
                    : const [Tab(text: 'פעילות'), Tab(text: 'היסטוריה')],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: _isProvider
              ? [
                  BookingKeepAlivePage(
                    child: ProviderTasksTab(
                      expertStream: _expertStream,
                      currentUserId: currentUserId,
                      isAdmin: _isAdmin,
                      onMarkDone: BookingActions.markJobDone,
                      onProviderCancel: BookingActions.providerCancelBooking,
                      onShowDetails: BookingActions.showJobDetailsSheet,
                      onShowReceipt: BookingActions.showReceiptFor,
                      onGoToSearch: widget.onGoToSearch,
                    ),
                  ),
                  BookingKeepAlivePage(
                    child: CalendarTab(
                      currentUserId: currentUserId,
                      expertStream: _expertStream,
                    ),
                  ),
                  BookingKeepAlivePage(
                    child: ProviderHistoryTab(
                      expertStream: _expertStream,
                      currentUserId: currentUserId,
                      onShowDetails: BookingActions.showJobDetailsSheet,
                      onShowReceipt: BookingActions.showReceiptFor,
                      onMarkDone: BookingActions.markJobDone,
                      onProviderCancel: BookingActions.providerCancelBooking,
                      onGoToSearch: widget.onGoToSearch,
                    ),
                  ),
                ]
              : [
                  BookingKeepAlivePage(
                    child: CustomerBookingsTab(
                      customerStream: _customerStream,
                      currentUserId: currentUserId,
                      isHistory: false,
                      onCompleteJob: BookingActions.handleCompleteJob,
                      onCancel: BookingActions.cancelBooking,
                      onDispute: BookingActions.openDispute,
                      onShowDetails: BookingActions.showJobDetailsSheet,
                      onShowReceipt: BookingActions.showReceiptFor,
                      onGoToSearch: widget.onGoToSearch,
                    ),
                  ),
                  BookingKeepAlivePage(
                    child: CustomerBookingsTab(
                      customerStream: _customerStream,
                      currentUserId: currentUserId,
                      isHistory: true,
                      onCompleteJob: BookingActions.handleCompleteJob,
                      onCancel: BookingActions.cancelBooking,
                      onDispute: BookingActions.openDispute,
                      onShowDetails: BookingActions.showJobDetailsSheet,
                      onShowReceipt: BookingActions.showReceiptFor,
                      onGoToSearch: widget.onGoToSearch,
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}
