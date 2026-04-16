import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Snapshot of simulation results rendered by [CommissionSimulator].
/// Stage 2 — producer side (Cloud Function `simulateCommissionChange`)
/// is stage 5 work. For now this comes from a cheap client-side heuristic
/// so the UI can show live updates as the admin drags sliders.
class SimulationResult {
  final double projectedRevenue;
  final double revenueDelta;
  final int providersAtChurnRisk;
  final int totalProviders;
  final double acceptanceRate; // 0-1
  final double projectedGmv;
  final String aiOpinion;

  const SimulationResult({
    required this.projectedRevenue,
    required this.revenueDelta,
    required this.providersAtChurnRisk,
    required this.totalProviders,
    required this.acceptanceRate,
    required this.projectedGmv,
    required this.aiOpinion,
  });

  factory SimulationResult.empty() => const SimulationResult(
        projectedRevenue: 0,
        revenueDelta: 0,
        providersAtChurnRisk: 0,
        totalProviders: 0,
        acceptanceRate: 1.0,
        projectedGmv: 0,
        aiOpinion: '—',
      );
}

/// Right-hand dark "Live Simulator" column in section 5.
class CommissionSimulator extends StatelessWidget {
  const CommissionSimulator({
    super.key,
    required this.newFeePct,
    required this.result,
  });

  final double newFeePct;
  final SimulationResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MonetizationTokens.surfaceDark,
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('סימולטור השפעה',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  )),
              const SizedBox(width: 6),
              MonetizationPill(
                label: 'LIVE',
                background: MonetizationTokens.warningVivid,
                foreground: MonetizationTokens.warningDarker,
                fontSize: 9,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'לפני שמבצעים שינוי',
            style: TextStyle(
              fontSize: 11,
              color: MonetizationTokens.textOnDarkDim,
            ),
          ),
          const SizedBox(height: 14),
          // Big pct card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MonetizationTokens.surfaceDarker,
              borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('אם תשנה עמלה ל-',
                    style: TextStyle(
                      fontSize: 10,
                      color: MonetizationTokens.textOnDarkDim,
                    )),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      newFeePct.toStringAsFixed(
                          newFeePct == newFeePct.toInt() ? 0 : 1),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('%',
                        style: TextStyle(
                          fontSize: 14,
                          color: MonetizationTokens.textOnDarkDim,
                        )),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SimRow(
            label: 'הכנסה צפויה',
            value: '₪${result.projectedRevenue.toStringAsFixed(0)}',
            delta: result.revenueDelta == 0
                ? null
                : '(${result.revenueDelta >= 0 ? '+' : ''}₪${result.revenueDelta.toStringAsFixed(0)})',
            valueColor: MonetizationTokens.successVivid,
          ),
          _SimRow(
            label: 'ספקים בסיכון churn',
            value: '${result.providersAtChurnRisk}',
            delta: '(מתוך ${result.totalProviders})',
            valueColor: MonetizationTokens.dangerBorder,
          ),
          _SimRow(
            label: 'אחוז קבלה',
            value: '${(result.acceptanceRate * 100).toStringAsFixed(0)}%',
            valueColor: MonetizationTokens.warningVivid,
          ),
          _SimRow(
            label: 'GMV צפוי',
            value: '₪${result.projectedGmv.toStringAsFixed(0)}',
            valueColor: Colors.white,
          ),
          const SizedBox(height: 12),
          const Divider(
            color: MonetizationTokens.borderDark,
            thickness: 0.5,
            height: 1,
          ),
          const SizedBox(height: 10),
          const Text('דעת ה-AI',
              style: TextStyle(
                fontSize: 10,
                color: MonetizationTokens.textTertiary,
              )),
          const SizedBox(height: 4),
          Text(result.aiOpinion,
              style: const TextStyle(
                fontSize: 11,
                height: 1.6,
                color: MonetizationTokens.textOnDarkFaint,
              )),
        ],
      ),
    );
  }
}

class _SimRow extends StatelessWidget {
  const _SimRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.delta,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 12,
                color: MonetizationTokens.textOnDarkDim,
              )),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  )),
              if (delta != null) ...[
                const SizedBox(width: 4),
                Text(delta!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: MonetizationTokens.textOnDarkDim,
                    )),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
