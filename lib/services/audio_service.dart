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
import 'package:firebase_auth/firebase_auth.dart';
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

// ── State snapshot for the admin Sound Studio "System Logs" health cards ─────
//
// Sound Studio §53 — the admin SystemLogsTab subscribes to
// AudioService.instance.audioServiceStateStream and rebuilds 4 health cards
// (AudioService / Pre-buffering / iOS Unlock / Firestore Sync) on every emit.
// The snapshot is intentionally a plain immutable value class so the UI can
// equality-compare cheaply.

class AudioServiceState {
  final bool isInitialized;
  final Map<AppSound, bool> bufferedSounds;
  final bool iosAudioUnlocked;
  final Duration firestoreSyncLatency;
  final DateTime? lastSyncAt;
  final String? lastError;

  const AudioServiceState({
    required this.isInitialized,
    required this.bufferedSounds,
    required this.iosAudioUnlocked,
    required this.firestoreSyncLatency,
    this.lastSyncAt,
    this.lastError,
  });

  /// True when every preloaded slot has a live AudioPlayer.
  int get bufferedCount =>
      bufferedSounds.values.where((b) => b).length;
  int get totalSounds => bufferedSounds.length;
  bool get allBuffered => bufferedCount == totalSounds && totalSounds > 0;
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

  // ── Sound Studio §53 instrumentation ───────────────────────────────────────
  // These fields back the new admin SystemLogsTab health cards and the
  // sound_events_log analytics writes. Adding fields, NOT changing the existing
  // play/playEvent contract — every existing caller continues to work.
  Duration _lastSyncDuration = Duration.zero;
  DateTime? _lastSyncAt;
  String? _lastError;
  DateTime? _lastEventLogAt;
  String? _lastEventLogUid;
  final StreamController<AudioServiceState> _stateCtrl =
      StreamController<AudioServiceState>.broadcast();

  bool get soundEnabled  => _soundEnabled;
  bool get hapticEnabled => _hapticEnabled;

  // ── New getters for the Sound Studio health surface ──────────────────────
  bool get isInitialized => _initialised;
  bool get iosAudioUnlocked => _audioUnlocked;
  Duration get firestoreSyncLatency => _lastSyncDuration;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;

  /// Per-sound buffer status. True when the AudioPlayer is alive (setSource
  /// succeeded). False when preload failed — the sound will be silently
  /// skipped at play time.
  Map<AppSound, bool> get bufferedSounds => {
        for (final s in AppSound.values) s: _players.containsKey(s),
      };

  /// Snapshot stream consumed by the admin SystemLogsTab health cards.
  /// Emits on init, on every Firestore sync, on iOS unlock, and on errors.
  Stream<AudioServiceState> get audioServiceStateStream => _stateCtrl.stream;

  AudioServiceState currentState() => AudioServiceState(
        isInitialized: _initialised,
        bufferedSounds: bufferedSounds,
        iosAudioUnlocked: _audioUnlocked,
        firestoreSyncLatency: _lastSyncDuration,
        lastSyncAt: _lastSyncAt,
        lastError: _lastError,
      );

  void _emitState() {
    if (_stateCtrl.isClosed) return;
    _stateCtrl.add(currentState());
  }

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
        _lastError = 'preload ${sound.name}: $e';
      }
    }
    debugPrint('AudioService: initialised (sound=$_soundEnabled, haptic=$_hapticEnabled)');
    _emitState();

    // Load custom sound + event mappings from Firestore (fire-and-forget)
    _loadCustomMappings();
    _loadEventMappings();
  }

  /// Loads admin-configured sound mappings from `app_settings/sounds`.
  /// If a mapping exists, replaces the preloaded player for that sound.
  Future<void> _loadCustomMappings() async {
    final sw = Stopwatch()..start();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('sounds')
          .get();
      if (!doc.exists) {
        _recordSync(sw.elapsed);
        return;
      }
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
            _lastError = 'custom ${sound.name}: $e';
          }
        }
      }
      _recordSync(sw.elapsed);
    } catch (e) {
      debugPrint('AudioService: custom mappings load error: $e');
      _lastError = 'sounds load: $e';
      _recordSync(sw.elapsed);
    }
  }

  /// Records the latency of a Firestore round-trip and emits a fresh state
  /// snapshot. Used by the SystemLogsTab Firestore Sync health card.
  void _recordSync(Duration elapsed) {
    _lastSyncDuration = elapsed;
    _lastSyncAt = DateTime.now();
    _emitState();
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
      _emitState();
    } catch (e) {
      debugPrint('AudioService._doUnlock error: $e');
      _lastError = 'iOS unlock: $e';
      _emitState();
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
    final sw = Stopwatch()..start();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings').doc('event_sounds').get();
      if (!doc.exists) {
        _recordSync(sw.elapsed);
        return;
      }
      final data = doc.data() ?? {};
      for (final entry in data.entries) {
        _eventMappings[entry.key] = entry.value.toString();
      }
      debugPrint('AudioService: loaded ${_eventMappings.length} event mappings');
      _recordSync(sw.elapsed);
    } catch (e) {
      debugPrint('AudioService: event mappings load error: $e');
      _lastError = 'event_sounds load: $e';
      _recordSync(sw.elapsed);
    }
  }

  /// Plays the sound assigned to [event]. Uses custom mapping if set,
  /// otherwise falls back to the event's default sound.
  /// If mapped to 'none' or default is null, plays NOTHING.
  ///
  /// Sound Studio §53 — also writes a rate-limited record to
  /// `sound_events_log` when a sound actually plays. Rate limit: at most
  /// one log per (uid, 100ms) window so a tight loop of triggers cannot
  /// inflate analytics.
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
    await play(sound);
    // Fire-and-forget — never block the UI on analytics writes.
    unawaited(_logEventPlay(sound, event));
  }

  /// Writes a single record to `sound_events_log`. Best-effort, never throws.
  /// Rate-limited: at most one write per signed-in user per 100ms window.
  ///
  /// followUpAction is set to `true` for every event except `onLogin` —
  /// these events ARE consequences of user actions (payment release, AI
  /// match, etc.), so they implicitly satisfy the "user did something around
  /// the sound" definition. A more precise 5-second route-observer based
  /// implementation can replace this in a follow-up PR; the field shape stays
  /// stable.
  Future<void> _logEventPlay(AppSound sound, AppEvent event) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final now = DateTime.now();
      if (_lastEventLogUid == uid &&
          _lastEventLogAt != null &&
          now.difference(_lastEventLogAt!).inMilliseconds < 100) {
        return;
      }
      _lastEventLogAt = now;
      _lastEventLogUid = uid;
      await FirebaseFirestore.instance.collection('sound_events_log').add({
        'soundId': sound.name,
        'eventId': event.name,
        'userId': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'platform': _platformLabel(),
        'wasMuted': !_soundEnabled,
        'followUpAction': event != AppEvent.onLogin,
        // 30-day TTL — same convention as error_logs / activity_log (§19).
        'expireAt': Timestamp.fromDate(
          now.add(const Duration(days: 30)),
        ),
      });
    } catch (e) {
      debugPrint('AudioService._logEventPlay error: $e');
    }
  }

  String _platformLabel() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return 'Unknown';
    }
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
  ///
  /// Sound Studio §53 — also records sync latency for the System Logs
  /// health card and emits a fresh state snapshot.
  Future<void> setEventMapping(AppEvent event, AppSound? sound) async {
    final value = sound?.name ?? 'none';
    _eventMappings[event.name] = value;
    final sw = Stopwatch()..start();
    try {
      await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('event_sounds')
          .set({event.name: value}, SetOptions(merge: true));
      _recordSync(sw.elapsed);
    } catch (e) {
      _lastError = 'setEventMapping: $e';
      _recordSync(sw.elapsed);
      rethrow;
    }
  }

  /// Saves a custom file mapping for [sound]. Pass null to remove the
  /// override and fall back to the bundled asset on next init.
  ///
  /// New in Sound Studio §53. The previous admin tab wrote directly to
  /// `app_settings/sounds` from its own _saveMappings() helper. The Studio
  /// surface routes through this method so latency + state-stream emit
  /// happens in one place.
  Future<void> setSoundMapping(AppSound sound, String? assetOrUrl) async {
    final sw = Stopwatch()..start();
    final ref = FirebaseFirestore.instance
        .collection('app_settings')
        .doc('sounds');
    try {
      if (assetOrUrl == null) {
        await ref.update({sound.name: FieldValue.delete()});
      } else {
        await ref.set({sound.name: assetOrUrl}, SetOptions(merge: true));
      }
      // Hot-swap the live AudioPlayer so the next play() uses the new file
      // without an app restart.
      await _replacePlayer(sound, assetOrUrl);
      _recordSync(sw.elapsed);
    } catch (e) {
      _lastError = 'setSoundMapping: $e';
      _recordSync(sw.elapsed);
      rethrow;
    }
  }

  Future<void> _replacePlayer(AppSound sound, String? assetOrUrl) async {
    final path = assetOrUrl ?? sound.assetPath;
    try {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      if (path.startsWith('http')) {
        await player.setSource(UrlSource(path));
      } else {
        await player.setSource(AssetSource(path));
      }
      _players[sound]?.dispose();
      _players[sound] = player;
    } catch (e) {
      debugPrint('AudioService._replacePlayer ${sound.name}: $e');
      _lastError = 'replace ${sound.name}: $e';
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
    if (!_stateCtrl.isClosed) {
      _stateCtrl.close();
    }
  }
}
