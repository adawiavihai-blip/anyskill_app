// Shared two-field address input — city autocomplete (offline, instant)
// + street autocomplete (OSM Nominatim, 350ms debounced).
//
// This widget replaces every ad-hoc `TextField(decoration: 'כתובת')` across
// the app — see CLAUDE.md §77 for the migration list. Designed to match the
// "Wolt/Uber/Airbnb" UX expectations the user articulated:
//   • City field shows results as you type (instant — bundled list of
//     ~270 Israeli cities/yishuvim).
//   • Street field shows real street suggestions FILTERED BY THE CITY
//     once the user has picked one. Until then, the field is disabled.
//   • Free-text fallback always works: if Nominatim returns nothing, the
//     user can still type any address and submit. We never block the
//     happy path on a third-party API.
//   • Optional lat/lng callback fires when the user selects a structured
//     suggestion — screens with a map pin (flash auction, babysitter,
//     motorcycle tow) can re-centre the pin.
//
// Public API: one widget [AddressInput] with city + street. Pure widget,
// no Riverpod. Parent owns the values via [onChanged].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../constants/israeli_cities.dart';
import '../services/geocoding_service.dart';

/// What [AddressInput.onChanged] reports back.
class AddressValue {
  final String city;
  final String street;
  final LatLng? coordinates;

  const AddressValue({
    required this.city,
    required this.street,
    this.coordinates,
  });

  bool get isEmpty => city.trim().isEmpty && street.trim().isEmpty;
  bool get hasBoth => city.trim().isNotEmpty && street.trim().isNotEmpty;

  /// Combined single-string representation suitable for legacy Firestore
  /// fields that store the whole address in one string (e.g.
  /// `pickupAddress`, `clinic.address`, `locationFrom`).
  ///
  /// Shape: `"<street>, <city>"` when both present, otherwise whichever
  /// half is non-empty, otherwise `""`. The comma + space matters — the
  /// [fromCombined] parser uses the last comma to split.
  String get combined {
    final c = city.trim();
    final s = street.trim();
    if (c.isEmpty && s.isEmpty) return '';
    if (c.isEmpty) return s;
    if (s.isEmpty) return c;
    return '$s, $c';
  }

  /// Best-effort split of a legacy single-string address into (street, city).
  ///
  /// Heuristic: split on the LAST comma — everything after = city,
  /// everything before = street. If no comma, the whole string goes into
  /// [street] (we assume "Tel Aviv" alone is rare in a full-address field).
  /// Callers that need only-city behaviour should override this — see
  /// AnyTasks migration which routes free-text city into the [city] field.
  factory AddressValue.fromCombined(String? combined,
      {LatLng? coordinates, bool cityOnly = false}) {
    final raw = (combined ?? '').trim();
    if (raw.isEmpty) {
      return AddressValue(city: '', street: '', coordinates: coordinates);
    }
    if (cityOnly) {
      return AddressValue(city: raw, street: '', coordinates: coordinates);
    }
    final lastComma = raw.lastIndexOf(',');
    if (lastComma == -1) {
      return AddressValue(city: '', street: raw, coordinates: coordinates);
    }
    final street = raw.substring(0, lastComma).trim();
    final city = raw.substring(lastComma + 1).trim();
    return AddressValue(city: city, street: street, coordinates: coordinates);
  }

  AddressValue copyWith({
    String? city,
    String? street,
    LatLng? coordinates,
    bool clearCoordinates = false,
  }) {
    return AddressValue(
      city: city ?? this.city,
      street: street ?? this.street,
      coordinates: clearCoordinates ? null : (coordinates ?? this.coordinates),
    );
  }
}

/// Two-field address input with smart autocomplete.
///
/// Typical usage inside a booking form:
/// ```dart
/// AddressInput(
///   initialCity: prefs.city,
///   initialStreet: prefs.street,
///   onChanged: (v) => setState(() => _address = v),
///   accentColor: BookingPalette.accent,
/// )
/// ```
///
/// Optional [onCoordinatesResolved] fires when Nominatim returns lat/lng
/// for a user-selected street suggestion. Screens with a map pin can
/// re-centre on the new coordinates.
class AddressInput extends StatefulWidget {
  /// Initial city value (e.g. from previously-saved provider profile or
  /// Express Reorder). Empty string for new forms.
  final String initialCity;

  /// Initial street+number value.
  final String initialStreet;

  /// Fires on every keystroke. The caller is responsible for storing the
  /// values; this widget is uncontrolled-style (parent doesn't push values
  /// back in after creation — see [resetTo] for that).
  final ValueChanged<AddressValue> onChanged;

  /// Fires when Nominatim resolves a structured street suggestion to
  /// concrete coordinates. Screens with a map pin should re-centre on
  /// these coordinates and reverse-geocode on subsequent pin drags.
  /// Receives `null` if the user clears the street field.
  final ValueChanged<LatLng?>? onCoordinatesResolved;

  /// Compact mode for in-card / sticky-bar contexts. Reduces vertical
  /// padding and field height; same widths.
  final bool dense;

  /// Accent color for focused borders / dropdown highlights / hint icon.
  /// Defaults to indigo if null. Pass the host screen's primary so the
  /// widget blends with its surroundings.
  final Color? accentColor;

  /// Optional label overrides. Default labels are `"עיר"` and `"רחוב ומספר"`.
  final String? cityLabel;
  final String? streetLabel;

  /// Optional hint overrides shown inside the field while empty. Defaults
  /// match Wolt/Airbnb style: short, action-oriented.
  final String? cityHint;
  final String? streetHint;

  /// Whether the street field can be edited while no city is selected.
  /// Default false (Wolt pattern — city first, then street). Set true if
  /// the screen wants both unlocked from the start.
  final bool allowStreetWithoutCity;

  /// If true, validates that the city is in the canonical bundled list.
  /// The user can still TYPE anything; this only affects validator output.
  /// Default false — we accept any free-text city.
  final bool strictCityValidation;

  /// Optional field validators called from [Form] context.
  final FormFieldValidator<String>? cityValidator;
  final FormFieldValidator<String>? streetValidator;

  /// Read-only mode (display-only, e.g. inside a confirmation summary).
  final bool readOnly;

  /// City-only mode — hides the street field entirely. Used by:
  ///   • Provider Registration (single city for service base location)
  ///   • AnyTasks publish (locationFrom / locationTo — general "city to
  ///     city" intent, not a delivery address)
  ///
  /// When true, [onChanged] still fires with `street: ""`.
  final bool cityOnly;

  /// Dark-card mode — flips field background to translucent white-on-dark
  /// and text color to white, so the widget blends with the premium-glass
  /// surfaces used by Delivery / Motorcycle Tow / Flash Auction / Babysitter
  /// Emergency. The dropdown stays light (standard Wolt/Uber pattern: dark
  /// hero with light autocomplete surface).
  final bool darkTheme;

  const AddressInput({
    super.key,
    this.initialCity = '',
    this.initialStreet = '',
    required this.onChanged,
    this.onCoordinatesResolved,
    this.dense = false,
    this.accentColor,
    this.cityLabel,
    this.streetLabel,
    this.cityHint,
    this.streetHint,
    this.allowStreetWithoutCity = false,
    this.strictCityValidation = false,
    this.cityValidator,
    this.streetValidator,
    this.readOnly = false,
    this.cityOnly = false,
    this.darkTheme = false,
  });

  @override
  State<AddressInput> createState() => _AddressInputState();
}

class _AddressInputState extends State<AddressInput> {
  late final TextEditingController _cityCtrl;
  late final TextEditingController _streetCtrl;
  final _cityFocus = FocusNode();
  final _streetFocus = FocusNode();

  /// Coordinates last resolved by Nominatim for the current (city, street).
  /// Cleared on any city/street edit; re-fetched only when the user
  /// SELECTS a structured suggestion from the dropdown.
  LatLng? _resolvedCoords;

  @override
  void initState() {
    super.initState();
    _cityCtrl = TextEditingController(text: widget.initialCity);
    _streetCtrl = TextEditingController(text: widget.initialStreet);
    _cityCtrl.addListener(_onTextChanged);
    _streetCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _cityCtrl
      ..removeListener(_onTextChanged)
      ..dispose();
    _streetCtrl
      ..removeListener(_onTextChanged)
      ..dispose();
    _cityFocus.dispose();
    _streetFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onChanged(AddressValue(
      city: _cityCtrl.text,
      street: _streetCtrl.text,
      coordinates: _resolvedCoords,
    ));
  }

  void _onCitySelected(String city) {
    _cityCtrl.value = TextEditingValue(
      text: city,
      selection: TextSelection.collapsed(offset: city.length),
    );
    // Selecting a city invalidates any previously-resolved coordinates
    // (likely from a different city) — let the street field re-resolve.
    _resolvedCoords = null;
    widget.onCoordinatesResolved?.call(null);
    _streetFocus.requestFocus();
  }

  void _onStreetSelected(StreetSuggestion suggestion) {
    _streetCtrl.value = TextEditingValue(
      text: suggestion.fieldValue,
      selection: TextSelection.collapsed(offset: suggestion.fieldValue.length),
    );
    // If Nominatim also reports a normalized city, prefer it — handles
    // common case where user typed "ת״א" and the street's official city
    // is "תל אביב-יפו".
    if ((suggestion.city ?? '').isNotEmpty &&
        suggestion.city != _cityCtrl.text) {
      _cityCtrl.value = TextEditingValue(
        text: suggestion.city!,
        selection: TextSelection.collapsed(offset: suggestion.city!.length),
      );
    }
    final coords = suggestion.latLng;
    if (coords != null) {
      _resolvedCoords = coords;
      widget.onCoordinatesResolved?.call(coords);
      // Re-fire onChanged so the new coordinates land in the parent's state.
      widget.onChanged(AddressValue(
        city: _cityCtrl.text,
        street: _streetCtrl.text,
        coordinates: coords,
      ));
    }
    _streetFocus.unfocus();
  }

  String? _cityValidatorDelegate(String? raw) {
    if (widget.cityValidator != null) return widget.cityValidator!(raw);
    if (widget.strictCityValidation) {
      final v = (raw ?? '').trim();
      if (v.isNotEmpty && !isCanonicalIsraeliCity(v)) {
        return 'בחרי עיר מהרשימה';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? const Color(0xFF6366F1);
    final streetEnabled = widget.allowStreetWithoutCity ||
        _cityCtrl.text.trim().isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CityField(
            controller: _cityCtrl,
            focusNode: _cityFocus,
            accent: accent,
            dense: widget.dense,
            readOnly: widget.readOnly,
            darkTheme: widget.darkTheme,
            label: widget.cityLabel ?? 'עיר',
            hint: widget.cityHint ?? 'התחילי להקליד שם עיר…',
            validator: _cityValidatorDelegate,
            onSelected: _onCitySelected,
          ),
          if (!widget.cityOnly) ...[
            SizedBox(height: widget.dense ? 8 : 12),
            _StreetField(
              controller: _streetCtrl,
              focusNode: _streetFocus,
              cityResolver: () => _cityCtrl.text.trim(),
              accent: accent,
              dense: widget.dense,
              readOnly: widget.readOnly,
              darkTheme: widget.darkTheme,
              enabled: streetEnabled,
              label: widget.streetLabel ?? 'רחוב ומספר',
              hint: widget.streetHint ?? 'לדוגמה: הרצל 10',
              validator: widget.streetValidator,
              onSelected: _onStreetSelected,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── private helpers ─────────────────────────────────────────────────────

/// City autocomplete — offline lookup against the bundled Israeli cities
/// list. Dropdown opens on focus + on every keystroke.
class _CityField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;
  final bool dense;
  final bool readOnly;
  final bool darkTheme;
  final String label;
  final String hint;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String> onSelected;

  const _CityField({
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.dense,
    required this.readOnly,
    required this.darkTheme,
    required this.label,
    required this.hint,
    required this.validator,
    required this.onSelected,
  });

  @override
  State<_CityField> createState() => _CityFieldState();
}

class _CityFieldState extends State<_CityField> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refreshSuggestions);
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshSuggestions);
    widget.focusNode.removeListener(_handleFocusChange);
    _removeOverlay();
    super.dispose();
  }

  void _refreshSuggestions() {
    if (!widget.focusNode.hasFocus) return;
    final newSuggestions = filterIsraeliCities(widget.controller.text);
    if (!listEquals(newSuggestions, _suggestions)) {
      _suggestions = newSuggestions;
      _rebuildOverlay();
    }
  }

  void _handleFocusChange() {
    if (widget.focusNode.hasFocus) {
      _suggestions = filterIsraeliCities(widget.controller.text);
      _insertOverlay();
    } else {
      // Delay just enough for a tap on the overlay to register before
      // dismissal — mirrors the same pattern from search_bar.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!widget.focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _insertOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_overlay!);
  }

  void _rebuildOverlay() => _overlay?.markNeedsBuild();

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Widget _buildOverlay(BuildContext ctx) {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Positioned(
      width: (context.findRenderObject() as RenderBox?)?.size.width ?? 320,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: Offset(0, widget.dense ? 50 : 58),
        child: _SuggestionList<String>(
          accent: widget.accent,
          items: _suggestions,
          labelBuilder: (s) => s,
          onTap: (s) {
            widget.onSelected(s);
            _removeOverlay();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        readOnly: widget.readOnly,
        validator: widget.validator,
        textInputAction: TextInputAction.next,
        textDirection: TextDirection.rtl,
        style: widget.darkTheme
            ? const TextStyle(color: Colors.white)
            : null,
        decoration: _addressDecoration(
          label: widget.label,
          hint: widget.hint,
          accent: widget.accent,
          dense: widget.dense,
          darkTheme: widget.darkTheme,
          icon: Icons.location_city_rounded,
        ),
      ),
    );
  }
}

/// Street autocomplete — debounced Nominatim search filtered by the
/// currently-typed city. Disabled when no city is set (unless the
/// parent overrode via `allowStreetWithoutCity: true`).
class _StreetField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Lazy getter for the city — read on every fetch so we always see the
  /// latest typed value (even if the user changed city mid-search).
  final String Function() cityResolver;
  final Color accent;
  final bool dense;
  final bool readOnly;
  final bool darkTheme;
  final bool enabled;
  final String label;
  final String hint;
  final FormFieldValidator<String>? validator;
  final ValueChanged<StreetSuggestion> onSelected;

  const _StreetField({
    required this.controller,
    required this.focusNode,
    required this.cityResolver,
    required this.accent,
    required this.dense,
    required this.readOnly,
    required this.darkTheme,
    required this.enabled,
    required this.label,
    required this.hint,
    required this.validator,
    required this.onSelected,
  });

  @override
  State<_StreetField> createState() => _StreetFieldState();
}

class _StreetFieldState extends State<_StreetField> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  Timer? _debounce;
  List<StreetSuggestion> _suggestions = const [];
  bool _loading = false;
  String _lastQuery = '';

  static const _kDebounce = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleQuery);
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleQuery);
    widget.focusNode.removeListener(_handleFocusChange);
    _debounce?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _scheduleQuery() {
    if (!widget.focusNode.hasFocus) return;
    _debounce?.cancel();
    _debounce = Timer(_kDebounce, _executeQuery);
  }

  Future<void> _executeQuery() async {
    final city = widget.cityResolver();
    final query = widget.controller.text.trim();
    if (city.isEmpty || query.length < 2) {
      _suggestions = const [];
      _loading = false;
      _rebuildOverlay();
      return;
    }
    final dedupeKey = '$city|$query';
    if (dedupeKey == _lastQuery) return;
    _lastQuery = dedupeKey;
    _loading = true;
    _rebuildOverlay();

    final results = await GeocodingService.searchStreets(
      city: city,
      query: query,
    );
    if (!mounted) return;
    // Stale-result guard: if the user kept typing while we were waiting,
    // discard this result.
    if (widget.controller.text.trim() != query ||
        widget.cityResolver() != city) {
      return;
    }
    _suggestions = results;
    _loading = false;
    _rebuildOverlay();
  }

  void _handleFocusChange() {
    if (widget.focusNode.hasFocus) {
      _insertOverlay();
      if (widget.controller.text.trim().length >= 2) {
        _scheduleQuery();
      }
    } else {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!widget.focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _insertOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_overlay!);
  }

  void _rebuildOverlay() => _overlay?.markNeedsBuild();

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Widget _buildOverlay(BuildContext ctx) {
    if (!_loading && _suggestions.isEmpty) return const SizedBox.shrink();
    return Positioned(
      width: (context.findRenderObject() as RenderBox?)?.size.width ?? 320,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: Offset(0, widget.dense ? 50 : 58),
        child: _loading && _suggestions.isEmpty
            ? _LoadingChip(accent: widget.accent)
            : _SuggestionList<StreetSuggestion>(
                accent: widget.accent,
                items: _suggestions,
                labelBuilder: (s) => s.listLabel,
                onTap: (s) {
                  widget.onSelected(s);
                  _removeOverlay();
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        readOnly: widget.readOnly,
        enabled: widget.enabled,
        validator: widget.validator,
        textInputAction: TextInputAction.done,
        textDirection: TextDirection.rtl,
        style: widget.darkTheme
            ? const TextStyle(color: Colors.white)
            : null,
        decoration: _addressDecoration(
          label: widget.label,
          hint: widget.enabled ? widget.hint : 'בחרי עיר קודם',
          accent: widget.accent,
          dense: widget.dense,
          darkTheme: widget.darkTheme,
          icon: Icons.alt_route_rounded,
          suffix: _loading
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: widget.accent,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// Shared dropdown rendering for both city + street fields.
class _SuggestionList<T> extends StatelessWidget {
  final Color accent;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onTap;

  const _SuggestionList({
    required this.accent,
    required this.items,
    required this.labelBuilder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: Colors.grey.shade100,
          ),
          itemBuilder: (ctx, i) {
            final item = items[i];
            return InkWell(
              onTap: () => onTap(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        labelBuilder(item),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1F2937),
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoadingChip extends StatelessWidget {
  final Color accent;
  const _LoadingChip({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'מחפש כתובות…',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _addressDecoration({
  required String label,
  required String hint,
  required Color accent,
  required bool dense,
  required IconData icon,
  bool darkTheme = false,
  Widget? suffix,
}) {
  final fillColor =
      darkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.white;
  final defaultBorder = darkTheme
      ? Colors.white.withValues(alpha: 0.18)
      : const Color(0xFFE5E7EB);
  final disabledBorder = darkTheme
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFF3F4F6);
  final labelColor =
      darkTheme ? Colors.white.withValues(alpha: 0.7) : null;
  final hintColor =
      darkTheme ? Colors.white.withValues(alpha: 0.45) : null;
  final iconColor =
      darkTheme ? Colors.white.withValues(alpha: 0.7) : null;

  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: labelColor == null ? null : TextStyle(color: labelColor),
    hintStyle: hintColor == null ? null : TextStyle(color: hintColor),
    prefixIcon: Icon(icon, size: 20, color: iconColor),
    suffixIcon: suffix,
    isDense: dense,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: dense ? 12 : 16,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: defaultBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: defaultBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: accent, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: disabledBorder),
    ),
    filled: true,
    fillColor: fillColor,
  );
}

/// Same as `package:flutter/foundation.dart` listEquals — duplicated here
/// to avoid an extra import for one call site.
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
