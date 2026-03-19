import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── Colors ────────────────────────────────────────────────────────────────────
const _kIndigo  = Color(0xFF6366F1);
const _kGreen   = Color(0xFF10B981);
const _kAmber   = Color(0xFFF59E0B);
const _kRed     = Color(0xFFEF4444);

/// Admin tab: Registration Funnel & Abandoned Lead Tracker.
///
/// Funnel data source: `activity_log` docs with type `reg_step_1..5`
/// written by [SignUpScreen] at each stage.
///
/// Abandoned leads source: `incomplete_registrations/{sessionId}` docs
/// written by [SignUpScreen] as users type into the form.
class RegistrationFunnelTab extends StatefulWidget {
  const RegistrationFunnelTab({super.key});

  @override
  State<RegistrationFunnelTab> createState() => _RegistrationFunnelTabState();
}

// ── Data model ────────────────────────────────────────────────────────────────
class _FunnelData {
  const _FunnelData({required this.counts, required this.abandoned});
  final Map<String, int>              counts;
  final List<QueryDocumentSnapshot>   abandoned;
}

class _RegistrationFunnelTabState extends State<RegistrationFunnelTab> {
  int _dayFilter = 30;
  final Set<String> _pinging = {};
  Future<_FunnelData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // ── Load funnel + abandoned leads ──────────────────────────────────────────
  Future<_FunnelData> _load() async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: _dayFilter)),
    );

    // 1. Funnel events — query activity_log for all reg_step types.
    //    Date filter is applied client-side to avoid composite index.
    final snap = await FirebaseFirestore.instance
        .collection('activity_log')
        .where('type', whereIn: [
          'reg_step_1',
          'reg_step_2',
          'reg_step_3',
          'reg_step_4',
          'reg_step_5',
        ])
        .limit(2000)
        .get();

    final stepSessions = <String, Set<String>>{
      'reg_step_1': {},
      'reg_step_2': {},
      'reg_step_3': {},
      'reg_step_4': {},
      'reg_step_5': {},
    };

    for (final doc in snap.docs) {
      final d  = doc.data();
      final ts = d['createdAt'] as Timestamp?;
      if (ts == null || ts.compareTo(cutoff) < 0) continue;
      final type = d['type'] as String? ?? '';
      // Use sessionId for deduplication; fall back to doc ID
      final sid  = (d['sessionId'] as String?)?.isNotEmpty == true
          ? d['sessionId'] as String
          : doc.id;
      stepSessions[type]?.add(sid);
    }

    final counts = stepSessions.map((k, v) => MapEntry(k, v.length));

    // 2. Abandoned leads from incomplete_registrations.
    //    No orderBy — sort client-side to avoid composite index requirement.
    final leadsSnap = await FirebaseFirestore.instance
        .collection('incomplete_registrations')
        .limit(300)
        .get();

    final abandoned = leadsSnap.docs.where((d) {
      final m  = d.data();
      final ts = m['startedAt'] as Timestamp?;
      if (ts == null || ts.compareTo(cutoff) < 0) return false;
      return m['isRegistrationComplete'] != true &&
          ((m['email'] as String? ?? '').isNotEmpty ||
           (m['phone'] as String? ?? '').isNotEmpty);
    }).toList()
      ..sort((a, b) {
        final ta = (a.data()['lastUpdatedAt'] as Timestamp?)?.toDate() ??
                   DateTime(2000);
        final tb = (b.data()['lastUpdatedAt'] as Timestamp?)?.toDate() ??
                   DateTime(2000);
        return tb.compareTo(ta); // newest first
      });

    return _FunnelData(counts: counts, abandoned: abandoned);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FunnelData>(
      future: _future,
      builder: (context, snapshot) {
        // ── Error state ─────────────────────────────────────────────────────
        if (snapshot.hasError) {
          return _ErrorState(
            error: snapshot.error.toString(),
            onRetry: () => setState(() => _future = _load()),
          );
        }

        // ── Loading state ───────────────────────────────────────────────────
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data     = snapshot.data!;
        final counts   = data.counts;
        final abandoned = data.abandoned;

        // ── Funnel steps definition ─────────────────────────────────────────
        final steps = [
          _FunnelStep('פתח הרשמה',  counts['reg_step_1'] ?? 0, _totalSessions(counts), const Color(0xFF6366F1)),
          _FunnelStep('מילא שם',    counts['reg_step_2'] ?? 0, _totalSessions(counts), const Color(0xFF8B5CF6)),
          _FunnelStep('הזין אימייל', counts['reg_step_3'] ?? 0, _totalSessions(counts), const Color(0xFFF59E0B)),
          _FunnelStep('לחץ הרשמה',  counts['reg_step_4'] ?? 0, _totalSessions(counts), const Color(0xFFEF4444)),
          _FunnelStep('הושלם',      counts['reg_step_5'] ?? 0, _totalSessions(counts), const Color(0xFF10B981)),
        ];

        final total     = steps[0].count;
        final completed = steps[4].count;
        final convRate  = total == 0 ? 0.0 : completed / total * 100;

        // ── Drop-off hotspot ────────────────────────────────────────────────
        int hotspotIdx = 1;
        int maxDrop    = 0;
        for (int i = 1; i < steps.length; i++) {
          final drop = steps[i - 1].count - steps[i].count;
          if (drop > maxDrop) { maxDrop = drop; hotspotIdx = i; }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📊 Registration Funnel',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('מעקב שלבי הרשמה ולידים פתוחים',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  // Refresh button
                  IconButton(
                    onPressed: () => setState(() => _future = _load()),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'רענן',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const SizedBox(width: 4),
                  _DayFilterChip(
                    value: _dayFilter,
                    options: const [7, 14, 30, 90],
                    onChanged: (v) => setState(() {
                      _dayFilter = v;
                      _future    = _load();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── KPI cards ─────────────────────────────────────────────
              Row(children: [
                _KpiCard('סשנים',  total.toString(),     Icons.person_add_alt_1_rounded, _kIndigo),
                const SizedBox(width: 10),
                _KpiCard('הושלמו', completed.toString(), Icons.check_circle_rounded,    _kGreen),
                const SizedBox(width: 10),
                _KpiCard('נטשו',   abandoned.length.toString(), Icons.exit_to_app_rounded, _kRed),
                const SizedBox(width: 10),
                _KpiCard('המרה',   '${convRate.toStringAsFixed(0)}%', Icons.trending_up_rounded, _kAmber),
              ]),
              const SizedBox(height: 20),

              // ── Funnel bars ───────────────────────────────────────────
              _SectionHeader('🔽 משפך ההמרה'),
              const SizedBox(height: 4),

              if (total == 0)
                _EmptyState(
                  icon: Icons.analytics_outlined,
                  label: 'אין נתוני הרשמה עדיין',
                  sub: 'הנתונים יופיעו כאשר משתמשים יפתחו את מסך ההרשמה',
                )
              else ...[
                const SizedBox(height: 8),
                ...steps.asMap().entries.map((e) => _FunnelBar(
                      step:      e.value,
                      isHotspot: e.key == hotspotIdx,
                      prevCount: e.key > 0 ? steps[e.key - 1].count : null,
                    )),
                const SizedBox(height: 8),

                // ── Hotspot callout ──────────────────────────────────
                if (maxDrop > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kRed.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'נקודת נטישה עיקרית: ${steps[hotspotIdx].label} '
                            '(${steps[hotspotIdx - 1].count - steps[hotspotIdx].count} משתמשים נטשו כאן)',
                            style: const TextStyle(
                              color: _kRed,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              // ── Abandoned leads list ──────────────────────────────────
              _SectionHeader('📋 לידים שנטשו (${abandoned.length})'),
              const SizedBox(height: 12),

              if (abandoned.isEmpty)
                _EmptyState(
                  icon: Icons.celebration_rounded,
                  label: 'אין לידים נטושים בתקופה זו 🎉',
                  sub: 'כל המשתמשים השלימו את ההרשמה',
                )
              else
                ...abandoned.map((doc) => _LeadCard(
                      docId: doc.id,
                      data: doc.data() as Map<String, dynamic>,
                      isPinging: _pinging.contains(doc.id),
                      onPing: () => _pingLead(doc),
                    )),
            ],
          ),
        );
      },
    );
  }

  int _totalSessions(Map<String, int> counts) =>
      counts['reg_step_1'] ?? 0;

  // ── Ping a lead ────────────────────────────────────────────────────────────
  Future<void> _pingLead(QueryDocumentSnapshot doc) async {
    if (_pinging.contains(doc.id)) return;
    setState(() => _pinging.add(doc.id));
    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.update(doc.reference, {
        'reengaged':   true,
        'reengagedAt': FieldValue.serverTimestamp(),
        'reengagedBy': 'admin_manual',
      });

      batch.set(
        FirebaseFirestore.instance.collection('reengagement_log').doc(),
        {
          'sessionId':   doc.id,
          'email':       (doc.data() as Map<String, dynamic>)['email'] ?? '',
          'phone':       (doc.data() as Map<String, dynamic>)['phone'] ?? '',
          'lastField':   (doc.data() as Map<String, dynamic>)['lastField'] ?? '',
          'triggeredAt': FieldValue.serverTimestamp(),
          'channel':     'admin_manual',
        },
      );

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('✅ ליד סומן לריאנגייג׳מנט'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _pinging.remove(doc.id));
    }
  }
}

// ── Data model ────────────────────────────────────────────────────────────────
class _FunnelStep {
  const _FunnelStep(this.label, this.count, this.total, this.color);
  final String label;
  final int    count;
  final int    total;
  final Color  color;
  double get pct => total == 0 ? 0 : count / total;
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.label, this.value, this.icon, this.color);
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _FunnelBar extends StatelessWidget {
  const _FunnelBar({
    required this.step,
    required this.isHotspot,
    this.prevCount,
  });
  final _FunnelStep step;
  final bool        isHotspot;
  final int?        prevCount;

  @override
  Widget build(BuildContext context) {
    final drop      = prevCount != null ? prevCount! - step.count : 0;
    final dropLabel = drop > 0 ? '  -$drop' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(step.label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: LayoutBuilder(builder: (_, c) {
              return Stack(
                children: [
                  Container(
                    height: 26,
                    width: c.maxWidth,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    height: 26,
                    width: c.maxWidth * step.pct,
                    decoration: BoxDecoration(
                      color: isHotspot
                          ? _kRed.withValues(alpha: 0.85)
                          : step.color.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  if (isHotspot)
                    const Positioned(
                      right: 6, top: 4,
                      child: Text('🔥', style: TextStyle(fontSize: 14)),
                    ),
                ],
              );
            }),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              '${step.count}  (${(step.pct * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          if (dropLabel.isNotEmpty)
            Text(dropLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: isHotspot ? _kRed : Colors.grey,
                    fontWeight:
                        isHotspot ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.docId,
    required this.data,
    required this.isPinging,
    required this.onPing,
  });
  final String                docId;
  final Map<String, dynamic>  data;
  final bool                  isPinging;
  final VoidCallback           onPing;

  @override
  Widget build(BuildContext context) {
    final email     = data['email']     as String? ?? '';
    final phone     = data['phone']     as String? ?? '';
    final lastField = data['lastField'] as String? ?? '—';
    final role      = data['role']      as String? ?? 'customer';
    final reengaged = data['reengaged'] == true;
    final ts        = data['lastUpdatedAt'] as Timestamp?;
    final elapsed   = ts != null ? _elapsed(ts.toDate()) : '—';
    final contact   = email.isNotEmpty ? email : phone;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reengaged
              ? _kGreen.withValues(alpha: 0.4)
              : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor:
                (role == 'expert' ? _kIndigo : _kAmber).withValues(alpha: 0.12),
            child: Icon(
              role == 'expert' ? Icons.work_outline : Icons.person_outline,
              size: 18,
              color: role == 'expert' ? _kIndigo : _kAmber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.isNotEmpty ? contact : 'לא ידוע',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(children: [
                  _Tag(_fieldLabel(lastField), _kIndigo),
                  const SizedBox(width: 6),
                  _Tag(elapsed, Colors.grey),
                  if (reengaged) ...[
                    const SizedBox(width: 6),
                    _Tag('נשלח ✅', _kGreen),
                  ],
                ]),
              ],
            ),
          ),
          if (!reengaged)
            SizedBox(
              width: 70,
              height: 32,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kIndigo,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: isPinging ? null : onPing,
                child: isPinging
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Ping', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  String _fieldLabel(String f) => switch (f) {
        'name'  => 'עצר בשם',
        'email' => 'עצר באימייל',
        'phone' => 'עצר בטלפון',
        _       => 'שדה: $f',
      };

  String _elapsed(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}ד׳';
    if (diff.inHours   < 24) return '${diff.inHours}ש׳';
    return '${diff.inDays}י׳';
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.label, required this.sub});
  final IconData icon;
  final String   label;
  final String   sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Icon(icon, size: 44, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final String       error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: _kRed),
            const SizedBox(height: 12),
            const Text('שגיאה בטעינת הנתונים',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('נסה שוב'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayFilterChip extends StatelessWidget {
  const _DayFilterChip(
      {required this.value, required this.options, required this.onChanged});
  final int          value;
  final List<int>    options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options
            .map((d) => GestureDetector(
                  onTap: () => onChanged(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: value == d ? _kIndigo : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$d' 'י\u05f3',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: value == d ? Colors.white : Colors.grey,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
