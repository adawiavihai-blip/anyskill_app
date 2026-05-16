// Helper widgets for EditProfileScreen — extracted in B.3 (§80, 2026-05-14).
// 'part of' the main library so the private _AddSecondIdentitySheet +
// _EditSecondIdentitySheet classes stay reachable without rename.
//
// Imports are inherited from the parent file — don't add any here.
part of '../../edit_profile_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Pure render helpers — E.3 (§83, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════

const _kHourOptions = [
  '07:00', '08:00', '09:00', '10:00', '11:00', '12:00',
  '13:00', '14:00', '15:00', '16:00', '17:00', '18:00',
  '19:00', '20:00', '21:00', '22:00',
];

/// Working-hours dropdown — single hour picker used in 7 places (one per day).
Widget _buildHourDropdown(String value, ValueChanged<String> onChanged) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: DropdownButton<String>(
      value: _kHourOptions.contains(value) ? value : '09:00',
      underline: const SizedBox.shrink(),
      isDense: true,
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      items: _kHourOptions
          .map((h) => DropdownMenuItem(
                value: h,
                child: Text(h, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

/// Gallery thumbnail — HTTPS network image OR base64 data URI, with
/// graceful broken-image fallback for both paths.
Widget _buildGalleryImage(String raw) {
  if (raw.isEmpty) {
    return Container(color: Colors.grey[200]);
  }
  if (raw.startsWith('http')) {
    return Image.network(
      raw,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
      ),
    );
  }
  try {
    final b64 = raw.contains(',') ? raw.split(',').last : raw;
    return Image.memory(
      base64Decode(b64),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  } catch (_) {
    return Container(
      color: Colors.grey[200],
      child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
    );
  }
}

// _buildLoadingHint removed 2026-05-15 — the only caller was the EditProfile
// main-category dropdown, which now uses an inline Builder showing the user's
// saved value as hint text (no spinner). See edit_profile_screen.dart ~1509.

// ═══════════════════════════════════════════════════════════════════════════════
// Contact widgets — E.2 (§83, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════
// Extracted from `_buildLockedPhoneField`, `_buildEmailField`,
// `_buildPendingExpertBanner` inside _EditProfileScreenState.

/// Pure pending-banner card — shown when the provider's verification is
/// awaiting admin review. No state coupling.
class _PendingExpertBanner extends StatelessWidget {
  const _PendingExpertBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC107)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppLocalizations.of(context).editAppPending,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).editAppPendingDesc,
                  textAlign: TextAlign.right,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.brown),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Locked-or-add phone field. Two states:
///   • [phoneDisplay] is empty → "Add Phone" CTA that calls [onAddPhone]
///   • [phoneDisplay] is set   → locked display (cannot be changed in-app)
class _LockedPhoneField extends StatelessWidget {
  const _LockedPhoneField({
    required this.phoneDisplay,
    required this.onAddPhone,
  });

  final String phoneDisplay;
  final Future<void> Function() onAddPhone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (phoneDisplay.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Icon(Icons.phone_rounded,
                  size: 14, color: Color(0xFF6366F1)),
              const SizedBox(width: 4),
              Text(
                l10n.editPhoneLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onAddPhone,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16, 13, 16, 13),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF6366F1), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_rounded,
                      size: 18, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'הוסף מספר טלפון ואמת אותו',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_back_ios_rounded,
                      size: 13, color: Color(0xFF6366F1)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 4),
            child: Text(
              'הוספת מספר חובה. תקבל קוד SMS לאימות. לאחר השמירה לא ניתן לשנות — צוות AnySkill בלבד.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const Icon(Icons.lock_rounded,
                size: 13, color: Color(0xFF6366F1)),
            const SizedBox(width: 4),
            Text(
              l10n.editPhoneLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  phoneDisplay,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.phone_rounded,
                size: 17,
                color: Color(0xFF6366F1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editPhoneVerified,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

/// Email field — editable TextField or locked display when signed in via
/// Google/Apple ([lockedFromAuth] = true).
class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.lockedFromAuth,
  });

  final TextEditingController controller;
  final bool lockedFromAuth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (lockedFromAuth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Icon(Icons.lock_rounded,
                  size: 13, color: Color(0xFF6366F1)),
              const SizedBox(width: 4),
              Text(
                l10n.loginEmail,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F7FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.text.isEmpty ? '—' : controller.text,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      color: controller.text.isEmpty
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.alternate_email_rounded,
                  size: 17,
                  color: Color(0xFF6366F1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              'מסונכרן אוטומטית מחשבון Google / Apple',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.loginEmail,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textAlign: TextAlign.start,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.alternate_email_rounded,
                size: 18, color: Color(0xFF6366F1)),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Identity Cards section — E.1 (§83, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════
// Extracted from `_buildSecondIdentityCard` + `_buildIdentityCards` +
// `_buildIdentityTile` inside _EditProfileScreenState. Bundles the 3
// methods into a self-contained widget. Takes:
//   • cachedListings — from State's _allListings (may be empty)
//   • activeListingId — from State's _activeListingId
//   • userData — widget.userData (forwarded into the switch navigation)
//   • onAddSecond — callback opens IdentityOnboardingScreen + setState
// The widget falls back to a one-shot ProviderListingService.getListings
// when the cache is empty, matching the original behavior.

class _IdentityCardsSection extends StatelessWidget {
  const _IdentityCardsSection({
    required this.cachedListings,
    required this.activeListingId,
    required this.userData,
    required this.onAddSecond,
  });

  final List<Map<String, dynamic>> cachedListings;
  final String? activeListingId;
  final Map<String, dynamic> userData;
  final VoidCallback onAddSecond;

  @override
  Widget build(BuildContext context) {
    if (cachedListings.isNotEmpty) {
      return _IdentityCardsList(
        listings: cachedListings,
        activeListingId: activeListingId,
        userData: userData,
        onAddSecond: onAddSecond,
      );
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ProviderListingService.getListings(uid),
      builder: (context, snap) {
        final listings = snap.data ?? [];
        return _IdentityCardsList(
          listings: listings,
          activeListingId: activeListingId,
          userData: userData,
          onAddSecond: onAddSecond,
        );
      },
    );
  }
}

class _IdentityCardsList extends StatelessWidget {
  const _IdentityCardsList({
    required this.listings,
    required this.activeListingId,
    required this.userData,
    required this.onAddSecond,
  });

  final List<Map<String, dynamic>> listings;
  final String? activeListingId;
  final Map<String, dynamic> userData;
  final VoidCallback onAddSecond;

  @override
  Widget build(BuildContext context) {
    final hasSecond = listings.length >= 2;
    return Column(
      children: [
        if (listings.isNotEmpty) ...[
          for (final listing in listings)
            _IdentityTile(
              listing: listing,
              activeListingId: activeListingId,
              userData: userData,
            ),
          const SizedBox(height: 12),
        ],
        if (!hasSecond)
          GestureDetector(
            onTap: onAddSecond,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8FAFC), Color(0xFFF0F0FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add_business_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            AppLocalizations.of(context).editAddSecondIdentity,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            )),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)
                              .editSecondIdentitySubtitle,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[600],
                              height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded,
                      color: Color(0xFF6366F1)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _IdentityTile extends StatelessWidget {
  const _IdentityTile({
    required this.listing,
    required this.activeListingId,
    required this.userData,
  });

  final Map<String, dynamic> listing;
  final String? activeListingId;
  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final listingId = listing['listingId'] as String? ?? '';
    final serviceType = listing['serviceType'] as String? ?? '';
    final index = (listing['identityIndex'] as num?)?.toInt() ?? 0;
    final isCurrent = listingId == activeListingId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: isCurrent
            ? null
            : () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(
                      userData: userData,
                      listingId: listingId,
                    ),
                  ),
                );
              },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFFEEF2FF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xFF6366F1)
                  : Colors.grey.shade200,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  index == 0
                      ? Icons.work_rounded
                      : Icons.add_business_rounded,
                  size: 20,
                  color: isCurrent
                      ? const Color(0xFF6366F1)
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceType,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isCurrent
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      index == 0
                          ? AppLocalizations.of(context).editPrimaryIdentity
                          : AppLocalizations.of(context)
                              .editSecondaryIdentity,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      AppLocalizations.of(context).editEditingNow,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                )
              else
                const Icon(Icons.swap_horiz_rounded,
                    color: Color(0xFF6366F1), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// My Dogs section — D.4 (§82, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════
// Extracted from `_buildMyDogsSection`. Pure top-level function — no state
// coupling, no setState. Reads FirebaseAuth.currentUser + streams
// DogProfileService.streamForOwner. Reachable from the State class via
// the `part of` directive.

Widget _buildMyDogsSection(BuildContext context) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const SizedBox.shrink();

  return StreamBuilder<List<DogProfile>>(
    stream: DogProfileService.instance.streamForOwner(uid),
    builder: (ctx, snap) {
      if (snap.hasError) return const SizedBox.shrink();
      final dogs = snap.data ?? const <DogProfile>[];
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pets_rounded,
                    color: Color(0xFF6366F1), size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(AppLocalizations.of(context).editMyDogs,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (dogs.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DogProfileListScreen()),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(AppLocalizations.of(context).editShowAll,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1A1A2E),
                          fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 10),
            if (dogs.isEmpty)
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DogProfileBuilderScreen()),
                ),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.add_circle_outline_rounded,
                          size: 28, color: Color(0xFF6366F1)),
                      const SizedBox(height: 6),
                      Text(AppLocalizations.of(context).editAddDogProfile,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6366F1))),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 116,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: dogs.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    if (i == dogs.length) {
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const DogProfileBuilderScreen()),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 92,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFF6366F1), width: 1.2),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_rounded,
                                  color: Color(0xFF6366F1)),
                              const SizedBox(height: 4),
                              Text(AppLocalizations.of(context).editNewDog,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF6366F1),
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      );
                    }
                    final d = dogs[i];
                    final photo = safeImageProvider(d.photoUrl);
                    return InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                DogProfileBuilderScreen(existing: d)),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 92,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(0xFFEEF2FF),
                              backgroundImage: photo,
                              child: photo == null
                                  ? const Icon(Icons.pets_rounded,
                                      color: Color(0xFF6366F1))
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              d.name.isEmpty
                                  ? AppLocalizations.of(context).editUnnamedDog
                                  : d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E)),
                            ),
                            if (d.breed.isNotEmpty)
                              Text(
                                d.breed,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFF6B7280)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// v10.1.0: ADD SECOND IDENTITY BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _AddSecondIdentitySheet extends StatefulWidget {
  final List<Map<String, dynamic>> mainCategories;
  final VoidCallback onCreated;

  const _AddSecondIdentitySheet({
    required this.mainCategories,
    required this.onCreated,
  });

  @override
  State<_AddSecondIdentitySheet> createState() => _AddSecondIdentitySheetState();
}

class _AddSecondIdentitySheetState extends State<_AddSecondIdentitySheet> {
  String? _selectedCatId;
  final _aboutCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _aboutCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selectedCatId == null) return;
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) return;

    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cat = widget.mainCategories.firstWhere(
      (c) => c['id'] == _selectedCatId,
      orElse: () => <String, dynamic>{},
    );
    final catName = cat['name'] as String? ?? '';

    try {
      // Ensure primary listing exists first
      await ProviderListingService.migrateIfNeeded(uid);

      await ProviderListingService.createListing(
        uid: uid,
        identityIndex: 1,
        serviceType: catName,
        aboutMe: _aboutCtrl.text.trim(),
        pricePerHour: price,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF22C55E),
            content: Text(AppLocalizations.of(context).editSecondIdentityCreated),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).editGenericError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).editAddSecondIdentityTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(AppLocalizations.of(context).editAddSecondIdentityDesc,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),

            // Category dropdown
            DropdownButtonFormField<String>(
              value: _selectedCatId,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).editCategoryLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: widget.mainCategories.map((c) => DropdownMenuItem(
                value: c['id'] as String?,
                child: Text(c['name'] as String? ?? ''),
              )).toList(),
              onChanged: (v) => setState(() => _selectedCatId = v),
            ),
            const SizedBox(height: 16),

            // Price
            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).editPriceLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixText: '₪ ',
              ),
            ),
            const SizedBox(height: 16),

            // About
            TextFormField(
              controller: _aboutCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).chatServiceDescLabel,
                hintText: AppLocalizations.of(context).editSecondServiceDesc,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Create button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.of(context).editCreateIdentity,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// v10.1.0: EDIT SECOND IDENTITY BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _EditSecondIdentitySheet extends StatefulWidget {
  final Map<String, dynamic> listing;
  final List<Map<String, dynamic>> mainCategories;
  final VoidCallback onSaved;

  const _EditSecondIdentitySheet({
    required this.listing,
    required this.mainCategories,
    required this.onSaved,
  });

  @override
  State<_EditSecondIdentitySheet> createState() => _EditSecondIdentitySheetState();
}

class _EditSecondIdentitySheetState extends State<_EditSecondIdentitySheet> {
  late final TextEditingController _aboutCtrl;
  late final TextEditingController _priceCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _aboutCtrl = TextEditingController(text: widget.listing['aboutMe'] as String? ?? '');
    _priceCtrl = TextEditingController(
      text: ((widget.listing['pricePerHour'] as num?) ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _aboutCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) return;

    setState(() => _saving = true);
    final listingId = widget.listing['listingId'] as String? ?? '';

    try {
      await ProviderListingService.updateListing(listingId, {
        'aboutMe': _aboutCtrl.text.trim(),
        'pricePerHour': price,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF22C55E),
            content: Text(AppLocalizations.of(context).editIdentityUpdated),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).editGenericError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editDeleteIdentityTitle),
        content: Text(l10n.editDeleteIdentityConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.profCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.editDelete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final uid = widget.listing['uid'] as String? ?? '';
      final listingId = widget.listing['listingId'] as String? ?? '';
      await ProviderListingService.deleteListing(listingId, uid);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text(AppLocalizations.of(context).editIdentityDeleted),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).editGenericError(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceType = widget.listing['serviceType'] as String? ?? '';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).editEditingIdentity(serviceType),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),

            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).editPriceLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixText: '₪ ',
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _aboutCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).chatServiceDescLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.of(context).editSaveChanges,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),

            // Delete button
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
              label: Text(AppLocalizations.of(context).editDeleteIdentity,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Cancellation Policy + Working Hours pickers — G.3 (§85, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════

/// Cancellation policy picker — radio-button list of all
/// [CancellationPolicyService.kPolicies] values with label + description.
///
/// Caller owns [selectedPolicy] and applies the change via [onChanged].
class _CancellationPolicyPicker extends StatelessWidget {
  const _CancellationPolicyPicker({
    required this.selectedPolicy,
    required this.onChanged,
  });

  final String selectedPolicy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.editProfileCancellationPolicy,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editProfileCancellationHint,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 10),
        ...CancellationPolicyService.kPolicies.map((p) {
          final selected = selectedPolicy == p;
          return GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFF0F0FF)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF6366F1)
                      : Colors.grey.shade200,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? const Color(0xFF6366F1)
                        : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          CancellationPolicyService.label(p),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: selected
                                ? const Color(0xFF6366F1)
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          CancellationPolicyService.description(p),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Working-hours editor — 7-day grid of (checkbox + from/to dropdowns).
///
/// Each day is enabled when present in [workingHours] (a `Map<int, ...>` keyed
/// by weekday index where the value is `{from, to}`).
/// Callbacks: [onToggle] when the checkbox flips, [onHoursChanged] when
/// either dropdown changes. [dayNames] supplies the localized weekday
/// labels (length 7, index 0 = Sunday).
class _WorkingHoursEditor extends StatelessWidget {
  const _WorkingHoursEditor({
    required this.workingHours,
    required this.dayNames,
    required this.onToggle,
    required this.onHoursChanged,
  });

  final Map<int, Map<String, String>> workingHours;
  final List<String> dayNames;
  final void Function(int dayIndex, bool enabled) onToggle;
  final void Function(int dayIndex, String field, String value) onHoursChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.editWorkingHours,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editWorkingHoursHint,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(7, (dayIndex) {
          final enabled = workingHours.containsKey(dayIndex);
          final from = workingHours[dayIndex]?['from'] ?? '09:00';
          final to = workingHours[dayIndex]?['to'] ?? '17:00';
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: enabled,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (val) => onToggle(dayIndex, val == true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text(
                    dayNames[dayIndex],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: enabled ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ),
                if (enabled) ...[
                  _buildHourDropdown(from, (val) {
                    onHoursChanged(dayIndex, 'from', val);
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '–',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  _buildHourDropdown(to, (val) {
                    onHoursChanged(dayIndex, 'to', val);
                  }),
                ] else
                  Text(
                    l10n.editDayOff,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Gallery + Certification + Video Upload — I.1 (§87, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════

/// Work-portfolio gallery editor — 3-col grid of thumbnails + "add" tile
/// at the end. Tap thumb's X to remove.
class _GallerySection extends StatelessWidget {
  const _GallerySection({
    required this.galleryImages,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  final List galleryImages;
  final VoidCallback onPickImage;
  final void Function(int index) onRemoveImage;

  /// Hard cap — keep in sync with `_kMaxGalleryImages` in
  /// edit_profile_screen.dart's `_pickAndCompressGalleryImage`.
  static const int _kMaxGallery = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final atCap = galleryImages.length >= _kMaxGallery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.editProfileGallery,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${galleryImages.length}/$_kMaxGallery',
              style: TextStyle(
                fontSize: 12,
                color: atCap ? const Color(0xFFEF4444) : Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          // +1 for the "add" slot unless we've hit the cap.
          itemCount: galleryImages.length + (atCap ? 0 : 1),
          itemBuilder: (context, index) {
            if (!atCap && index == galleryImages.length) {
              return GestureDetector(
                onTap: onPickImage,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.blue.shade100,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: Colors.blue,
                    size: 35,
                  ),
                ),
              );
            }
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildGalleryImage(
                    galleryImages[index] as String? ?? '',
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => onRemoveImage(index),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cancel,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Certification image upload card. Two states: empty (amber CTA) or
/// uploaded (image + X to clear + "replace" link).
class _CertificationImageSection extends StatelessWidget {
  const _CertificationImageSection({
    required this.imageData,
    required this.onPick,
    required this.onClear,
  });

  final String? imageData;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editCertificate,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editCertificateDesc,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 10),
        if (imageData != null) ...[
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildGalleryImage(imageData!),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onClear,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cancel,
                      color: Colors.red,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(l10n.editReplaceCertificate),
          ),
        ] else
          GestureDetector(
            onTap: onPick,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 36,
                      color: Colors.amber[700],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.editUploadCertificate,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[800],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Verification video upload card — animated container with three visual
/// states (idle indigo / uploading progress / uploaded green).
class _VideoVerificationSection extends StatelessWidget {
  const _VideoVerificationSection({
    required this.videoUrl,
    required this.uploadInProgress,
    required this.uploadProgress,
    required this.onPick,
  });

  final String? videoUrl;
  final bool uploadInProgress;
  final double uploadProgress;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editIntroVideo,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editIntroVideoDesc,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: uploadInProgress ? null : onPick,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            decoration: BoxDecoration(
              color: videoUrl != null
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFF0F0FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: videoUrl != null
                    ? const Color(0xFF10B981)
                    : const Color(0xFF6366F1),
                width: 1.5,
              ),
            ),
            child: uploadInProgress
                ? Column(
                    children: [
                      LinearProgressIndicator(
                        value: uploadProgress,
                        backgroundColor: const Color(0xFFE0E0FF),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF6366F1)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.editUploading((uploadProgress * 100).toInt()),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        videoUrl != null
                            ? Icons.videocam_rounded
                            : Icons.video_call_rounded,
                        color: videoUrl != null
                            ? const Color(0xFF10B981)
                            : const Color(0xFF6366F1),
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        videoUrl != null
                            ? l10n.editVideoUploaded
                            : l10n.editUploadVideo,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: videoUrl != null
                              ? const Color(0xFF10B981)
                              : const Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (videoUrl != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              l10n.editPendingAdmin,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Volunteer toggle + Quick Tags picker — I.2 (§87, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider-only volunteer-mode toggle. Switches between an idle grey
/// state and an active green state with a red heart icon.
class _VolunteerToggleCard extends StatelessWidget {
  const _VolunteerToggleCard({
    required this.isVolunteer,
    required this.onChanged,
  });

  final bool isVolunteer;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isVolunteer
            ? const Color(0xFFECFDF5)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isVolunteer
              ? const Color(0xFF10B981)
              : Colors.grey.shade200,
          width: isVolunteer ? 1.5 : 1,
        ),
      ),
      child: SwitchListTile.adaptive(
        value: isVolunteer,
        onChanged: onChanged,
        activeColor: const Color(0xFF10B981),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              l10n.editVolunteerToggleTitle,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 6),
            if (isVolunteer)
              const Icon(Icons.favorite, color: Colors.red, size: 18),
          ],
        ),
        subtitle: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editVolunteerToggleDesc,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.right,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
    );
  }
}

/// Quick-tags picker — 8 predefined chips from [kQuickTagCatalog], max
/// 3 selected. Disabled (grey) chips are unselected ones when the cap
/// is reached.
class _QuickTagsPicker extends StatelessWidget {
  const _QuickTagsPicker({
    required this.selectedKeys,
    required this.onToggle,
  });

  final Set<String> selectedKeys;
  final void Function(String key) onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.editProfileTagsSelected(selectedKeys.length),
              style: TextStyle(
                fontSize: 12,
                color: selectedKeys.length >= 3
                    ? const Color(0xFF6366F1)
                    : Colors.grey,
              ),
            ),
            Text(
              l10n.editProfileQuickTags,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.editProfileTagsHint,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: kQuickTagCatalog.map((tag) {
            final key = tag['key']!;
            final selected = selectedKeys.contains(key);
            final maxed = selectedKeys.length >= 3;
            return GestureDetector(
              onTap: () {
                if (!selected && maxed) return;
                onToggle(key);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF6366F1)
                      : (!selected && maxed)
                          ? Colors.grey[100]
                          : const Color(0xFFF0F0FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF6366F1)
                        : (!selected && maxed)
                            ? Colors.grey.shade300
                            : const Color(0xFF6366F1)
                                .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '${tag['emoji']} ${tag['label']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : (!selected && maxed)
                            ? Colors.grey
                            : const Color(0xFF6366F1),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tax ID + Payment-Settings notice + Business Bio — I.3 (§87, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════

/// Tax ID field — number input with receipt icon. Used for invoicing.
class _TaxIdField extends StatelessWidget {
  const _TaxIdField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.profileFieldTaxId,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.profileFieldTaxIdHelp,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            hintText: l10n.profileFieldTaxIdHint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            prefixIcon: const Icon(
              Icons.receipt_long_outlined,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}

/// Phase 2 notice card — Stripe Connect was removed pending the Israeli
/// payment provider integration. Read-only amber notice.
class _PaymentSettingsNotice extends StatelessWidget {
  const _PaymentSettingsNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              const Icon(
                Icons.construction_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.editPaymentSettings,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.editPaymentSettingsDesc,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF7C2D12),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Business description / bio textfield (4 lines).
class _BusinessBioField extends StatelessWidget {
  const _BusinessBioField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.editProfileAbout,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextField(
          controller: controller,
          maxLines: 4,
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: l10n.editProfileAboutHint,
          ),
        ),
      ],
    );
  }
}
