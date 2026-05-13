import 'package:flutter/material.dart';

import 'chat_guard/chat_guard_service.dart';
import 'chat_guard/models.dart';

/// Chat Guard admin workspace (Phase 1).
///
/// Four tabs, all backed by real Firestore data via [ChatGuardService]:
///   1. מילים       — add / edit / delete / toggle blocked words
///   2. תקריות      — live feed of detection events
///   3. הגדרות      — sensitivity + per-layer toggles + kill-switch
///   4. סטטיסטיקות  — 7-day KPIs
///
/// Phase 1 ships the UI + data layer ONLY. The detection engine and chat
/// integration land in later phases behind `ChatGuardSettings.enabled`.
class AdminChatGuardTab extends StatefulWidget {
  const AdminChatGuardTab({super.key});

  @override
  State<AdminChatGuardTab> createState() => _AdminChatGuardTabState();
}

class _AdminChatGuardTabState extends State<AdminChatGuardTab>
    with SingleTickerProviderStateMixin {
  final _svc = ChatGuardService();
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // ── Status banner (kill-switch indicator) ──────────────────────
          StreamBuilder<ChatGuardSettings>(
            stream: _svc.streamSettings(),
            builder: (_, snap) {
              final s = snap.data ?? ChatGuardSettings.defaults;
              return _StatusBanner(enabled: s.enabled);
            },
          ),
          // ── Tabs ───────────────────────────────────────────────────────
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              labelColor: const Color(0xFF7C3AED),
              indicatorColor: const Color(0xFF7C3AED),
              unselectedLabelColor: const Color(0xFF6B7280),
              tabs: const [
                Tab(text: 'מילים 🏷'),
                Tab(text: 'תקריות 🚨'),
                Tab(text: 'הגדרות ⚙️'),
                Tab(text: 'סטטיסטיקות 📊'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _WordsTab(svc: _svc),
                _IncidentsTab(svc: _svc),
                _SettingsTab(svc: _svc),
                _StatsTab(svc: _svc),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status banner ───────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bg = enabled
        ? const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(enabled ? Icons.shield_rounded : Icons.shield_outlined,
              color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? 'Chat Guard — פעיל' : 'Chat Guard — מושבת',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'ההודעות נבדקות בזמן אמת לפני שליחה'
                      : 'טיוטה בלבד — הדשבורד פעיל אך ההודעות לא נבדקות',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 1. Words tab ────────────────────────────────────────────────────────────

class _WordsTab extends StatefulWidget {
  const _WordsTab({required this.svc});
  final ChatGuardService svc;

  @override
  State<_WordsTab> createState() => _WordsTabState();
}

class _WordsTabState extends State<_WordsTab> {
  WordCategory? _filterCategory;
  WordSeverity? _filterSeverity;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BlockedWord>>(
      stream: widget.svc.streamWords(),
      builder: (context, snap) {
        final all = snap.data ?? const <BlockedWord>[];
        final q = _searchQuery.trim().toLowerCase();
        final filtered = all.where((w) {
          if (_filterCategory != null && w.category != _filterCategory) return false;
          if (_filterSeverity != null && w.severity != _filterSeverity) return false;
          if (q.isNotEmpty && !w.text.toLowerCase().contains(q)) return false;
          return true;
        }).toList();

        return Column(
          children: [
            // Toolbar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'חיפוש מילה...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openAddDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('הוסף'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            // Filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in WordCategory.values)
                    FilterChip(
                      label: Text(c.hebrew, style: const TextStyle(fontSize: 12)),
                      selected: _filterCategory == c,
                      onSelected: (v) => setState(() =>
                          _filterCategory = v ? c : null),
                      selectedColor: const Color(0xFFEDE9FE),
                    ),
                  const SizedBox(width: 6),
                  for (final s in WordSeverity.values)
                    FilterChip(
                      label: Text(s.hebrew, style: const TextStyle(fontSize: 12)),
                      selected: _filterSeverity == s,
                      onSelected: (v) => setState(() =>
                          _filterSeverity = v ? s : null),
                      selectedColor: _severityColor(s).withValues(alpha: 0.15),
                    ),
                ],
              ),
            ),
            // Seed button (only when no words exist)
            if (!snap.hasData || all.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _EmptyWordsState(onSeed: _handleSeed),
              ),
            // Results
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        all.isEmpty
                            ? 'אין מילים — הוסף את הראשונה ☝️'
                            : 'אין תוצאות תואמות לפילטר',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _WordRow(
                        word: filtered[i],
                        onEdit: () => _openEditDialog(context, filtered[i]),
                        onToggle: () => widget.svc.updateWord(
                            filtered[i].id, isActive: !filtered[i].isActive),
                        onDelete: () => _confirmDelete(context, filtered[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSeed() async {
    try {
      final res = await widget.svc.seedInitialWordsIfEmpty();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.skipped
            ? 'כבר קיימות מילים — דילגתי'
            : 'נוספו ${res.added} מילי בסיס ✅'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה ב-seeding: $e')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, BlockedWord w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחק מילה?'),
        content: Text('"${w.text}" תוסר מרשימת הבדיקה. ניתן להוסיף אותה שוב בעתיד.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.svc.deleteWord(w.id);
  }

  Future<void> _openAddDialog(BuildContext context) =>
      _openWordDialog(context);

  Future<void> _openEditDialog(BuildContext context, BlockedWord w) =>
      _openWordDialog(context, existing: w);

  Future<void> _openWordDialog(BuildContext context,
      {BlockedWord? existing}) async {
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    WordCategory cat = existing?.category ?? WordCategory.payment;
    WordSeverity sev = existing?.severity ?? WordSeverity.medium;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'הוספת מילה' : 'עריכת מילה'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(labelText: 'מילה / ביטוי'),
                  autofocus: existing == null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<WordCategory>(
                  value: cat,
                  decoration: const InputDecoration(labelText: 'קטגוריה'),
                  items: [
                    for (final c in WordCategory.values)
                      DropdownMenuItem(value: c, child: Text(c.hebrew)),
                  ],
                  onChanged: (v) => setLocal(() => cat = v ?? cat),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<WordSeverity>(
                  value: sev,
                  decoration: const InputDecoration(labelText: 'חומרה'),
                  items: [
                    for (final s in WordSeverity.values)
                      DropdownMenuItem(value: s, child: Text(s.hebrew)),
                  ],
                  onChanged: (v) => setLocal(() => sev = v ?? sev),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'הערות (אופציונלי)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול')),
            ElevatedButton(
              onPressed: () {
                if (textCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white),
              child: Text(existing == null ? 'הוסף' : 'שמור'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      if (existing == null) {
        await widget.svc.addWord(
          text: textCtrl.text,
          category: cat,
          severity: sev,
          notes: notesCtrl.text,
        );
      } else {
        await widget.svc.updateWord(
          existing.id,
          text: textCtrl.text,
          category: cat,
          severity: sev,
          notes: notesCtrl.text,
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Use the State's context explicitly — `this.context` — so the
      // `mounted` guard above is the one the analyzer associates with it.
      ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')));
    }
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.word,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final BlockedWord word;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sevColor = _severityColor(word.severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: word.isActive ? Colors.white : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: sevColor.withValues(alpha: word.isActive ? 0.35 : 0.15)),
      ),
      child: Row(
        children: [
          // Severity dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: sevColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          // Text + category
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  word.text,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: word.isActive ? Colors.black : Colors.grey,
                    decoration: word.isActive
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${word.category.hebrew} · חומרה ${word.severity.hebrew} · ${word.hits} זיהויים',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            onPressed: onToggle,
            icon: Icon(word.isActive ? Icons.visibility : Icons.visibility_off,
                size: 18, color: const Color(0xFF6B7280)),
            tooltip: word.isActive ? 'השבת' : 'הפעל',
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: Color(0xFF6B7280)),
            tooltip: 'ערוך',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Color(0xFFEF4444)),
            tooltip: 'מחק',
          ),
        ],
      ),
    );
  }
}

class _EmptyWordsState extends StatelessWidget {
  const _EmptyWordsState({required this.onSeed});
  final Future<void> Function() onSeed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded,
              color: Color(0xFF2563EB), size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'רשימת המילים ריקה. טען 12 מילות בסיס כדי להתחיל.',
              style: TextStyle(fontSize: 13, color: Color(0xFF1E3A8A)),
            ),
          ),
          ElevatedButton(
            onPressed: onSeed,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white),
            child: const Text('טען'),
          ),
        ],
      ),
    );
  }
}

// ── 2. Incidents tab ────────────────────────────────────────────────────────

class _IncidentsTab extends StatelessWidget {
  const _IncidentsTab({required this.svc});
  final ChatGuardService svc;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatGuardIncident>>(
      stream: svc.streamIncidents(),
      builder: (context, snap) {
        final list = snap.data ?? const <ChatGuardIncident>[];
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: Color(0xFF10B981), size: 48),
                const SizedBox(height: 10),
                Text('אין תקריות עדיין',
                    style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  'לאחר הפעלת ההגנה בהגדרות, כל זיהוי יופיע כאן בזמן אמת.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _IncidentRow(inc: list[i]),
        );
      },
    );
  }
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.inc});
  final ChatGuardIncident inc;

  @override
  Widget build(BuildContext context) {
    final actionColor = _actionColor(inc.action);
    final time = inc.timestamp == null
        ? ''
        : '${inc.timestamp!.day}/${inc.timestamp!.month} '
          '${inc.timestamp!.hour}:${inc.timestamp!.minute.toString().padLeft(2, "0")}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: actionColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: actionColor.withValues(alpha: 0.35)),
                ),
                child: Text(inc.action.hebrew,
                    style: TextStyle(
                        color: actionColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(inc.userName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Text(time,
                  style: TextStyle(
                      color: Colors.grey[500], fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            inc.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF374151)),
          ),
          if (inc.matchedWords.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: inc.matchedWords
                  .map((w) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(w,
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF92400E))),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 3. Settings tab ─────────────────────────────────────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.svc});
  final ChatGuardService svc;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  /// The local working copy. Tracks whatever the admin has typed/toggled
  /// since the last server-confirmed value.
  ChatGuardSettings? _draft;

  /// The last value confirmed by Firestore. We treat the explicit "Save"
  /// button as committing only the *non-toggle* fields (sensitivity), and
  /// every toggle (master kill-switch + per-layer) auto-saves immediately.
  /// `_baseline` is what the save button compares against.
  ChatGuardSettings? _baseline;

  /// Cached stream — created ONCE in initState. The previous code called
  /// `widget.svc.streamSettings()` inside `build()`, which created a new
  /// Stream object on every rebuild and forced StreamBuilder to re-subscribe.
  late final Stream<ChatGuardSettings> _stream;

  /// Used to disable the master Switch + per-layer toggles momentarily
  /// while the optimistic write is in flight. Prevents double-taps from
  /// fighting each other for the same field.
  String? _savingFieldKey;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamSettings();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatGuardSettings>(
      stream: _stream,
      builder: (context, snap) {
        final current = snap.data ?? ChatGuardSettings.defaults;

        // First emission OR remote changed (e.g. another admin saved):
        // sync the baseline. The local draft tracks unsaved sensitivity
        // edits — for everything else, baseline === draft because toggles
        // auto-save.
        if (_baseline == null) {
          _baseline = current;
          _draft = current;
        } else if (_baseline != current) {
          // External change — preserve any in-flight sensitivity edit, but
          // sync every other field so toggles always reflect the truth.
          _baseline = current;
          final localSensitivity = _draft?.sensitivity ?? current.sensitivity;
          _draft = current.copyWith(sensitivity: localSensitivity);
        }

        final d = _draft!;
        final hasUnsavedSensitivity = d.sensitivity != current.sensitivity;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Master kill-switch (auto-saves) ──────────────────────────
            _AutoSaveSettingCard(
              fieldKey: 'enabled',
              activeKey: _savingFieldKey,
              child: SwitchListTile(
                title: const Text(
                  'הפעל את Chat Guard',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  d.enabled
                      ? 'פעיל — כל הודעה נבדקת לפני שליחה'
                      : 'מושבת — הדשבורד פעיל אך ההודעות לא נבדקות',
                  style: const TextStyle(fontSize: 12),
                ),
                value: d.enabled,
                activeColor: const Color(0xFF10B981),
                onChanged: _savingFieldKey == null
                    ? (v) => _autoSaveToggle('enabled', d.copyWith(enabled: v))
                    : null,
              ),
            ),
            const SizedBox(height: 12),

            // ── Sensitivity (explicit save — continuous slider) ──────────
            _SettingCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('רגישות',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (hasUnsavedSensitivity) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'שינוי לא שמור',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF92400E),
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text('${d.sensitivity}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7C3AED))),
                      ],
                    ),
                    Slider(
                      value: d.sensitivity.toDouble(),
                      min: 0.0,
                      max: 100.0,
                      divisions: 20,
                      label: '${d.sensitivity}',
                      activeColor: const Color(0xFF7C3AED),
                      onChanged: (v) => setState(() =>
                          _draft = d.copyWith(sensitivity: v.round())),
                    ),
                    Text(
                      d.sensitivity <= 30
                          ? 'מתונה — רק התאמות מובהקות ייחסמו'
                          : d.sensitivity <= 65
                              ? 'מאוזנת — מומלצת לרוב המקרים'
                              : 'אגרסיבית — גם רמזים עדינים יגרמו לבדיקה',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Detection layers (auto-save each) ───────────────────────
            _SettingCard(
              child: Column(
                children: [
                  _AutoSaveDetectToggle(
                    fieldKey: 'detectSpaces',
                    activeKey: _savingFieldKey,
                    label: 'זיהוי רווחים בין אותיות',
                    hint: '"מ ז ו מ ן" → "מזומן"',
                    value: d.detectSpaces,
                    onChanged: (v) => _autoSaveToggle(
                        'detectSpaces', d.copyWith(detectSpaces: v)),
                  ),
                  _AutoSaveDetectToggle(
                    fieldKey: 'detectLeetspeak',
                    activeKey: _savingFieldKey,
                    label: 'Leetspeak',
                    hint: '"c@sh" / "m0ney"',
                    value: d.detectLeetspeak,
                    onChanged: (v) => _autoSaveToggle(
                        'detectLeetspeak', d.copyWith(detectLeetspeak: v)),
                  ),
                  _AutoSaveDetectToggle(
                    fieldKey: 'detectEmoji',
                    activeKey: _savingFieldKey,
                    label: 'אימוג\'י',
                    hint: '"💵 💰" → "מזומן"',
                    value: d.detectEmoji,
                    onChanged: (v) => _autoSaveToggle(
                        'detectEmoji', d.copyWith(detectEmoji: v)),
                  ),
                  _AutoSaveDetectToggle(
                    fieldKey: 'detectPhoneNumbers',
                    activeKey: _savingFieldKey,
                    label: 'מספרי טלפון',
                    hint: 'ישראלי / בינלאומי / במילים',
                    value: d.detectPhoneNumbers,
                    onChanged: (v) => _autoSaveToggle('detectPhoneNumbers',
                        d.copyWith(detectPhoneNumbers: v)),
                  ),
                  _AutoSaveDetectToggle(
                    fieldKey: 'detectLinks',
                    activeKey: _savingFieldKey,
                    label: 'קישורים חיצוניים',
                    hint: 'wa.me · t.me · instagram.com · ...',
                    value: d.detectLinks,
                    onChanged: (v) => _autoSaveToggle(
                        'detectLinks', d.copyWith(detectLinks: v)),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Save (only sensitivity needs an explicit save click) ────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasUnsavedSensitivity ? _saveSensitivity : null,
                icon: const Icon(Icons.save_rounded),
                label: Text(hasUnsavedSensitivity
                    ? 'שמור רגישות'
                    : 'אין שינויים לשמירה'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  disabledForegroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'הטוגלים נשמרים אוטומטית · רגישות דורשת לחיצה על "שמור"',
                style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Optimistic save for any single boolean toggle (master kill-switch
  /// + per-layer detection toggles).
  ///
  ///   1. Update the visible state immediately so the switch animates.
  ///   2. Mark `_savingFieldKey` so other toggles disable until done.
  ///   3. Write to Firestore.
  ///   4. On success — leave the optimistic state in place; the stream
  ///      will confirm it on the next emission.
  ///   5. On failure — REVERT the visible state and show a snackbar.
  Future<void> _autoSaveToggle(
      String fieldKey, ChatGuardSettings next) async {
    final previous = _draft ?? ChatGuardSettings.defaults;
    setState(() {
      _draft = next;
      _baseline = next;
      _savingFieldKey = fieldKey;
    });
    try {
      await widget.svc.saveSettings(next);
      if (!mounted) return;
      setState(() => _savingFieldKey = null);
    } catch (e) {
      if (!mounted) return;
      // Visual rollback so the switch returns to its real state.
      setState(() {
        _draft = previous;
        _baseline = previous;
        _savingFieldKey = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        content: Text('שגיאה בשמירה: ${_friendlyError(e)}'),
        action: SnackBarAction(
          textColor: Colors.white,
          label: 'נסה שוב',
          onPressed: () => _autoSaveToggle(fieldKey, next),
        ),
      ));
    }
  }

  Future<void> _saveSensitivity() async {
    final s = _draft;
    if (s == null) return;
    setState(() => _savingFieldKey = 'sensitivity');
    try {
      await widget.svc.saveSettings(s);
      if (!mounted) return;
      setState(() {
        _baseline = s;
        _savingFieldKey = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('הרגישות נשמרה ✅'),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingFieldKey = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        content: Text('שגיאה בשמירה: ${_friendlyError(e)}'),
      ));
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
      return 'אין הרשאת מנהל';
    }
    if (s.contains('unavailable') || s.contains('network')) {
      return 'אין חיבור לרשת';
    }
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }
}

/// Wraps a `_SettingCard` with a small "saving…" indicator on top-end
/// while an auto-save write is in flight for this card's [fieldKey].
class _AutoSaveSettingCard extends StatelessWidget {
  const _AutoSaveSettingCard({
    required this.fieldKey,
    required this.activeKey,
    required this.child,
  });
  final String fieldKey;
  final String? activeKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isSaving = activeKey == fieldKey;
    return Stack(
      children: [
        _SettingCard(child: child),
        if (isSaving)
          PositionedDirectional(
            top: 8,
            end: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                  ),
                ),
                SizedBox(width: 6),
                Text('שומר…',
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Auto-saving detection toggle row. Disables when ANY toggle on the
/// page is currently saving (prevents racing parallel writes that would
/// flip flags in unexpected order).
class _AutoSaveDetectToggle extends StatelessWidget {
  const _AutoSaveDetectToggle({
    required this.fieldKey,
    required this.activeKey,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });
  final String fieldKey;
  final String? activeKey;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isSaving = activeKey == fieldKey;
    final disabled = activeKey != null;
    return Column(
      children: [
        Stack(
          children: [
            SwitchListTile(
              title: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text(hint,
                  style: const TextStyle(fontSize: 11)),
              value: value,
              activeColor: const Color(0xFF7C3AED),
              onChanged: disabled ? null : onChanged,
            ),
            if (isSaving)
              const PositionedDirectional(
                top: 14,
                end: 60,
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                  ),
                ),
              ),
          ],
        ),
        if (!isLast) const Divider(height: 1, color: Color(0xFFF3F4F6)),
      ],
    );
  }
}

// ── 4. Stats tab ────────────────────────────────────────────────────────────

class _StatsTab extends StatefulWidget {
  const _StatsTab({required this.svc});
  final ChatGuardService svc;

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late Future<ChatGuardKpis> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.svc.computeKpis();
  }

  void _refresh() {
    setState(() => _future = widget.svc.computeKpis());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChatGuardKpis>(
      future: _future,
      builder: (context, snap) {
        final k = snap.data ?? ChatGuardKpis.empty;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Text('סטטיסטיקה · 7 ימים אחרונים',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'רענן',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                // 4 top KPIs
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.6,
                  children: [
                    _KpiTile(
                      label: 'סה״כ תקריות',
                      value: '${k.totalIncidents7d}',
                      color: const Color(0xFF7C3AED),
                      icon: Icons.shield_rounded,
                    ),
                    _KpiTile(
                      label: 'משתמשים ייחודיים',
                      value: '${k.distinctUsers}',
                      color: const Color(0xFF2563EB),
                      icon: Icons.people_rounded,
                    ),
                    _KpiTile(
                      label: 'נחסמו',
                      value: '${k.blocked}',
                      color: const Color(0xFFEF4444),
                      icon: Icons.block_rounded,
                    ),
                    _KpiTile(
                      label: 'מילים פעילות',
                      value: '${k.activeWords} / ${k.totalWords}',
                      color: const Color(0xFF10B981),
                      icon: Icons.label_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Breakdown by action
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('התפלגות פעולות',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 10),
                      _breakdownRow('אושרו', k.allowed,
                          const Color(0xFF9CA3AF), k.totalIncidents7d),
                      _breakdownRow('אזהרות', k.warned,
                          const Color(0xFFF59E0B), k.totalIncidents7d),
                      _breakdownRow('הוחלפו', k.rewritten,
                          const Color(0xFF3B82F6), k.totalIncidents7d),
                      _breakdownRow('נחסמו', k.blocked,
                          const Color(0xFFEF4444), k.totalIncidents7d),
                      _breakdownRow('השעיות', k.suspended,
                          const Color(0xFF991B1B), k.totalIncidents7d),
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

  Widget _breakdownRow(String label, int count, Color color, int total) {
    final pct = total > 0 ? (count / total) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8.0,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text('$count',
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

Color _severityColor(WordSeverity s) {
  switch (s) {
    case WordSeverity.low:      return const Color(0xFF9CA3AF);
    case WordSeverity.medium:   return const Color(0xFFF59E0B);
    case WordSeverity.high:     return const Color(0xFFEF4444);
    case WordSeverity.critical: return const Color(0xFF991B1B);
  }
}

Color _actionColor(IncidentAction a) {
  switch (a) {
    case IncidentAction.allowed:   return const Color(0xFF9CA3AF);
    case IncidentAction.warned:    return const Color(0xFFF59E0B);
    case IncidentAction.rewritten: return const Color(0xFF3B82F6);
    case IncidentAction.blocked:   return const Color(0xFFEF4444);
    case IncidentAction.suspended: return const Color(0xFF991B1B);
  }
}
