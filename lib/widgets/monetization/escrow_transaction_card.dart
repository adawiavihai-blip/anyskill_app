import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'design_tokens.dart';

enum EscrowStage { paid, inProgress, released }

/// A single escrow transaction card for section 8 — with a 3-stage
/// progress indicator and three actions (release / refund / more).
class EscrowTransactionCard extends StatelessWidget {
  const EscrowTransactionCard({
    super.key,
    required this.jobId,
    required this.data,
    required this.onRelease,
    required this.onRefund,
    this.onMore,
  });

  final String jobId;
  final Map<String, dynamic> data;
  final Future<void> Function() onRelease;
  final Future<void> Function() onRefund;
  final VoidCallback? onMore;

  EscrowStage get _stage {
    final status = (data['status'] ?? '').toString();
    if (status == 'expert_completed') return EscrowStage.released;
    if (status == 'paid_escrow') {
      // "in_progress" if the provider has accepted / marked on-the-way.
      if (data['workStartedAt'] != null || data['expertOnWay'] == true) {
        return EscrowStage.inProgress;
      }
      return EscrowStage.paid;
    }
    return EscrowStage.paid;
  }

  String get _customer => (data['customerName'] ?? '—').toString();
  String get _expert   => (data['expertName']   ?? '—').toString();
  double get _amount =>
      ((data['totalAmount'] ?? 0) as num).toDouble();

  String get _createdAtLabel {
    final ts = data['createdAt'];
    if (ts is Timestamp) return DateFormat('dd/MM HH:mm', 'he').format(ts.toDate());
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MonetizationTokens.warning.withValues(alpha: 0.05),
        border: Border.all(
            color: MonetizationTokens.warningLight, width: 0.5),
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '₪${_amount.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_customer ← $_expert',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    Text(_createdAtLabel,
                        style: const TextStyle(
                            fontSize: 11,
                            color: MonetizationTokens.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StagesBar(stage: _stage),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onRelease(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MonetizationTokens.success,
                    side: BorderSide(
                        color: MonetizationTokens.successBorder, width: 0.5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 14),
                  label: const Text('שחרר לספק',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onRefund(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MonetizationTokens.danger,
                    side: const BorderSide(
                        color: MonetizationTokens.dangerBorder, width: 0.5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.undo_rounded, size: 14),
                  label: const Text('החזר ללקוח',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StagesBar extends StatelessWidget {
  const _StagesBar({required this.stage});
  final EscrowStage stage;

  @override
  Widget build(BuildContext context) {
    final paidDone   = true; // always reached by the time the row renders
    final workDone   = stage != EscrowStage.paid;
    final releaseDone = stage == EscrowStage.released;
    return Row(
      children: [
        _StagePill(label: 'שולם', done: paidDone),
        const SizedBox(width: 4),
        _StagePill(label: 'בביצוע', done: workDone),
        const SizedBox(width: 4),
        _StagePill(label: 'שחרור', done: releaseDone),
      ],
    );
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill({required this.label, required this.done});
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: done
              ? MonetizationTokens.success
              : MonetizationTokens.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: done ? Colors.white : MonetizationTokens.textTertiary,
          ),
        ),
      ),
    );
  }
}
