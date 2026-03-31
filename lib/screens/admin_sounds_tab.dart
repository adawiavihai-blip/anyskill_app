/// AnySkill — Admin Sounds Management Tab (צלילים)
///
/// Lists all app sound actions with:
///   - Action name (Hebrew)
///   - Current sound file name
///   - Play preview button
///   - Edit button to select from predefined list in Firebase Storage
///
/// Persists mappings to `app_settings/sounds` in Firestore.
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/audio_service.dart';

class AdminSoundsTab extends StatefulWidget {
  const AdminSoundsTab({super.key});

  @override
  State<AdminSoundsTab> createState() => _AdminSoundsTabState();
}

class _AdminSoundsTabState extends State<AdminSoundsTab> {
  static final _db = FirebaseFirestore.instance;
  static final _settingsRef = _db.collection('app_settings').doc('sounds');

  Map<String, String> _customMappings = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMappings();
  }

  Future<void> _loadMappings() async {
    try {
      final doc = await _settingsRef.get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        _customMappings = Map<String, String>.from(
          data.map((k, v) => MapEntry(k, v.toString())),
        );
      }
    } catch (e) {
      debugPrint('[AdminSoundsTab] load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveMappings() async {
    setState(() => _saving = true);
    try {
      await _settingsRef.set(_customMappings, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ מיפויי הצלילים נשמרו בהצלחה'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _playSound(AppSound sound) {
    AudioService.instance.play(sound);
  }

  void _showSoundPicker(AppSound sound) {
    final options = _predefinedSounds;
    final currentFile = _customMappings[sound.name] ?? sound.assetPath;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'בחר צליל ל${sound.hebrewLabel.split('—').last.trim()}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 16),

            // Sound options list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final opt = options[index];
                  final isSelected = opt.path == currentFile;
                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? const Color(0xFF6366F1)
                          : Colors.grey,
                    ),
                    title: Text(
                      opt.nameHe,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF1A1A2E),
                      ),
                    ),
                    subtitle: Text(
                      opt.path.split('/').last,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill,
                          color: Color(0xFF6366F1), size: 28),
                      onPressed: () {
                        // Preview this option
                        AudioService.instance.play(sound);
                      },
                    ),
                    onTap: () {
                      setState(() {
                        _customMappings[sound.name] = opt.path;
                      });
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Reset to default button
            TextButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('איפוס לברירת מחדל'),
              onPressed: () {
                setState(() {
                  _customMappings.remove(sound.name);
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.music_note_rounded,
                        color: Color(0xFF6366F1), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'ניהול צלילים',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppSound.values.length} פעולות עם צליל • לחצו על "ערוך" כדי להחליף צליל',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),

          // ── Event → Sound mapping ─────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.link_rounded, color: Color(0xFF6366F1), size: 18),
                    SizedBox(width: 6),
                    Text('מיפוי אירועים ← צלילים',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                ...AppEvent.values.map((event) {
                  final currentSound =
                      AudioService.instance.soundForEvent(event);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            event.hebrewLabel,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF4B5563)),
                          ),
                        ),
                        const Icon(Icons.arrow_back, size: 12,
                            color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 3,
                          child: DropdownButton<String>(
                            value: currentSound?.name ?? 'none',
                            isExpanded: true,
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6366F1)),
                            items: [
                              const DropdownMenuItem(
                                value: 'none',
                                child: Text('ללא צליל',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF))),
                              ),
                              ...AppSound.values.map((s) => DropdownMenuItem(
                                    value: s.name,
                                    child: Text(
                                      s.hebrewLabel.split('—').first.trim(),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  )),
                            ],
                            onChanged: (val) async {
                              if (val == null) return;
                              final sound = val == 'none'
                                  ? null
                                  : AppSound.values.byName(val);
                              await AudioService.instance
                                  .setEventMapping(event, sound);
                              setState(() {});
                              if (sound != null) {
                                AudioService.instance.play(sound);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.triggerFile.split('.').first,
                          style: const TextStyle(
                              fontSize: 9, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          // ── Sound inventory list ────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: AppSound.values.length,
              itemBuilder: (context, index) {
                final sound = AppSound.values[index];
                final customPath = _customMappings[sound.name];
                final isCustom = customPath != null;
                final displayFile = (customPath ?? sound.assetPath)
                    .split('/')
                    .last;

                // Parse Hebrew label: "Wealth Crystal 💎 — תשלומים"
                final parts = sound.hebrewLabel.split('—');
                final englishName = parts.first.trim();
                final hebrewAction = parts.length > 1 ? parts.last.trim() : '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        // ── Sound icon ─────────────────────────────────
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.audiotrack_rounded,
                            color: Color(0xFF6366F1),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),

                        // ── Info ───────────────────────────────────────
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hebrewAction.isNotEmpty
                                    ? hebrewAction
                                    : englishName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayFile,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ),
                                  if (isCustom) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1)
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'מותאם',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF6366F1),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── Play button ────────────────────────────────
                        IconButton(
                          onPressed: () => _playSound(sound),
                          icon: const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Color(0xFF6366F1),
                            size: 32,
                          ),
                          tooltip: 'השמע',
                        ),

                        // ── Edit button ────────────────────────────────
                        IconButton(
                          onPressed: () => _showSoundPicker(sound),
                          icon: const Icon(
                            Icons.edit_rounded,
                            color: Color(0xFF9CA3AF),
                            size: 20,
                          ),
                          tooltip: 'ערוך',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // ── Save FAB ────────────────────────────────────────────────────────
      floatingActionButton: _customMappings.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _saveMappings,
              backgroundColor: const Color(0xFF6366F1),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                _saving ? 'שומר...' : 'שמור שינויים',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  // ── Predefined sound options ───────────────────────────────────────────────
  // These are the sounds available for admins to select from.
  // In future, this list can be loaded from Firebase Storage listing.

  static final List<_SoundOption> _predefinedSounds = [
    _SoundOption(
      nameHe: 'Wealth Crystal — גביש עושר',
      path: 'audio/wealth_crystal.mp3',
    ),
    _SoundOption(
      nameHe: 'Solution Snap — פתרון מהיר',
      path: 'audio/solution_snap.mp3',
    ),
    _SoundOption(
      nameHe: 'Opportunity Pulse — פולס הזדמנות',
      path: 'audio/opportunity_pulse.mp3',
    ),
    _SoundOption(
      nameHe: 'Growth Ascend — עלייה וצמיחה',
      path: 'audio/growth_ascend.mp3',
    ),
  ];
}

class _SoundOption {
  final String nameHe;
  final String path;
  const _SoundOption({required this.nameHe, required this.path});
}
