// ignore_for_file: use_build_context_synchronously
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colours & constants
// ─────────────────────────────────────────────────────────────────────────────
const _kRed    = Color(0xFFEF4444);
const _kGreen  = Color(0xFF10B981);
const _kOrange = Color(0xFFF59E0B);
const _kIndigo = Color(0xFF6366F1);
const _kBg     = Color(0xFFF5F7FA);

// ─────────────────────────────────────────────────────────────────────────────
// DisputeResolutionScreen — embeds as the "מחלוקות 🔴" admin tab
// ─────────────────────────────────────────────────────────────────────────────

class DisputeResolutionScreen extends StatelessWidget {
  const DisputeResolutionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('status', isEqualTo: 'disputed')
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        // Permissions error or network failure — never show infinite spinner
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 56, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'שגיאה בטעינת המחלוקות',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snap.error.toString(),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Sort client-side by disputeOpenedAt desc (avoids composite index)
        final docs = List.of(snap.data?.docs ?? [])
          ..sort((a, b) {
            final ta =
                ((a.data() as Map)['disputeOpenedAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                    0;
            final tb =
                ((b.data() as Map)['disputeOpenedAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                    0;
            return tb.compareTo(ta);
          });

        if (docs.isEmpty) {
          return const _EmptyState();
        }

        // ── Header metrics ─────────────────────────────────────────────
        double totalLocked = 0;
        for (final d in docs) {
          totalLocked +=
              ((d.data() as Map)['totalAmount'] as num? ?? 0).toDouble();
        }

        return Column(
          children: [
            _StatsBar(count: docs.length, totalLocked: totalLocked),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: docs.length,
                itemBuilder: (_, i) => _DisputeCard(
                  doc:     docs[i],
                  onTap: () => _showDetailSheet(context, docs[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDetailSheet(
      BuildContext context, QueryDocumentSnapshot doc) {
    showModalBottomSheet(
      context:        context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DisputeDetailSheet(doc: doc),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats bar at the top of the disputes list
// ─────────────────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int    count;
  final double totalLocked;

  const _StatsBar({required this.count, required this.totalLocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _kRed.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('$count', AppLocalizations.of(context).disputeOpenDisputes, Icons.gavel_rounded),
          Container(width: 1, height: 36, color: Colors.white30),
          _statItem(
            '₪${totalLocked.toStringAsFixed(0)}',
            AppLocalizations.of(context).disputeLockedEscrow,
            Icons.lock_rounded,
          ),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single dispute summary card
// ─────────────────────────────────────────────────────────────────────────────

class _DisputeCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final VoidCallback           onTap;

  const _DisputeCard({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final job    = doc.data() as Map<String, dynamic>;
    final amount = (job['totalAmount'] as num? ?? 0).toDouble();
    final ts     = (job['disputeOpenedAt'] as Timestamp?)?.toDate();
    final reason = job['disputeReason'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(18),
          border:       Border.all(color: const Color(0xFFFFE4E4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset:     const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: amount + date ─────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kRed.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.gavel_rounded,
                            color: _kRed, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₪${amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            AppLocalizations.of(context).disputeLockedEscrow,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (ts != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        DateFormat('dd/MM HH:mm', 'he').format(ts),
                        style: TextStyle(
                            color: _kRed.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // ── Parties ────────────────────────────────────────────
              _partyRow(
                icon:  Icons.person_outline_rounded,
                label: AppLocalizations.of(context).disputePartyCustomer,
                name:  job['customerName'] as String? ?? job['customerId'] as String? ?? '—',
              ),
              const SizedBox(height: 4),
              _partyRow(
                icon:  Icons.build_circle_outlined,
                label: AppLocalizations.of(context).disputePartyProvider,
                name:  job['expertName'] as String? ?? job['expertId'] as String? ?? '—',
              ),

              // ── Dispute reason snippet ─────────────────────────────
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color:        const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(
                        color: _kOrange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.format_quote_rounded,
                          color: _kOrange.withValues(alpha: 0.7),
                          size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reason,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[900],
                              fontStyle: FontStyle.italic,
                              height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Tap hint ────────────────────────────────────────────
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    AppLocalizations.of(context).disputeTapForDetails,
                    style: TextStyle(
                        fontSize: 11,
                        color: _kIndigo.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: _kIndigo.withValues(alpha: 0.7)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _partyRow(
      {required IconData icon, required String label, required String name}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 6),
        Text('$label: ',
            style: TextStyle(
                fontSize: 12, color: Colors.grey[500])),
        Text(name,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DisputeDetailSheet extends StatefulWidget {
  final QueryDocumentSnapshot doc;

  const _DisputeDetailSheet({required this.doc});

  @override
  State<_DisputeDetailSheet> createState() => _DisputeDetailSheetState();
}

class _DisputeDetailSheetState extends State<_DisputeDetailSheet> {
  final _noteCtrl  = TextEditingController();
  bool  _resolving = false;

  Map<String, dynamic> get _job => widget.doc.data() as Map<String, dynamic>;
  String get _jobId            => widget.doc.id;
  double get _amount     => (_job['totalAmount'] as num? ?? 0).toDouble();
  String get _chatRoomId => _job['chatRoomId'] as String? ?? '';

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── Resolution action ──────────────────────────────────────────────────────

  Future<void> _resolve(String resolution) async {
    if (_resolving) return;

    // Confirm with breakdown dialog
    final confirmed = await _showConfirmDialog(resolution);
    if (!confirmed || !mounted) return;

    setState(() => _resolving = true);

    try {
      await FirebaseFunctions.instance
          .httpsCallable('resolveDisputeAdmin')
          .call({
        'jobId':      _jobId,
        'resolution': resolution,
        'adminNote':  _noteCtrl.text.trim(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_resolvedMessage(resolution)),
          backgroundColor: _kGreen,
          behavior:    SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _resolving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('[${e.code}] ${e.message}'),
          backgroundColor: _kRed,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resolving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text(AppLocalizations.of(context).disputeErrorPrefix(e.toString())),
          backgroundColor: _kRed,
        ));
      }
    }
  }

  String _resolvedMessage(String r) {
    final l10n = AppLocalizations.of(context);
    switch (r) {
      case 'refund':  return l10n.disputeResolvedRefund;
      case 'release': return l10n.disputeResolvedRelease;
      default:        return l10n.disputeResolvedSplit;
    }
  }

  // ── Confirmation dialog with amount breakdown ──────────────────────────────

  Future<bool> _showConfirmDialog(String resolution) async {
    final l10n    = AppLocalizations.of(context);
    final feePct  = 0.10; // displayed estimate — real value read server-side
    final half    = _amount / 2;
    final netExp  = _amount * (1 - feePct);
    final halfNet = half   * (1 - feePct);

    String title, body;
    Color  headerColor;

    switch (resolution) {
      case 'refund':
        title       = l10n.disputeConfirmRefund;
        body        = l10n.disputeRefundBody(
          _amount.toStringAsFixed(0),
          _job['customerName'] ?? l10n.disputePartyCustomer,
        );
        headerColor = _kRed;
        break;
      case 'release':
        title       = l10n.disputeConfirmRelease;
        body        = l10n.disputeReleaseBody(
          netExp.toStringAsFixed(0),
          _job['expertName'] ?? l10n.requestsDefaultExpert,
          (feePct * 100).toStringAsFixed(0),
        );
        headerColor = _kGreen;
        break;
      default: // split
        title       = l10n.disputeConfirmSplit;
        body        = l10n.disputeSplitBody(
          half.toStringAsFixed(0),
          halfNet.toStringAsFixed(0),
          (half - halfNet).toStringAsFixed(0),
        );
        headerColor = _kOrange;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:       RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color:  headerColor.withValues(alpha: 0.12),
                shape:  BoxShape.circle,
              ),
              child: Icon(Icons.gavel_rounded, color: headerColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body,
                style: const TextStyle(fontSize: 14, height: 1.6)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF856404)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(ctx).disputeIrreversible,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF856404)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: headerColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx).confirm,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reason    = _job['disputeReason']    as String? ?? '';
    final adminNote = _job['adminNote']        as String? ?? '';
    final ts        = (_job['disputeOpenedAt'] as Timestamp?)?.toDate();

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Container(
        height:      MediaQuery.of(context).size.height * 0.92,
        decoration:  const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            const _SheetHandle(),

            // ── Title ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:  _kRed.withValues(alpha: 0.10),
                      shape:  BoxShape.circle,
                    ),
                    child: const Icon(Icons.gavel_rounded,
                        color: _kRed, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context).disputeArbitrationCenter,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold)),
                      Text(
                        '${AppLocalizations.of(context).disputeIdPrefix} ${_jobId.substring(0, 8)}…  •  '
                        '₪${_amount.toStringAsFixed(0)} ${AppLocalizations.of(context).disputeLockedSuffix}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Scrollable body ────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20, right: 20, top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Parties ──────────────────────────────────
                    _sectionHeader(
                        Icons.people_alt_rounded, AppLocalizations.of(context).disputePartiesSection),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: _PartyCard(
                        icon:  Icons.person_rounded,
                        role:  AppLocalizations.of(context).disputePartyCustomer,
                        name:  _job['customerName'] as String? ?? '—',
                        color: _kIndigo,
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _PartyCard(
                        icon:  Icons.build_circle_rounded,
                        role:  AppLocalizations.of(context).disputePartyProvider,
                        name:  _job['expertName'] as String? ?? '—',
                        color: _kGreen,
                      )),
                    ]),
                    const SizedBox(height: 16),

                    // ── Dispute reason ───────────────────────────
                    _sectionHeader(
                        Icons.report_problem_rounded, AppLocalizations.of(context).disputeReasonSection),
                    const SizedBox(height: 8),
                    if (reason.isNotEmpty)
                      _ReasonCard(reason: reason, openedAt: ts)
                    else
                      Text(AppLocalizations.of(context).disputeNoReason,
                          style:
                              TextStyle(color: Colors.grey[500])),
                    const SizedBox(height: 16),

                    // ── Chat history ─────────────────────────────
                    _sectionHeader(
                        Icons.chat_bubble_outline_rounded,
                        AppLocalizations.of(context).disputeChatHistory),
                    const SizedBox(height: 8),
                    _ChatHistorySection(chatRoomId: _chatRoomId),
                    const SizedBox(height: 20),

                    // ── Admin note ───────────────────────────────
                    _sectionHeader(
                        Icons.sticky_note_2_outlined,
                        AppLocalizations.of(context).disputeAdminNote),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteCtrl,
                      maxLines:   3,
                      textDirection: ui.TextDirection.rtl,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).disputeAdminNoteHint,
                        filled:   true,
                        fillColor: _kBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:   BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    if (adminNote.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context).disputeExistingNote(adminNote),
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // ── Action buttons ───────────────────────────
                    _sectionHeader(
                        Icons.balance_rounded, AppLocalizations.of(context).disputeActionsSection),
                    const SizedBox(height: 12),
                    if (_resolving)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 10),
                              Text(AppLocalizations.of(context).disputeResolving),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      _ActionButton(
                        icon:    Icons.undo_rounded,
                        label:   AppLocalizations.of(context).disputeRefundLabel,
                        sublabel: AppLocalizations.of(context).disputeRefundSublabel(_amount.toStringAsFixed(0)),
                        color:   _kRed,
                        onTap:   () => _resolve('refund'),
                      ),
                      const SizedBox(height: 10),
                      _ActionButton(
                        icon:    Icons.check_circle_rounded,
                        label:   AppLocalizations.of(context).disputeReleaseLabel,
                        sublabel: AppLocalizations.of(context).disputeReleaseSublabel((_amount * 0.9).toStringAsFixed(0)),
                        color:   _kGreen,
                        onTap:   () => _resolve('release'),
                      ),
                      const SizedBox(height: 10),
                      _ActionButton(
                        icon:    Icons.balance_rounded,
                        label:   AppLocalizations.of(context).disputeSplitLabel,
                        sublabel: AppLocalizations.of(context).disputeSplitSublabel((_amount / 2).toStringAsFixed(0)),
                        color:   _kOrange,
                        onTap:   () => _resolve('split'),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 16, color: _kIndigo),
          const SizedBox(width: 7),
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _kIndigo)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PartyCard extends StatelessWidget {
  final IconData icon;
  final String   role;
  final String   name;
  final Color    color;

  const _PartyCard({
    required this.icon,
    required this.role,
    required this.name,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(role,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 3),
            Text(name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines:  2,
                overflow:  TextOverflow.ellipsis),
          ],
        ),
      );
}

class _ReasonCard extends StatelessWidget {
  final String    reason;
  final DateTime? openedAt;

  const _ReasonCard({required this.reason, this.openedAt});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: _kOrange.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.report_problem_rounded,
                    color: _kOrange.withValues(alpha: 0.8), size: 16),
                const SizedBox(width: 6),
                if (openedAt != null)
                  Text(
                    AppLocalizations.of(context).disputeOpenedAt(DateFormat('dd/MM/yyyy HH:mm', 'he').format(openedAt!)),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[700]),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(reason,
                style: TextStyle(
                    fontSize: 14,
                    color:     Colors.orange[900],
                    fontStyle: FontStyle.italic,
                    height:    1.5)),
          ],
        ),
      );
}

// ── Chat history ──────────────────────────────────────────────────────────────

class _ChatHistorySection extends StatelessWidget {
  final String chatRoomId;

  const _ChatHistorySection({required this.chatRoomId});

  @override
  Widget build(BuildContext context) {
    if (chatRoomId.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kBg, borderRadius: BorderRadius.circular(12)),
        child: Text(AppLocalizations.of(context).disputeNoChatId,
            style: const TextStyle(color: Colors.grey)),
      );
    }

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kBg, borderRadius: BorderRadius.circular(12)),
            child: Text(AppLocalizations.of(context).disputeNoMessages,
                style: const TextStyle(color: Colors.grey)),
          );
        }

        final msgs = snap.data!.docs.reversed.toList();

        return Container(
          decoration: BoxDecoration(
            color:        _kBg,
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: msgs.map((m) {
              final d    = m.data() as Map<String, dynamic>;
              final text = d['message'] as String? ?? '';
              final type = d['type']    as String? ?? 'text';
              final ts   = (d['timestamp'] as Timestamp?)?.toDate();
              final sid  = d['senderId']  as String? ?? '';
              final isSystem = sid == 'system';

              if (isSystem) {
                return _SystemMsgRow(text: text, ts: ts);
              }

              return _ChatMsgRow(
                text:      type == 'text' ? text : _typeLabel(type, context),
                senderId:  sid,
                ts:        ts,
                isSystem:  false,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _typeLabel(String type, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'image':    return l10n.disputeTypeImage;
      case 'location': return l10n.disputeTypeLocation;
      case 'audio':    return l10n.disputeTypeAudio;
      default:         return type;
    }
  }
}

class _ChatMsgRow extends StatelessWidget {
  final String    text;
  final String    senderId;
  final DateTime? ts;
  final bool      isSystem;

  const _ChatMsgRow({
    required this.text,
    required this.senderId,
    required this.ts,
    required this.isSystem,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius:          14,
            backgroundColor: _kIndigo.withValues(alpha: 0.15),
            child: Text(
              senderId.isNotEmpty ? senderId[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 11,
                  color:    _kIndigo,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        senderId.length > 8
                            ? '${senderId.substring(0, 8)}…'
                            : senderId,
                        style: TextStyle(
                            fontSize:   10,
                            color:      Colors.grey[400],
                            fontFamily: 'monospace'),
                      ),
                    ),
                    if (ts != null)
                      Text(
                        DateFormat('HH:mm', 'he').format(ts!),
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[400]),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(text,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                    maxLines:  4,
                    overflow:  TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemMsgRow extends StatelessWidget {
  final String    text;
  final DateTime? ts;

  const _SystemMsgRow({required this.text, this.ts});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(AppLocalizations.of(context).disputeSystemSender,
                style:
                    TextStyle(fontSize: 10, color: Colors.grey[600])),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   sublabel;
  final Color    color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(
                color: color.withValues(alpha: 0.30), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width:  44,
                height: 44,
                decoration: BoxDecoration(
                  color:  color.withValues(alpha: 0.12),
                  shape:  BoxShape.circle,
                ),
                child:  Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    const SizedBox(height: 2),
                    Text(sublabel,
                        style: TextStyle(
                            fontSize: 12,
                            color: color.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded,
                  color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      );
}

// ── Misc helpers ─────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color:        Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline_rounded,
                  size: 64, color: _kGreen),
            ),
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).disputeEmptyTitle,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context).disputeEmptySubtitle,
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
}
