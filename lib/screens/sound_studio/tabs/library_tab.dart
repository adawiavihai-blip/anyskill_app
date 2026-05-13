/// Sound Studio §53 — Screen 2 (Library).
///
/// Mirrors `docs/ui-specs/sound_studio_mockups/sound_studio_mockups/library.html`.
/// Lists every sound the app could play (active + archived + AI suggestions),
/// supports filtering, file upload, and a deep-dive panel with waveform +
/// emotion fingerprint.
///
/// Upload is web-only for now (delegated to [pickAudioFile] via a
/// conditional import — see `audio_file_picker.dart` and CLAUDE.md §65).
/// Mobile admins see an "available on web" notice — acceptable since the
/// admin panel is a web-first surface and adding `file_picker` to deps
/// just for one admin tab is overkill.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/sound_library_service.dart';
import '../sound_studio_screen.dart';
import '../sound_studio_tokens.dart';
import 'audio_file_picker.dart';

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

enum _LibraryFilter { all, active, payments, notifications, achievements, archived }

extension _LibraryFilterX on _LibraryFilter {
  String get label => switch (this) {
        _LibraryFilter.all => 'הכל',
        _LibraryFilter.active => 'פעילים',
        _LibraryFilter.payments => 'תשלומים',
        _LibraryFilter.notifications => 'התראות',
        _LibraryFilter.achievements => 'הישגים',
        _LibraryFilter.archived => 'בארכיון',
      };
}

class _LibraryTabState extends State<LibraryTab> {
  _LibraryFilter _filter = _LibraryFilter.all;
  String? _selectedId;
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SoundMetadata>>(
      stream: SoundLibraryService.instance.streamAll(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _empty('שגיאה בטעינת הספרייה: ${snap.error}');
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: StudioPalette.primary),
          );
        }
        final all = snap.data!;
        if (all.isEmpty) {
          return _empty('הספרייה ריקה — לחצו על "העלה צליל חדש" כדי להתחיל');
        }
        // Auto-select first if none selected (covers cold open).
        _selectedId ??= all.first.id;
        final selected = all.firstWhere(
          (s) => s.id == _selectedId,
          orElse: () => all.first,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(all),
              const SizedBox(height: 20),
              _filterChips(all),
              const SizedBox(height: 16),
              _grid(_applyFilter(all)),
              const SizedBox(height: 24),
              _DeepDive(sound: selected),
            ],
          ),
        );
      },
    );
  }

  List<SoundMetadata> _applyFilter(List<SoundMetadata> all) {
    return all.where((s) {
      switch (_filter) {
        case _LibraryFilter.all:
          return true;
        case _LibraryFilter.active:
          return s.status == SoundStatus.active;
        case _LibraryFilter.archived:
          return s.status == SoundStatus.archived;
        case _LibraryFilter.payments:
        case _LibraryFilter.notifications:
        case _LibraryFilter.achievements:
          return s.categoryFilter == _filter.name;
      }
    }).toList();
  }

  Widget _empty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined,
                size: 48, color: StudioPalette.textTertiary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: StudioPalette.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(List<SoundMetadata> all) {
    final total = all.length;
    final active = all.where((s) => s.status == SoundStatus.active).length;
    final archived = all.where((s) => s.status == SoundStatus.archived).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ספריית הצלילים',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: StudioPalette.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$total צלילים זמינים · $active פעילים · $archived בארכיון',
                style: const TextStyle(
                  fontSize: 13,
                  color: StudioPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _uploading ? null : _handleUpload,
          icon: _uploading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.file_upload_outlined, size: 16),
          label: Text(_uploading ? 'מעלה…' : 'העלה צליל חדש'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioPalette.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  Widget _filterChips(List<SoundMetadata> all) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _LibraryFilter.values)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _Chip(
                label: f == _LibraryFilter.all || f == _LibraryFilter.active
                    ? '${f.label} · ${_countFor(f, all)}'
                    : f.label,
                active: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  int _countFor(_LibraryFilter f, List<SoundMetadata> all) {
    switch (f) {
      case _LibraryFilter.all:
        return all.length;
      case _LibraryFilter.active:
        return all.where((s) => s.status == SoundStatus.active).length;
      case _LibraryFilter.archived:
        return all.where((s) => s.status == SoundStatus.archived).length;
      case _LibraryFilter.payments:
      case _LibraryFilter.notifications:
      case _LibraryFilter.achievements:
        return all.where((s) => s.categoryFilter == f.name).length;
    }
  }

  Widget _grid(List<SoundMetadata> filtered) {
    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: const Text(
          'אין צלילים בקטגוריה זו',
          style: TextStyle(color: StudioPalette.textTertiary),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 2 ? 2.4 : 2.6,
          ),
          itemBuilder: (_, i) => _SoundCard(
            sound: filtered[i],
            selected: filtered[i].id == _selectedId,
            onTap: () => setState(() => _selectedId = filtered[i].id),
            onPreview: () => showStudioToast(
              context,
              '▶ ${filtered[i].name}',
            ),
            onActivate: () async {
              final ctx = context;
              try {
                await SoundLibraryService.instance.activate(filtered[i].id);
                if (!ctx.mounted) return;
                showStudioToast(ctx, '✓ ${filtered[i].name} נוסף לספרייה');
              } catch (e) {
                if (!ctx.mounted) return;
                showStudioToast(ctx, 'שגיאה: $e');
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _handleUpload() async {
    if (!kIsWeb) {
      showStudioToast(
        context,
        'ההעלאה זמינה כרגע רק מהפאנל בדפדפן (Web).',
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      // §65: cross-platform picker via conditional import. On web it
      // spawns the real `<input type=file>` element; on the test VM
      // / mobile native it returns null synchronously.
      final picked = !kIsWeb ? null : await pickAudioFile();
      if (picked == null) {
        if (!mounted) return;
        setState(() => _uploading = false);
        return;
      }
      final meta = await SoundLibraryService.instance.uploadNew(
        filename: picked.name,
        bytes: picked.bytes,
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _selectedId = meta.id;
      });
      showStudioToast(context, '✓ ${meta.name} הועלה (${meta.sizeLabel})');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showStudioToast(context, 'שגיאה בהעלאה: $e');
    }
  }
}

// _PickedFile lifted to `audio_file_picker.dart` as `PickedAudioFile`
// (§65 — conditional-import pattern so the test VM can compile this file).

// ── Filter chip ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
}

// ── Sound card ───────────────────────────────────────────────────────────────

class _SoundCard extends StatelessWidget {
  final SoundMetadata sound;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPreview;
  final VoidCallback onActivate;
  const _SoundCard({
    required this.sound,
    required this.selected,
    required this.onTap,
    required this.onPreview,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final tint = StudioPalette.soundColor(sound.id);
    final tintLight = StudioPalette.soundLight(sound.id);
    final isMuted = sound.status == SoundStatus.archived;
    final isSuggested = sound.status == SoundStatus.suggested;
    return Opacity(
      opacity: isMuted ? 0.7 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(selected ? 17 : 18),
          decoration: BoxDecoration(
            color: StudioPalette.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? StudioPalette.primary
                  : (isSuggested
                      ? StudioPalette.primary
                      : StudioPalette.borderLight),
              width: selected ? 2 : (isSuggested ? 1 : 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tintLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.audiotrack_rounded,
                      color: tint,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sound.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: StudioPalette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sound.category,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSuggested
                                ? tint
                                : StudioPalette.textTertiary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(),
                ],
              ),
              const SizedBox(height: 12),
              _MiniWaveform(color: tint, soundId: sound.id),
              const SizedBox(height: 12),
              Row(
                children: [
                  InkWell(
                    onTap: onPreview,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selected ? tint : tintLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: selected ? Colors.white : tint,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _metaLine(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: StudioPalette.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (isSuggested) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onActivate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioPalette.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('הוסף לספרייה',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _metaLine() {
    final parts = <String>[];
    if (sound.frequencyHz.isNotEmpty) parts.add('${sound.frequencyHz} Hz');
    if (sound.durationSeconds > 0) parts.add(sound.durationLabel);
    if (sound.sizeBytes > 0) parts.add(sound.sizeLabel);
    return parts.join(' · ');
  }

  Widget _statusBadge() {
    switch (sound.status) {
      case SoundStatus.active:
        return _StatusPill(
          text: 'פעיל',
          background: StudioPalette.green,
          foreground: Colors.white,
        );
      case SoundStatus.archived:
        return StudioPills.pill(text: 'בארכיון');
      case SoundStatus.suggested:
        return _StatusPill(
          text: 'חדש',
          background: StudioPalette.primaryLight,
          foreground: StudioPalette.primaryDark,
        );
    }
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  const _StatusPill({
    required this.text,
    required this.background,
    required this.foreground,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
      ),
    );
  }
}

// ── Mini waveform painter ────────────────────────────────────────────────────

class _MiniWaveform extends StatelessWidget {
  final Color color;
  final String soundId;
  const _MiniWaveform({required this.color, required this.soundId});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: CustomPaint(
        painter: _WaveformPainter(color: color, pattern: _patternFor(soundId)),
        size: Size.infinite,
      ),
    );
  }

  static List<double> _patternFor(String id) {
    // Same shapes as the mockup library.html `patterns` map.
    switch (id) {
      case 'wealthCrystal':
        return const [4, 8, 16, 24, 28, 20, 12, 18, 10, 6, 4, 6, 4, 2];
      case 'solutionSnap':
        return const [2, 8, 28, 20, 4, 2, 2, 2, 2];
      case 'opportunityPulse':
        return const [6, 14, 22, 26, 18, 12, 22, 14, 6];
      case 'growthAscend':
        return const [2, 6, 10, 16, 20, 26, 28, 32];
      case 'crystalBell':
      case 'softChime':
        return const [2, 6, 18, 28, 16, 6, 2];
      case 'coinDrop':
        return const [28, 20, 6, 16, 4, 2];
      default:
        return const [4, 8, 12, 16, 20, 16, 12, 8, 4];
    }
  }
}

class _WaveformPainter extends CustomPainter {
  final Color color;
  final List<double> pattern;
  _WaveformPainter({required this.color, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final barWidth = size.width / (pattern.length * 2);
    for (var i = 0; i < pattern.length; i++) {
      final h = pattern[i];
      final cx = barWidth * (i * 2 + 1);
      final scaledH = (h / 32) * size.height;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, size.height / 2),
          width: barWidth * 1.4,
          height: scaledH,
        ),
        const Radius.circular(1),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.color != color || old.pattern != pattern;
}

// ── Deep dive ────────────────────────────────────────────────────────────────

class _DeepDive extends StatelessWidget {
  final SoundMetadata sound;
  const _DeepDive({required this.sound});

  @override
  Widget build(BuildContext context) {
    final tint = StudioPalette.soundColor(sound.id);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'תצוגת עומק',
                      style: TextStyle(
                        fontSize: 11,
                        color: StudioPalette.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sound.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: StudioPalette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _ghostButton('השווה', () {
                showStudioToast(context, 'בקרוב — כלי השוואה');
              }),
              const SizedBox(width: 8),
              _ghostButton('A/B test', () {
                showStudioToast(context, 'בקרוב — הגדרת A/B test');
              }),
            ],
          ),
          const SizedBox(height: 20),
          _bigPlayer(tint),
          const SizedBox(height: 20),
          _statsGrid(),
          const SizedBox(height: 16),
          _analysisGrid(tint),
        ],
      ),
    );
  }

  Widget _bigPlayer(Color tint) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioPalette.bgMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: StudioPalette.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 56,
              child: CustomPaint(
                painter: _BigWaveformPainter(color: tint),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            sound.durationLabel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: StudioPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 600 ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cols == 4 ? 1.3 : 1.6,
          children: [
            _statCard(
              label: 'תדר עיקרי',
              value: sound.frequencyHz.isEmpty ? '—' : sound.frequencyHz,
              meta: sound.psychDescription,
              metaColor: StudioPalette.soundColor(sound.id),
            ),
            _statCard(
              label: 'BPM שווה ערך',
              value: '${sound.bpm}',
              meta: sound.bpm < 80
                  ? 'קצב לב רגוע'
                  : (sound.bpm < 100 ? 'קצב פעיל' : 'קצב מואץ'),
            ),
            _statCard(
              label: 'משך',
              value: sound.durationLabel,
              meta: 'בטווח אופטימלי',
            ),
            _statCard(
              label: 'עומס קוגניטיבי',
              value: sound.cognitiveLoad,
              meta: sound.cognitiveLoad == 'נמוך' ? 'לא מעייף' : 'דורש קשב',
              valueColor: sound.cognitiveLoad == 'נמוך'
                  ? StudioPalette.greenDark
                  : StudioPalette.amberDark,
            ),
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required String meta,
    Color? metaColor,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioPalette.bgMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: StudioPalette.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: valueColor ?? StudioPalette.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            style: TextStyle(
              fontSize: 11,
              color: metaColor ?? StudioPalette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _analysisGrid(Color tint) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 600;
        final children = [
          _frequencyProfileCard(tint),
          _emotionFingerprintCard(tint),
        ];
        if (!isWide) {
          return Column(
            children: [
              children[0],
              const SizedBox(height: 12),
              children[1],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }

  Widget _frequencyProfileCard(Color tint) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudioPalette.bgMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('פרופיל תדר',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text('Hz',
                  style: TextStyle(
                      fontSize: 11, color: StudioPalette.textTertiary)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 76,
            child: CustomPaint(
              painter: _FrequencyCurvePainter(color: tint),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('20', style: TextStyle(fontSize: 10, color: StudioPalette.textTertiary)),
              Text('200', style: TextStyle(fontSize: 10, color: StudioPalette.textTertiary)),
              Text('2K', style: TextStyle(fontSize: 10, color: StudioPalette.textTertiary)),
              Text('20K', style: TextStyle(fontSize: 10, color: StudioPalette.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emotionFingerprintCard(Color tint) {
    final entries = sound.emotionScores.entries.toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudioPalette.bgMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('טביעת רגש',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text('ניתוח AI',
                  style: TextStyle(
                      fontSize: 11,
                      color: StudioPalette.greenDark,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'אין נתוני רגש לצליל זה',
                style: TextStyle(
                    fontSize: 12, color: StudioPalette.textTertiary),
              ),
            )
          else
            ...entries.asMap().entries.map((e) {
              final i = e.key;
              final emotion = e.value.key;
              final score = e.value.value;
              final palette = [tint, StudioPalette.primary, StudioPalette.blue];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(emotion,
                                style: const TextStyle(fontSize: 12))),
                        Text('$score%',
                            style: const TextStyle(
                                fontSize: 12,
                                color: StudioPalette.textTertiary)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: score / 100,
                        minHeight: 6,
                        backgroundColor: StudioPalette.bgSurface,
                        valueColor: AlwaysStoppedAnimation(
                          palette[i % palette.length],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _ghostButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: StudioPalette.textPrimary,
        side: const BorderSide(color: StudioPalette.borderMedium, width: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

// ── Painter helpers ──────────────────────────────────────────────────────────

class _BigWaveformPainter extends CustomPainter {
  final Color color;
  _BigWaveformPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.7);
    const barCount = 50;
    final spacing = size.width / barCount;
    for (var i = 0; i < barCount; i++) {
      // Mimic the SVG sine*cos shape from the mockup big_player.
      final wave =
          (((i % 7) - 3).abs() * 8 + ((i % 11) - 5).abs() * 4 + 6).toDouble();
      final h = wave.clamp(4, size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(spacing * (i + 0.5), size.height / 2),
          width: spacing * 0.4,
          height: h.toDouble(),
        ),
        const Radius.circular(1),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BigWaveformPainter old) => old.color != color;
}

class _FrequencyCurvePainter extends CustomPainter {
  final Color color;
  _FrequencyCurvePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = color.withValues(alpha: 0.18);
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.9)
      ..quadraticBezierTo(w * 0.07, h * 0.78, w * 0.14, h * 0.6)
      ..quadraticBezierTo(w * 0.28, h * 0.18, w * 0.42, h * 0.22)
      ..quadraticBezierTo(w * 0.57, h * 0.45, w * 0.71, h * 0.55)
      ..quadraticBezierTo(w * 0.85, h * 0.76, w, h * 0.9);
    final fill = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _FrequencyCurvePainter old) =>
      old.color != color;
}
