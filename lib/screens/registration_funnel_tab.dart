import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Brand colors ──────────────────────────────────────────────────────────────
const _kIndigo = Color(0xFF6366F1);
const _kGreen  = Color(0xFF10B981);
const _kAmber  = Color(0xFFF59E0B);
const _kRed    = Color(0xFFEF4444);
const _kWA     = Color(0xFF25D366); // WhatsApp green

/// Admin tab: Registration Funnel + Abandoned Leads.
///
/// Sub-tab 1 (📊 משפך):  funnel bars from activity_log reg_step_* events.
/// Sub-tab 2 (📋 לידים): abandoned leads from incomplete_registrations with
///                        one-click WhatsApp re-engagement.
class RegistrationFunnelTab extends StatefulWidget {
  const RegistrationFunnelTab({super.key});

  @override
  State<RegistrationFunnelTab> createState() => _RegistrationFunnelTabState();
}

// ── Data models ───────────────────────────────────────────────────────────────
class _FunnelData {
  const _FunnelData({required this.counts, required this.hotLeads24h});
  final Map<String, int> counts;
  final int hotLeads24h; // sessions with step 2/3 but not step 5 in last 24h
}

class _Lead {
  _Lead({
    required this.docId,
    required this.data,
  });
  final String               docId;
  final Map<String, dynamic> data;

  String get name    => data['name']  as String? ?? '';
  String get email   => data['email'] as String? ?? '';
  String get phone   => data['phone'] as String? ?? '';
  String get contact => email.isNotEmpty ? email : phone;
  String get role    => data['role']  as String? ?? 'customer';
  bool   get reengaged => data['reengaged'] == true;

  DateTime? get lastUpdated {
    final ts = data['lastUpdatedAt'] as Timestamp?;
    return ts?.toDate();
  }

  String get lastField => data['lastField'] as String? ?? '—';

  // WhatsApp-ready international number (Israeli 05x → 9725x)
  String get waPhone {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0') && digits.length == 10) {
      return '972${digits.substring(1)}';
    }
    if (digits.startsWith('972')) return digits;
    return digits;
  }

  bool get hasPhone => phone.trim().isNotEmpty;
}

// ── State ─────────────────────────────────────────────────────────────────────
class _RegistrationFunnelTabState extends State<RegistrationFunnelTab>
    with SingleTickerProviderStateMixin {
  // Funnel sub-tab controller
  late final TabController _tabs;

  // Funnel filters
  int  _dayFilter  = 30;
  Future<_FunnelData>? _funnelFuture;

  // Abandoned leads filters
  int  _leadHours  = 24;
  Future<List<_Lead>>? _leadsFuture;

  final Set<String> _contacting = {}; // doc IDs being processed

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _funnelFuture = _loadFunnel();
    _leadsFuture  = _loadLeads();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Load funnel metrics ────────────────────────────────────────────────────
  Future<_FunnelData> _loadFunnel() async {
    final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(Duration(days: _dayFilter)));
    final cutoff24h = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 24)));

    final snap = await FirebaseFirestore.instance
        .collection('activity_log')
        .where('type', whereIn: [
          'reg_step_1', 'reg_step_2', 'reg_step_3',
          'reg_step_4', 'reg_step_5',
        ])
        .limit(2000)
        .get();

    final stepSessions = <String, Set<String>>{
      for (final s in ['reg_step_1','reg_step_2','reg_step_3','reg_step_4','reg_step_5'])
        s: <String>{},
    };

    for (final doc in snap.docs) {
      final d   = doc.data();
      final ts  = d['createdAt'] as Timestamp?;
      if (ts == null || ts.compareTo(cutoff) < 0) continue;
      final type = d['type'] as String? ?? '';
      final sid  = (d['sessionId'] as String?)?.isNotEmpty == true
          ? d['sessionId'] as String : doc.id;
      stepSessions[type]?.add(sid);
    }

    // Hot leads in last 24 h: have step 2 or 3 but NOT step 5
    final have23 = <String>{
      ...?stepSessions['reg_step_2'],
      ...?stepSessions['reg_step_3'],
    }.where((sid) {
      // must have had the event in last 24h
      final ts = snap.docs
          .firstWhere((d) =>
              d.data()['sessionId'] == sid &&
              (d.data()['type'] == 'reg_step_2' ||
               d.data()['type'] == 'reg_step_3'),
              orElse: () => snap.docs.first)
          .data()['createdAt'] as Timestamp?;
      return ts != null && ts.compareTo(cutoff24h) >= 0;
    }).toSet();
    final completed24h = snap.docs
        .where((d) =>
            d.data()['type'] == 'reg_step_5' &&
            ((d.data()['createdAt'] as Timestamp?)?.compareTo(cutoff24h) ?? -1) >= 0)
        .map((d) => d.data()['sessionId'] as String? ?? d.id)
        .toSet();

    final hotLeads = have23.difference(completed24h).length;

    final counts = stepSessions.map((k, v) => MapEntry(k, v.length));
    return _FunnelData(counts: counts, hotLeads24h: hotLeads);
  }

  // ── Load abandoned leads ───────────────────────────────────────────────────
  Future<List<_Lead>> _loadLeads() async {
    final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(Duration(hours: _leadHours)));

    final snap = await FirebaseFirestore.instance
        .collection('incomplete_registrations')
        .limit(500)
        .get();

    final leads = snap.docs
        .where((d) {
          final m  = d.data();
          final ts = m['startedAt'] as Timestamp?;
          if (ts == null || ts.compareTo(cutoff) < 0) return false;
          if (m['isRegistrationComplete'] == true) return false;
          // Must have at least reached step 2 (has a name)
          return (m['name']  as String? ?? '').isNotEmpty ||
                 (m['email'] as String? ?? '').isNotEmpty ||
                 (m['phone'] as String? ?? '').isNotEmpty;
        })
        .map((d) => _Lead(docId: d.id, data: d.data()))
        .toList()
      ..sort((a, b) {
        final ta = a.lastUpdated ?? DateTime(2000);
        final tb = b.lastUpdated ?? DateTime(2000);
        return tb.compareTo(ta); // newest first
      });

    return leads;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sub-tab bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: _kIndigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _kIndigo,
            indicatorWeight: 2,
            labelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              const Tab(text: '📊 משפך הרשמה'),
              Tab(
                child: FutureBuilder<List<_Lead>>(
                  future: _leadsFuture,
                  builder: (_, snap) {
                    final count = snap.hasData ? snap.data!.length : 0;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('📋 לידים שנטשו'),
                        if (count > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('$count',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildFunnelTab(),
              _buildLeadsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Sub-tab 1: Funnel ──────────────────────────────────────────────────────
  Widget _buildFunnelTab() {
    return FutureBuilder<_FunnelData>(
      future: _funnelFuture,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            error: snapshot.error.toString(),
            onRetry: () => setState(() => _funnelFuture = _loadFunnel()),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data      = snapshot.data!;
        final counts    = data.counts;
        final hotLeads  = data.hotLeads24h;
        final total     = counts['reg_step_1'] ?? 0;
        final completed = counts['reg_step_5'] ?? 0;
        final convRate  = total == 0 ? 0.0 : completed / total * 100;

        final steps = [
          _FunnelStep('פתח הרשמה',   counts['reg_step_1'] ?? 0, total, const Color(0xFF6366F1)),
          _FunnelStep('מילא שם',     counts['reg_step_2'] ?? 0, total, const Color(0xFF8B5CF6)),
          _FunnelStep('הזין אימייל', counts['reg_step_3'] ?? 0, total, const Color(0xFFF59E0B)),
          _FunnelStep('לחץ הרשמה',  counts['reg_step_4'] ?? 0, total, const Color(0xFFEF4444)),
          _FunnelStep('הושלם',       counts['reg_step_5'] ?? 0, total, const Color(0xFF10B981)),
        ];

        int hotIdx = 1, maxDrop = 0;
        for (int i = 1; i < steps.length; i++) {
          final drop = steps[i - 1].count - steps[i].count;
          if (drop > maxDrop) { maxDrop = drop; hotIdx = i; }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hot leads summary card ──────────────────────────────────
              if (hotLeads > 0)
                GestureDetector(
                  onTap: () => _tabs.animateTo(1),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text('🔥', style: TextStyle(fontSize: 22)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'יש לך $hotLeads לידים שמחכים ליחס חם',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'התחילו להירשם ב-24 ש׳ האחרונות — לחץ לסגירה',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white70, size: 16),
                      ],
                    ),
                  ),
                ),

              // ── Header row ──────────────────────────────────────────────
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📊 משפך ההמרה',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('מעקב שלבי הרשמה',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _funnelFuture = _loadFunnel()),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'רענן',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const SizedBox(width: 4),
                  _DayFilterChip(
                    value: _dayFilter,
                    options: const [7, 14, 30, 90],
                    onChanged: (v) => setState(() {
                      _dayFilter    = v;
                      _funnelFuture = _loadFunnel();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── KPI cards ────────────────────────────────────────────────
              Row(children: [
                _KpiCard('סשנים',  total.toString(),
                    Icons.person_add_alt_1_rounded, _kIndigo),
                const SizedBox(width: 10),
                _KpiCard('הושלמו', completed.toString(),
                    Icons.check_circle_rounded, _kGreen),
                const SizedBox(width: 10),
                _KpiCard('לידים חמים', hotLeads.toString(),
                    Icons.local_fire_department_rounded, _kRed),
                const SizedBox(width: 10),
                _KpiCard('המרה', '${convRate.toStringAsFixed(0)}%',
                    Icons.trending_up_rounded, _kAmber),
              ]),
              const SizedBox(height: 20),

              // ── Funnel bars ──────────────────────────────────────────────
              const _SectionHeader('🔽 שלבי ההרשמה'),
              const SizedBox(height: 12),

              if (total == 0)
                _EmptyState(
                  icon: Icons.analytics_outlined,
                  label: 'אין נתוני הרשמה עדיין',
                  sub: 'הנתונים יופיעו כאשר משתמשים יפתחו את מסך ההרשמה',
                )
              else ...[
                ...steps.asMap().entries.map((e) => _FunnelBar(
                      step:      e.value,
                      isHotspot: e.key == hotIdx,
                      prevCount: e.key > 0 ? steps[e.key - 1].count : null,
                    )),
                const SizedBox(height: 8),
                if (maxDrop > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: _kRed.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'נקודת נטישה: ${steps[hotIdx].label} '
                            '(${steps[hotIdx - 1].count - steps[hotIdx].count} נטשו)',
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
            ],
          ),
        );
      },
    );
  }

  // ── Sub-tab 2: Abandoned Leads ─────────────────────────────────────────────
  Widget _buildLeadsTab() {
    return FutureBuilder<List<_Lead>>(
      future: _leadsFuture,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            error: snapshot.error.toString(),
            onRetry: () => setState(() => _leadsFuture = _loadLeads()),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final leads = snapshot.data!;

        return Column(
          children: [
            // ── Filter bar ──────────────────────────────────────────────
            Container(
              color: const Color(0xFFF8F8FF),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      leads.isEmpty
                          ? 'אין לידים נטושים'
                          : '${leads.length} לידים נטשו',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _leadsFuture = _loadLeads()),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  const SizedBox(width: 4),
                  _HoursFilterChip(
                    value: _leadHours,
                    options: const [6, 24, 48, 72],
                    onChanged: (v) => setState(() {
                      _leadHours   = v;
                      _leadsFuture = _loadLeads();
                    }),
                  ),
                ],
              ),
            ),

            // ── List ────────────────────────────────────────────────────
            Expanded(
              child: leads.isEmpty
                  ? _EmptyState(
                      icon: Icons.celebration_rounded,
                      label: 'אין לידים נטושים! 🎉',
                      sub: 'כל מי שהתחיל להירשם ב-$_leadHours ש׳ האחרונות סיים',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: leads.length,
                      itemBuilder: (_, i) => _LeadCard(
                        lead: leads[i],
                        isContacting: _contacting.contains(leads[i].docId),
                        onWhatsApp: leads[i].hasPhone
                            ? () => _contactWhatsApp(leads[i])
                            : null,
                        onPing: leads[i].reengaged
                            ? null
                            : () => _pingLead(leads[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  // ── WhatsApp one-click ─────────────────────────────────────────────────────
  Future<void> _contactWhatsApp(_Lead lead) async {
    if (_contacting.contains(lead.docId)) return;
    setState(() => _contacting.add(lead.docId));

    final name = lead.name.isNotEmpty ? lead.name.split(' ').first : 'שם';
    final message =
        'היי $name, ראינו שהתחלת להירשם ל-AnySkill ולא סיימת. '
        'צריך עזרה במשהו? 😊';
    final url =
        'https://wa.me/${lead.waPhone}?text=${Uri.encodeComponent(message)}';

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      // Log the contact attempt
      await _logReengagement(lead, 'whatsapp');
      // Refresh list to reflect updated state
      if (mounted) setState(() => _leadsFuture = _loadLeads());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בפתיחת וואטסאפ: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _contacting.remove(lead.docId));
    }
  }

  // ── Admin ping (existing channel) ─────────────────────────────────────────
  Future<void> _pingLead(_Lead lead) async {
    if (_contacting.contains(lead.docId)) return;
    setState(() => _contacting.add(lead.docId));
    try {
      await _logReengagement(lead, 'admin_manual');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('✅ ליד סומן לריאנגייג׳מנט'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
        setState(() => _leadsFuture = _loadLeads());
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
      if (mounted) setState(() => _contacting.remove(lead.docId));
    }
  }

  // ── Shared log helper ──────────────────────────────────────────────────────
  Future<void> _logReengagement(_Lead lead, String channel) async {
    final batch = FirebaseFirestore.instance.batch();

    // Mark doc as reengaged to prevent double-contact
    batch.update(
      FirebaseFirestore.instance
          .collection('incomplete_registrations')
          .doc(lead.docId),
      {
        'reengaged':            true,
        'reengagedAt':          FieldValue.serverTimestamp(),
        'reengagedBy':          channel,
        'reengagedChannel':     channel,
      },
    );

    // Write to reengagement_log for audit
    batch.set(
      FirebaseFirestore.instance.collection('reengagement_log').doc(),
      {
        'sessionId':   lead.docId,
        'name':        lead.name,
        'email':       lead.email,
        'phone':       lead.phone,
        'lastField':   lead.lastField,
        'channel':     channel,
        'triggeredAt': FieldValue.serverTimestamp(),
        'triggeredBy': 'admin_manual',
      },
    );

    // Also log to activity_log so it appears in Live Feed
    batch.set(
      FirebaseFirestore.instance.collection('activity_log').doc(),
      {
        'type':      'reengagement_sent',
        'sessionId': lead.docId,
        'createdAt': FieldValue.serverTimestamp(),
        'priority':  'normal',
        'title':     '📲 נשלח ריאנגייג׳מנט ל${lead.name.isNotEmpty ? lead.name : "ליד"}',
        'detail':    'ערוץ: $channel · ${lead.contact}',
      },
    );

    await batch.commit();
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
  final String label; final String value;
  final IconData icon; final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _FunnelBar extends StatelessWidget {
  const _FunnelBar(
      {required this.step, required this.isHotspot, this.prevCount});
  final _FunnelStep step;
  final bool        isHotspot;
  final int?        prevCount;

  @override
  Widget build(BuildContext context) {
    final drop = prevCount != null ? prevCount! - step.count : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(step.label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: LayoutBuilder(builder: (_, c) {
              return Stack(children: [
                Container(
                    height: 26, width: c.maxWidth,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6))),
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
                      child: Text('🔥', style: TextStyle(fontSize: 13))),
              ]);
            }),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              '${step.count} (${(step.pct * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          if (drop > 0)
            Text(' -$drop',
                style: TextStyle(
                    fontSize: 11,
                    color: isHotspot ? _kRed : Colors.grey,
                    fontWeight: isHotspot
                        ? FontWeight.bold
                        : FontWeight.normal)),
        ],
      ),
    );
  }
}

// ── Lead card ─────────────────────────────────────────────────────────────────
class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.isContacting,
    this.onWhatsApp,
    this.onPing,
  });
  final _Lead        lead;
  final bool         isContacting;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onPing;

  @override
  Widget build(BuildContext context) {
    final elapsed = lead.lastUpdated != null
        ? _elapsed(lead.lastUpdated!)
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lead.reengaged
              ? _kGreen.withValues(alpha: 0.4)
              : Colors.grey.shade100,
        ),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: avatar + contact info + time ──────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    (lead.role == 'expert' ? _kIndigo : _kAmber)
                        .withValues(alpha: 0.12),
                child: Icon(
                  lead.role == 'expert'
                      ? Icons.work_outline
                      : Icons.person_outline,
                  size: 18,
                  color: lead.role == 'expert' ? _kIndigo : _kAmber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (lead.name.isNotEmpty)
                      Text(lead.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    if (lead.contact.isNotEmpty)
                      Text(lead.contact,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(elapsed,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 3),
                  _Tag(_fieldLabel(lead.lastField), _kIndigo),
                ],
              ),
            ],
          ),

          // ── Row 2: action buttons ─────────────────────────────────────
          if (!lead.reengaged) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                // WhatsApp button (primary)
                if (onWhatsApp != null)
                  Expanded(
                    child: _ActionButton(
                      label: 'WhatsApp',
                      icon: Icons.chat_rounded,
                      color: _kWA,
                      loading: isContacting,
                      onTap: onWhatsApp,
                    ),
                  ),
                if (onWhatsApp != null && onPing != null)
                  const SizedBox(width: 8),
                // Ping / mark button (secondary)
                if (onPing != null)
                  SizedBox(
                    width: 80,
                    child: _ActionButton(
                      label: 'סמן',
                      icon: Icons.check_rounded,
                      color: _kIndigo,
                      loading: isContacting && onWhatsApp == null,
                      onTap: onPing,
                      outlined: true,
                    ),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.check_circle_rounded,
                  color: _kGreen, size: 16),
              const SizedBox(width: 6),
              Text(
                'נוצר קשר · ${_channel(lead.data['reengagedBy'] as String? ?? '')}',
                style: const TextStyle(
                    color: _kGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ],
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

  String _channel(String c) => switch (c) {
        'whatsapp'    => 'וואטסאפ',
        'admin_manual'=> 'ידני',
        _             => c,
      };

  String _elapsed(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes}ד׳';
    if (diff.inHours   < 24) return 'לפני ${diff.inHours}ש׳';
    return 'לפני ${diff.inDays}י׳';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    this.onTap,
    this.outlined = false,
  });
  final String     label;
  final IconData   icon;
  final Color      color;
  final bool       loading;
  final VoidCallback? onTap;
  final bool       outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        decoration: BoxDecoration(
          color: outlined ? Colors.white : color,
          borderRadius: BorderRadius.circular(9),
          border: outlined ? Border.all(color: color, width: 1.5) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: loading
              ? [SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: outlined ? color : Colors.white))]
              : [
                  Icon(icon,
                      size: 15,
                      color: outlined ? color : Colors.white),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: outlined ? color : Colors.white)),
                ],
        ),
      ),
    );
  }
}

// ── Small reusables ───────────────────────────────────────────────────────────
class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label; final Color color;

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
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.label, required this.sub});
  final IconData icon; final String label; final String sub;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87)),
          const SizedBox(height: 4),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final String error; final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
      ),
    );
  }
}

class _DayFilterChip extends StatelessWidget {
  const _DayFilterChip(
      {required this.value, required this.options, required this.onChanged});
  final int value; final List<int> options;
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:
                          value == d ? _kIndigo : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$d' 'י\u05f3',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              value == d ? Colors.white : Colors.grey,
                        )),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _HoursFilterChip extends StatelessWidget {
  const _HoursFilterChip(
      {required this.value, required this.options, required this.onChanged});
  final int value; final List<int> options;
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
            .map((h) => GestureDetector(
                  onTap: () => onChanged(h),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color:
                          value == h ? _kIndigo : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$h' 'ש\u05f3',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              value == h ? Colors.white : Colors.grey,
                        )),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
