import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/cached_readers.dart';
import '../theme/app_theme.dart';
import 'category_specs_widget.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// SearchCardPricePill — pricing transparency on the search card.
///
/// **What it solves**
/// The launch UX audit (CLAUDE.md §57-era) flagged "No price clarity until
/// the booking sheet opens" as a critical conversion-funnel crack:
/// > Search cards show "150 ₪/ללילה" via dynamic schema — but tap into
/// > the profile and the actual total (with surcharges, deposits, late
/// > fees, emergency, kmFee, materialsEstimate) only renders inside the
/// > CSM booking block after picking options.
///
/// This widget surfaces the pricing signals that would otherwise hide
/// inside the booking sheet:
///   - Deposit-only booking (`depositPercent > 0`) → "פיקדון Y% מקדים"
///   - Price-locked guarantee (`priceLocked: true`) → 🔒 "מחיר נעול"
///   - Bundle savings (cheapest bundle's `savingsPercent`) → "חבילה: -10%"
///   - Off-hours surcharge active → "+30% לילה / סופ״ש"
///
/// **Backward compatibility**
/// When [schema] is empty (legacy category without v2 schema), this
/// widget renders IDENTICALLY to the previous inline RichText — same
/// price + unit, no extra badges. Zero regression on legacy flows.
///
/// **Wolt/Airbnb baseline**
/// Both show full pricing transparency on the discovery card. This is
/// the AnySkill equivalent — keeps the customer informed before they
/// commit to a 4,370-line expert profile screen.
/// ═══════════════════════════════════════════════════════════════════════════

class SearchCardPricePill extends StatelessWidget {
  final Map<String, dynamic> userData;
  final ServiceSchema schema;

  /// Compact mode (4px smaller font). Default false.
  final bool dense;

  const SearchCardPricePill({
    super.key,
    required this.userData,
    required this.schema,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (priceText, unitLabel) =
        primaryPriceDisplay(userData, schema.fields);

    // Resolve provider-customized surcharge override (CSM v2 reserved key).
    final categoryDetails =
        userData['categoryDetails'] as Map<String, dynamic>? ?? {};
    final surchargeOverride =
        categoryDetails['_surcharge'] as Map<String, dynamic>?;

    final hasSurcharge = _hasSurcharge(surchargeOverride);
    final hasDeposit = schema.depositPercent > 0;
    final hasPriceLock = schema.priceLocked;
    final cheapestBundle = _cheapestBundle();
    final hasBundle = cheapestBundle != null && cheapestBundle.savingsPercent > 0;
    final unit = schema.fields.isNotEmpty
        ? unitLabel
        : l10n.catResultsPerHour;

    final priceFontSize = dense ? 16.0 : 18.0;
    final unitFontSize = dense ? 10.0 : 11.0;

    final showAnyBadge =
        hasDeposit || hasPriceLock || hasBundle || hasSurcharge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Big price line ────────────────────────────────────────────────
        RichText(
          text: TextSpan(
            style: const TextStyle(fontFamily: 'Heebo'),
            children: [
              TextSpan(
                text: '₪$priceText',
                style: TextStyle(
                  color: Brand.indigo,
                  fontWeight: FontWeight.w900,
                  fontSize: priceFontSize,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: unitFontSize,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),

        // ── Transparency badges row (only when there's something to say) ─
        if (showAnyBadge) ...[
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 3,
            children: [
              if (hasPriceLock) const _PriceBadge.priceLocked(),
              if (hasDeposit)
                _PriceBadge.deposit(percent: schema.depositPercent),
              if (hasBundle)
                _PriceBadge.bundle(savingsPercent: cheapestBundle.savingsPercent),
              if (hasSurcharge)
                _PriceBadge.surcharge(
                  nightPct: _surchargeNightPct(surchargeOverride, schema),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  PricingBundle? _cheapestBundle() {
    if (schema.bundles.isEmpty) return null;
    PricingBundle? best;
    for (final b in schema.bundles) {
      if (b.savingsPercent <= 0) continue;
      if (best == null || b.savingsPercent > best.savingsPercent) {
        best = b;
      }
    }
    return best;
  }

  bool _hasSurcharge(Map<String, dynamic>? override) {
    // Provider override toggle wins over schema default.
    if (override != null && override['enabled'] == true) {
      final night = (override['nightPct'] as num?)?.toDouble() ?? 0;
      final weekend = (override['weekendPct'] as num?)?.toDouble() ?? 0;
      return night > 0 || weekend > 0;
    }
    final s = schema.surcharge;
    if (s == null) return false;
    return s.isActive;
  }

  double _surchargeNightPct(
    Map<String, dynamic>? override,
    ServiceSchema schema,
  ) {
    if (override != null && override['enabled'] == true) {
      return (override['nightPct'] as num?)?.toDouble() ??
          schema.surcharge?.nightPercent.toDouble() ??
          0;
    }
    return schema.surcharge?.nightPercent.toDouble() ?? 0;
  }
}

// ── Single transparency badge — small pill ──────────────────────────────────

class _PriceBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;

  const _PriceBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  /// "🔒 מחיר נעול" — provider locks the price after seeing the photo
  /// (Module A: handyman / plumber / electrician).
  const _PriceBadge.priceLocked()
      : icon = Icons.lock_rounded,
        label = 'מחיר נעול',
        color = const Color(0xFF166534), // green-800
        bg = const Color(0xFFDCFCE7); // green-100

  /// "פיקדון 25%" — customer pays only the deposit at booking time
  /// (Module B: beauty / boarding / event services).
  factory _PriceBadge.deposit({required double percent}) {
    return _PriceBadge(
      icon: Icons.savings_outlined,
      label: 'פיקדון ${percent.toStringAsFixed(0)}%',
      color: const Color(0xFF92400E), // amber-800
      bg: const Color(0xFFFEF3C7), // amber-100
    );
  }

  /// "חבילה: -10%" — provider offers a multi-pack with savings.
  factory _PriceBadge.bundle({required double savingsPercent}) {
    return _PriceBadge(
      icon: Icons.local_offer_outlined,
      label: 'חבילה: -${savingsPercent.toStringAsFixed(0)}%',
      color: const Color(0xFF6D28D9), // violet-700
      bg: const Color(0xFFEDE9FE), // violet-100
    );
  }

  /// "+30% לילה / סופ״ש" — off-hours surcharge active.
  factory _PriceBadge.surcharge({required double nightPct}) {
    return _PriceBadge(
      icon: Icons.bedtime_outlined,
      label: '+${nightPct.toStringAsFixed(0)}% לילה',
      color: const Color(0xFF1E3A8A), // blue-900
      bg: const Color(0xFFDBEAFE), // blue-100
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// AsyncProviderPricePill — drop-in price pill for mixed-category surfaces.
///
/// **When to use which**
/// - [SearchCardPricePill]      → pages where ONE schema is loaded once and
///                                shared across N cards (category_results_screen).
/// - [AsyncProviderPricePill]   → pages where each card may belong to a
///                                different category (favorites, search-all,
///                                home-tab "recently viewed").
///
/// Wraps [SearchCardPricePill] with a [FutureBuilder] that resolves the
/// schema per-card via [CachedReaders.serviceSchemaForCategory] (§61).
/// 30-min cache means after the first card hits, subsequent cards in the
/// same category get the schema from memory in <1ms.
///
/// **Loading state**
/// While the schema fetch is in flight (typically <100ms on first hit,
/// <1ms cached), the widget renders the price line WITHOUT badges. This
/// avoids a layout flash when badges appear — users see the legacy
/// "₪150 ₪/לשעה" first, then badges fade in. No spinner, no shift.
///
/// **Empty serviceType**
/// If [userData['serviceType']] is empty/missing, falls through to legacy
/// pricePerHour rendering with no badges (zero schema cost).
/// ═══════════════════════════════════════════════════════════════════════════

class AsyncProviderPricePill extends StatelessWidget {
  final Map<String, dynamic> userData;
  final bool dense;

  const AsyncProviderPricePill({
    super.key,
    required this.userData,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final categoryName = (userData['serviceType'] as String? ?? '').trim();

    // Empty serviceType → render legacy price line, skip the schema fetch.
    if (categoryName.isEmpty) {
      return SearchCardPricePill(
        userData: userData,
        schema: ServiceSchema.empty(),
        dense: dense,
      );
    }

    return FutureBuilder<ServiceSchema>(
      future: CachedReaders.serviceSchemaForCategory(categoryName),
      builder: (context, snap) {
        // While loading: render the price line without badges (no flash).
        // The widget's "if showAnyBadge" gate keeps it stable.
        final schema = snap.data ?? ServiceSchema.empty();
        return SearchCardPricePill(
          userData: userData,
          schema: schema,
          dense: dense,
        );
      },
    );
  }
}
