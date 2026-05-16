// Helper widgets for CategoryResultsScreen — extracted in B.2 (§80, 2026-05-14).
// 'part of' the main library so the private _XxxWidget classes stay reachable
// from inside _CategoryResultsScreenState without rename or import noise.
//
// Imports (theme tokens, l10n, services, packages) are inherited from the
// parent file. Don't add imports here — Dart's part-of contract forbids it.
part of '../../category_results_screen.dart';

// ── Community action button ───────────────────────────────────────────────────
class _CommunityActionButton extends StatelessWidget {
  const _CommunityActionButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });
  final String       label;
  final IconData     icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Internal Support FAB (replaces WhatsApp — v9.0.8) ───────────────────────
class _WhatsAppSosButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: const Color(0xFF6366F1),
      elevation: 6,
      icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
      label: Text(
        AppLocalizations.of(context).catSupport,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SupportCenterScreen(
              jobCategory: 'volunteer',
            ),
          ),
        );
      },
    );
  }
}

// ── Help request form sheet ───────────────────────────────────────────────────
class _HelpRequestSheet extends StatefulWidget {
  const _HelpRequestSheet({required this.forOther});
  final bool forOther;

  @override
  State<_HelpRequestSheet> createState() => _HelpRequestSheetState();
}

class _HelpRequestSheetState extends State<_HelpRequestSheet> {
  final _descCtrl        = TextEditingController();
  final _locationCtrl    = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _beneficiaryCtrl = TextEditingController();

  String? _selectedCategory;
  bool    _iAmContact  = true;
  bool    _submitting  = false;

  List<Map<String, dynamic>> _mainCategories = [];

  @override
  void initState() {
    super.initState();
    // Load category list once for the picker
    // .first throws "Bad state: No element" if the stream closes empty.
    // .catchError silently ignores that case — the picker just stays empty.
    CategoryService.streamMainCategories().first.then((cats) {
      if (mounted) setState(() => _mainCategories = cats);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    _beneficiaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCategory == null ||
        _descCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).catFillFields),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final nav       = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Capture localized strings BEFORE async gaps (Section 9 async-safe pattern)
    final l10n = AppLocalizations.of(context);
    final sentMsg = l10n.catRequestSent;

    try {
      final uid      = FirebaseAuth.instance.currentUser?.uid ?? '';
      final category = _selectedCategory!;
      final db       = FirebaseFirestore.instance;

      // 1. Save the volunteer request
      await db.collection('volunteer_requests').add({
        'requesterId':     uid,
        'forOther':        widget.forOther,
        'beneficiaryName': widget.forOther ? _beneficiaryCtrl.text.trim() : null,
        'contactIsRequester': widget.forOther ? _iAmContact : true,
        'category':        category,
        'description':     _descCtrl.text.trim(),
        'location':        _locationCtrl.text.trim(),
        'contactPhone':    _phoneCtrl.text.trim(),
        'status':          'open',
        'createdAt':       FieldValue.serverTimestamp(),
      });

      // 2. Notify matching volunteers (fire-and-forget batch)
      _notifyVolunteers(category, _descCtrl.text.trim());

      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sentMsg,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.catRequestError(e.toString())),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Queries all volunteer providers in [category] and writes an in-app
  /// notification for each (capped at 30 to stay within free Firestore quota).
  Future<void> _notifyVolunteers(String category, String description) async {
    try {
      final db   = FirebaseFirestore.instance;
      final snap = await db
          .collection('users')
          .where('isProvider',  isEqualTo: true)
          .where('isVolunteer', isEqualTo: true)
          .where('serviceType', isEqualTo: category)
          .limit(30)
          .get();

      final batch = db.batch();
      for (final doc in snap.docs) {
        final ref = db.collection('notifications').doc();
        batch.set(ref, {
          'userId':    doc.id,
          'title':    '❤️ בקשת התנדבות חדשה',
          'body':     'יש בקשת עזרה בתחום $category: "${description.length > 60 ? '${description.substring(0, 60)}…' : description}"',
          'type':     'volunteer_request',
          'isRead':   false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {
      // Best-effort — a notification failure must never affect the request post
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),

              // Title + free badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('100% חינם ❤️',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  Text(
                    widget.forOther ? AppLocalizations.of(context).catHelpForOther : AppLocalizations.of(context).catNeedHelp,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Category picker ──────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text(AppLocalizations.of(context).catCategory,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedCategory,
                hint: Text(AppLocalizations.of(context).catChooseCategory, textAlign: TextAlign.right),
                items: _mainCategories
                    .map((c) => DropdownMenuItem(
                          value: c['name'] as String,
                          child: Text(c['name'] as String? ?? '',
                              textAlign: TextAlign.right),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),
              const SizedBox(height: 16),

              // ── Description ──────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text(AppLocalizations.of(context).catRequestDescription,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).catDescHint,
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),
              const SizedBox(height: 16),

              // ── Location ─────────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text(AppLocalizations.of(context).catLocation,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _locationCtrl,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).catLocationHint,
                  prefixIcon: const Icon(Icons.location_on_outlined,
                      color: Color(0xFF10B981)),
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),
              const SizedBox(height: 16),

              // ── Contact phone ─────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text(AppLocalizations.of(context).catContactPhone,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: '05X-XXXXXXX',
                  prefixIcon: const Icon(Icons.phone_outlined,
                      color: Color(0xFF10B981)),
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),

              // ── For-other extras ──────────────────────────────────────────
              if (widget.forOther) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(AppLocalizations.of(context).catBeneficiaryName,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700])),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _beneficiaryCtrl,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).catBeneficiaryHint,
                    filled: true,
                    fillColor: const Color(0xFFF5F6FA),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFF10B981))),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _iAmContact,
                  onChanged: (v) => setState(() => _iAmContact = v),
                  activeColor: const Color(0xFF10B981),
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppLocalizations.of(context).catIAmContact,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      AppLocalizations.of(context).catIAmCoordinator,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],

              const SizedBox(height: 24),

              // ── Submit button ─────────────────────────────────────────────
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  backgroundColor: const Color(0xFF10B981),
                  disabledBackgroundColor:
                      const Color(0xFF10B981).withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(
                        AppLocalizations.of(context).catSendRequest,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Compact stat chip used by the search card — mirrors the profile's
// specialist-card stat rows (expert_profile_screen._buildSpecialistCard).
// Icon + bold number, no label (the icon implies the meaning). The chip
// hides itself in the parent if its value is 0 so non-volunteers / new
// providers don't carry "0 0 0" visual noise.
// ═══════════════════════════════════════════════════════════════════════════
class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Motorcycle CSM (§55): "מצא גרר דחוף" urgent-search pill.
// ═══════════════════════════════════════════════════════════════════════════
// Mirrors the home tab's [_GlassUrgentSearchButton] (home_screen.dart:1974)
// in *intent* — pulsing halos + pill + "urgent" feel — but adapts the visual
// for the white scaffold of [CategoryResultsScreen]: red gradient pill with
// red halos instead of the home button's glassmorphic white.
//
// Sits to the trailing side of the existing "מפה" pill (see
// [_buildBottomFab]). Only mounted when the customer is browsing
// motorcycle towing — gated by isMotorcycleTowingCategory().
//
// onTap is currently a placeholder snackbar — the destination screen ships
// in a follow-up.
class _UrgentTowSearchPillFab extends StatefulWidget {
  const _UrgentTowSearchPillFab({
    required this.label,
    required this.onTap,
    this.icon = Icons.bolt_rounded,
  });

  final String label;
  final VoidCallback onTap;

  /// Leading icon. Defaults to a bolt for the motorcycle towing case;
  /// the babysitter emergency variant overrides with a child-care icon.
  final IconData icon;

  @override
  State<_UrgentTowSearchPillFab> createState() =>
      _UrgentTowSearchPillFabState();
}

class _UrgentTowSearchPillFabState extends State<_UrgentTowSearchPillFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _haloCtrl;

  @override
  void initState() {
    super.initState();
    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _haloCtrl.dispose();
    super.dispose();
  }

  /// One pulsing halo. Two of these are stacked behind the pill, staggered by
  /// half a cycle (phaseOffset 0 + 0.5) so the breathing rhythm never pauses.
  Widget _halo(double phaseOffset) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _haloCtrl,
          builder: (_, __) {
            final t = (_haloCtrl.value + phaseOffset) % 1.0;
            final eased = Curves.easeInOut.transform(t);
            final scale = 1.0 + 0.45 * eased;     // 1.0 → 1.45
            final opacity = 0.55 * (1.0 - eased); // 0.55 → 0
            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _halo(0.0),
        _halo(0.5),
        Material(
          color: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: widget.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// v15.x: AppBar pill — lives in the AppBar actions (top-left in RTL, next to
// the centred sub-category title). Per user request (2026-05-16) restyled to
// match the home-tab "חיפוש דחוף" glass pill, ADAPTED for a white AppBar:
// the home button's translucent-white glass is invisible on white, so this
// uses a light-indigo translucent fill + indigo border + dark-indigo icon &
// text. Compact padding so it fits the AppBar height. RTL-safe.
//
// Dual-purpose: in list mode it shows the "מפה" icon (opens the map); in map
// mode the SAME slot swaps to a "רשימה" / view-list icon (back to the list)
// — the two states trade places in-position so they feel like one toggle.
class _OpenMapPillFab extends StatelessWidget {
  const _OpenMapPillFab({
    required this.label,
    required this.onTap,
    this.icon = Icons.map_rounded,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  static const Color _indigo = Color(0xFF6366F1);
  static const Color _indigoDark = Color(0xFF1E1B4B);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _indigo.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _indigo.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _indigoDark, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _indigoDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// v12.9.0: Map overlay widgets (top bar + fading gradient)
// ═══════════════════════════════════════════════════════════════════════════
// Purely presentational — state lives on _CategoryResultsScreenState and is
// passed in via callbacks. Kept as private widgets in this file so they can
// share the _showMap context without a cross-file import.

class _MapTopGradient extends StatelessWidget {
  const _MapTopGradient();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.95),
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

class _MapTopBar extends StatefulWidget {
  final String initialQuery;
  final VoidCallback onBack;
  final ValueChanged<String> onQueryChanged;

  const _MapTopBar({
    required this.initialQuery,
    required this.onBack,
    required this.onQueryChanged,
  });

  @override
  State<_MapTopBar> createState() => _MapTopBarState();
}

class _MapTopBarState extends State<_MapTopBar> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 0),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          _RoundIconButton(
            icon: Icons.arrow_forward_rounded,
            onTap: widget.onBack,
            tooltip: AppLocalizations.of(context).catBack,
          ),
          const SizedBox(width: 10),
          // The list-view toggle moved to the AppBar actions slot
          // (2026-05-16) so it occupies the exact spot the "מפה" pill
          // held — they swap in place. See _buildMapAppBarAction().
          Expanded(child: _buildSearchPill()),
        ],
      ),
    );
  }

  Widget _buildSearchPill() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: MapShadows.chip,
      ),
      padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 20, color: MapPalette.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              textDirection: TextDirection.rtl,
              onChanged: widget.onQueryChanged,
              style: const TextStyle(fontSize: 13.5, color: MapPalette.textPrimary),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).catSearchInCategory,
                hintStyle: const TextStyle(
                    fontSize: 13.5, color: MapPalette.textTertiary),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _ctrl.clear();
                widget.onQueryChanged('');
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.close_rounded,
                    size: 18, color: MapPalette.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42, height: 42,
          child: Icon(icon, size: 20, color: MapPalette.textPrimary),
        ),
      ),
    );
    final boxed = DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: MapShadows.floatingControl,
      ),
      child: btn,
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: boxed) : boxed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// v12.9.0: Filter chips + provider count badge
// ═══════════════════════════════════════════════════════════════════════════

class _MapFilterChips extends StatelessWidget {
  final double? maxDistanceKm;
  final double  minRating;
  final bool    under100;
  final bool    onlineOnly;
  final VoidCallback onPickDistance;
  final VoidCallback onPickRating;
  final VoidCallback onToggleUnder100;
  final VoidCallback onToggleOnline;
  final VoidCallback onInstantBook;

  const _MapFilterChips({
    required this.maxDistanceKm,
    required this.minRating,
    required this.under100,
    required this.onlineOnly,
    required this.onPickDistance,
    required this.onPickRating,
    required this.onToggleUnder100,
    required this.onToggleOnline,
    required this.onInstantBook,
  });

  @override
  Widget build(BuildContext context) {
    final distanceLabel = maxDistanceKm == null
        ? AppLocalizations.of(context).catFilterDistance
        : AppLocalizations.of(context).catUpToKm(maxDistanceKm!.toInt());
    final ratingLabel = minRating == 0
        ? AppLocalizations.of(context).catFilterRating
        : '${minRating.toStringAsFixed(minRating == 5 ? 0 : 1)}+ ⭐';

    return SizedBox(
      height: 38,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _FilterChip(
              icon: Icons.place_rounded,
              label: distanceLabel,
              active: maxDistanceKm != null,
              onTap: onPickDistance,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              icon: Icons.star_rounded,
              label: ratingLabel,
              active: minRating > 0,
              onTap: onPickRating,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              icon: Icons.attach_money_rounded,
              label: AppLocalizations.of(context).catUnder100,
              active: under100,
              onTap: onToggleUnder100,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              icon: Icons.circle,
              iconColor: onlineOnly ? Colors.white : MapPalette.online,
              iconSize: 10,
              label: AppLocalizations.of(context).catAvailableNow,
              active: onlineOnly,
              onTap: onToggleOnline,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              icon: Icons.bolt_rounded,
              label: AppLocalizations.of(context).catInstantBook,
              active: false,
              disabledLookSoft: true,
              onTap: onInstantBook,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final Color?   iconColor;
  final double?  iconSize;
  final String   label;
  final bool     active;
  final bool     disabledLookSoft;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    this.iconColor,
    this.iconSize,
    required this.label,
    required this.active,
    this.disabledLookSoft = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? const Color(0xFF1A1D26)
        : disabledLookSoft
            ? const Color(0xFFF3F4F6)
            : Colors.white;
    final fg = active
        ? Colors.white
        : disabledLookSoft
            ? MapPalette.textTertiary
            : MapPalette.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
            border: active || disabledLookSoft
                ? null
                : Border.all(color: MapPalette.border, width: 1),
            boxShadow: active ? null : MapShadows.chip,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: iconSize ?? 16,
                  color: iconColor ?? fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// v12.9.0 (PR-5): Provider card shown inside the map carousel.
// ═══════════════════════════════════════════════════════════════════════════

class _MapProviderCard extends StatefulWidget {
  final Map<String, dynamic> expert;
  final bool                 active;
  final Position?            myPosition;
  final VoidCallback         onTapCard;
  final VoidCallback         onMessage;
  final VoidCallback         onBookNow;

  const _MapProviderCard({
    required this.expert,
    required this.active,
    required this.myPosition,
    required this.onTapCard,
    required this.onMessage,
    required this.onBookNow,
  });

  @override
  State<_MapProviderCard> createState() => _MapProviderCardState();
}

class _MapProviderCardState extends State<_MapProviderCard>
    with SingleTickerProviderStateMixin {
  bool _isFavorite = false;
  late final AnimationController _heartCtrl;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    super.dispose();
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    _heartCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final expert       = widget.expert;
    final active       = widget.active;
    final myPosition   = widget.myPosition;
    final name         = (expert['name'] as String?) ?? '';
    final aboutMe      = (expert['aboutMe'] as String?) ?? '';
    final rating       = (expert['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewsCount = (expert['reviewsCount'] as num?)?.toInt() ?? 0;
    final city         = (expert['city'] as String?) ??
        (expert['address'] as String?) ?? '';
    final profileImage = expert['profileImage'] as String?;
    final gallery      = (expert['gallery'] as List?)
        ?.whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList() ?? const <String>[];
    final isOnline     = expert['isOnline'] == true;
    final isVerified   = expert['isVerified'] == true;
    final isPromoted   = expert['isPromoted'] == true;
    final pricePerHour = (expert['pricePerHour'] as num?)?.toDouble();
    final quickTags    = (expert['quickTags'] as List?)
        ?.whereType<String>()
        .toList() ?? const <String>[];

    // Distance + ETA in km / minutes (if we have user location + expert coords)
    String? distanceLabel;
    int? etaMinutes;
    final lat = (expert['latitude'] as num?)?.toDouble();
    final lng = (expert['longitude'] as num?)?.toDouble();
    if (myPosition != null && lat != null && lng != null) {
      final km = Geolocator.distanceBetween(
              myPosition.latitude, myPosition.longitude, lat, lng) /
          1000.0;
      distanceLabel = km < 1
          ? AppLocalizations.of(context).catInNeighborhood
          : '${km.toStringAsFixed(km < 10 ? 1 : 0)} ${AppLocalizations.of(context).catFilterKm}';
      // Assume 40 km/h average urban speed.
      etaMinutes = (km / 40.0 * 60.0).round().clamp(1, 999);
    }

    final borderColor = active ? MapPalette.goldActive : MapPalette.gold;
    final borderWidth = active ? 2.5 : 2.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTapCard,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: active ? MapShadows.card : MapShadows.chip,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Gallery strip + overlays ─────────────────────────────
              _buildGallery(profileImage, gallery, isOnline, pricePerHour),
              // ── Body ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeaderRow(name, isVerified, isPromoted,
                        profileImage, aboutMe),
                    const SizedBox(height: 8),
                    _buildMetaRow(rating, reviewsCount),
                    if (etaMinutes != null || city.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildEtaRow(etaMinutes, distanceLabel, city),
                    ],
                    if (quickTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildTags(quickTags),
                    ],
                    const SizedBox(height: 10),
                    const Divider(height: 1, color: MapPalette.border),
                    const SizedBox(height: 8),
                    _buildActionRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildGallery(
    String? profileImage,
    List<String> gallery,
    bool isOnline,
    double? pricePerHour,
  ) {
    // If there's a real gallery, show up to 3 images side-by-side. Otherwise
    // fall back to the profile image as a single wide hero.
    final imgs = gallery.isNotEmpty ? gallery.take(3).toList()
                                    : (profileImage != null && profileImage.isNotEmpty
                                       ? [profileImage] : const <String>[]);

    return Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        // Images row
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: SizedBox(
            height: 120,
            child: imgs.isEmpty
                ? Container(
                    color: MapPalette.primaryLight,
                    alignment: Alignment.center,
                    child: const Icon(Icons.person_rounded,
                        size: 40, color: MapPalette.primary),
                  )
                : Row(
                    children: [
                      for (int i = 0; i < imgs.length; i++) ...[
                        Expanded(child: _buildImage(imgs[i])),
                        if (i < imgs.length - 1) const SizedBox(width: 2),
                      ],
                    ],
                  ),
          ),
        ),
        // Online status pill (top-end in RTL = top-left visually)
        PositionedDirectional(
          top: 10, end: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOnline
                  ? const Color(0xFFDCFCE7)
                  : Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? MapPalette.online
                        : Colors.white.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isOnline ? AppLocalizations.of(context).catAvailableNowUser : AppLocalizations.of(context).catDayOffline,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isOnline
                        ? const Color(0xFF166534)
                        : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Price pill (bottom-start in RTL = bottom-right visually)
        if (pricePerHour != null && pricePerHour > 0)
          PositionedDirectional(
            bottom: 10, start: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D26),
                borderRadius: BorderRadius.circular(14),
                boxShadow: MapShadows.chip,
              ),
              child: Text(
                '₪${pricePerHour.toStringAsFixed(0)}/שעה',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        // v12.11.0: Heart (favorite) button — top-start = visually top-right in RTL
        PositionedDirectional(
          top: 10, start: 10,
          child: _buildHeartButton(),
        ),
        // v12.11.0: Photo count badge — bottom-end = visually bottom-left in RTL
        if (gallery.isNotEmpty)
          PositionedDirectional(
            bottom: 10, end: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '📸 ${gallery.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeartButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _toggleFavorite,
        child: AnimatedBuilder(
          animation: _heartCtrl,
          builder: (_, __) {
            // Bounce 1 → 1.3 → 1 over the controller cycle.
            final t = _heartCtrl.value;
            final scale = 1.0 + (t < 0.5 ? t * 0.6 : (1 - t) * 0.6);
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  boxShadow: MapShadows.chip,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  size: 15,
                  color: _isFavorite
                      ? MapPalette.red
                      : MapPalette.textSecondary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildImage(String url) {
    final img = safeImageProvider(url);
    if (img == null) {
      return Container(color: MapPalette.primaryLight);
    }
    return Image(image: img, fit: BoxFit.cover);
  }

  Widget _buildHeaderRow(
    String name,
    bool isVerified,
    bool isPromoted,
    String? profileImage,
    String aboutMe,
  ) {
    return Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: MapPalette.primaryLight, width: 2),
          ),
          child: ClipOval(
            child: safeImageProvider(profileImage) != null
                ? Image(image: safeImageProvider(profileImage)!,
                        fit: BoxFit.cover)
                : Container(
                    color: MapPalette.primaryLight,
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(
                          color: MapPalette.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        // Name + description
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: MapPalette.textPrimary,
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded,
                        size: 15, color: MapPalette.primary),
                  ],
                  if (isPromoted) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppLocalizations.of(context).catRecommended,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (aboutMe.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  aboutMe,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MapPalette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(double rating, int reviewsCount) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFBBF24)),
        const SizedBox(width: 2),
        Text(
          rating > 0 ? rating.toStringAsFixed(1) : '—',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: MapPalette.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '($reviewsCount)',
          style: const TextStyle(
            fontSize: 12,
            color: MapPalette.textTertiary,
          ),
        ),
      ],
    );
  }

  // v12.11.0: travel row — "🕐 12 דק׳ • קרית מלאכי"
  Widget _buildEtaRow(int? etaMinutes, String? distanceLabel, String city) {
    final parts = <String>[];
    if (etaMinutes != null) parts.add('$etaMinutes דק׳');
    if (distanceLabel != null) parts.add(distanceLabel);
    if (city.isNotEmpty) parts.add(city);
    final line = parts.join(' • ');
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        const Icon(Icons.schedule_rounded, size: 13, color: MapPalette.primary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            line,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: MapPalette.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTags(List<String> tags) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in tags.take(3)) _buildTagChip(t),
      ],
    );
  }

  // v12.11.0: Firestore stores tag KEYS (english snake_case). Map them to
  // Hebrew labels + semantic colors. Unknown keys fall back to a grey chip
  // but still render (so we don't silently drop data).
  static const Map<String, ({String label, Color bg, Color fg})> _kTagMap = {
    'certified':      (label: '🎓 מוסמך/ת',        bg: MapPalette.tagGreenBg, fg: MapPalette.tagGreenFg),
    'home_service':   (label: '🏠 מגיע/ה עד הבית', bg: MapPalette.tagBlueBg,  fg: MapPalette.tagBlueFg),
    'first_discount': (label: '🎁 שיעור ראשון ב-50%', bg: MapPalette.tagRoseBg, fg: MapPalette.tagRoseFg),
    'insured':        (label: '🛡️ מבוטח/ת',         bg: MapPalette.tagGreenBg, fg: MapPalette.tagGreenFg),
    'instant_book':   (label: '⚡ הזמנה מיידית',     bg: Color(0xFFFEF3C7),     fg: Color(0xFFB45309)),
    'fast_response':  (label: '⚡ תגובה מהירה',      bg: Color(0xFFFEF3C7),     fg: Color(0xFFB45309)),
    'reliable':       (label: '✅ אמין/ה',           bg: MapPalette.tagGreenBg, fg: MapPalette.tagGreenFg),
    'experienced':    (label: '⭐ מנוסה',            bg: MapPalette.tagBlueBg,  fg: MapPalette.tagBlueFg),
  };

  Widget _buildTagChip(String tag) {
    final entry = _kTagMap[tag];
    final Color bg;
    final Color fg;
    final String label;

    if (entry != null) {
      bg = entry.bg;
      fg = entry.fg;
      label = entry.label;
    } else {
      // Legacy Hebrew-text fallback.
      final lowered = tag.toLowerCase();
      if (lowered.contains('home') || tag.contains('הביתה') ||
          tag.contains('הבית')) {
        bg = MapPalette.tagBlueBg; fg = MapPalette.tagBlueFg;
      } else if (lowered.contains('cert') || tag.contains('מוסמך')) {
        bg = MapPalette.tagGreenBg; fg = MapPalette.tagGreenFg;
      } else if (lowered.contains('50') || tag.contains('הנחה')) {
        bg = MapPalette.tagRoseBg; fg = MapPalette.tagRoseFg;
      } else {
        bg = MapPalette.tagGrayBg; fg = MapPalette.tagGrayFg;
      }
      label = tag;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        // When free? (left in RTL = end of row visually)
        TextButton.icon(
          onPressed: widget.onTapCard,
          style: TextButton.styleFrom(
            foregroundColor: MapPalette.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 36),
          ),
          icon: const Icon(Icons.event_available_rounded, size: 16),
          label: Text(
            AppLocalizations.of(context).catWhenAvailable,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const Spacer(),
        // Message button
        Material(
          color: Colors.white,
          shape: const CircleBorder(side: BorderSide(color: MapPalette.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onMessage,
            child: const SizedBox(
              width: 36, height: 36,
              child: Icon(Icons.chat_bubble_outline_rounded,
                  size: 18, color: MapPalette.textPrimary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Book now CTA
        Material(
          color: MapPalette.primary,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: widget.onBookNow,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(
                AppLocalizations.of(context).catBookNow,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderCountBadge extends StatelessWidget {
  final int count;
  final String categoryName;
  final bool anyFilterActive;

  const _ProviderCountBadge({
    required this.count,
    required this.categoryName,
    required this.anyFilterActive,
  });

  @override
  Widget build(BuildContext context) {
    // v12.11.0: show whenever there are results — hides only when empty.
    final visible = count > 0;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -0.6),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicWidth(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D26),
                borderRadius: BorderRadius.circular(24),
                boxShadow: MapShadows.chip,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: MapPalette.online,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$count $categoryName באזור שלך',
                      textDirection: TextDirection.rtl,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// Availability sheet — D.3 (§82, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════
// Extracted from `_showAvailabilitySheet` + `_timesForDay` inside the State
// class. Top-level functions reachable via the `part of` directive.

List<String> _timesForDay(Map<String, dynamic>? workingHours, DateTime day) {
  const fallback = ['09:00', '11:00', '14:00', '16:00'];
  if (workingHours == null || workingHours.isEmpty) return fallback;
  // Schema: 0=Sunday..6=Saturday. DateTime.weekday: 1=Mon..7=Sun.
  final dayIndex = day.weekday == 7 ? 0 : day.weekday;
  final entry = workingHours['$dayIndex'] as Map<String, dynamic>?;
  if (entry == null) return [];
  final fromHour =
      int.tryParse((entry['from'] ?? '09:00').toString().split(':').first) ??
          9;
  final toHour =
      int.tryParse((entry['to'] ?? '17:00').toString().split(':').first) ??
          17;
  final slots = <String>[];
  for (int h = fromHour; h < toHour; h += 2) {
    slots.add('${h.toString().padLeft(2, '0')}:00');
  }
  return slots.isEmpty ? fallback : slots;
}

void _showAvailabilitySheet(
    BuildContext context, Map<String, dynamic> data, String expertId) {
  final l10n = AppLocalizations.of(context);

  // Parse blocked dates (ISO-8601: 'YYYY-MM-DD')
  final blocked = ((data['unavailableDates'] as List?) ?? [])
      .map((d) => d.toString().substring(0, 10))
      .toSet();

  // Next 7 days, keep first 3 available
  final today = DateTime.now();
  final slots = <DateTime>[];
  for (int i = 1; i <= 14 && slots.length < 3; i++) {
    final day = today.add(Duration(days: i));
    final key = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    if (!blocked.contains(key)) slots.add(day);
  }

  final rawHours = data['workingHours'] as Map<String, dynamic>?;
  final dayLabels = [
    l10n.editDaySunday,
    l10n.editDayMonday,
    l10n.editDayTuesday,
    l10n.editDayWednesday,
    l10n.editDayThursday,
    l10n.editDayFriday,
    l10n.editDaySaturday,
  ];
  final monthLabels = List<String>.generate(12, (i) {
    final d = DateTime(2024, i + 1, 1);
    return DateFormat.MMM(l10n.localeName).format(d);
  });

  final expertDefaultName = l10n.catResultsExpertDefault;
  final availableSlotsTitle = l10n.catResultsAvailableSlots;
  final noAvailabilityMsg = l10n.catResultsNoAvailability;
  final fullBookingLabel = l10n.catResultsFullBooking;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                data['name'] ?? expertDefaultName,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              Text(
                availableSlotsTitle,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (slots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(noAvailabilityMsg,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 14)),
              ),
            )
          else
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: slots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final day = slots[i];
                  final dayName = dayLabels[day.weekday % 7];
                  final dateStr =
                      '${day.day} ${monthLabels[day.month - 1]}';
                  return Container(
                    width: 130,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kPurpleSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _kPurple.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(dayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _kPurple,
                                fontSize: 14)),
                        Text(dateStr,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.end,
                          children: _timesForDay(rawHours, day)
                              .map((t) => GestureDetector(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ExpertProfileScreen(
                                            expertId: expertId,
                                            expertName: data['name'] ??
                                                expertDefaultName,
                                            listingId: data['listingId']
                                                as String?,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: _kPurple
                                                .withValues(alpha: 0.4)),
                                      ),
                                      child: Text(t,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: _kPurple,
                                              fontWeight:
                                                  FontWeight.w600)),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExpertProfileScreen(
                      expertId: expertId,
                      expertName: data['name'] ?? expertDefaultName,
                      listingId: data['listingId'] as String?,
                    ),
                  ),
                );
              },
              child: Text(fullBookingLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI Teacher (Alex) card — D.1 (§82, 2026-05-14)
// ═══════════════════════════════════════════════════════════════════════════════
// Extracted from `_buildAiTeacherCard`. Stateless: takes the synthetic
// `data` Map + Navigator.push to AlexProfileScreen. Constants (_kPurple,
// _kPurpleSoft, _kGold) reached via the `part of` directive.

class _AiTeacherCard extends StatelessWidget {
  const _AiTeacherCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Alex';
    final bio = data['aboutMe'] as String? ?? '';
    final price = (data['pricePerHour'] as num?)?.toInt() ?? 30;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AlexProfileScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _kPurple.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.12),
              blurRadius: 20,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: 185, maxWidth: 130),
                child: SizedBox(
                  width: 130,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    child: Container(
                      color: _kPurpleSoft,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF6366F1),
                                    Color(0xFF8B5CF6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kPurple.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text('A',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle,
                                      color: Color(0xFF22C55E), size: 7),
                                  SizedBox(width: 4),
                                  Text('Online 24/7',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.auto_awesome,
                                        color: Colors.white, size: 11),
                                    SizedBox(width: 4),
                                    Text('AI Teacher',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontFamily: 'Heebo'),
                                  children: [
                                    TextSpan(
                                      text: '₪$price',
                                      style: const TextStyle(
                                          color: _kPurple,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18),
                                    ),
                                    const TextSpan(
                                      text: '/לשעה',
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                          fontWeight: FontWeight.normal),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(Icons.verified,
                                  color: Color(0xFF1877F2), size: 15),
                              const SizedBox(width: 4),
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text('AI English Teacher',
                              style: TextStyle(
                                  color: _kPurple,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          if (bio.isNotEmpty)
                            Text(bio,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12)),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _kPurpleSoft,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color:
                                        _kPurple.withValues(alpha: 0.2)),
                              ),
                              child: const Text('Intermediate (B1-B2)',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: _kPurple,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: _kGold, size: 14),
                              const SizedBox(width: 2),
                              const Text('5.0',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                              const SizedBox(width: 3),
                              Text('(128)',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 38,
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPurple,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.play_circle_filled_rounded,
                              size: 18),
                          label: Text(
                              AppLocalizations.of(context).catStartLesson,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AlexProfileScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Expert card subsystem — H.1 (§86, 2026-05-14)
// ═════════════════════════════════════════════════════════════════════════════
// Top-level functions in this library (via `part of`). State fields are
// passed explicitly:
//   • [serviceSchema] for SearchCardPricePill (§62 transparency badges)
//   • [currentPosition] for the per-card distance row (Haversine)
//
// Call site uses `_libBuildExpertCard(context, data, _serviceSchema,
// _currentPosition)`. State class keeps NO body for these methods.

/// Pure check — provider has an active story posted in the last 24h.
bool _libIsStoryActive(Map<String, dynamic> data) {
  if (data['hasActiveStory'] != true) return false;
  final ts = (data['storyTimestamp'] as Timestamp?)?.toDate();
  if (ts == null) return false;
  return DateTime.now().difference(ts).inHours < 24;
}

/// Card image column (~38% width) — gradient avatar + 4 trust badges +
/// optional story-tap.
Widget _libBuildActionImage(
    BuildContext context, Map<String, dynamic> data, bool isOnline) {
  final l10n = AppLocalizations.of(context);
  final hasStory = _libIsStoryActive(data);
  final profileImg = data['profileImage'] as String? ?? '';
  final hasImg = profileImg.isNotEmpty;

  final orderCount = (data['orderCount'] as num?)?.toInt() ?? 0;
  final respTime = (data['responseTimeMinutes'] as num?)?.toInt() ?? 0;
  final rating = (data['rating'] as num?)?.toDouble() ?? 0;
  final reviewsCount = (data['reviewsCount'] as num?)?.toInt() ?? 0;

  final badges = <String>[];
  if (orderCount >= 5) badges.add(l10n.catResultsOrderCount(orderCount));
  if (respTime > 0 && respTime <= 10) {
    badges.add(l10n.catResultsResponseTime(respTime));
  }
  if (rating >= 4.8 && reviewsCount >= 3) badges.add(l10n.catResultsTopRated);

  return ClipRRect(
    borderRadius: const BorderRadius.only(
      topRight: Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
    child: SizedBox(
      width: 130,
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: _kPurpleSoft)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final expertId = data['uid'] as String? ?? '';
              if (data['hasActiveStory'] != true || expertId.isEmpty) return;
              final doc = await FirebaseFirestore.instance
                  .collection('stories')
                  .doc(expertId)
                  .get();
              if (!context.mounted || !doc.exists) return;
              openStoryViewer(context, expertId, doc.data()!);
            },
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: hasStory
                            ? null
                            : Border.all(
                                color: _kPurple.withValues(alpha: 0.18),
                                width: 2),
                        gradient: hasStory
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFFEC4899),
                                  Color(0xFFF59E0B),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                      ),
                      padding:
                          hasStory ? const EdgeInsets.all(3) : EdgeInsets.zero,
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: const Color(0xFFEEEBFF),
                        backgroundImage:
                            hasImg ? safeImageProvider(profileImg) : null,
                        child: safeImageProvider(profileImg) == null
                            ? Icon(Icons.person,
                                size: 40,
                                color: _kPurple.withValues(alpha: 0.5))
                            : null,
                      ),
                    ),
                    if (shouldShowHeartFor(
                      viewerUid: FirebaseAuth.instance.currentUser?.uid,
                      ownerData: data,
                    ))
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.favorite_rounded,
                              color: Color(0xFFD4AF37), size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 4,
            right: 4,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 3,
              children: [
                if (isOnline)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle,
                            color: Color(0xFF22C55E), size: 7),
                        const SizedBox(width: 3),
                        Text(l10n.onlineStatus,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle,
                            color: Color(0xFF9CA3AF), size: 7),
                        const SizedBox(width: 3),
                        Text(l10n.catDayOffline,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                if (reviewsCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBF24), size: 10),
                        const SizedBox(width: 2),
                        Text(rating.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                if (hasStory)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 9),
                        SizedBox(width: 2),
                        Text('STORY',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Quick-tags row — max 2 chips, unknown keys silently ignored.
Widget _libBuildQuickTagsRow(List<String> tagKeys) {
  final resolved = tagKeys
      .map(quickTagByKey)
      .whereType<Map<String, String>>()
      .take(2)
      .toList();
  if (resolved.isEmpty) return const SizedBox.shrink();

  return Wrap(
    spacing: 5,
    runSpacing: 4,
    alignment: WrapAlignment.end,
    children: resolved
        .map((t) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _kPurpleSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kPurple.withValues(alpha: 0.18)),
              ),
              child: Text(
                '${t['emoji']} ${t['label']}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _kPurple.withValues(alpha: 0.85),
                ),
              ),
            ))
        .toList(),
  );
}

/// Distance chip — Haversine from [currentPosition] to provider coords.
Widget _libBuildCardDistanceRow(
    Map<String, dynamic> data, Position? currentPosition) {
  final lat = (data['latitude'] as num?)?.toDouble();
  final lng = (data['longitude'] as num?)?.toDouble();
  final uid = (data['uid'] as String?) ?? '?';
  // ignore: avoid_print
  print('[ListCard/distance] uid=$uid '
      'my=${currentPosition == null ? "null" : "(${currentPosition.latitude}, ${currentPosition.longitude})"} '
      'provider=($lat, $lng) raw latitude=${data['latitude']} longitude=${data['longitude']}');
  String label;
  Color color;
  if (currentPosition == null) {
    label = 'מחשב מרחק...';
    color = Colors.grey.shade400;
  } else if (lat == null || lng == null) {
    label = 'מרחק לא ידוע';
    color = Colors.grey.shade400;
  } else {
    try {
      final meters = Geolocator.distanceBetween(
          currentPosition.latitude, currentPosition.longitude, lat, lng);
      // ignore: avoid_print
      print('[ListCard/distance] uid=$uid distance = ${meters.toStringAsFixed(0)} m');
      label = meters < 1000
          ? 'בשכונתך'
          : '${(meters / 1000).toStringAsFixed(1)} ק"מ';
      color = const Color(0xFF10B981);
    } catch (e) {
      // ignore: avoid_print
      print('[ListCard/distance] uid=$uid distanceBetween threw: $e');
      label = 'מרחק לא ידוע';
      color = Colors.grey.shade400;
    }
  }
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Icon(Icons.location_on_rounded, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label,
          style: TextStyle(
              fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
    ],
  );
}

/// Details panel (~62% width) — price + name + bio + tags + stats +
/// distance + 2-CTA footer.
Widget _libBuildExpertDetails(
  BuildContext context,
  Map<String, dynamic> data,
  bool isVerified,
  bool isPromoted,
  bool isOnline,
  String expertId,
  ServiceSchema serviceSchema,
  Position? currentPosition,
) {
  final l10n = AppLocalizations.of(context);
  final isPro = data['isAnySkillPro'] == true;
  final name = data['name'] as String? ?? l10n.catResultsExpertDefault;
  final rating = (data['rating'] as num?)?.toDouble() ?? 5.0;
  final reviewsCount = (data['reviewsCount'] as num?)?.toInt() ?? 0;
  final bio = data['aboutMe'] as String? ?? '';
  final tagKeys = ((data['quickTags'] as List?) ?? []).cast<String>();
  final jobsCount = (data['completedJobsCount'] as num? ??
          data['orderCount'] as num? ??
          0)
      .toInt();
  final volunteersCount = (data['volunteerTaskCount'] as num? ?? 0).toInt();

  return Padding(
    padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if ((data['xp'] as num? ?? 0) > 0)
                  LevelBadge(xp: (data['xp'] as num).toInt(), size: 16),
                SearchCardPricePill(
                  userData: data,
                  schema: serviceSchema,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isPromoted)
                  Container(
                    margin: const EdgeInsetsDirectional.only(start: 5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            color: Colors.amber[700], size: 10),
                        const SizedBox(width: 3),
                        Text(l10n.catResultsRecommended,
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.amber[800],
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                if (isVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified,
                      color: Color(0xFF1877F2), size: 15),
                ],
                if (shouldShowHeartFor(
                  viewerUid: FirebaseAuth.instance.currentUser?.uid,
                  ownerData: data,
                )) ...[
                  const SizedBox(width: 4),
                  VolunteerService.hasActiveVolunteerBadge(data)
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFD4AF37),
                                Color(0xFFB8860B),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.favorite_rounded,
                                  color: Colors.white, size: 11),
                              const SizedBox(width: 2),
                              Text(
                                _CategoryResultsScreenState
                                    ._communityBadgeLabel(data, context),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const Icon(Icons.favorite,
                          color: Color(0xFFD4AF37), size: 15),
                ],
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (isPro) ...[
              const SizedBox(height: 5),
              const Align(
                alignment: Alignment.centerRight,
                child: ProBadge(),
              ),
            ],
            const SizedBox(height: 4),
            if (bio.isNotEmpty)
              Text(
                bio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            if (bio.isNotEmpty) const SizedBox(height: 4),
            _libBuildQuickTagsRow(tagKeys),
            if (tagKeys.isNotEmpty) const SizedBox(height: 4),
            if ((data['categoryTags'] as List?)?.isNotEmpty == true) ...[
              ProviderCategoryTagsDisplay(
                category: (data['serviceType'] as String? ?? '').trim(),
                tagIds: ((data['categoryTags'] as List?) ?? const [])
                    .cast<String>(),
                maxVisible: 3,
              ),
              const SizedBox(height: 4),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (jobsCount > 0) ...[
                  _MiniStatChip(
                    icon: Icons.shield_outlined,
                    value: '$jobsCount',
                    color: _kPurple,
                  ),
                  const SizedBox(width: 8),
                ],
                _MiniStatChip(
                  icon: Icons.star_rounded,
                  value: rating.toStringAsFixed(1),
                  color: _kGold,
                ),
                if (reviewsCount > 0) ...[
                  const SizedBox(width: 8),
                  _MiniStatChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    value: '$reviewsCount',
                    color: Colors.teal,
                  ),
                ],
                if (volunteersCount > 0) ...[
                  const SizedBox(width: 8),
                  _MiniStatChip(
                    icon: Icons.favorite_rounded,
                    value: '$volunteersCount',
                    color: const Color(0xFFD4AF37),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            _libBuildCardDistanceRow(data, currentPosition),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  side: BorderSide(color: _kPurple.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  foregroundColor: _kPurple,
                ),
                icon: const Icon(Icons.calendar_today_rounded, size: 13),
                label: Text(l10n.catResultsWhenFree,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: () =>
                    _showAvailabilitySheet(context, data, expertId),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExpertProfileScreen(
                      expertId: expertId,
                      expertName: name,
                      listingId: data['listingId'] as String?,
                    ),
                  ),
                ),
                child: Text(l10n.bookNow,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Full expert card — left image column + right details. Tap anywhere
/// (except buttons) opens ExpertProfileScreen.
Widget _libBuildExpertCard(
  BuildContext context,
  Map<String, dynamic> data,
  ServiceSchema serviceSchema,
  Position? currentPosition,
) {
  final l10n = AppLocalizations.of(context);
  final isVerified = data['isVerified'] as bool? ?? false;
  final isOnline = data['isOnline'] as bool? ?? false;
  final isPromoted = data['isPromoted'] as bool? ?? false;
  final isAiTeacher = data['isAiTeacher'] == true;
  final expertId = data['uid'] as String? ?? '';
  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final isSelf = expertId == currentUid;

  if (isAiTeacher) return _AiTeacherCard(data: data);

  final expertName = data['name'] as String? ?? l10n.catResultsExpertDefault;
  final rating = (data['rating'] as num?)?.toStringAsFixed(1) ?? '0.0';
  final priceHourly = (data['pricePerHour'] as num?)?.toInt() ?? 0;
  return Semantics(
    button: true,
    label: 'Expert: $expertName, rating $rating, ${String.fromCharCode(0x20AA)}$priceHourly per hour',
    hint: 'Tap to view full profile',
    child: GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExpertProfileScreen(
            expertId: expertId,
            expertName: data['name'] ?? l10n.catResultsExpertDefault,
            listingId: data['listingId'] as String?,
          ),
        ),
      ),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isPromoted
                  ? Border.all(color: Colors.amber.shade300, width: 1.5)
                  : Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: isPromoted
                      ? Colors.amber.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.07),
                  blurRadius: isPromoted ? 20 : 12,
                  spreadRadius: isPromoted ? 1 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                        minHeight: 185, maxWidth: 130),
                    child: SizedBox(
                      width: 130,
                      child: _libBuildActionImage(context, data, isOnline),
                    ),
                  ),
                  Expanded(
                    child: _libBuildExpertDetails(
                      context,
                      data,
                      isVerified,
                      isPromoted,
                      isOnline,
                      expertId,
                      serviceSchema,
                      currentPosition,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isSelf)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(l10n.catYourProfile,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 24,
            right: 12,
            child: FavoriteButton(providerId: expertId),
          ),
        ],
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Map view subsystem — H.2 (§86, 2026-05-14)
// ═════════════════════════════════════════════════════════════════════════════
// All four functions take `_CategoryResultsScreenState state` as the first
// param. `part of` grants library-private access so `state._mapFilteredExperts()`,
// `state._currentPosition`, etc. resolve normally without exposing private API.

Widget _libBuildMapOverlayHeader(_CategoryResultsScreenState state) {
  final context = state.context;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _MapTopBar(
        initialQuery: state._searchQuery,
        onBack: () => Navigator.of(context).maybePop(),
        // ignore: invalid_use_of_protected_member
        onQueryChanged: (v) => state.setState(() => state._searchQuery = v),
      ),
      const SizedBox(height: 10),
      _MapFilterChips(
        maxDistanceKm: state._maxDistanceKm,
        minRating: state._minRating,
        under100: state._filterUnder100,
        onlineOnly: state._onlineOnly,
        onPickDistance: state._pickMapDistance,
        onPickRating: state._pickMapRating,
        onToggleUnder100: () =>
            // ignore: invalid_use_of_protected_member
            state.setState(() => state._filterUnder100 = !state._filterUnder100),
        onToggleOnline: () =>
            // ignore: invalid_use_of_protected_member
            state.setState(() => state._onlineOnly = !state._onlineOnly),
        onInstantBook: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(AppLocalizations.of(context).catInstantBookingSoon),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.topCenter,
        child: _ProviderCountBadge(
          count: state._mapFilteredCount(),
          categoryName: state.widget.categoryName,
          anyFilterActive: state._mapAnyFilterActive(),
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}

Widget _libBuildMapSideBySideLayout(_CategoryResultsScreenState state) {
  final experts = state._mapFilteredExperts();
  final withCoords = experts.where((e) {
    final lat = (e['latitude'] as num?)?.toDouble();
    final lng = (e['longitude'] as num?)?.toDouble();
    return lat != null && lng != null;
  }).toList();

  return Column(
    children: [
      Container(
        color: Colors.white,
        child: SafeArea(
          bottom: false,
          child: _libBuildMapOverlayHeader(state),
        ),
      ),
      Container(height: 0.5, color: const Color(0x1A000000)),
      Expanded(
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: _libBuildMapView(state),
            ),
            Container(width: 0.5, color: const Color(0x1A000000)),
            Expanded(
              flex: 4,
              child: Container(
                color: const Color(0xFFFAFAF9),
                child: withCoords.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'אין נותני שירות עם מיקום באזור',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        itemCount: withCoords.length,
                        itemBuilder: (context, i) {
                          final e = withCoords[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MapProviderCard(
                              expert: e,
                              active: (e['uid'] as String?) ==
                                  state._mapSelectedUid,
                              myPosition: state._currentPosition,
                              onTapCard: () {
                                final lat =
                                    (e['latitude'] as num?)?.toDouble();
                                final lng =
                                    (e['longitude'] as num?)?.toDouble();
                                // ignore: invalid_use_of_protected_member
                                state.setState(() {
                                  state._mapSelectedUid = e['uid'] as String?;
                                  if (lat != null && lng != null) {
                                    state._mapFocusedLatLng = LatLng(lat, lng);
                                  }
                                });
                              },
                              onMessage: () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        receiverId:
                                            (e['uid'] as String?) ?? '',
                                        receiverName:
                                            (e['name'] as String?) ?? '',
                                      ),
                                    ));
                              },
                              onBookNow: () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ExpertProfileScreen(
                                        expertId:
                                            (e['uid'] as String?) ?? '',
                                        expertName:
                                            (e['name'] as String?) ?? '',
                                        listingId:
                                            e['listingId'] as String?,
                                      ),
                                    ));
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _libBuildMapCarouselSheet(_CategoryResultsScreenState state) {
  final experts = state._mapFilteredExperts();
  final withCoords = experts.where((e) {
    final lat = (e['latitude'] as num?)?.toDouble();
    final lng = (e['longitude'] as num?)?.toDouble();
    return lat != null && lng != null;
  }).toList();

  if (withCoords.isEmpty) return const SizedBox.shrink();

  return DraggableScrollableSheet(
    initialChildSize: 0.38,
    minChildSize: 0.16,
    maxChildSize: 0.85,
    snap: true,
    snapSizes: const [0.16, 0.38, 0.85],
    builder: (context, scrollCtrl) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: MapShadows.card,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                physics: const ClampingScrollPhysics(),
                children: [
                  SizedBox(
                    height: 320,
                    child: PageView.builder(
                      controller: state._mapPageCtrl,
                      itemCount: withCoords.length,
                      onPageChanged: (i) {
                        final e = withCoords[i];
                        final lat = (e['latitude'] as num?)?.toDouble();
                        final lng = (e['longitude'] as num?)?.toDouble();
                        if (lat == null || lng == null) return;
                        // ignore: invalid_use_of_protected_member
                        state.setState(() {
                          state._mapSelectedUid = e['uid'] as String?;
                          state._mapFocusedLatLng = LatLng(lat, lng);
                        });
                      },
                      itemBuilder: (context, i) {
                        final e = withCoords[i];
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(
                              start: 6, end: 6, top: 4, bottom: 10),
                          child: _MapProviderCard(
                            expert: e,
                            active: (e['uid'] as String?) ==
                                state._mapSelectedUid,
                            myPosition: state._currentPosition,
                            onTapCard: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ExpertProfileScreen(
                                  expertId: (e['uid'] as String?) ?? '',
                                  expertName: (e['name'] as String?) ?? '',
                                  listingId: e['listingId'] as String?,
                                ),
                              ));
                            },
                            onMessage: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  receiverId: (e['uid'] as String?) ?? '',
                                  receiverName: (e['name'] as String?) ?? '',
                                ),
                              ));
                            },
                            onBookNow: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ExpertProfileScreen(
                                  expertId: (e['uid'] as String?) ?? '',
                                  expertName: (e['name'] as String?) ?? '',
                                  listingId: e['listingId'] as String?,
                                ),
                              ));
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _libBuildMapView(_CategoryResultsScreenState state) {
  final context = state.context;
  final experts = state._mapFilteredExperts();
  final markers = <MapProvider>[];
  for (final e in experts) {
    final lat = (e['latitude'] as num?)?.toDouble();
    final lng = (e['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) continue;
    markers.add(MapProvider(
      uid: e['uid'] as String? ?? '',
      name: e['name'] as String? ?? '',
      profileImage: e['profileImage'] as String?,
      serviceType: e['serviceType'] as String?,
      rating: (e['rating'] as num?)?.toDouble(),
      reviewsCount: (e['reviewsCount'] as num?)?.toInt(),
      lat: lat,
      lng: lng,
      isOnline: e['isOnline'] == true,
      pricePerHour: (e['pricePerHour'] as num?)?.toDouble(),
    ));
  }

  return ProvidersMapView(
    providers: markers,
    userLocation: state._currentPosition != null
        ? LatLng(state._currentPosition!.latitude,
            state._currentPosition!.longitude)
        : null,
    radiusKm: state._maxDistanceKm ?? 20,
    externalSelectedUid: state._mapSelectedUid,
    focusedLatLng: state._mapFocusedLatLng,
    bottomSafeArea: 320,
    onSearchThisArea: () {
      // ignore: invalid_use_of_protected_member
      state.setState(() {});
    },
    onMarkerTap: (uid) {
      final idx = markers.indexWhere((m) => m.uid == uid);
      if (idx < 0) return;
      // ignore: invalid_use_of_protected_member
      state.setState(() {
        state._mapSelectedUid = uid;
        state._mapFocusedLatLng = markers[idx].latLng;
      });
      if (state._mapPageCtrl.hasClients) {
        state._mapPageCtrl.animateToPage(
          idx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    },
    onProviderTap: (uid) {
      final expert = experts.firstWhere(
        (e) => e['uid'] == uid,
        orElse: () => <String, dynamic>{},
      );
      if (expert.isNotEmpty) {
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExpertProfileScreen(
                expertId: uid,
                expertName: expert['name'] as String? ?? '',
                listingId: expert['listingId'] as String?,
              ),
            ));
      }
    },
    onQuickChat: (uid) {
      final expert = experts.firstWhere(
        (e) => e['uid'] == uid,
        orElse: () => <String, dynamic>{},
      );
      if (expert.isNotEmpty) {
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                receiverId: uid,
                receiverName: expert['name'] as String? ?? '',
              ),
            ));
      }
    },
  );
}
