import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// SystemAlertsBanner — surfaces unresolved system_alerts at the top of
/// the admin scaffold (CLAUDE.md §73).
///
/// **Why this exists**: §58 added `checkBackupHealth` which writes to
/// `system_alerts/backup_stale` whenever the daily Firestore backup hasn't
/// run within 26h. But until §73, no admin UI displayed those alerts —
/// if the backup broke silently, nobody would know until manual inspection.
///
/// **Behavior**:
///   - Streams `system_alerts` where `resolved != true`
///   - Critical alerts → red banner, warning alerts → amber
///   - Tap → modal with full details + "סמן כנפתר" action
///   - Empty stream / no alerts → renders SizedBox.shrink (zero height)
///   - Stream error → also renders SizedBox.shrink (defensive)
///
/// **Visual placement**: drop into AdminScreen above the IndexedStack so
/// the banner is visible regardless of which admin section is active.
///
/// **Future**: a Sentry / FCM-to-admin gateway should also fire on every
/// new critical alert. Not in scope for §73 — see §58 backup-health
/// notes for the deferred work.
/// ═══════════════════════════════════════════════════════════════════════════

class SystemAlertsBanner extends StatelessWidget {
  const SystemAlertsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system_alerts')
          .where('resolved', isEqualTo: false)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        // Defensive: stream error → no banner. Don't break the admin scaffold.
        if (snap.hasError || !snap.hasData) {
          return const SizedBox.shrink();
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        // Sort by severity: critical first, then warning, then info
        final sorted = [...docs]..sort((a, b) {
            const order = {'critical': 0, 'warning': 1, 'info': 2};
            final aSev = order[a.data()['severity']] ?? 3;
            final bSev = order[b.data()['severity']] ?? 3;
            return aSev.compareTo(bSev);
          });

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: sorted
              .map((doc) => _AlertRow(doc: doc))
              .toList(growable: false),
        );
      },
    );
  }
}

class _AlertRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _AlertRow({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final severity = (data['severity'] as String?) ?? 'warning';
    final title = (data['title'] as String?) ?? 'התראת מערכת';
    final message = (data['message'] as String?) ?? '';

    final isCritical = severity == 'critical';
    final bg = isCritical ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
    final fg = isCritical ? const Color(0xFF991B1B) : const Color(0xFF92400E);
    final icon = isCritical
        ? Icons.error_outline_rounded
        : Icons.warning_amber_rounded;

    return Material(
      color: bg,
      child: InkWell(
        onTap: () => _showDetails(context, doc, fg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: fg.withValues(alpha: 0.15), width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: fg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 12,
                          color: fg.withValues(alpha: 0.85),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left_rounded, color: fg, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Color fg,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AlertDetailsSheet(doc: doc, accent: fg),
    );
  }
}

class _AlertDetailsSheet extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Color accent;
  const _AlertDetailsSheet({required this.doc, required this.accent});

  @override
  State<_AlertDetailsSheet> createState() => _AlertDetailsSheetState();
}

class _AlertDetailsSheetState extends State<_AlertDetailsSheet> {
  final _noteCtrl = TextEditingController();
  bool _resolving = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() => _resolving = true);
    try {
      await widget.doc.reference.update({
        'resolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
        'resolutionNote': _noteCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בסגירת ההתראה: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final title = (data['title'] as String?) ?? 'התראת מערכת';
    final message = (data['message'] as String?) ?? '';
    final type = (data['type'] as String?) ?? '';
    final severity = (data['severity'] as String?) ?? 'warning';
    final ageHours = (data['ageHours'] as num?)?.toDouble();
    final lastStatus = (data['lastStatus'] as String?);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title row with severity badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: widget.accent,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    severity,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: widget.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (message.isNotEmpty)
              Text(
                message,
                style: const TextStyle(
                    fontSize: 14, color: Colors.black87, height: 1.5),
              ),
            const SizedBox(height: 16),
            // Metadata grid
            _kvRow('סוג', type),
            if (ageHours != null)
              _kvRow('זמן מהבדיקה האחרונה', '${ageHours.toStringAsFixed(1)} שעות'),
            if (lastStatus != null) _kvRow('סטטוס אחרון', lastStatus),
            const SizedBox(height: 20),
            // Note input
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                hintText: 'הערת סגירה (אופציונלי)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resolving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('סגור'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _resolving ? null : _resolve,
                    icon: _resolving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 16),
                    label: const Text('סמן כנפתר'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
