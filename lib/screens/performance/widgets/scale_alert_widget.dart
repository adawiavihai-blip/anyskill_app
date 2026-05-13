import 'package:flutter/material.dart';

import '../models/performance_metric.dart';
import '../models/scale_alert.dart';
import '../services/metrics_calculator.dart';
import '_design.dart';

/// The hero widget of the Performance Observatory. Reads the live
/// `PerformanceMetric` passed in and surfaces the top `ScaleAlert` as a
/// glass banner. Tapping the action button opens a sheet with the full
/// trigger chain (what triggered it, which Milestone file to run, other
/// alerts of lower severity).
///
/// This is the "self-upgrading dashboard" mechanism described in the
/// scaling_system spec — the tab tells the admin when to upgrade.
class ScaleAlertWidget extends StatelessWidget {
  final PerformanceMetric metric;

  const ScaleAlertWidget({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final alerts = ScaleAlertEngine.evaluate(metric);
    final top = alerts.first;
    final hasMore = alerts.length > 1;

    return PerfDesign.glassCard(
      padding: const EdgeInsets.all(22),
      borderColor: top.level.color.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LevelBadge(level: top.level),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      top.title,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: PerfDesign.textHi,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      top.message,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: PerfDesign.textMid,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (top.triggerDetail != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _TriggerPill(
                label: top.triggerDetail!,
                color: top.level.color,
              ),
            ),
          ],
          if (top.actionLabel != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (hasMore)
                  _GhostButton(
                    label: 'כל האזהרות (${alerts.length})',
                    onTap: () => _showAllAlertsSheet(context, alerts),
                  ),
                const Spacer(),
                _ActionButton(
                  label: top.actionLabel!,
                  color: top.level.color,
                  onTap: () => _showActionSheet(context, top),
                ),
              ],
            ),
          ] else if (hasMore) ...[
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _GhostButton(
                label: 'צפה בכל האזהרות (${alerts.length})',
                onTap: () => _showAllAlertsSheet(context, alerts),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showActionSheet(BuildContext context, ScaleAlert alert) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PerfDesign.bgDeep2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 40,
                height: 4,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _LevelBadge(level: alert.level),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      alert.title,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: PerfDesign.textHi,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                alert.message,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: PerfDesign.textMid,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              if (alert.milestoneFile != null) ...[
                const SizedBox(height: 16),
                _InfoRow(
                  label: 'קובץ להפעלה',
                  value: alert.milestoneFile!,
                ),
              ],
              _InfoRow(
                label: 'Milestone יעד',
                value: 'Milestone ${alert.targetMilestone}',
              ),
              if (alert.triggerDetail != null)
                _InfoRow(
                  label: 'גורם הטריגר',
                  value: alert.triggerDetail!,
                ),
              const SizedBox(height: 22),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: PerfDesign.indigo.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: PerfDesign.indigo.withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  'איך מפעילים? בקש מ-Claude Code: '
                  '"בצע את ${alert.milestoneFile ?? "Milestone ${alert.targetMilestone}"}"',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: PerfDesign.textMid,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllAlertsSheet(BuildContext context, List<ScaleAlert> alerts) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PerfDesign.bgDeep2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'כל האזהרות הפעילות',
                style: TextStyle(
                  color: PerfDesign.textHi,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 16),
              ...alerts.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AlertRow(alert: a),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final ScaleAlertLevel level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: level.color.withValues(alpha: 0.15),
        border: Border.all(color: level.color.withValues(alpha: 0.45)),
      ),
      child: Icon(level.icon, color: level.color, size: 22),
    );
  }
}

class _TriggerPill extends StatelessWidget {
  final String label;
  final Color color;
  const _TriggerPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.70)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded,
                color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: PerfDesign.textMid,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: PerfDesign.textHi,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(color: PerfDesign.textLo, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final ScaleAlert alert;
  const _AlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alert.level.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert.level.color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(alert.level.icon, color: alert.level.color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  alert.title,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: PerfDesign.textHi,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: PerfDesign.textMid,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                if (alert.triggerDetail != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    alert.triggerDetail!,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: alert.level.color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
