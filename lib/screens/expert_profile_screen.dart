// ignore_for_file: use_build_context_synchronously
// H.3 (§86, 2026-05-14): `library;` + part directive added so the
// 508-LOC _showBookingSummary moves to a sibling part file while keeping
// library-private access to all State fields + closure helpers.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';
import 'account_settings_screen.dart';
import 'chat_screen.dart';
import 'expert_profile/widgets/about_section.dart';
import 'expert_profile/widgets/action_squares.dart';
import 'expert_profile/widgets/booking_time_slots.dart';
import 'expert_profile/widgets/service_menu.dart';
import 'expert_profile/widgets/booking_bottom_bar.dart';
import 'expert_profile/widgets/booking_calendar.dart';
import 'expert_profile/widgets/reviews_section.dart';
import 'expert_profile/widgets/booking_success_view.dart';
import 'expert_profile/widgets/csm_booking_blocks.dart';
import 'expert_profile/widgets/specialist_card.dart';
// quick_tags.dart imported by about_section.dart (§81 C.3).
import '../services/cancellation_policy_service.dart';
import '../services/expert_booking_service.dart';
import '../services/cache_service.dart';
import '../services/cached_readers.dart';
import '../services/location_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/anyskill_logo.dart';
import '../widgets/favorite_button.dart';
// service_architect.dart used by service_menu.dart now (§81 C.3).
import '../models/pricing_model.dart';
import '../widgets/primary_cta.dart';
import '../utils/profile_guard.dart';
import '../constants.dart' show appVersion;
import '../widgets/price_list_widget.dart';
import '../widgets/provider_category_tags_display.dart';
import '../widgets/category_specs_widget.dart';
import '../features/pet_stay/models/dog_profile.dart';
// Pet Stay imports moved to expert_booking_service.dart (§81).
import '../features/pet_stay/widgets/dog_picker_section.dart';
// §80 (2026-05-14): CSM imports trimmed after the booking-block builders
// moved to expert_profile/widgets/csm_booking_blocks.dart. Only the
// `*BookingPreferences` types still referenced by state fields remain.
import '../models/handyman_profile.dart'; // HandymanBookingPreferences
import '../models/fitness_trainer_profile.dart'; // PricingPackage
import '../models/motorcycle_tow_profile.dart'; // MotorcycleTowBookingPreferences
import 'massage/build_your_treatment_block.dart'; // MassageBookingPreferences
import 'pest_control/pest_booking_block.dart'; // PestControlBookingPreferences
import 'delivery/delivery_booking_block.dart'; // DeliveryBookingPreferences
import 'cleaning/cleaning_booking_block.dart'; // CleaningBookingPreferences
import 'babysitter/babysitter_booking_block.dart'; // BabysitterBookingPreferences

part 'expert_profile/widgets/booking_summary_sheet.dart';

// Brand tokens
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);


class ExpertProfileScreen extends StatefulWidget {
  final String expertId;
  final String expertName;
  /// v10.5.0: When provided, the profile shows identity-specific rating,
  /// reviewsCount, and reviews from this listing only.
  final String? listingId;

  const ExpertProfileScreen({
    super.key,
    required this.expertId,
    required this.expertName,
    this.listingId,
  });

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

  // ── Portfolio image viewer state ───────────────────────────────────────────
  final PageController _pageController = PageController();

  // ── Bio expand state ───────────────────────────────────────────────────────
  // §81 (C.3, 2026-05-14): _bioExpanded moved into BioSection's own State
  // (about_section.dart). The flag was purely UI-local.

  // ── Dynamic pricing state ──────────────────────────────────────────────────
  /// Indices of add-ons the client has checked in the order sheet.
  final Set<int> _selectedAddOnIndices = {};

  /// Slots already booked for the selected day — grayed out in the time picker.
  Set<String> _bookedSlots = {};
  bool _loadingSlots = false;

  /// v2 service schema for the expert's category. Loaded once when the profile
  /// resolves. Used by the booking sheet to render booking requirements + show
  /// deposit / surcharge information.
  ServiceSchema _serviceSchema = ServiceSchema.empty();
  String _lastSchemaCategory = '';

  /// Customer-supplied answers to [ServiceSchema.bookingRequirements].
  /// Persisted to `jobs/{id}.bookingRequirementValues` on payment.
  final Map<String, dynamic> _bookingReqValues = {};

  /// Pet Stay Tracker (v13.0.0) — selected dog for pet-services bookings.
  /// Required when `_serviceSchema.walkTracking || dailyProof`.
  /// Snapshot is written to `jobs/{id}/petStay/data` inside the payment tx.
  DogProfile? _selectedDog;

  /// End date for multi-night boarding (pension). Defaults to start+1 at
  /// booking time. Irrelevant for dog-walker (single session).
  DateTime? _petStayEndDate;

  /// Customer's current GPS position — used to compute distance to the
  /// provider in the stats column. Seeded from LocationService.cached
  /// immediately; re-fetched via requestAndGet if null so we don't wait
  /// on some other screen to have requested permission first.
  Position? _myPosition;

  final List<String> _timeSlots = [
    "08:00", "09:00", "10:00", "11:00",
    "14:00", "15:00", "16:00", "17:00", "18:00", "19:00",
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('he_IL', null);
    _initMyPosition();
    // Flash Auction no longer routes through this screen — it direct-books
    // via `FlashAuctionService.bookFromOffer` from FlashAuctionOffersScreen.
    // See CLAUDE.md §57.
    // 2026-05-15 — CACHE the profile-load future. Previously the
    // FutureBuilder called `_loadProfileData()` directly in `build()`,
    // so EVERY rebuild (setState, parent rebuild, keyboard open, etc.)
    // created a NEW future → FutureBuilder reset to its loading
    // spinner → re-fetched the whole profile. That caused both the
    // wasteful re-reads AND the intermittent "profile data didn't
    // sync" symptom (a rebuild mid-display flashed back to loading
    // and could fail the re-fetch). Now the future is created ONCE
    // here and only re-created when `_refreshTrigger` bumps.
    _profileDataFuture = _loadProfileData();
  }

  /// Cached profile-load future — see initState. Recreated ONLY in
  /// [_reloadProfile] when `_refreshTrigger` changes (pull-to-refresh
  /// or a provider-reply that needs fresh reviews).
  late Future<Map<String, dynamic>> _profileDataFuture;

  /// Bump the refresh trigger AND recreate the cached future so the
  /// FutureBuilder actually re-fetches. Calling setState alone would
  /// NOT re-fetch (the cached future is reused by design).
  void _reloadProfile() {
    if (!mounted) return;
    setState(() {
      _refreshTrigger++;
      _profileDataFuture = _loadProfileData();
    });
  }

  /// Seed from cache (instant) or request actively with retry. Logs to
  /// console so you can see in DevTools why distance isn't resolving.
  /// Retries once after 1.5s if the first attempt returns null — this
  /// covers the web case where the browser needs a beat to resolve
  /// permission state on first call.
  Future<void> _initMyPosition() async {
    final cached = LocationService.cached;
    // ignore: avoid_print
    print('[ExpertProfile/distance] LocationService.cached = '
        '${cached == null ? "null" : "(${cached.latitude}, ${cached.longitude})"}');
    if (cached != null) {
      if (mounted) setState(() => _myPosition = cached);
      return;
    }
    if (!mounted) return;
    Position? pos;
    try {
      pos = await LocationService.requestAndGet(context);
      // ignore: avoid_print
      print('[ExpertProfile/distance] requestAndGet (attempt 1) returned = '
          '${pos == null ? "null" : "(${pos.latitude}, ${pos.longitude})"}');
    } catch (e) {
      // ignore: avoid_print
      print('[ExpertProfile/distance] requestAndGet (attempt 1) threw: $e');
    }

    // Retry once — sometimes web geolocation needs a beat to resolve state
    if (pos == null && mounted) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      try {
        pos = await LocationService.getIfGranted();
        // ignore: avoid_print
        print('[ExpertProfile/distance] getIfGranted (attempt 2) returned = '
            '${pos == null ? "null (permission denied or service unavailable)" : "(${pos.latitude}, ${pos.longitude})"}');
      } catch (e) {
        // ignore: avoid_print
        print('[ExpertProfile/distance] getIfGranted (attempt 2) threw: $e');
      }
    }

    if (mounted && pos != null) setState(() => _myPosition = pos);
  }

  /// v10.5.0: Loads user doc + merges listing-specific fields when listingId
  /// is provided. This ensures rating/reviewsCount/aboutMe/gallery reflect
  /// the specific professional identity, not the global user aggregate.
  Future<Map<String, dynamic>> _loadProfileData() async {
    // §15 Law 15 — bounded fetches with cache-first fallback. Without
    // timeouts, a zombie WebChannel left the FutureBuilder stuck on
    // CircularProgressIndicator forever (רועי צברי report 2026-05-14:
    // "click on profile card → spinner spins forever, never opens").
    //
    // Strategy:
    //   1. Try to load `users/{expertId}` (12s + 8s fallback).
    //   2. Always try to load `provider_listings/{listingId}` in
    //      parallel — for demo profiles where `expertId` is empty
    //      OR the user doc doesn't exist (e.g. demo created with
    //      a fake uid), the listing IS the source of truth.
    //   3. Merge: listing fields override user fields when present.
    //   4. Only treat the load as failed when BOTH are empty.
    Map<String, dynamic> userData = const <String, dynamic>{};
    if (widget.expertId.isNotEmpty) {
      try {
        // First pass: cache + server (up to 12s). 5-min cache TTL means
        // hot reads return instantly; cold reads race the server.
        userData = await CacheService.getDoc(
          'users',
          widget.expertId,
          ttl: CacheService.kExpertProfile,
          forceRefresh: false,
        ).timeout(const Duration(seconds: 12));
      } catch (e) {
        debugPrint('[ExpertProfile] _loadProfileData primary timeout: $e');
        try {
          userData = await CacheService.getDoc(
            'users',
            widget.expertId,
            ttl: CacheService.kExpertProfile,
            forceRefresh: false,
          ).timeout(const Duration(seconds: 8));
        } catch (_) {
          debugPrint('[ExpertProfile] _loadProfileData both attempts failed');
        }
      }
      // 2026-05-15 (live bug, רועי צברי "demo profile image lo
      // mistanchren"): CacheService.getDoc caches EMPTY maps for the
      // full TTL when a prior call hit a missing doc / partial fetch /
      // cold-cache race. Subsequent calls within 5 minutes get the
      // cached empty map → profile image renders the initials
      // fallback. If `userData` came back without a `profileImage`,
      // force a fresh server read (bypassing cache) so we definitely
      // have the latest data before falling through to listing merge.
      final hasUsableImage =
          ((userData['profileImage'] as String?) ?? '').trim().isNotEmpty;
      if (!hasUsableImage) {
        try {
          final fresh = await CacheService.getDoc(
            'users',
            widget.expertId,
            ttl: CacheService.kExpertProfile,
            forceRefresh: true,
          ).timeout(const Duration(seconds: 8));
          if (fresh.isNotEmpty) {
            userData = fresh;
            debugPrint(
                '[ExpertProfile] Forced fresh server read recovered profileImage');
          }
        } catch (_) {
          // Network blip — fall through to listing merge below.
        }
      }
    }

    // ── Resolve the listing doc ─────────────────────────────────────────
    // 2026-05-15 ROOT FIX (רועי צברי "clicks VIP banner → opens
    // provider with NO details"): the VIP carousel + chat + deep-links
    // push ExpertProfileScreen with `expertId` but WITHOUT `listingId`.
    // The old code then returned userData as-is — skipping the listing
    // merge entirely AND the reviews-by-listingId query. For a
    // dual-identity provider whose identity data lives on the listing,
    // the profile rendered empty.
    //
    // Fix: when `listingId` is null but the user is a provider, AUTO-
    // RESOLVE their primary listing (`provider_listings where uid ==
    // expertId, identityIndex == 0`). Now the profile is correct no
    // matter HOW it was navigated to — search card, VIP banner, chat,
    // deep-link all work identically.
    String? resolvedListingId = widget.listingId;
    if (resolvedListingId == null && widget.expertId.isNotEmpty) {
      final isProviderUser = userData['isProvider'] == true ||
          (userData['listingIds'] as List?)?.isNotEmpty == true;
      // Even when userData is empty (cold-cache), still try — a demo
      // profile may have an empty users doc but a real listing.
      if (isProviderUser || userData.isEmpty) {
        try {
          final lq = await FirebaseFirestore.instance
              .collection('provider_listings')
              .where('uid', isEqualTo: widget.expertId)
              .orderBy('identityIndex')
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 8));
          if (lq.docs.isNotEmpty) {
            resolvedListingId = lq.docs.first.id;
            debugPrint(
                '[ExpertProfile] Auto-resolved listingId=$resolvedListingId for expertId=${widget.expertId}');
          }
        } catch (e) {
          debugPrint('[ExpertProfile] Listing auto-resolve failed: $e');
        }
      }
    }

    // If still no listingId, return user data as-is (backward compat).
    if (resolvedListingId == null) return userData;

    // Merge listing-specific fields over the user doc — also timeout-
    // bounded so a slow listing read can't hang the whole profile.
    // CRITICAL: for demo profiles where `users/{uid}` may not exist
    // (admin-created uid that isn't a real Firebase Auth account),
    // the listing IS the source of truth and supplies ALL the
    // user-facing fields (name, profileImage, aboutMe, rating, etc.).
    final merged = Map<String, dynamic>.from(userData);
    try {
      final listingSnap = await FirebaseFirestore.instance
          .collection('provider_listings')
          .doc(resolvedListingId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (listingSnap.exists) {
        final listing = listingSnap.data() ?? {};
        // Identity-specific fields ALWAYS sourced from listing — these
        // are per-listing (one provider can have 2 identities w/
        // different categories, prices, reviews).
        for (final key in const [
          'rating', 'reviewsCount', 'gallery', 'pricePerHour',
          'serviceType', 'quickTags', 'categoryTags', 'categoryDetails',
          'priceList', 'cancellationPolicy',
        ]) {
          if (listing[key] != null) merged[key] = listing[key];
        }
        if (listing['aboutMe'] != null &&
            (listing['aboutMe'] as String).isNotEmpty) {
          merged['aboutMe'] = listing['aboutMe'];
        }
        // FALLBACK fields — only filled IN when the user doc is missing
        // those values. Critical for demo profiles where users/{uid}
        // doesn't exist at all and the listing carries the display data.
        // Without this, demos rendered with empty name/image/etc. and
        // my empty-data guard surfaced a misleading "בעיית חיבור"
        // (רועי צברי report 2026-05-14).
        //
        // 2026-05-15: extended the "is missing" check to ALSO trigger on
        // empty strings. Previously `merged[key] == null` was the only
        // condition — so a user doc with `profileImage: ''` (empty,
        // not null) blocked the listing's REAL profileImage from
        // filling in. Live bug (רועי צברי, again): expert profiles
        // showed initials instead of photos on first cold-WebChannel
        // open because the user-doc fetch returned with empty fields
        // before the listing's denormalized fields could take over.
        bool isMissing(dynamic v) {
          if (v == null) return true;
          if (v is String) return v.trim().isEmpty;
          if (v is List) return v.isEmpty;
          if (v is Map) return v.isEmpty;
          return false;
        }
        for (final key in const [
          'name', 'profileImage', 'phone', 'email',
          'isVerified', 'isOnline', 'isDemo', 'isHidden',
          'isAnySkillPro', 'isPromoted', 'isVolunteer',
          'parentCategory', 'subCategory', 'workingHours',
        ]) {
          if (isMissing(merged[key]) && listing[key] != null) {
            merged[key] = listing[key];
          }
        }
        // Always denormalize the uid back onto merged so downstream
        // code (chat, booking) doesn't break on demo profiles with
        // missing expertId.
        if ((merged['uid'] as String? ?? '').isEmpty &&
            (listing['uid'] as String? ?? '').isNotEmpty) {
          merged['uid'] = listing['uid'];
        }
        // Carry the resolved listingId so downstream consumers can use
        // it (e.g. booking flow). Used even when widget.listingId was
        // null and we auto-resolved the primary listing.
        merged['listingId'] = resolvedListingId;
      }
    } catch (e) {
      debugPrint('[ExpertProfile] Listing merge error: $e');
    }

    // Load v2 schema for the expert's most-specific category. Stored on
    // state so the booking sheet can render booking requirements + show
    // deposit / surcharge banners. Cached by category name to avoid refetching.
    final categoryName = (merged['serviceType'] as String? ?? '').trim();
    if (categoryName.isNotEmpty && categoryName != _lastSchemaCategory) {
      try {
        // §61: cached read — 30 min TTL. Schema changes via Categories v3
        // admin call CachedReaders.invalidateServiceSchema(name) to bust.
        final schema = await CachedReaders.serviceSchemaForCategory(categoryName);
        if (mounted) {
          setState(() {
            _serviceSchema = schema;
            _lastSchemaCategory = categoryName;
          });
        }
      } catch (e) {
        debugPrint('[ExpertProfile] Schema load error: $e');
      }
    }

    return merged;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Derived service tiers (no separate Firestore collection needed)
  // ─────────────────────────────────────────────────────────────────────────

  // §81 (C.3, 2026-05-14): _deriveServices moved to
  // ServiceMenu.deriveServices (service_menu.dart).

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  // §81 (2026-05-14): _getChatRoomId moved into ExpertBookingService
  // (deterministic ids.sort().join('_')).

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

  // Returns true on success, false on any error (error UI already shown).
  //
  // v4.3.0 — WriteBatch architecture:
  //   Phase 1: Sequential reads (fee %, balance, slot existence) — plain awaits,
  //            no runTransaction wrapper, so no JS Promise retry loop on Web.
  //   Phase 2: WriteBatch.commit() — single batched RPC, stable on all platforms
  //            including Desktop Chrome where runTransaction's internal Promise
  //            chain caused "Dart exception from converted Future" (minified:kt).
  //
  // navigator.pop() is still intentionally NOT called here — the success view's
  // "Done" button is the sole trigger, decoupled from every async chain.
  /// §81 (2026-05-14): thin orchestration layer. The atomic escrow
  /// transaction + demo booking writes are now in
  /// [ExpertBookingService] (lib/services/expert_booking_service.dart).
  /// This method:
  ///   1. Demo / profile / self-booking gates
  ///   2. setState(_isProcessing=true)
  ///   3. Build BookingRequest from state
  ///   4. await ExpertBookingService.processEscrow(request)
  ///   5. Translate outcome → snackbar / dialog / success
  ///   6. finally: setState(_isProcessing=false)
  Future<bool> _processEscrowPayment(
      BuildContext context, double totalPrice, String cancellationPolicy,
      {bool isDemo = false}) async {
    // ── Demo expert: show success illusion, no real writes ──────────────
    if (isDemo) {
      return await _handleDemoBooking(context);
    }

    if (_isProcessing) return false;

    // ── Profile completeness gate (ProfileGuard handles UI itself) ─────
    if (!await ProfileGuard.ensureComplete(context)) return false;

    // ── Anti-fraud: block self-booking ────────────────────────────────
    final selfUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (selfUid == widget.expertId) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).expCantBookSelf),
          backgroundColor: const Color(0xFFEF4444),
        ));
      }
      return false;
    }

    // Selected day/time guard (UI normally enforces this, but safe-fail).
    if (_selectedDay == null || _selectedTimeSlot == null) return false;

    setState(() => _isProcessing = true);

    // Capture l10n + messenger BEFORE await (context may unmount).
    final l10n = AppLocalizations.of(context);
    final msgInsufficientBalance = l10n.expertInsufficientBalance;
    final transactionTitle =
        l10n.expertTransactionTitle(widget.expertName);
    final dateStr = '${_selectedDay!.day}/${_selectedDay!.month}';
    final messenger = ScaffoldMessenger.of(context);

    // Compute commission for the system-message preview (mirrors the
    // server-side math — service writes the real number atomically).
    final adminFeePctApprox = 0.10; // service reads the real value inside tx
    final expertNetApprox = double.parse(
        (totalPrice * (1 - adminFeePctApprox)).toStringAsFixed(2));
    final systemMsg = l10n.expertSystemMessage(
      dateStr,
      _selectedTimeSlot!,
      expertNetApprox.toStringAsFixed(0),
    );

    try {
      final request = BookingRequest(
        customerId: selfUid,
        customerName: '', // service reads from Firestore inside tx
        expertId: widget.expertId,
        expertName: widget.expertName,
        totalPrice: totalPrice,
        cancellationPolicy: cancellationPolicy,
        selectedDay: _selectedDay!,
        selectedTimeSlot: _selectedTimeSlot!,
        serviceSchema: _serviceSchema,
        lastSchemaCategory: _lastSchemaCategory,
        bookingReqValues: _bookingReqValues,
        transactionTitle: transactionTitle,
        systemMessage: systemMsg,
        massagePreferences: _massagePreferences,
        massageTotalPrice: _massageTotalPrice,
        pestControlPreferences: _pestControlPreferences,
        pestControlTotalPrice: _pestControlTotalPrice,
        deliveryPreferences: _deliveryPreferences,
        deliveryTotalPrice: _deliveryTotalPrice,
        cleaningPreferences: _cleaningPreferences,
        cleaningTotalPrice: _cleaningTotalPrice,
        handymanPreferences: _handymanPreferences,
        handymanTotalPrice: _handymanTotalPrice,
        fitnessPackage: _fitnessPackage,
        fitnessTotalPrice: _fitnessTotalPrice,
        babysitterPreferences: _babysitterPreferences,
        babysitterTotalPrice: _babysitterTotalPrice,
        motorcycleTowPreferences: _motorcycleTowPreferences,
        motorcycleTowTotalPrice: _motorcycleTowTotalPrice,
        selectedDog: _selectedDog,
        petStayEndDate: _petStayEndDate,
      );

      final outcome = await ExpertBookingService.processEscrow(request);

      switch (outcome.kind) {
        case BookingOutcomeKind.success:
          // Best-effort: system chat message AFTER successful tx commit.
          try {
            await ExpertBookingService.sendSystemMessage(
              chatRoomId: outcome.chatRoomId!,
              customerId: selfUid,
              expertId: widget.expertId,
              message: systemMsg,
            );
          } catch (e) {
            debugPrint('[ExpertProfile] system msg failed (non-fatal): $e');
          }
          return true;

        case BookingOutcomeKind.insufficientBalance:
          if (mounted) {
            messenger.showSnackBar(SnackBar(
              backgroundColor: Colors.red,
              content: Text(msgInsufficientBalance),
            ));
          }
          return false;

        case BookingOutcomeKind.slotConflict:
          if (mounted) {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Row(children: [
                  const Icon(Icons.event_busy_rounded,
                      color: Color(0xFFEF4444), size: 22),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).expSlotTakenTitle,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                content: Text(
                  AppLocalizations.of(context).expSlotTakenBody,
                  textAlign: TextAlign.right,
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                        AppLocalizations.of(context).expUnderstood,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
          return false;

        case BookingOutcomeKind.error:
          if (mounted) {
            final raw = outcome.errorMessage ?? '';
            final lower = raw.toLowerCase();
            final friendly =
                (lower.contains('permission') || lower.contains('insufficient'))
                    ? AppLocalizations.of(context).expBookingError
                    : raw;
            messenger.showSnackBar(SnackBar(
              backgroundColor: Colors.red,
              content: Text(friendly),
            ));
          }
          return false;
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
    // Unreachable — switch above is exhaustive. Defensive fallback for
    // dart analyzer, which can't always prove enum exhaustiveness through
    // a try/finally block.
    // ignore: dead_code
    return false;
  }

  // ── Demo booking: thin l10n wrapper around ExpertBookingService ─────────
  //
  // §81 (2026-05-14): the Firestore writes (demo_bookings + activity_log +
  // admin notifications + customer notification) moved to
  // ExpertBookingService.handleDemoBooking. This wrapper just captures
  // l10n strings BEFORE the await (context-safe pattern) and forwards.
  Future<bool> _handleDemoBooking(BuildContext context) async {
    final defaultCustomerName =
        AppLocalizations.of(context).expDefaultCustomer;
    final customerNotificationBody =
        AppLocalizations.of(context).expDemoBookingMsg(widget.expertName);
    return ExpertBookingService.handleDemoBooking(
      customerId: FirebaseAuth.instance.currentUser?.uid ?? '',
      expertId: widget.expertId,
      expertName: widget.expertName,
      selectedDay: _selectedDay,
      selectedTimeSlot: _selectedTimeSlot,
      defaultCustomerName: defaultCustomerName,
      customerNotificationBody: customerNotificationBody,
    );
  }

  // §81 (2026-05-14): _sendSystemNotification moved to
  // ExpertBookingService.sendSystemMessage. Caller is the success
  // branch of _processEscrowPayment's switch.



  // ─────────────────────────────────────────────────────────────────────────
  // UI: Quick Tags
  // ─────────────────────────────────────────────────────────────────────────

  // §81 (C.3, 2026-05-14): _buildQuickTagsSection → QuickTagsSection,
  // _buildBioSection → BioSection. Both in about_section.dart.

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Service menu
  // ─────────────────────────────────────────────────────────────────────────

  // §81 (C.3, 2026-05-14): _buildServiceMenu + _buildAddOnsPanel moved
  // to ServiceMenu (service_menu.dart).
  // ignore: unused_element

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Interactive Portfolio grid
  // ─────────────────────────────────────────────────────────────────────────

  void _expandPortfolioImage(
      BuildContext context, List<String> images, int startIndex) {
    final ctrl = PageController(initialPage: startIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      // dialogCtx is the dialog's own context — required for correct Navigator.pop
      builder: (dialogCtx) => Dialog(
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
                // Use dialogCtx so only the dialog is popped, not the whole page
                onTap: () => Navigator.pop(dialogCtx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
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
    ).then((_) => ctrl.dispose());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Share — lets a customer recommend this provider's profile (WhatsApp +
  // copy-link). Mirrors profile_screen.dart `_shareProfile` but with text
  // written from a customer's perspective ("found a great provider..."
  // instead of the provider promoting themselves).
  // ─────────────────────────────────────────────────────────────────────────

  void _shareExpertProfile() {
    final String profileLink =
        'https://anyskill-6fdf3.web.app/#/expert?id=${widget.expertId}';
    final String shareText =
        'מצאתי נותן שירות מעולה ב-AnySkill — ${widget.expertName}. '
        'כדאי לבדוק את הפרופיל: $profileLink';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 15),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              // RTL inherited from MaterialApp locale — no need to pass
              // textDirection (intl import in this file shadows
              // dart:ui's TextDirection enum).
              child: Text(
                'שתף את הפרופיל',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF25D366),
                child: Icon(Icons.chat_bubble_outline,
                    color: Colors.white, size: 20),
              ),
              title: const Text('שתף ב-WhatsApp'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(sheetCtx);
                final whatsappUrl =
                    'https://wa.me/?text=${Uri.encodeComponent(shareText)}';
                try {
                  final uri = Uri.parse(whatsappUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  } else {
                    throw 'Could not launch WhatsApp';
                  }
                } catch (_) {
                  messenger.showSnackBar(const SnackBar(
                    content: Text('פתיחת WhatsApp נכשלה'),
                  ));
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.copy, color: Colors.white),
              ),
              title: const Text('העתק קישור'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: profileLink));
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('הקישור הועתק'),
                ));
              },
            ),
            const SizedBox(height: 20),
          ],
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

  // §80 (2026-05-14): _buildCalendar extracted to BookingCalendar
  // in expert_profile/widgets/booking_calendar.dart. Call site ~line 3926.

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Time slots
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches already-booked slots for [day] from the bookingSlots collection.
  Future<void> _loadBookedSlots(DateTime day) async {
    setState(() => _loadingSlots = true);
    try {
      final datePrefix =
          '${widget.expertId}_'
          '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}_';
      // bookingSlots doc IDs follow the pattern: {expertId}_{YYYYMMDD}_{HHmm}
      // Query all slots for this expert + date.
      final snap = await FirebaseFirestore.instance
          .collection('bookingSlots')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: datePrefix)
          .where(FieldPath.documentId, isLessThan: '${datePrefix}z')
          .limit(20)
          .get();

      final booked = <String>{};
      for (final doc in snap.docs) {
        // Extract HHmm from doc ID → "HH:mm"
        final suffix = doc.id.replaceFirst(datePrefix, '');
        if (suffix.length == 4) {
          booked.add('${suffix.substring(0, 2)}:${suffix.substring(2)}');
        }
      }
      if (mounted) setState(() { _bookedSlots = booked; _loadingSlots = false; });
    } catch (e) {
      debugPrint('[Booking] Failed to load booked slots: $e');
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  /// Generates time slots from the provider's `workingHours` for [_selectedDay].
  /// Falls back to hardcoded [_timeSlots] if the provider hasn't set hours.

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Reviews — Advanced Social Proof System
  // ─────────────────────────────────────────────────────────────────────────

  // ── Reviews: Airbnb-style state ─────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Sticky bottom bar
  // ─────────────────────────────────────────────────────────────────────────

  // §80 (2026-05-14): _buildBottomBar extracted to BookingBottomBar
  // (expert_profile/widgets/booking_bottom_bar.dart).

  // ─────────────────────────────────────────────────────────────────────────
  // Booking summary sheet
  // ─────────────────────────────────────────────────────────────────────────
  // §86 H.3 (2026-05-14): body moved to
  // expert_profile/widgets/booking_summary_sheet.dart (part-of). This
  // wrapper preserves the original call signature so the existing call
  // site stays unchanged.
  void _showBookingSummary(
    BuildContext context,
    Map<String, dynamic> data,
    double price, {
    List<AddOn> addOns = const [],
    Set<int> selectedAddOns = const {},
  }) =>
      _libShowBookingSummary(
        this,
        context,
        data,
        price,
        addOns: addOns,
        selectedAddOns: selectedAddOns,
      );

  // ── Booking success view ──────────────────────────────────────────────────
  // Replaces the booking summary inside the bottom sheet upon transaction
  // commit. The "Done" button is the sole trigger for navigator.pop(), which
  // means pop() is always a direct user gesture — never inside an async chain.
  //
  // Demo path (isDemo = true): the Firestore booking transaction is bypassed
  // entirely. We still render this success view so the customer believes the
  // booking went through. The wording is intentionally softer ("we'll update
  // you when the provider is available") to set expectations without revealing
  // §80 (2026-05-14): _buildBookingSuccessView extracted to
  // expert_profile/widgets/booking_success_view.dart. Call site at
  // line ~2530 uses BookingSuccessView(isDemo: ...).

  Widget _summaryRow(String label, String value,
      {bool isBold = false, bool isGreen = false, bool isAddOn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: isAddOn ? 12 : 14,
                  fontWeight:
                      isBold ? FontWeight.bold : FontWeight.normal,
                  color: isAddOn ? const Color(0xFF6366F1) : Colors.grey[700])),
          Text(value,
              style: TextStyle(
                  fontSize: isAddOn ? 12 : 14,
                  color: isGreen
                      ? Colors.green
                      : isAddOn
                          ? const Color(0xFF6366F1)
                          : isBold
                              ? Colors.black
                              : Colors.black87,
                  fontWeight: (isBold || isAddOn)
                      ? FontWeight.bold
                      : FontWeight.normal)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section header helper
  // ─────────────────────────────────────────────────────────────────────────

  // ── Massage Treatment Block helpers ────────────────────────────────────

  MassageBookingPreferences? _massagePreferences;
  double _massageTotalPrice = 0;
  PestControlBookingPreferences? _pestControlPreferences;
  double _pestControlTotalPrice = 0;
  DeliveryBookingPreferences? _deliveryPreferences;
  double _deliveryTotalPrice = 0;
  CleaningBookingPreferences? _cleaningPreferences;
  HandymanBookingPreferences? _handymanPreferences;
  double _handymanTotalPrice = 0;
  double _cleaningTotalPrice = 0;
  PricingPackage? _fitnessPackage;
  double _fitnessTotalPrice = 0;
  BabysitterBookingPreferences? _babysitterPreferences;
  double _babysitterTotalPrice = 0;
  MotorcycleTowBookingPreferences? _motorcycleTowPreferences;
  double _motorcycleTowTotalPrice = 0;

  // §80 (2026-05-14): 8 CSM booking-block builders + 8 detector methods
  // extracted to expert_profile/widgets/csm_booking_blocks.dart as:
  //   • {Massage,Pest,Delivery,Cleaning,Handyman,Babysitter,
  //      MotorcycleTow,FitnessTrainer}BookingAdapter
  //   • hasXProfileFor(data) top-level functions

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

  // ─────────────────────────────────────────────────────────────────────────
  // §80 (2026-05-14): Specialist card moved to SpecialistCard
  // (expert_profile/widgets/specialist_card.dart) along with its helpers
  // _expertStatRow → _StatRow (private to widget),
  // _buildDistanceRow → _DistanceRow,
  // _volunteerCountStream → _VolunteerCountStat.
  // ─────────────────────────────────────────────────────────────────────────


  // §80 (2026-05-14):
  // - _buildActionSquares → ActionSquares (widgets/action_squares.dart)
  // - _extractYouTubeId → ActionSquares.extractYouTubeId
  // - _showCertificationDialog + _buildCertImage → CertificationDialog
  //   (widgets/certification_dialog.dart)

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        titleSpacing: 0,
        title: Text(widget.expertName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          // Account Settings entry — visible ONLY when the provider is
          // viewing their own profile (Roi-style: tapped own avatar from
          // search/stories and landed here instead of the Profile tab).
          // Same destination as the Profile-tab button — see CLAUDE.md
          // (Account Settings section).
          if ((FirebaseAuth.instance.currentUser?.uid ?? '') ==
              widget.expertId)
            IconButton(
              tooltip: 'הגדרות חשבון',
              icon: const Icon(Icons.manage_accounts_rounded,
                  size: 22, color: Color(0xFF6366F1)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AccountSettingsScreen()),
              ),
            ),
          // Share: lets a customer recommend this provider to a friend.
          // Mirrors the WhatsApp + copy-link pattern used by the provider's
          // own self-share in profile_screen.dart `_shareProfile`.
          IconButton(
            tooltip: 'שתף פרופיל',
            icon: const Icon(Icons.ios_share_rounded, size: 22),
            onPressed: () => _shareExpertProfile(),
          ),
          FavoriteButton(providerId: widget.expertId, size: 24),
          const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(child: AnySkillBrandIcon(size: 22)),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(_refreshTrigger),
        future: _profileDataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final l10n    = AppLocalizations.of(context);
          // 2026-05-14: removed the "בעיית חיבור" retry scaffold here.
          // The user reported false-positive errors on working networks.
          // Now `data` may be `{}` (load failed silently) — downstream
          // widgets render with fallbacks (empty name, no gallery, etc.)
          // and the user can pull-to-refresh OR navigate back to retry.
          // For demos, the listing merge inside `_loadProfileData` already
          // fills the minimum fields needed to show the profile.
          final data    = snapshot.data!;
          final unavail = _parseUnavailableDates(data);

          return Stack(
            children: [
              // ── Main scrollable content ──────────────────────────────────
              RefreshIndicator(
                onRefresh: () async => _reloadProfile(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Specialist card (mirrors ProfileScreen) ─────────────
                    SliverToBoxAdapter(
                      child: SpecialistCard(
                        data: data,
                        expertId: widget.expertId,
                        expertName: widget.expertName,
                        myPosition: _myPosition,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: ActionSquares(
                          data: data,
                          onPortfolioTap: (i) =>
                              _expandPortfolioImage(context, (data['gallery'] as List? ?? []).cast<String>(), i),
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // ── About ──────────────────────────────────
                                _sectionHeader(l10n.expertSectionAbout),
                                BioSection(data: data),
                                const SizedBox(height: 16),

                                // ── Quick Tags ─────────────────────────────
                                QuickTagsSection(data: data),
                                if ((data['quickTags'] as List? ?? [])
                                    .isNotEmpty)
                                  const SizedBox(height: 10),

                                // ── Category-specific tags (all, no cap) ──
                                if ((data['categoryTags'] as List?)
                                        ?.isNotEmpty ==
                                    true) ...[
                                  ProviderCategoryTagsDisplay(
                                    category:
                                        (data['serviceType'] as String? ?? '')
                                            .trim(),
                                    tagIds: ((data['categoryTags']
                                                as List?) ??
                                            const [])
                                        .cast<String>(),
                                    maxVisible: null,
                                    compact: false,
                                  ),
                                  const SizedBox(height: 24),
                                ] else if ((data['quickTags'] as List? ?? [])
                                    .isNotEmpty)
                                  const SizedBox(height: 14),

                                // ── CSM adapters (§80) — one per category.
                                // Detectors and adapter widgets live in
                                // expert_profile/widgets/csm_booking_blocks.dart.
                                if (hasMassageProfileFor(data))
                                  MassageBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onPreferencesChanged: (p) {
                                      _massagePreferences = p;
                                    },
                                    onTotalChanged: (t) {
                                      setState(() => _massageTotalPrice = t);
                                    },
                                  ),
                                if (hasPestControlProfileFor(data))
                                  PestBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onPreferencesChanged: (p) {
                                      _pestControlPreferences = p;
                                    },
                                    onTotalChanged: (t) {
                                      setState(() => _pestControlTotalPrice = t);
                                    },
                                  ),
                                if (hasDeliveryProfileFor(data))
                                  DeliveryBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onChanged: (p, t) {
                                      _deliveryPreferences = p;
                                      if (t != _deliveryTotalPrice) {
                                        setState(() => _deliveryTotalPrice = t);
                                      }
                                    },
                                  ),
                                if (hasCleaningProfileFor(data))
                                  CleaningBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onChanged: (p, t) {
                                      _cleaningPreferences = p;
                                      if (t != _cleaningTotalPrice) {
                                        setState(() => _cleaningTotalPrice = t);
                                      }
                                    },
                                  ),
                                if (hasHandymanProfileFor(data))
                                  HandymanBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onChanged: (p, t) {
                                      _handymanPreferences = p;
                                      if (t != _handymanTotalPrice) {
                                        setState(() => _handymanTotalPrice = t);
                                      }
                                    },
                                  ),
                                if (hasFitnessTrainerProfileFor(data))
                                  FitnessTrainerBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onPackageSelected: (pkg) {
                                      final newTotal = pkg.price.toDouble();
                                      _fitnessPackage = pkg;
                                      if (newTotal != _fitnessTotalPrice) {
                                        setState(() => _fitnessTotalPrice = newTotal);
                                      }
                                    },
                                  ),
                                if (hasBabysitterProfileFor(data))
                                  BabysitterBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onPreferencesChanged: (p) {
                                      _babysitterPreferences = p;
                                    },
                                    onTotalChanged: (t) {
                                      if (t != _babysitterTotalPrice) {
                                        setState(() => _babysitterTotalPrice = t);
                                      }
                                    },
                                  ),
                                if (hasMotorcycleTowProfileFor(data))
                                  MotorcycleTowBookingAdapter(
                                    data: data,
                                    expertId: widget.expertId,
                                    onChanged: (p, t) {
                                      _motorcycleTowPreferences = p;
                                      if (t != _motorcycleTowTotalPrice) {
                                        setState(() => _motorcycleTowTotalPrice = t);
                                      }
                                    },
                                  ),

                                // ── Service Menu ───────────────────────────
                                // Hidden for motorcycle towing providers — the
                                // tow request block above is the only service.
                                if (!isMotorcycleTowingCategory(
                                    data['serviceType'] as String?)) ...[
                                  _sectionHeader(l10n.expertSectionService),
                                  ServiceMenu(
                                    data: data,
                                    selectedServiceIndex: _selectedServiceIndex,
                                    selectedAddOnIndices: _selectedAddOnIndices,
                                    onServiceSelected: (i) => setState(
                                        () => _selectedServiceIndex = i),
                                    onAddOnToggle: (i) => setState(() {
                                      if (_selectedAddOnIndices.contains(i)) {
                                        _selectedAddOnIndices.remove(i);
                                      } else {
                                        _selectedAddOnIndices.add(i);
                                      }
                                    }),
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                // ── Price List (category-specific) ────────
                                if (hasPriceList(data) &&
                                    (data['priceList'] as Map?)?.isNotEmpty == true)
                                  PriceListDisplay(
                                    priceList: Map<String, dynamic>.from(
                                        data['priceList'] as Map),
                                    userData: data,
                                    onSendQuote: (msg) => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                                receiverId: widget.expertId,
                                                receiverName: widget.expertName,
                                                initialMessage: msg))),
                                  ),
                                if (hasPriceList(data) &&
                                    (data['priceList'] as Map?)?.isNotEmpty == true)
                                  const SizedBox(height: 24),

                                // ── Booking calendar ──────────────────────
                                const Divider(height: 1),
                                const SizedBox(height: 24),
                                _sectionHeader(l10n.expertSectionSchedule),
                                BookingCalendar(
                                  unavailableDates: unavail,
                                  selectedDay: _selectedDay,
                                  focusedDay: _focusedDay,
                                  onDaySelected: (selectedDay, focusedDay) {
                                    setState(() {
                                      _selectedDay = selectedDay;
                                      _focusedDay = focusedDay;
                                      _selectedTimeSlot = null;
                                      _bookedSlots = {};
                                    });
                                    _loadBookedSlots(selectedDay);
                                  },
                                ),
                                if (_selectedDay != null) ...[
                                  const SizedBox(height: 16),
                                  BookingTimeSlots(
                                    expertData: data,
                                    selectedDay: _selectedDay,
                                    legacyTimeSlots: _timeSlots,
                                    selectedSlot: _selectedTimeSlot,
                                    bookedSlots: _bookedSlots,
                                    loading: _loadingSlots,
                                    onSlotSelected: (s) => setState(
                                        () => _selectedTimeSlot = s),
                                    onSelectionInvalidated: () {
                                      if (mounted) {
                                        setState(
                                            () => _selectedTimeSlot = null);
                                      }
                                    },
                                  ),
                                ],
                                const SizedBox(height: 24),

                                // ── Reviews ────────────────────────────────
                                const Divider(height: 1),
                                const SizedBox(height: 24),
                                ReviewsSection(
                                  expertId: widget.expertId,
                                  listingId: widget.listingId,
                                  refreshKey: _refreshTrigger,
                                  onReplySent: _reloadProfile,
                                ),

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
              BookingBottomBar(
                data: data,
                expertId: widget.expertId,
                expertName: widget.expertName,
                services: ServiceMenu.deriveServices(
                    PricingModel.fromFirestore(data).basePrice,
                    data['serviceType'] as String? ?? ''),
                selectedServiceIndex: _selectedServiceIndex,
                selectedAddOnIndices: _selectedAddOnIndices,
                selectedDay: _selectedDay,
                selectedTimeSlot: _selectedTimeSlot,
                isProcessing: _isProcessing,
                onBookPressed: (totalPrice, addOns) {
                  _showBookingSummary(
                    context,
                    data,
                    totalPrice,
                    addOns: addOns,
                    selectedAddOns: _selectedAddOnIndices,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Booking sheet — night stepper button (used by the multi-night pension picker)
// ═══════════════════════════════════════════════════════════════════════════

class _NightStepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NightStepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color:
                enabled ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Full-screen photo viewer for review photos (pinch-to-zoom + swipe)
// ═══════════════════════════════════════════════════════════════════════════

