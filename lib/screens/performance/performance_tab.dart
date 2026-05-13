import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'models/performance_metric.dart';
import 'services/performance_service.dart';
import 'widgets/_design.dart';
import 'widgets/business_impact_widget.dart';
import 'widgets/cost_projection_widget.dart';
import 'widgets/freshness_dot.dart';
import 'widgets/golden_signals_widget.dart';
import 'widgets/nova_ai_chat_widget.dart';
import 'widgets/scale_alert_widget.dart';
import 'widgets/scale_readiness_widget.dart';

/// Performance Observatory · Milestone 1 (Option A).
///
/// Renders the premium dark glassmorphism tab. Reads from
/// `performance_metrics/current` (written by `updateMetricsSnapshot` CF
/// every 5 minutes) and drives ALL widgets off a single StreamBuilder
/// to minimize Firestore reads.
///
/// Scaling behavior: when DAU/cost/latency triggers fire, the Scale Alert
/// Widget surfaces the recommended next Milestone — the admin just tells
/// Claude Code which file to run.
class PerformanceTab extends StatelessWidget {
  const PerformanceTab({super.key});

  // Infra flags — update these when a Milestone completes (per CURRENT_STATUS.md).
  static const bool _hasRedis = false;
  static const bool _hasBigQuery = false;
  static const bool _hasSharding = false;
  static const bool _hasMultiRegion = false;
  static const bool _hasAiAgents = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PerfDesign.bgDeep1,
        body: Stack(
          children: [
            // Base gradient
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: PerfDesign.pageGradient),
              ),
            ),
            // Ambient orbs (5 decorative radial gradients)
            PerfDesign.orb(
              left: -80,
              top: -60,
              size: 320,
              color: PerfDesign.indigo,
            ),
            PerfDesign.orb(
              left: 220,
              top: 180,
              size: 260,
              color: PerfDesign.purple,
            ),
            PerfDesign.orb(
              left: -120,
              top: 520,
              size: 300,
              color: PerfDesign.pink,
            ),
            PerfDesign.orb(
              left: 280,
              top: 820,
              size: 260,
              color: PerfDesign.orange,
            ),
            PerfDesign.orb(
              left: -60,
              top: 1180,
              size: 260,
              color: PerfDesign.statusGreen,
            ),
            // Content
            StreamBuilder<PerformanceMetric>(
              stream: PerformanceService.instance.streamCurrent(),
              builder: (context, snap) {
                final metric = snap.data ?? PerformanceMetric.empty();
                final loading = snap.connectionState == ConnectionState.waiting;

                return RefreshIndicator(
                  onRefresh: () async {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 500),
                    );
                  },
                  color: PerfDesign.indigo,
                  backgroundColor: PerfDesign.bgDeep2,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 18, 16, 8),
                            child: _Header(metric: metric, loading: loading),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 6, 16, 80),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate.fixed([
                            if (metric.lastUpdated == null) ...[
                              const WaitingForSnapshotBanner(),
                              const SizedBox(height: 14),
                            ],
                            ScaleAlertWidget(metric: metric),
                            const SizedBox(height: 14),
                            BusinessImpactWidget(metric: metric),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (ctx, c) {
                                if (c.maxWidth >= 900) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ScaleReadinessWidget(
                                          hasRedis: _hasRedis,
                                          hasBigQuery: _hasBigQuery,
                                          hasSharding: _hasSharding,
                                          hasMultiRegion: _hasMultiRegion,
                                          hasAiAgents: _hasAiAgents,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: CostProjectionWidget(
                                            metric: metric),
                                      ),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    const ScaleReadinessWidget(
                                      hasRedis: _hasRedis,
                                      hasBigQuery: _hasBigQuery,
                                      hasSharding: _hasSharding,
                                      hasMultiRegion: _hasMultiRegion,
                                      hasAiAgents: _hasAiAgents,
                                    ),
                                    const SizedBox(height: 14),
                                    CostProjectionWidget(metric: metric),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            GoldenSignalsWidget(metric: metric),
                            const SizedBox(height: 14),
                            const NovaAiChatWidget(),
                            const SizedBox(height: 14),
                            _Footer(metric: metric),
                          ]),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PerformanceMetric metric;
  final bool loading;
  const _Header({required this.metric, required this.loading});

  @override
  Widget build(BuildContext context) {
    final last = metric.lastUpdated;
    final lastText = last == null
        ? 'ממתין לעדכון ראשון…'
        : 'עודכן ${DateFormat('HH:mm', 'he').format(last)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [PerfDesign.indigo, PerfDesign.purple],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: PerfDesign.indigo.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.satellite_alt_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            FreshnessDot(lastUpdated: metric.lastUpdated),
            const SizedBox(width: 8),
            Text(
              loading ? 'מתחבר…' : lastText,
              style: TextStyle(
                color: PerfDesign.textLo,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Performance Observatory',
                  style: TextStyle(
                    color: PerfDesign.textHi,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Milestone 1 · Premium + Nova AI',
                  style: TextStyle(
                    color: PerfDesign.purple,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  final PerformanceMetric metric;
  const _Footer({required this.metric});

  @override
  Widget build(BuildContext context) {
    return PerfDesign.glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.shield_outlined,
              color: PerfDesign.textLo, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'מטא · updateMetricsSnapshot מתעדכן כל 5 דקות · '
              'Gemini 2.5 Flash Lite · Firestore בלבד (ללא תשתית חדשה)',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: PerfDesign.textLo,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
