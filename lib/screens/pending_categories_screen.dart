import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/category_ai_service.dart';
import '../l10n/app_localizations.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
const _kPurple = Color(0xFF6366F1);
const _kGreen  = Color(0xFF10B981);
const _kRed    = Color(0xFFEF4444);
const _kAmber  = Color(0xFFF59E0B);

class PendingCategoriesScreen extends StatelessWidget {
  const PendingCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          AppLocalizations.of(context).pendingCatsTitle,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: Color(0xFF0F172A)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('categories_pending')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('שגיאה: ${snapshot.error}',
                    style: const TextStyle(color: _kRed)));
          }

          final docs = snapshot.data?.docs ?? [];
          final pending  = docs.where((d) => (d.data() as Map)['status'] == 'pending').toList();
          final reviewed = docs.where((d) => (d.data() as Map)['status'] != 'pending').toList();

          if (docs.isEmpty) {
            return _EmptyState();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              if (pending.isNotEmpty) ...[
                _SectionHeader(
                    label: AppLocalizations.of(context).pendingCatsSectionPending,
                    count: pending.length,
                    color: _kAmber),
                const SizedBox(height: 8),
                ...pending.map((d) => _PendingCard(
                      docId: d.id,
                      data: d.data() as Map<String, dynamic>,
                    )),
              ],
              if (reviewed.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionHeader(
                    label: AppLocalizations.of(context).pendingCatsSectionReviewed, count: reviewed.length, color: Colors.grey),
                const SizedBox(height: 8),
                ...reviewed.map((d) => _ReviewedCard(
                      data: d.data() as Map<String, dynamic>,
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.label, required this.count, required this.color});

  final String label;
  final int    count;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$count',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A))),
      ],
    );
  }
}

// ─── Pending card (with approve / reject buttons) ─────────────────────────────

class _PendingCard extends StatefulWidget {
  const _PendingCard({required this.docId, required this.data});

  final String               docId;
  final Map<String, dynamic> data;

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard> {
  bool _loading = false;

  Future<void> _act(String action) async {
    setState(() => _loading = true);
    try {
      await CategoryAiService.reviewPending(
          pendingId: widget.docId, action: action);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'approve' ? l10n.pendingCatsApproved : l10n.pendingCatsRejected),
          backgroundColor: action == 'approve' ? _kGreen : _kRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).pendingCatsErrorPrefix(e.toString())),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d          = widget.data;
    final catName    = d['suggestedCategoryName']    as String? ?? '—';
    final subName    = d['suggestedSubCategoryName'] as String?;
    final desc       = d['serviceDescription']       as String? ?? '—';
    final reasoning  = d['reasoning']                as String? ?? '—';
    final imagePrompt = d['imagePrompt']             as String?;
    final confidence = ((d['confidence'] as num? ?? 0) * 100).round();
    final keywords   = List<String>.from(d['keywords'] as List? ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _kAmber.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
              color: _kAmber.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Header row ─────────────────────────────────────────────────
            Row(
              children: [
                // Confidence badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: confidence >= 80
                        ? _kAmber.withValues(alpha: 0.12)
                        : _kRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('AI $confidence%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: confidence >= 80 ? _kAmber : _kRed)),
                ),
                const Spacer(),
                // Category name
                Text(catName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _kPurple)),
                const SizedBox(width: 6),
                const Icon(Icons.auto_awesome_rounded,
                    size: 16, color: _kAmber),
              ],
            ),

            if (subName != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(AppLocalizations.of(context).pendingCatsSubCategory(subName),
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600)),
              ),
            ],

            const SizedBox(height: 10),
            Container(height: 1, color: const Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // ── Detail rows ────────────────────────────────────────────────
            _DetailRow(label: AppLocalizations.of(context).pendingCatsProviderDesc, value: desc),
            const SizedBox(height: 6),
            _DetailRow(label: AppLocalizations.of(context).pendingCatsAiReason, value: reasoning),

            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 5,
                runSpacing: 5,
                children: keywords
                    .map((k) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kPurple.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(k,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _kPurple,
                                  fontWeight: FontWeight.w500)),
                        ))
                    .toList(),
              ),
            ],

            if (imagePrompt != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8FF),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: _kPurple.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.image_outlined,
                            size: 13, color: _kPurple),
                        const SizedBox(width: 4),
                        Text(AppLocalizations.of(context).pendingCatsImagePrompt,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _kPurple)),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(imagePrompt,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // ── Action buttons ─────────────────────────────────────────────
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      // Reject
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _act('reject'),
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: _kRed),
                          label: Text(AppLocalizations.of(context).pendingCatsReject,
                              style: const TextStyle(color: _kRed)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: _kRed.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Approve
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => _act('approve'),
                          icon: const Icon(Icons.check_rounded,
                              size: 16, color: Colors.white),
                          label: Text(AppLocalizations.of(context).pendingCatsApprove,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
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
}

// ─── Reviewed card (read-only, collapsed) ─────────────────────────────────────

class _ReviewedCard extends StatelessWidget {
  const _ReviewedCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status   = data['status'] as String? ?? '';
    final catName  = data['suggestedCategoryName'] as String? ?? '—';
    final isApproved = status == 'approved';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Icon(
            isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: isApproved ? _kGreen : _kRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(catName,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isApproved
                  ? _kGreen.withValues(alpha: 0.10)
                  : _kRed.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(isApproved ? AppLocalizations.of(context).pendingCatsStatusApproved : AppLocalizations.of(context).pendingCatsStatusRejected,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isApproved ? _kGreen : _kRed)),
          ),
        ],
      ),
    );
  }
}

// ─── Detail row ───────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF374151))),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(label,
              textAlign: TextAlign.left,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500)),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 64, color: _kGreen.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context).pendingCatsEmptyTitle,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          Text(AppLocalizations.of(context).pendingCatsEmptySubtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
