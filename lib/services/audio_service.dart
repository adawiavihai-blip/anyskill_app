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
