import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat-screen-LOCAL theme mode. Scoped to the 1-on-1 conversation view
/// only — NOT a global app theme (per messages-upgrade spec section 8 +
/// opening clause "השינויים חלים רק על מסך השיחה הספציפית").
///
/// `auto` flips to dark between 19:00-07:00 device-local time; the
/// controller re-evaluates every minute via [Timer.periodic] so a long
/// open chat session crossing 19:00 switches without the user having
/// to re-enter the screen.
enum ChatThemeMode { light, dark, auto }

/// Singleton ChangeNotifier holding the chat-screen theme choice.
class ChatThemeController extends ChangeNotifier {
  ChatThemeController._();
  static final ChatThemeController instance = ChatThemeController._();

  static const _prefKey = 'chat.theme_mode_v1';
  static const _darkStartHour = 19;
  static const _darkEndHour = 7;

  ChatThemeMode _mode = ChatThemeMode.light;
  bool _initialized = false;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  ChatThemeMode get mode => _mode;

  /// Resolves the current mode into a boolean — `true` when the chat
  /// should render in dark palette right now.
  bool get isDark {
    switch (_mode) {
      case ChatThemeMode.light:
        return false;
      case ChatThemeMode.dark:
        return true;
      case ChatThemeMode.auto:
        return _isNightHour(_now);
    }
  }

  static bool _isNightHour(DateTime d) {
    final h = d.hour;
    return h >= _darkStartHour || h < _darkEndHour;
  }

  /// Reads persisted mode + starts the minute ticker. Safe to call
  /// multiple times — no-op after the first.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        _mode = ChatThemeMode.values.firstWhere(
          (e) => e.name == raw,
          orElse: () => ChatThemeMode.light,
        );
      }
    } catch (_) {
      // Silent fallback — ship light mode if SharedPreferences is broken.
    }
    _startTicker();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      final newNow = DateTime.now();
      // Only the `auto` mode actually cares about the wall clock — for
      // fixed light/dark modes we still update _now (cheap) but skip
      // the notifyListeners so we don't thrash rebuilds every minute.
      final wasDark = _mode == ChatThemeMode.auto ? _isNightHour(_now) : null;
      _now = newNow;
      if (wasDark != null) {
        final nowDark = _isNightHour(newNow);
        if (wasDark != nowDark) notifyListeners();
      }
    });
  }

  /// Persists the new mode and fires a rebuild. Returns the same Future
  /// the caller can await if it needs to synchronize something after
  /// the write lands.
  Future<void> setMode(ChatThemeMode m) async {
    if (_mode == m) return;
    _mode = m;
    _now = DateTime.now();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, m.name);
    } catch (_) {
      // Silent — the in-memory value is already correct for this session.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Immutable palette holding every color the chat screen needs. Two
/// instances ship: [ChatPalette.light] (current visuals) and
/// [ChatPalette.dark] (per spec §8). [ChatPalette.lerp] tweens between
/// them so theme switches animate smoothly over 500ms.
@immutable
class ChatPalette {
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color bubbleMe;
  final Color bubbleOther;
  final Color bubbleMeText;
  final Color bubbleOtherText;
  final Color accent;
  final Color accentSoft;

  const ChatPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.bubbleMe,
    required this.bubbleOther,
    required this.bubbleMeText,
    required this.bubbleOtherText,
    required this.accent,
    required this.accentSoft,
  });

  static const light = ChatPalette(
    background: Color(0xFFF0F2F8),
    surface: Colors.white,
    surfaceRaised: Colors.white,
    surfaceMuted: Color(0xFFF5F6FA),
    border: Color(0xFFE5E7EB),
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF6B7280),
    textMuted: Color(0xFF9CA3AF),
    bubbleMe: Color(0xFF6366F1),
    bubbleOther: Colors.white,
    bubbleMeText: Colors.white,
    bubbleOtherText: Color(0xFF1A1A2E),
    accent: Color(0xFF4F46E5),
    accentSoft: Color(0xFF818CF8),
  );

  static const dark = ChatPalette(
    background: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    surfaceRaised: Color(0xFF0B1220),
    surfaceMuted: Color(0xFF1A2234),
    border: Color(0xFF334155),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF64748B),
    bubbleMe: Color(0xFF6366F1),
    bubbleOther: Color(0xFF1E293B),
    bubbleMeText: Colors.white,
    bubbleOtherText: Color(0xFFE2E8F0),
    accent: Color(0xFF818CF8),
    accentSoft: Color(0xFF6366F1),
  );

  /// Linearly interpolates between two palettes. [t] is clamped to
  /// `[0, 1]` — 0 returns [a], 1 returns [b]. Used by the
  /// [TweenAnimationBuilder] that drives the 500ms transition.
  static ChatPalette lerp(ChatPalette a, ChatPalette b, double t) {
    final c = t.clamp(0.0, 1.0);
    return ChatPalette(
      background: Color.lerp(a.background, b.background, c)!,
      surface: Color.lerp(a.surface, b.surface, c)!,
      surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, c)!,
      surfaceMuted: Color.lerp(a.surfaceMuted, b.surfaceMuted, c)!,
      border: Color.lerp(a.border, b.border, c)!,
      textPrimary: Color.lerp(a.textPrimary, b.textPrimary, c)!,
      textSecondary: Color.lerp(a.textSecondary, b.textSecondary, c)!,
      textMuted: Color.lerp(a.textMuted, b.textMuted, c)!,
      bubbleMe: Color.lerp(a.bubbleMe, b.bubbleMe, c)!,
      bubbleOther: Color.lerp(a.bubbleOther, b.bubbleOther, c)!,
      bubbleMeText: Color.lerp(a.bubbleMeText, b.bubbleMeText, c)!,
      bubbleOtherText: Color.lerp(a.bubbleOtherText, b.bubbleOtherText, c)!,
      accent: Color.lerp(a.accent, b.accent, c)!,
      accentSoft: Color.lerp(a.accentSoft, b.accentSoft, c)!,
    );
  }
}

/// Supplies the resolved (possibly mid-transition) [ChatPalette] to any
/// descendant that needs it. Wrap the chat Scaffold body once; widgets
/// deeper in the tree call [ChatThemeScope.of(context).palette].
class ChatThemeScope extends InheritedWidget {
  final ChatPalette palette;
  final bool isDark;

  const ChatThemeScope({
    super.key,
    required this.palette,
    required this.isDark,
    required super.child,
  });

  static ChatThemeScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ChatThemeScope>();
    // Fallback for widgets rendered outside a chat screen (e.g. shared
    // bubble widgets reused elsewhere) — default to the existing light
    // visuals so nothing breaks.
    return scope ??
        const ChatThemeScope(
          palette: ChatPalette.light,
          isDark: false,
          child: SizedBox.shrink(),
        );
  }

  @override
  bool updateShouldNotify(ChatThemeScope old) =>
      old.isDark != isDark || old.palette != palette;
}
