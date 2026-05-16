import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/pricing_model.dart';
import '../../../services/service_architect.dart';
import 'tokens.dart';

/// Service-tier picker + optional add-ons panel.
///
/// Extracted from `expert_profile_screen.dart` in §81 (C.3). Stateless:
/// receives `selectedServiceIndex` + `selectedAddOnIndices` from the parent
/// and emits taps via [onServiceSelected] / [onAddOnToggle]. The parent's
/// State class owns the selection state because the bottom bar reads it
/// to compute the live total price.
class ServiceMenu extends StatelessWidget {
  const ServiceMenu({
    super.key,
    required this.data,
    required this.selectedServiceIndex,
    required this.selectedAddOnIndices,
    required this.onServiceSelected,
    required this.onAddOnToggle,
  });

  final Map<String, dynamic> data;
  final int selectedServiceIndex;
  final Set<int> selectedAddOnIndices;
  final ValueChanged<int> onServiceSelected;
  final ValueChanged<int> onAddOnToggle;

  /// Pure helper — exposed publicly so the booking bottom bar can re-derive
  /// the same `services` list for live total price computation.
  static List<Map<String, dynamic>> deriveServices(
      double pricePerHour, String category) {
    final templates = ServiceArchitect.templatesFor(category);
    return templates
        .map((t) => {
              'title': t.title,
              'subtitle': t.subtitle,
              'unitLabel': t.unitLabel,
              'unitIcon': t.unitIcon,
              'price': (pricePerHour * t.multiplier).roundToDouble(),
            })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final pricing = PricingModel.fromFirestore(data);
    final category = data['serviceType'] as String? ?? '';
    final services = deriveServices(pricing.basePrice, category);

    return Column(
      children: [
        ...List.generate(services.length, (i) {
          final svc = services[i];
          final selected = i == selectedServiceIndex;
          final svcPrice = svc['price'] as double;

          return GestureDetector(
            onTap: () => onServiceSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? ExpertProfileTokens.purpleSoft
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? ExpertProfileTokens.purple
                      : Colors.grey.shade200,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? ExpertProfileTokens.purple
                          : Colors.transparent,
                      border: Border.all(
                          color: selected
                              ? ExpertProfileTokens.purple
                              : Colors.grey.shade300,
                          width: 2),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 12)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: selected
                                ? ExpertProfileTokens.purple
                                    .withValues(alpha: 0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(svc['unitLabel'] as String,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: selected
                                      ? ExpertProfileTokens.purple
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Text(svc['title'] as String,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: selected
                                    ? ExpertProfileTokens.purple
                                    : Colors.black87)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('₪${svcPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: ExpertProfileTokens.purple,
                          fontWeight: FontWeight.w900,
                          fontSize: 15)),
                ],
              ),
            ),
          );
        }),
        if (pricing.addOns.isNotEmpty) ...[
          const SizedBox(height: 16),
          _AddOnsPanel(
            pricing: pricing,
            selectedAddOnIndices: selectedAddOnIndices,
            onToggle: onAddOnToggle,
          ),
        ],
      ],
    );
  }
}

class _AddOnsPanel extends StatelessWidget {
  const _AddOnsPanel({
    required this.pricing,
    required this.selectedAddOnIndices,
    required this.onToggle,
  });

  final PricingModel pricing;
  final Set<int> selectedAddOnIndices;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExpertProfileTokens.purpleSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                ExpertProfileTokens.purple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(AppLocalizations.of(context).expOptionalAddons,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 6),
              const Icon(Icons.add_circle_outline_rounded,
                  size: 16, color: ExpertProfileTokens.purple),
            ],
          ),
          const SizedBox(height: 10),
          ...pricing.addOns.asMap().entries.map((entry) {
            final i = entry.key;
            final ao = entry.value;
            final checked = selectedAddOnIndices.contains(i);
            return GestureDetector(
              onTap: () => onToggle(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: checked
                      ? ExpertProfileTokens.purple
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: checked
                        ? ExpertProfileTokens.purple
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: checked
                            ? Colors.white
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: checked
                              ? Colors.white
                              : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: checked
                          ? const Icon(Icons.check_rounded,
                              color: ExpertProfileTokens.purple, size: 13)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '+₪${ao.price.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: checked
                            ? Colors.white
                            : ExpertProfileTokens.purple,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      ao.title,
                      style: TextStyle(
                        color: checked ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
