/// AnySkill — Audio Branding Service
///
/// Singleton. Pre-loads all 4 brand sounds at app init so every trigger fires
/// with zero latency. Pairs each sound with its matched haptic pattern.
///
/// iOS Safari Audio Unlock:
///   iOS blocks audio playback until the user has tapped the screen at least
///   once in the current session. Call `unlockAudioOnGesture()` from the very
///   first pointer-down event (see main.dart's root Listener) to play a silent
///   clip inside the gesture handler, which permanently unlocks the Web Audio
///   Context for the session.
///
/// Usage:
///   await AudioService.instance.init();          // once, in main()
///   AudioService.instance.play(AppSound.wealthCrystal);
library;

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Sound catalogue ───────────────────────────────────────────────────────────

enum AppSound {
  wealthCrystal,    // wealth_crystal.mp3    — Reward / Luxury
  solutionSnap,     // solution_snap.mp3     — Tension Relief
  opportunityPulse, // opportunity_pulse.mp3 — Curiosity / Urgency
  growthAscend;     // growth_ascend.mp3     — Achievement / Dopamine

  String get assetPath => switch (this) {
    AppSound.wealthCrystal    => 'audio/wealth_crystal.mp3',
    AppSound.solutionSnap     => 'audio/solution_snap.mp3',
    AppSound.opportunityPulse => 'audio/opportunity_pulse.mp3',
    AppSound.growthAscend     => 'audio/growth_ascend.mp3',
  };

  String get hebrewLabel => switch (this) {
    AppSound.wealthCrystal    => 'Wealth Crystal 💎 — תשלומים',
    AppSound.solutionSnap     => 'Solution Snap 🔒 — התאמת AI',
    AppSound.opportunityPulse => 'Opportunity Pulse 🌊 — התראות',
    AppSound.growthAscend     => 'Growth Ascend 🚀 — עלייה ב-XP',
  };
}

// ── App Events → Sound Mapping ───────────────────────────────────────────────
// Central registry: every sound trigger in the app is mapped here.
// The admin Sounds tab displays this mapping and allows reassignment.

enum AppEvent {
  onPaymentSuccess,   // Expert marks job complete / escrow unlocked
  onAiMatchFound,     // AI Matchmaker locked in a provider
  onNewOpportunity,   // New job request arrives in opportunities feed
  onCourseCompleted,  // Academy course completion + XP
  onLogin;            // User successfully logs in (default: none)

  /// Default sound for this event. Null means silent (no sound).
  AppSound? get defaultSound => switch (this) {
    AppEvent.onPaymentSuccess  => AppSound.wealthCrystal,
    AppEvent.onAiMatchFound    => AppSound.solutionSnap,
    AppEvent.onNewOpportunity  => AppSound.opportunityPulse,
    AppEvent.onCourseCompleted => AppSound.growthAscend,
    AppEvent.onLogin           => null,  // silent by default
  };

  /// Hebrew description shown in admin UI.
  String get hebrewLabel => switch (this) {
    AppEvent.onPaymentSuccess  => 'תשלום שוחרר (אסקרו)',
    AppEvent.onAiMatchFound    => 'התאמת AI נמצאה',
    AppEvent.onNewOpportunity  => 'הזדמנות עבודה חדשה',
    AppEvent.onCourseCompleted => 'קורס הושלם (XP)',
    AppEvent.onLogin           => 'כניסת משתמש',
  };

  /// Code-level trigger location for admin reference.
  String get triggerFile => switch (this) {
    AppEvent.onPaymentSuccess  => 'chat_screen.dart',
    AppEvent.onAiMatchFound    => 'home_screen.dart',
    AppEvent.onNewOpportunity  => 'opportunities_screen.dart',
    AppEvent.onCourseCompleted => 'course_player_screen.dart',
    AppEvent.onLogin           => 'home_tab.dart',
  };
}

// ── Service ───────────────────────────────────────────────────────────────────

class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  static const String _kSound  = 'audio_sound_enabled';
  static const String _kHaptic = 'audio_haptic_enabled';

  bool _soundEnabled   = true;
  bool _hapticEnabled  = true;
  bool _initialised    = false;
  // true once the first user gesture has unlocked the iOS Web Audio Context.
  bool _audioUnlocked  = false;

  final Map<AppSound, AudioPlayer> _players = {};

  bool get soundEnabled  => _soundEnabled;
  bool get hapticEnabled => _hapticEnabled;

  // ── Initialisation — call once in main() after Firebase ────────────────────

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // Load user preferences
    try {
      final prefs  = await SharedPreferences.getInstance();
      _soundEnabled  = prefs.getBool(_kSound)  ?? true;
      _hapticEnabled = prefs.getBool(_kHaptic) ?? true;
    } catch (_) {}

    // Pre-buffer each sound. On web the AudioPlayer uses an <audio> element —
    // calling setSource() kicks off the network fetch before any user action,
    // ensuring zero-latency on first trigger.
    for (final sound in AppSound.values) {
      try {
        final player = AudioPlayer();
        // ReleaseMode.stop keeps the player alive after playback ends
        // so seek() + resume() can restart it instantly.
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(sound.assetPath));
        _players[sound] = player;
      } catch (e) {
        // Graceful: missing audio file just means no sound for that slot.
        debugPrint('AudioService: failed to preload ${sound.assetPath} — $e');
      }
    }
    debugPrint('AudioService: initialised (sound=$_soundEnabled, haptic=$_hapticEnabled)');

    // Load custom sound + event mappings from Firestore (fire-and-forget)
    _loadCustomMappings();
    _loadEventMappings();
  }

  /// Loads admin-configured sound mappings from `app_settings/sounds`.
  /// If a mapping exists, replaces the preloaded player for that sound.
  Future<void> _loadCustomMappings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('sounds')
          .get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      for (final sound in AppSound.values) {
        final customPath = data[sound.name] as String?;
        if (customPath != null && customPath != sound.assetPath) {
          try {
            final player = AudioPlayer();
            await player.setReleaseMode(ReleaseMode.stop);
            if (customPath.startsWith('http')) {
              await player.setSource(UrlSource(customPath));
            } else {
              await player.setSource(AssetSource(customPath));
            }
            // Dispose old player and replace
            _players[sound]?.dispose();
            _players[sound] = player;
            debugPrint('AudioService: loaded custom sound for ${sound.name}');
          } catch (e) {
            debugPrint('AudioService: failed to load custom ${sound.name}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('AudioService: custom mappings load error: $e');
    }
  }

  // ── iOS Web Audio Context unlock ──────────────────────────────────────────
  //
  // iOS Safari enforces a strict "user gesture required" policy on all audio.
  // Call this method from the very first pointer-down anywhere in the app
  // (see the root Listener in main.dart). It fires-and-forgets a 0-volume
  // playback of the first available preloaded sound, which permanently unlocks
  // the Web Audio Context for the current browser session.
  //
  // After this call, every subsequent AudioService.play() works without any
  // gesture requirement — even from background notification callbacks.
  //
  // On non-web platforms this is a no-op (native audio never needs unlocking).
  void unlockAudioOnGesture() {
    // Native platforms handle audio without gesture restrictions.
    if (!kIsWeb) return;
    // Already unlocked — skip.
    if (_audioUnlocked) return;
    _audioUnlocked = true;

    // Fire-and-forget: starting the play call within this synchronous method
    // means the browser sees it as initiated by the user gesture event handler.
    // Using unawaited() keeps us in the same JS event loop tick.
    unawaited(_doUnlock());
  }

  Future<void> _doUnlock() async {
    final player = _players.values.firstOrNull;
    if (player == null) return;
    try {
      // Volume 0 — the user hears nothing; the Audio Context gets unlocked.
      await player.setVolume(0.0);
      await player.seek(Duration.zero);
      await player.resume();
      await Future.delayed(const Duration(milliseconds: 80));
      await player.stop();
      // Restore normal volume for subsequent real playback.
      await player.setVolume(1.0);
      debugPrint('AudioService: iOS Web Audio Context unlocked ✓');
    } catch (e) {
      debugPrint('AudioService._doUnlock error: $e');
    }
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  Future<void> play(AppSound sound) async {
    // Haptic always fires regardless of audio mute setting.
    // On iOS, this provides tactile feedback even when the phone is on silent.
    if (_hapticEnabled) _triggerHaptic(sound);

    if (!_soundEnabled) return;

    final player = _players[sound];
    if (player == null) return; // file not preloaded — silent fallback

    try {
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('AudioService.play(${sound.name}) error: $e');
    }
  }

  // ── Event-based playback (resolves through custom mapping) ─────────────────

  /// Custom event→sound mapping loaded from Firestore `app_settings/sounds`.
  /// Key: AppEvent.name, Value: AppSound.name.
  final Map<String, String> _eventMappings = {};

  /// Loads custom event→sound mappings from Firestore.
  /// Called during init() after sound files are preloaded.
  Future<void> _loadEventMappings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings').doc('event_sounds').get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      for (final entry in data.entries) {
        _eventMappings[entry.key] = entry.value.toString();
      }
      debugPrint('AudioService: loaded ${_eventMappings.length} event mappings');
    } catch (e) {
      debugPrint('AudioService: event mappings load error: $e');
    }
  }

  /// Plays the sound assigned to [event]. Uses custom mapping if set,
  /// otherwise falls back to the event's default sound.
  /// If mapped to 'none' or default is null, plays NOTHING.
  Future<void> playEvent(AppEvent event) async {
    final mappedName = _eventMappings[event.name];

    // Explicit "none" mapping — play nothing
    if (mappedName == 'none') return;

    AppSound? sound = event.defaultSound;
    if (mappedName != null) {
      try {
        sound = AppSound.values.byName(mappedName);
      } catch (_) {
        // Invalid mapping — fall back to default
      }
    }

    // Null default (e.g., onLogin) — play nothing unless admin mapped a sound
    if (sound == null) return;
    return play(sound);
  }

  /// Returns the current sound for an event (respecting custom mapping).
  /// Returns null if mapped to 'none' or default is null.
  AppSound? soundForEvent(AppEvent event) {
    final mappedName = _eventMappings[event.name];
    if (mappedName == 'none') return null;
    if (mappedName != null) {
      try {
        return AppSound.values.byName(mappedName);
      } catch (_) {}
    }
    return event.defaultSound;
  }

  /// Saves a custom event→sound mapping. Pass null to set "none" (silent).
  Future<void> setEventMapping(AppEvent event, AppSound? sound) async {
    final value = sound?.name ?? 'none';
    _eventMappings[event.name] = value;
    await FirebaseFirestore.instance
        .collection('app_settings')
        .doc('event_sounds')
        .set({event.name: value}, SetOptions(merge: true));
  }

  // ── Haptic patterns — each matched to its sound's psychoacoustic profile ────
  //
  // HapticFeedback works on iOS regardless of silent/ring switch position.
  // It also works in Flutter Web running as a PWA on iPhone (via the platform
  // channel bridged to UIImpactFeedbackGenerator).

  void _triggerHaptic(AppSound sound) {
    if (!_hapticEnabled) return;
    switch (sound) {
      case AppSound.wealthCrystal:
        // Sharp, premium — single heavy thud mirrors the crystal "clink"
        HapticFeedback.heavyImpact();
        break;
      case AppSound.solutionSnap:
        // Firm "lock-in" click — medium impact at the snap moment
        HapticFeedback.mediumImpact();
        break;
      case AppSound.opportunityPulse:
        // Soft double-tap — two light taps 120ms apart = organic pulse feel
        HapticFeedback.lightImpact();
        Future.delayed(
          const Duration(milliseconds: 120),
          HapticFeedback.lightImpact,
        );
        break;
      case AppSound.growthAscend:
        // Rising pattern — three light taps, 100ms apart = ascending feel
        HapticFeedback.lightImpact();
        Future.delayed(
          const Duration(milliseconds: 100),
          HapticFeedback.lightImpact,
        );
        Future.delayed(
          const Duration(milliseconds: 200),
          HapticFeedback.mediumImpact,
        );
        break;
    }
  }

  // ── User preference setters (persisted to SharedPreferences) ───────────────

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSound, value);
    } catch (_) {}
  }

  Future<void> setHapticEnabled(bool value) async {
    _hapticEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHaptic, value);
    } catch (_) {}
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    _initialised  = false;
    _audioUnlocked = false;
  }
}
