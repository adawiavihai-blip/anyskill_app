import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/massage_specialties.dart';
import '../../constants/massage_addons_catalog.dart';
import '../../constants/massage_focus_areas.dart';
import '../../models/massage_profile.dart';
import '../../services/massage_booking_service.dart';

const _kDark = Color(0xFF1A1A1A);
const _kDarkSecondary = Color(0xFF2D3142);
const _kCreamBorder = Color(0xFFEAE7DF);
const _kSuccess = Color(0xFF10B981);
const _kAmberLight = Color(0xFFFFF8E7);
const _kAmberBorder = Color(0xFFFBBF24);

class MassageBookingPreferences {
  final String? massageType;
  final String? location;
  final int duration;
  final String pressure;
  final List<String> focusAreas;
  final List<String> selectedAddOns;
  final String? musicPreference;
  final String? conversationStyle;
  final String additionalNotes;

  const MassageBookingPreferences({
    this.massageType,
    this.location,
    this.duration = 60,
    this.pressure = 'medium',
    this.focusAreas = const [],
    this.selectedAddOns = const [],
    this.musicPreference = 'calm',
    this.conversationStyle = 'minimal',
    this.additionalNotes = '',
  });

  Map<String, dynamic> toMap() => {
        'massageType': massageType,
        'location': location,
        'duration': duration,
        'pressureLevel': pressure,
        'focusAreas': focusAreas,
        'addOns': selectedAddOns,
        'musicPreference': musicPreference,
        'conversationStyle': conversationStyle,
        'additionalNotes': additionalNotes,
      };
}

class BuildYourTreatmentBlock extends StatefulWidget {
  final MassageProfile massageProfile;
  final String providerName;
  final String providerId;
  final ValueChanged<MassageBookingPreferences> onPreferencesChanged;
  final ValueChanged<double> onTotalChanged;

  const BuildYourTreatmentBlock({
    super.key,
    required this.massageProfile,
    required this.providerName,
    required this.providerId,
    required this.onPreferencesChanged,
    required this.onTotalChanged,
  });

  @override
  State<BuildYourTreatmentBlock> createState() =>
      _BuildYourTreatmentBlockState();
}

class _BuildYourTreatmentBlockState extends State<BuildYourTreatmentBlock> {
  String? _selectedType;
  String? _selectedLocation;
  int _selectedDuration = 60;
  String _selectedPressure = 'medium';
  final List<String> _selectedFocusAreas = [];
  final List<String> _selectedAddOns = [];
  String _selectedMusic = 'calm';
  String _selectedConversation = 'minimal';
  final TextEditingController _notesCtrl = TextEditingController();

  Map<String, dynamic>? _lastBookingPrefs;
  bool _lastBookingLoaded = false;

  MassageProfile get _mp => widget.massageProfile;

  @override
  void initState() {
    super.initState();
    _loadLastBooking();
    if (_mp.specialties.length == 1) _selectedType = _mp.specialties.first;
    final locs = _mp.serviceLocations;
    if (locs.home.enabled && !locs.clinic.enabled) _selectedLocation = 'home';
    if (!locs.home.enabled && locs.clinic.enabled) _selectedLocation = 'clinic';
    final enabledDurations = _mp.durations.where((d) => d.enabled).toList();
    if (enabledDurations.isNotEmpty) {
      final has60 = enabledDurations.any((d) => d.minutes == 60);
      _selectedDuration = has60 ? 60 : enabledDurations.first.minutes;
    }
    if (_mp.pressureLevels.length == 1) {
      _selectedPressure = _mp.pressureLevels.first;
    }
    if (_mp.conversationStyles.length == 1) {
      _selectedConversation = _mp.conversationStyles.first;
    }
    _notifyParent();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLastBooking() async {
    final prefs = await MassageBookingService.getLastBookingPreferences(
        widget.providerId);
    if (!mounted) return;
    setState(() {
      _lastBookingPrefs = prefs;
      _lastBookingLoaded = true;
    });
  }

  void _restoreFromLastBooking() {
    final prefs = _lastBookingPrefs;
    if (prefs == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      final type = prefs['massageType'] as String?;
      if (type != null && _mp.specialties.contains(type)) {
        _selectedType = type;
      }
      final loc = prefs['location'] as String?;
      if (loc != null) _selectedLocation = loc;
      final dur = prefs['duration'] as int?;
      if (dur != null) _selectedDuration = dur;
      final pressure = prefs['pressureLevel'] as String?;
      if (pressure != null && _mp.pressureLevels.contains(pressure)) {
        _selectedPressure = pressure;
      }
      final areas = (prefs['focusAreas'] as List?)?.cast<String>() ?? [];
      _selectedFocusAreas
        ..clear()
        ..addAll(areas);
      final addOns = (prefs['addOns'] as List?)?.cast<String>() ?? [];
      final enabledIds = _mp.addOns.where((a) => a.enabled).map((a) => a.id).toSet();
      _selectedAddOns
        ..clear()
        ..addAll(addOns.where(enabledIds.contains));
      final music = prefs['musicPreference'] as String?;
      if (music != null) _selectedMusic = music;
      final conv = prefs['conversationStyle'] as String?;
      if (conv != null) _selectedConversation = conv;
      final notes = prefs['additionalNotes'] as String? ?? '';
      _notesCtrl.text = notes;
      _lastBookingPrefs = null;
    });
    _notifyParent();
  }

  void _notifyParent() {
    final prefs = MassageBookingPreferences(
      massageType: _selectedType,
      location: _selectedLocation,
      duration: _selectedDuration,
      pressure: _selectedPressure,
      focusAreas: List.unmodifiable(_selectedFocusAreas),
      selectedAddOns: List.unmodifiable(_selectedAddOns),
      musicPreference: _selectedMusic,
      conversationStyle: _selectedConversation,
      additionalNotes: _notesCtrl.text,
    );
    widget.onPreferencesChanged(prefs);
    widget.onTotalChanged(_calculateTotal());
  }

  double _calculateTotal() {
    final dur = _mp.durations
        .where((d) => d.enabled && d.minutes == _selectedDuration)
        .firstOrNull;
    double base = dur?.price.toDouble() ?? 0;
    for (final addonId in _selectedAddOns) {
      final addon = _mp.addOns.where((a) => a.id == addonId).firstOrNull;
      if (addon != null) {
        base += addon.customPrice;
      } else {
        final def = findAddon(addonId);
        if (def != null) base += def.recommendedPrice;
      }
    }
    if (_selectedLocation == 'home') {
      base += _mp.serviceLocations.home.travelFee;
    }
    return base;
  }

  int _totalDurationMinutes() {
    int extra = 0;
    if (_selectedAddOns.contains('head_massage')) extra += 10;
    if (_selectedAddOns.contains('post_nap')) extra += 20;
    return _selectedDuration + extra;
  }

  List<String> _smartRecommendedAddOns() {
    final recs = <String>{};
    for (final area in _selectedFocusAreas) {
      if (area == 'neck') recs.add('head_massage');
      if (area == 'lower_back') recs.add('hot_stones');
      if (area == 'feet') recs.add('foot_scrub');
    }
    if (_selectedType == 'sports') {
      recs.addAll(['theragun', 'assisted_stretching', 'cold_compress']);
    }
    if (_selectedType == 'deep_tissue') {
      recs.addAll(['hot_stones', 'theragun']);
    }
    if (_selectedType == 'pregnancy') {
      recs.addAll(['aromatherapy_oil', 'hot_towels']);
      recs.removeAll(['cbd_oil', 'theragun', 'cupping']);
    }
    if (_selectedType == 'aromatherapy') {
      recs.addAll(['aromatherapy_oil', 'scalp_oil_treatment']);
    }
    final enabledIds = _mp.addOns.where((a) => a.enabled).map((a) => a.id).toSet();
    recs.retainAll(enabledIds);
    return recs.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kAmberLight, Color(0xFFFEF3C7)],
        ),
        border: Border.all(color: _kAmberBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text('✨ בנה את הטיפול שלך',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: _kDark)),
          const SizedBox(height: 4),
          Text(
            '${widget.providerName} תכין הכל לפי הבחירות שלך',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8B8B85)),
          ),
          if (_lastBookingLoaded && _lastBookingPrefs != null) ...[
            const SizedBox(height: 10),
            _buildSmartRestoreBanner(),
          ],
          const SizedBox(height: 14),
          _buildMassageTypeSection(),
          const SizedBox(height: 12),
          _buildLocationSection(),
          const SizedBox(height: 12),
          _buildDurationSection(),
          const SizedBox(height: 12),
          _buildPressureSection(),
          const SizedBox(height: 12),
          _buildFocusAreasSection(),
          const SizedBox(height: 12),
          _buildAddOnsSection(),
          if (_mp.discountPackages.where((p) => p.enabled).isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPackagesSection(),
          ],
          const SizedBox(height: 12),
          _buildAmbianceSection(),
          const SizedBox(height: 12),
          _buildNotesSection(),
          const SizedBox(height: 14),
          _buildSummaryBar(),
        ],
      ),
    );
  }

  // ── Smart Restore Banner ─────────────────────────────────────

  Widget _buildSmartRestoreBanner() {
    final prefs = _lastBookingPrefs;
    if (prefs == null) return const SizedBox.shrink();
    final type = prefs['massageType'] as String?;
    final dur = prefs['duration'] as int?;
    final loc = prefs['location'] as String?;
    final typeName = type != null ? (findSpecialty(type)?.nameHe ?? type) : null;
    final parts = <String>[
      if (typeName != null) typeName,
      if (dur != null) '$dur דק׳',
      if (loc != null) (loc == 'home' ? 'בית' : 'קליניקה'),
    ];
    return GestureDetector(
      onTap: _restoreFromLastBooking,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kDark, _kDarkSecondary]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Text('⚡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ההעדפות מהפעם הקודמת',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white)),
                  if (parts.isNotEmpty)
                    Text(parts.join(' · '),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white70)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('השתמש',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _kDark)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 1. Massage Type ─────────────────────────────────────────

  Widget _buildMassageTypeSection() {
    final specs = _mp.specialties
        .map((id) => findSpecialty(id))
        .whereType<MassageSpecialty>()
        .toList();
    if (specs.isEmpty) return const SizedBox.shrink();

    return _sectionCard(
      number: '1',
      title: 'סוג העיסוי',
      subtitle: 'בחר אחד',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.85,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: specs.length,
        itemBuilder: (_, i) {
          final s = specs[i];
          final selected = _selectedType == s.id;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedType = s.id);
              _notifyParent();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_kDark, _kDarkSecondary])
                    : null,
                color: selected ? null : Colors.white,
                border: selected ? null : Border.all(color: _kCreamBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected)
                    const Align(
                      alignment: AlignmentDirectional.topEnd,
                      child: Icon(Icons.check_circle,
                          size: 16, color: Colors.white),
                    ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.15)
                          : s.bgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(s.icon, style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(height: 4),
                  Text(s.nameHe,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : _kDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center),
                  Text(s.taglineHe,
                      style: TextStyle(
                          fontSize: 9,
                          color: selected
                              ? Colors.white70
                              : const Color(0xFF999999)),
                      maxLines: 1,
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 2. Location ─────────────────────────────────────────────

  Widget _buildLocationSection() {
    final home = _mp.serviceLocations.home;
    final clinic = _mp.serviceLocations.clinic;
    final showBoth = home.enabled && clinic.enabled;
    if (!home.enabled && !clinic.enabled) return const SizedBox.shrink();

    return _sectionCard(
      number: '2',
      title: 'איפה?',
      child: Column(
        children: [
          Row(
            children: [
              if (home.enabled)
                Expanded(
                  child: _locationTile(
                    icon: '🏠',
                    title: 'אצלי בבית',
                    subtitle: 'המעסה מגיע אליך\nעד 30 דק׳ הגעה',
                    selected: _selectedLocation == 'home',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedLocation = 'home');
                      _notifyParent();
                    },
                  ),
                ),
              if (showBoth) const SizedBox(width: 10),
              if (clinic.enabled)
                Expanded(
                  child: _locationTile(
                    icon: '🏢',
                    title: 'בקליניקה',
                    subtitle: clinic.address.isNotEmpty
                        ? clinic.address
                        : 'כתובת לא צויינה',
                    selected: _selectedLocation == 'clinic',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedLocation = 'clinic');
                      _notifyParent();
                    },
                  ),
                ),
            ],
          ),
          if (_selectedLocation == 'home' && home.travelFee > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('🚗', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Text('דמי הגעה: ₪${home.travelFee}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF92400E))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _locationTile({
    required String icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [_kDark, _kDarkSecondary])
              : null,
          color: selected ? null : Colors.white,
          border: selected ? null : Border.all(color: _kCreamBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            if (selected)
              const Align(
                alignment: AlignmentDirectional.topEnd,
                child:
                    Icon(Icons.check_circle, size: 16, color: Colors.white),
              ),
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : _kDark)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 10,
                    color:
                        selected ? Colors.white70 : const Color(0xFF999999)),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── 3. Duration ─────────────────────────────────────────────

  Widget _buildDurationSection() {
    final enabled = _mp.durations.where((d) => d.enabled).toList();
    if (enabled.isEmpty) return const SizedBox.shrink();

    return _sectionCard(
      number: '3',
      title: 'משך',
      trailing: 'הכי פופולרי: 60 דק׳',
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F2EC),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: enabled.map((d) {
            final sel = _selectedDuration == d.minutes;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedDuration = d.minutes);
                  _notifyParent();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 4)
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text('${d.minutes}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: sel ? _kDark : Colors.grey)),
                      Text('דק׳',
                          style: TextStyle(
                              fontSize: 10,
                              color: sel ? _kDark : Colors.grey)),
                      const SizedBox(height: 2),
                      Text('₪${d.price}',
                          style: TextStyle(
                              fontSize: 11,
                              color: sel
                                  ? _kDark
                                  : const Color(0xFF999999))),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── 4. Pressure ─────────────────────────────────────────────

  Widget _buildPressureSection() {
    final levels = _mp.pressureLevels;
    if (levels.isEmpty) return const SizedBox.shrink();

    const labels = {'light': '🪶 עדין', 'medium': '✋ בינוני', 'strong': '💪 חזק'};
    const helpers = {
      'light': 'מגע עדין ורגוע',
      'medium': 'לחץ נעים, מתאים לרוב האנשים',
      'strong': 'לחץ עוצמתי לשחרור עמוק',
    };

    if (levels.length == 1) {
      return _sectionCard(
        number: '4',
        title: 'עוצמת לחץ',
        child: Chip(
          label: Text(labels[levels.first] ?? levels.first),
          backgroundColor: const Color(0xFFF5F2EC),
        ),
      );
    }

    final idx = levels.indexOf(_selectedPressure).clamp(0, levels.length - 1);

    return _sectionCard(
      number: '4',
      title: 'עוצמת לחץ',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _kDark, width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: levels.map((l) {
                final sel = _selectedPressure == l;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedPressure = l);
                      _notifyParent();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? const LinearGradient(
                                colors: [_kDark, _kDarkSecondary])
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(labels[l] ?? l,
                          style: TextStyle(
                              fontSize: 12,
                              color: sel ? Colors.white : _kDark)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F2EC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              helpers[levels[idx]] ?? '',
              style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. Focus Areas ──────────────────────────────────────────

  Widget _buildFocusAreasSection() {
    return _sectionCard(
      number: '5',
      title: 'איפה כואב?',
      subtitle: 'סמן ו${widget.providerName} תתמקד שם',
      trailing: _selectedFocusAreas.isNotEmpty
          ? '${_selectedFocusAreas.length} נבחרו'
          : null,
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kMassageFocusAreas.map((area) {
              final sel = _selectedFocusAreas.contains(area.id);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (sel) {
                      _selectedFocusAreas.remove(area.id);
                    } else {
                      _selectedFocusAreas.add(area.id);
                    }
                  });
                  _notifyParent();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: sel
                        ? const LinearGradient(
                            colors: [_kDark, _kDarkSecondary])
                        : null,
                    color: sel ? null : Colors.white,
                    border: sel ? null : Border.all(color: _kCreamBorder),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sel)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsetsDirectional.only(end: 6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF59E0B),
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(area.nameHe,
                          style: TextStyle(
                              fontSize: 12,
                              color: sel ? Colors.white : _kDark)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_selectedFocusAreas.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildFocusAreaSuggestion(),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusAreaSuggestion() {
    final recs = _smartRecommendedAddOns();
    if (recs.isEmpty) return const SizedBox.shrink();
    final firstRec = recs.first;
    final def = findAddon(firstRec);
    if (def == null) return const SizedBox.shrink();
    final alreadySelected = _selectedAddOns.contains(firstRec);
    if (alreadySelected) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedAddOns.add(firstRec));
        _notifyParent();
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Text('✨', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'מומלץ "${def.nameHe}" להקלת מתח באזור',
                style: TextStyle(fontSize: 11, color: Colors.green[800]),
              ),
            ),
            const Icon(Icons.add_circle_outline,
                size: 18, color: _kSuccess),
          ],
        ),
      ),
    );
  }

  // ── 6. Add-Ons ──────────────────────────────────────────────

  Widget _buildAddOnsSection() {
    final available = _mp.addOns.where((a) => a.enabled).toList();
    if (available.isEmpty) return const SizedBox.shrink();

    final incompatible = <String>{};
    if (_selectedType == 'pregnancy') {
      incompatible.addAll(['cbd_oil', 'theragun', 'cupping']);
    }
    final filtered =
        available.where((a) => !incompatible.contains(a.id)).toList();
    final recs = _smartRecommendedAddOns();

    return _sectionCard(
      number: '6',
      title: 'תוספות',
      subtitle: 'שדרג את החוויה',
      child: Column(
        children: filtered.map((addon) {
          final def = findAddon(addon.id);
          final name = addon.isCustom
              ? (addon.nameHe ?? addon.id)
              : (def?.nameHe ?? addon.id);
          final icon = addon.isCustom
              ? (addon.icon ?? '✨')
              : (def?.icon ?? '✨');
          final desc = addon.isCustom
              ? (addon.descriptionHe ?? '')
              : (def?.descriptionHe ?? '');
          final price = addon.customPrice > 0
              ? addon.customPrice
              : (def?.recommendedPrice ?? 0);
          final sel = _selectedAddOns.contains(addon.id);
          final isRecommended = recs.contains(addon.id);

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                if (sel) {
                  _selectedAddOns.remove(addon.id);
                } else {
                  _selectedAddOns.add(addon.id);
                }
              });
              _notifyParent();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: sel
                    ? const LinearGradient(
                        colors: [Color(0xFFFAFAF6), Color(0xFFF5F2EC)])
                    : null,
                color: sel ? null : Colors.white,
                border: Border.all(
                  color: sel ? _kDark : _kCreamBorder,
                  width: sel ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isRecommended && !sel)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kSuccess.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('מומלץ עבורך',
                          style:
                              TextStyle(fontSize: 9, color: _kSuccess)),
                    ),
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F2EC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            Text(icon, style: const TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                            if (desc.isNotEmpty)
                              Text(desc,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF999999))),
                          ],
                        ),
                      ),
                      Text('+₪$price',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: sel ? _kDark : const Color(0xFF999999))),
                      const SizedBox(width: 8),
                      Icon(
                        sel
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                        color: sel ? _kDark : _kCreamBorder,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 7. Packages ─────────────────────────────────────────────

  Widget _buildPackagesSection() {
    final pkgs = _mp.discountPackages.where((p) => p.enabled).toList();
    if (pkgs.isEmpty) return const SizedBox.shrink();

    return _sectionCard(
      number: '7',
      title: '🎁 חבילות הנחה',
      child: SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: pkgs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final p = pkgs[i];
            final baseDur = _mp.durations
                .where((d) => d.enabled)
                .firstOrNull;
            final basePrice = (baseDur?.price ?? 150).toDouble();
            final fullPrice = basePrice * p.sessionsCount;
            final discounted =
                fullPrice * (1 - p.discountPercent / 100);
            final savings = fullPrice - discounted;

            return Container(
              width: 220,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)]),
                border:
                    Border.all(color: _kAmberBorder, width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎁',
                      style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text('✓ ${p.sessionsCount} טיפולים מלאים',
                      style: const TextStyle(fontSize: 11)),
                  Text('✓ הנחה ${p.discountPercent}% על כל טיפול',
                      style: const TextStyle(fontSize: 11)),
                  Text('✓ תוקף ${p.validityDays} ימים',
                      style: const TextStyle(fontSize: 11)),
                  const Spacer(),
                  Row(
                    children: [
                      Text('₪${fullPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                              color: Color(0xFF999999))),
                      const SizedBox(width: 6),
                      Text('₪${discounted.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Text('חיסכון של ₪${savings.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 10, color: _kSuccess)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── 8. Ambiance ─────────────────────────────────────────────

  Widget _buildAmbianceSection() {
    return _sectionCard(
      number: '8',
      title: 'אווירה',
      subtitle: 'המקום שלך, החוקים שלך',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('מוזיקת רקע',
              style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _musicChip('calm', '🧘 רגועה'),
              _musicChip('nature', '🌊 טבע'),
              _musicChip('classical', '🎵 קלאסי'),
              _musicChip('silent', '🤫 שקט'),
            ],
          ),
          const SizedBox(height: 12),
          const Text('שיחה במהלך הטיפול',
              style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final style in _mp.conversationStyles)
                _convChip(
                    style,
                    style == 'chatty'
                        ? '💬 בכיף לדבר'
                        : '🤫 מינימלי'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _musicChip(String id, String label) {
    final sel = _selectedMusic == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedMusic = id);
        _notifyParent();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: sel
              ? const LinearGradient(colors: [_kDark, _kDarkSecondary])
              : null,
          color: sel ? null : Colors.white,
          border: sel ? null : Border.all(color: _kCreamBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: sel ? Colors.white : _kDark)),
      ),
    );
  }

  Widget _convChip(String id, String label) {
    final sel = _selectedConversation == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedConversation = id);
        _notifyParent();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: sel
              ? const LinearGradient(colors: [_kDark, _kDarkSecondary])
              : null,
          color: sel ? null : Colors.white,
          border: sel ? null : Border.all(color: _kCreamBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: sel ? Colors.white : _kDark)),
      ),
    );
  }

  // ── 9. Notes ────────────────────────────────────────────────

  Widget _buildNotesSection() {
    return _sectionCard(
      number: '9',
      title: 'משהו שכדאי ש${widget.providerName} תדע?',
      subtitle: 'הודעה אישית · נשלחת מאובטחת',
      child: Column(
        children: [
          TextField(
            controller: _notesCtrl,
            textAlign: TextAlign.right,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  'לדוגמה: יש לי רגישות באזור הצוואר, פציעת ספורט ישנה...',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => _notifyParent(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              _noteChip('+ פציעה ישנה'),
              _noteChip('+ הריון'),
              _noteChip('+ אלרגיה לשמן'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noteChip(String label) {
    return GestureDetector(
      onTap: () {
        final trimmed = label.replaceFirst('+ ', '');
        final current = _notesCtrl.text;
        if (!current.contains(trimmed)) {
          _notesCtrl.text =
              current.isEmpty ? trimmed : '$current, $trimmed';
          _notesCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _notesCtrl.text.length));
          _notifyParent();
        }
      },
      child: Chip(
        label:
            Text(label, style: const TextStyle(fontSize: 11, color: _kDark)),
        backgroundColor: const Color(0xFFF5F2EC),
        side: const BorderSide(color: _kCreamBorder),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── Summary Bar ─────────────────────────────────────────────

  Widget _buildSummaryBar() {
    final total = _calculateTotal();
    final totalMinutes = _totalDurationMinutes();
    final typeName = _selectedType != null
        ? (findSpecialty(_selectedType!)?.nameHe ?? _selectedType!)
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFBFAF6), Color(0xFFF5F2EC)]),
        border: Border.all(color: _kCreamBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('סך הכל',
                      style:
                          TextStyle(fontSize: 11, color: Color(0xFF999999))),
                  Text(total > 0 ? '₪${total.toStringAsFixed(0)}' : 'מחיר ייקבע',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w500)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('משך כולל',
                      style:
                          TextStyle(fontSize: 11, color: Color(0xFF999999))),
                  Text('$totalMinutes דק׳',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (typeName != null) _summaryTag(typeName),
              if (_selectedLocation != null)
                _summaryTag(_selectedLocation == 'home' ? 'בית' : 'קליניקה'),
              _summaryTag('$_selectedDuration דק׳'),
              _summaryTag(
                  _selectedPressure == 'light'
                      ? 'עדין'
                      : _selectedPressure == 'strong'
                          ? 'חזק'
                          : 'בינוני'),
              for (final area in _selectedFocusAreas)
                _summaryTag(findFocusArea(area)?.nameHe ?? area),
              for (final addonId in _selectedAddOns)
                _summaryTag(
                    '+ ${findAddon(addonId)?.nameHe ?? addonId}'),
            ],
          ),
          const SizedBox(height: 10),
          Text('🔒 תשלום מאובטח · ביטול חינם עד 24 שעות לפני',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _summaryTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kCreamBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, color: _kDark)),
    );
  }

  // ── Shared section card ─────────────────────────────────────

  Widget _sectionCard({
    required String number,
    required String title,
    String? subtitle,
    String? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: _kDark,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(number,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              if (trailing != null)
                Text(trailing,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF999999))),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 30),
              child: Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF999999))),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
