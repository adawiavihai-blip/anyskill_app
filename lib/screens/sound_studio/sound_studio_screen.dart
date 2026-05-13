/// Sound Studio §53 — admin "Sounds" tab shell.
///
/// Replaces the legacy `AdminSoundsTab` with a 4-pane workspace:
///   1. Studio    — event ↔ sound mapping (existing functionality)
///   2. Library   — every sound the app could play, filterable + uploadable
///   3. Analytics — KPIs from sound_events_log + AI insight
///   4. Logs      — sound_system_log timeline + 4 health cards
///
/// AudioService state is loaded once for the parent screen and shared with
/// every tab via plain widget params. The legacy admin_sounds_tab.dart was
/// deleted in this PR — `git revert` is the rollback path. See CLAUDE.md
/// §53 (sound studio).
library;

import 'package:flutter/material.dart';

import '../../services/audio_service.dart';
import '../../services/sound_library_service.dart';
import 'sound_studio_tokens.dart';
import 'tabs/studio_tab.dart';
import 'tabs/library_tab.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/system_logs_tab.dart';

class SoundStudioScreen extends StatefulWidget {
  const SoundStudioScreen({super.key});

  @override
  State<SoundStudioScreen> createState() => _SoundStudioScreenState();
}

class _SoundStudioScreenState extends State<SoundStudioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    // Idempotent: skips ids that already exist. Fire-and-forget.
    SoundLibraryService.instance.ensureSeeded();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: StudioPalette.bgPage,
        body: SafeArea(
          child: Column(
            children: [
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  physics: const ClampingScrollPhysics(),
                  children: const [
                    StudioTab(),
                    LibraryTab(),
                    AnalyticsTab(),
                    SystemLogsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: StudioPalette.bgPage,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: StudioPalette.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StudioPalette.borderLight, width: 0.5),
        ),
        child: TabBar(
          controller: _tab,
          isScrollable: true,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          indicator: BoxDecoration(
            color: StudioPalette.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          labelColor: Colors.white,
          unselectedLabelColor: StudioPalette.textSecondary,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: const [
            Tab(child: _TabLabel('סטודיו')),
            Tab(child: _TabLabel('ספרייה')),
            Tab(child: _TabLabel('אנליטיקס')),
            Tab(child: _TabLabel('לוג מערכת')),
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String text;
  const _TabLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text),
    );
  }
}

// ── Shared utilities ─────────────────────────────────────────────────────────

/// Resolves the Hebrew label for an [AppSound] from its enum hebrewLabel
/// ("Wealth Crystal 💎 — תשלומים"). Returns the Hebrew action part after
/// the em-dash, or the English name if no dash.
String soundActionLabelHe(AppSound sound) {
  final parts = sound.hebrewLabel.split('—');
  return parts.length > 1 ? parts.last.trim() : parts.first.trim();
}

String soundEnglishLabel(AppSound sound) {
  final parts = sound.hebrewLabel.split('—');
  return parts.first.trim();
}

/// Floating bottom toast — wired from every tab (Studio status + Library
/// upload + Analytics insight + Logs export). Styled per mockup.
void showStudioToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      backgroundColor: StudioPalette.textPrimary,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      width: 320,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
