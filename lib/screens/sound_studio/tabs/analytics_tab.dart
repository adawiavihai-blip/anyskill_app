/// Sound Studio §53 — Screen 3 (Analytics).
///
/// Mirrors `docs/ui-specs/sound_studio_mockups/sound_studio_mockups/analytics.html`.
/// One-shot aggregation over `sound_events_log` (limit 1000 per spec).
/// Time-range selector flips 24h / 7d / 30d. Chart uses fl_chart.
/// AI insight surfaces the lowest-CTR sound + a placeholder action.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../services/audio_service.dart';
import '../../../services/sound_library_service.dart';
import '../sound_studio_screen.dart';
import '../sound_studio_tokens.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  AnalyticsRange _range = AnalyticsRange.last7d;
  Future<SoundAnalyticsSnapshot>? _future;
  bool _aiDismissed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = SoundLibraryService.instance.fetchAnalytics(range: _range);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      color: StudioPalette.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 20),
            FutureBuilder<SoundAnalyticsSnapshot>(
              future: _future,
              builder: (context, snap) {
                final data = snap.data ?? SoundAnalyticsSnapshot.empty();
                final loading =
                    snap.connectionState == ConnectionState.waiting;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _kpiGrid(data, loading),
                    const SizedBox(height: 24),
                    _chartCard(data, loading),
                    const SizedBox(height: 24),
                    _rankingCard(data, loading),
                    const SizedBox(height: 24),
                    if (!_aiDismissed) _aiInsightCard(data),
                  ],
                );
              },
            ),
          ],
        ),
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
                'איך הצלילים מתפקדים',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: StudioPalette.textPrimary,
                  height: 1.2,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'כל מה שצריך לדעת כדי לקבל החלטות מבוססות נתונים',
                style: TextStyle(
                  fontSize: 13,
                  color: StudioPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        _rangeSelector(),
      ],
    );
  }

  Widget _rangeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in AnalyticsRange.values) _rangeBtn(r),
        ],
      ),
    );
  }

  Widget _rangeBtn(AnalyticsRange r) {
    final selected = _range == r;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          if (_range == r) return;
          setState(() => _range = r);
          _refresh();
          showStudioToast(context, '📊 מציג נתונים: ${r.label}');
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color:
                selected ? StudioPalette.bgMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            r.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
              color: selected
                  ? StudioPalette.textPrimary
                  : StudioPalette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiGrid(SoundAnalyticsSnapshot data, bool loading) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 4 ? 1.7 : 1.6,
          children: [
            _KpiCard(
              label: 'סך השמעות',
              value: loading
                  ? '—'
                  : NumberFormat.decimalPattern('he_IL').format(data.totalPlays),
              trendLabel: data.totalPlays == 0
                  ? 'אין נתונים בטווח'
                  : 'בטווח ${_range.label}',
              trendUp: true,
            ),
            _KpiCard(
              label: 'CTR ממוצע',
              value: loading
                  ? '—'
                  : '${data.avgCtrPercent.toStringAsFixed(0)}%',
              trendLabel: 'פעולה אחרי השמעה',
              trendUp: data.avgCtrPercent >= 60,
            ),
            _KpiCard(
              label: 'השתקות משתמשים',
              value: loading
                  ? '—'
                  : '${data.mutePercent.toStringAsFixed(1)}%',
              trendLabel:
                  data.mutePercent > 4 ? 'דורש בדיקה' : 'בטווח רגיל',
              trendUp: data.mutePercent <= 4,
            ),
            _KpiCard(
              label: 'צליל מוביל',
              value: loading || data.topSoundId.isEmpty
                  ? '—'
                  : _englishLabelFor(data.topSoundId),
              trendLabel: data.topSoundId.isEmpty
                  ? 'ממתין לנתונים'
                  : 'CTR ${data.topSoundCtr.toStringAsFixed(0)}%',
              trendUp: true,
              valueFontSize: 18,
            ),
          ],
        );
      },
    );
  }

  String _englishLabelFor(String soundId) {
    try {
      final s = AppSound.values.firstWhere((e) => e.name == soundId);
      return soundEnglishLabel(s);
    } catch (_) {
      return soundId;
    }
  }

  Widget _chartCard(SoundAnalyticsSnapshot data, bool loading) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'השמעות לפי יום',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: StudioPalette.textPrimary,
                ),
              ),
              for (final s in AppSound.values)
                _legend(soundEnglishLabel(s),
                    StudioPalette.soundColor(s.name)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'פילוח לפי סוג צליל',
            style: TextStyle(
              fontSize: 12,
              color: StudioPalette.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: StudioPalette.primary,
                    ),
                  )
                : data.daily.isEmpty
                    ? const Center(
                        child: Text(
                          'אין נתונים מספיקים בטווח',
                          style: TextStyle(
                            color: StudioPalette.textTertiary,
                          ),
                        ),
                      )
                    : _BarChart(daily: data.daily, range: _range),
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: StudioPalette.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _rankingCard(SoundAnalyticsSnapshot data, bool loading) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'דירוג ביצועים',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: StudioPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  color: StudioPalette.primary,
                ),
              ),
            )
          else if (data.ranking.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'אין נתונים מספיקים בטווח',
                style: TextStyle(color: StudioPalette.textTertiary),
              ),
            )
          else
            for (var i = 0; i < data.ranking.length; i++) ...[
              _rankingRow(data.ranking[i]),
              if (i < data.ranking.length - 1)
                const Divider(
                  height: 16,
                  thickness: 0.5,
                  color: StudioPalette.borderLight,
                ),
            ],
        ],
      ),
    );
  }

  Widget _rankingRow(SoundRanking r) {
    final tint = StudioPalette.soundColor(r.soundId);
    final tintLight = StudioPalette.soundLight(r.soundId);
    final tintDark = StudioPalette.soundDark(r.soundId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tintLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${r.rank}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: tintDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _englishLabelFor(r.soundId),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: StudioPalette.textPrimary,
                  ),
                ),
              ),
              Text(
                '${NumberFormat.decimalPattern('he_IL').format(r.plays)} השמעות',
                style: const TextStyle(
                  fontSize: 12,
                  color: StudioPalette.textTertiary,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'CTR ${r.ctrPercent.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: r.ctrPercent >= 85
                      ? StudioPalette.greenDark
                      : StudioPalette.amberDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 44),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: r.ctrPercent / 100,
                minHeight: 6,
                backgroundColor: StudioPalette.bgMuted,
                valueColor: AlwaysStoppedAnimation(tint),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiInsightCard(SoundAnalyticsSnapshot data) {
    final lowest = data.ranking.isEmpty
        ? null
        : (List<SoundRanking>.from(data.ranking)
              ..sort((a, b) => a.ctrPercent.compareTo(b.ctrPercent)))
            .first;
    final body = lowest == null
        ? 'נצברו עוד מעט נתונים? בקרוב נציג כאן תובנות כשיהיו 50+ השמעות בטווח.'
        : '${_englishLabelFor(lowest.soundId)} עם CTR של ${lowest.ctrPercent.toStringAsFixed(0)}% — הנמוך ביותר. שווה לבחון חלופה ולעקוב.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioPalette.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: StudioPalette.primaryLighter,
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: StudioPalette.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'תובנת AI לטווח הנוכחי',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: StudioPalette.primaryDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: StudioPalette.primary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () => showStudioToast(
                        context,
                        '🧪 בקרוב — הגדרת A/B test',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StudioPalette.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'הרץ A/B test ←',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _aiDismissed = true);
                        showStudioToast(context, '✓ התובנה נדחתה');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StudioPalette.textPrimary,
                        side: const BorderSide(
                          color: StudioPalette.borderMedium,
                          width: 0.5,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'דחה תובנה',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String trendLabel;
  final bool trendUp;
  final double valueFontSize;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.trendLabel,
    required this.trendUp,
    this.valueFontSize = 28,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: StudioPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w500,
              color: StudioPalette.textPrimary,
              height: 1.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Text(
            trendLabel,
            style: TextStyle(
              fontSize: 11,
              color: trendUp ? StudioPalette.greenDark : StudioPalette.red,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<SoundDailyBucket> daily;
  final AnalyticsRange range;
  const _BarChart({required this.daily, required this.range});

  @override
  Widget build(BuildContext context) {
    final maxTotal = daily
        .map((b) => b.total)
        .fold<int>(0, (p, c) => c > p ? c : p)
        .toDouble();
    final yMax = maxTotal == 0 ? 10.0 : (maxTotal * 1.15);
    final soundOrder = AppSound.values;

    return BarChart(
      BarChartData(
        maxY: yMax,
        alignment: BarChartAlignment.spaceAround,
        barGroups: List.generate(daily.length, (i) {
          final bucket = daily[i];
          var stack = 0.0;
          final stacks = <BarChartRodStackItem>[];
          for (final sound in soundOrder) {
            final v = (bucket.bySoundId[sound.name] ?? 0).toDouble();
            if (v <= 0) continue;
            stacks.add(BarChartRodStackItem(
              stack,
              stack + v,
              StudioPalette.soundColor(sound.name),
            ));
            stack += v;
          }
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: stack,
                width: 24,
                borderRadius: BorderRadius.circular(2),
                rodStackItems: stacks,
                color: StudioPalette.bgMuted,
              ),
            ],
          );
        }),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yMax / 4,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: StudioPalette.borderLight,
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: yMax / 4,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Text(
                  v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}K' : v.toInt().toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: StudioPalette.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= daily.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _bucketLabel(daily[i].day),
                    style: const TextStyle(
                      fontSize: 10,
                      color: StudioPalette.textTertiary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(enabled: true),
      ),
    );
  }

  String _bucketLabel(DateTime day) {
    if (range == AnalyticsRange.last24h) {
      return '${day.hour.toString().padLeft(2, '0')}:00';
    }
    return DateFormat('d/M', 'he_IL').format(day);
  }
}
