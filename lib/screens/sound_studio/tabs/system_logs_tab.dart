/// Sound Studio §53 — Screen 4 (System Logs).
///
/// Mirrors `docs/ui-specs/sound_studio_mockups/sound_studio_mockups/logs.html`.
/// 4 health cards driven by AudioService.audioServiceStateStream + a filterable
/// timeline of `sound_system_log`. CSV export via the browser's data: URL
/// (web only) — mobile shows a "available on web" hint.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../services/audio_service.dart';
import '../../../services/sounds_log_service.dart';
import '../sound_studio_screen.dart';
import '../sound_studio_tokens.dart';
import '_csv_downloader.dart';

class SystemLogsTab extends StatefulWidget {
  const SystemLogsTab({super.key});

  @override
  State<SystemLogsTab> createState() => _SystemLogsTabState();
}

class _SystemLogsTabState extends State<SystemLogsTab> {
  SoundsLogType? _filter; // null == all
  final _entries = <SoundsLogEntry>[];
  bool _loadingMore = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _resubscribe();
  }

  void _resubscribe() {
    _sub?.cancel();
    _sub = SoundsLogService.instance
        .stream(type: _filter, limit: 50)
        .listen((batch) {
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(batch);
      });
    }, onError: (e) {
      if (!mounted) return;
      showStudioToast(context, 'שגיאה בטעינת הלוג: $e');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 20),
          _healthGrid(),
          const SizedBox(height: 20),
          _filterBar(),
          const SizedBox(height: 12),
          _timeline(),
          const SizedBox(height: 16),
          _loadMore(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'היסטוריה ובריאות מערכת',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: StudioPalette.textPrimary,
                  height: 1.2,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'שינויים, שגיאות, ודיאגנוסטיקה כשמשהו לא עובד',
                style: TextStyle(
                  fontSize: 13,
                  color: StudioPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _exportCsv,
          icon: const Icon(Icons.file_download_outlined, size: 14),
          label: const Text('יצא לוג'),
          style: OutlinedButton.styleFrom(
            foregroundColor: StudioPalette.textPrimary,
            side: const BorderSide(
                color: StudioPalette.borderMedium, width: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _healthGrid() {
    return StreamBuilder<AudioServiceState>(
      stream: AudioService.instance.audioServiceStateStream,
      initialData: AudioService.instance.currentState(),
      builder: (context, snap) {
        final state = snap.data ?? AudioService.instance.currentState();
        return LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 720 ? 4 : 2;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: cols == 4 ? 2.7 : 2.4,
              children: [
                _HealthCard(
                  label: 'AudioService',
                  value: state.isInitialized ? 'פעיל' : 'לא מאותחל',
                  color: state.isInitialized
                      ? StudioPalette.green
                      : StudioPalette.red,
                  pulse: state.isInitialized,
                ),
                _HealthCard(
                  label: 'Pre-buffering',
                  value:
                      '${state.bufferedCount}/${state.totalSounds} טעונים',
                  color: state.allBuffered
                      ? StudioPalette.green
                      : StudioPalette.amber,
                ),
                _HealthCard(
                  label: 'iOS Unlock',
                  value: kIsWeb
                      ? (state.iosAudioUnlocked ? 'משוחרר' : 'ממתין למגע')
                      : 'לא נדרש',
                  color: kIsWeb
                      ? (state.iosAudioUnlocked
                          ? StudioPalette.green
                          : StudioPalette.amber)
                      : StudioPalette.green,
                ),
                _HealthCard(
                  label: 'Firestore Sync',
                  value: state.lastSyncAt == null
                      ? 'ממתין לסנכרון'
                      : 'השהייה ${_latencyLabel(state.firestoreSyncLatency)}',
                  color: state.firestoreSyncLatency.inSeconds > 5
                      ? StudioPalette.amber
                      : StudioPalette.green,
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _latencyLabel(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds} מ״ש';
    return '${d.inSeconds} שנ׳';
  }

  Widget _filterBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'סנן:',
            style: TextStyle(
              fontSize: 12,
              color: StudioPalette.textTertiary,
            ),
          ),
        ),
        _filterChip('הכל', null),
        _filterChip('שינויים', SoundsLogType.change),
        _filterChip('שגיאות', SoundsLogType.error),
        _filterChip('אזהרות', SoundsLogType.warning),
        _filterChip('העלאות', SoundsLogType.upload),
        _filterChip('מערכת', SoundsLogType.system),
      ],
    );
  }

  Widget _filterChip(String label, SoundsLogType? type) {
    final active = _filter == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() => _filter = type);
          _resubscribe();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? StudioPalette.bgSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? StudioPalette.borderStrong
                  : StudioPalette.borderLight,
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w500 : FontWeight.normal,
              color: active
                  ? StudioPalette.textPrimary
                  : StudioPalette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeline() {
    if (_entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60),
        alignment: Alignment.center,
        child: const Text(
          'אין רשומות בקטגוריה זו',
          style: TextStyle(color: StudioPalette.textTertiary),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _entries.length; i++) ...[
            _LogRow(entry: _entries[i]),
            if (i < _entries.length - 1)
              const Divider(
                height: 0.5,
                thickness: 0.5,
                color: StudioPalette.borderLight,
              ),
          ],
        ],
      ),
    );
  }

  Widget _loadMore() {
    if (_entries.isEmpty) return const SizedBox.shrink();
    return Center(
      child: OutlinedButton(
        onPressed: _loadingMore ? null : _onLoadMore,
        style: OutlinedButton.styleFrom(
          foregroundColor: StudioPalette.textPrimary,
          side: const BorderSide(
              color: StudioPalette.borderMedium, width: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: Text(_loadingMore ? 'טוען…' : 'טען עוד 20 רשומות'),
      ),
    );
  }

  Future<void> _onLoadMore() async {
    if (_entries.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final next = await SoundsLogService.instance.fetchMore(
        type: _filter,
        startAfter: _entries.last.rawDoc,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(next);
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showStudioToast(context, 'שגיאה: $e');
    }
  }

  Future<void> _exportCsv() async {
    if (!kIsWeb) {
      showStudioToast(context, 'ייצוא CSV זמין כרגע רק מהדפדפן (Web).');
      return;
    }
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final sb = StringBuffer();
    sb.writeln('type,title,description,actor,platform,timestamp');
    for (final e in _entries) {
      sb.writeln([
        e.type.wireName,
        _csvEscape(e.title),
        _csvEscape(e.description),
        _csvEscape(e.actor),
        _csvEscape(e.platform),
        e.timestamp == null ? '' : fmt.format(e.timestamp!),
      ].join(','));
    }
    final filename =
        'sound_system_log_${DateTime.now().millisecondsSinceEpoch}.csv';
    // §65: cross-platform via conditional import. On web → triggers an
    // <a download> click. On non-web → no-op (the export button is gated
    // upstream on kIsWeb anyway, so this is just compile-safety).
    downloadCsv(filename: filename, content: sb.toString());
    if (!mounted) return;
    showStudioToast(context, '📥 הוורד CSV עם ${_entries.length} רשומות');
  }

  String _csvEscape(String s) {
    if (s.isEmpty) return '';
    final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
    if (!needsQuote) return s;
    return '"${s.replaceAll('"', '""')}"';
  }
}

class _HealthCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool pulse;
  const _HealthCard({
    required this.label,
    required this.value,
    required this.color,
    this.pulse = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StudioPills.statusDot(color: color, pulse: pulse),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: StudioPalette.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: StudioPalette.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final SoundsLogEntry entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = _typeStyle(entry.type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(t.icon, color: t.color, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: StudioPalette.textPrimary,
                      ),
                    ),
                    StudioPills.pill(
                      text: t.label,
                      background: t.bg,
                      foreground: t.color,
                    ),
                  ],
                ),
                if (entry.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: StudioPalette.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _relative(entry.timestamp),
                  style: const TextStyle(
                    fontSize: 12,
                    color: StudioPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.actor,
                  style: const TextStyle(
                    fontSize: 11,
                    color: StudioPalette.textTertiary,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime? at) {
    if (at == null) return '—';
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return 'לפני ${diff.inSeconds} שנ׳';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שע׳';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    return DateFormat('d/M/yy').format(at);
  }

  static _LogTypeStyle _typeStyle(SoundsLogType type) {
    switch (type) {
      case SoundsLogType.change:
        return const _LogTypeStyle(
          color: StudioPalette.primary,
          bg: StudioPalette.primaryLight,
          label: 'שינוי',
          icon: Icons.edit_outlined,
        );
      case SoundsLogType.upload:
        return const _LogTypeStyle(
          color: StudioPalette.greenDark,
          bg: StudioPalette.greenLight,
          label: 'העלאה',
          icon: Icons.file_upload_outlined,
        );
      case SoundsLogType.warning:
        return const _LogTypeStyle(
          color: StudioPalette.amberDark,
          bg: StudioPalette.amberLight,
          label: 'אזהרה',
          icon: Icons.warning_amber_rounded,
        );
      case SoundsLogType.system:
        return const _LogTypeStyle(
          color: StudioPalette.blue,
          bg: StudioPalette.blueLight,
          label: 'מערכת',
          icon: Icons.refresh_rounded,
        );
      case SoundsLogType.error:
        return const _LogTypeStyle(
          color: StudioPalette.red,
          bg: StudioPalette.redLight,
          label: 'שגיאה',
          icon: Icons.error_outline_rounded,
        );
    }
  }
}

class _LogTypeStyle {
  final Color color;
  final Color bg;
  final String label;
  final IconData icon;
  const _LogTypeStyle({
    required this.color,
    required this.bg,
    required this.label,
    required this.icon,
  });
}

