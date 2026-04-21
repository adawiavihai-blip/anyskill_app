import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/chat_theme_controller.dart';

/// Bottom sheet opened from the chat screen's ⋮ AppBar menu
/// (messages-upgrade PR-3a). Two sections:
///   1. Translation — DISABLED placeholders until PR-3b lands.
///   2. Appearance — 3 buttons driving [ChatThemeController].
/// The sheet rebuilds itself when the controller notifies, so tapping
/// a theme option updates both the underlying chat screen AND this
/// sheet's own palette live, with a 500ms smooth transition.
Future<void> showChatSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ChatSettingsSheet(),
  );
}

class _ChatSettingsSheet extends StatelessWidget {
  const _ChatSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: ChatThemeController.instance,
      builder: (ctx, _) {
        final isDark = ChatThemeController.instance.isDark;
        // Palette tweens along with the main chat — both run on the same
        // 500ms duration via the TweenAnimationBuilder below.
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: isDark ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          builder: (ctx, t, __) {
            final palette = ChatPalette.lerp(
                ChatPalette.light, ChatPalette.dark, t);
            return _buildSheet(ctx, palette, l10n);
          },
        );
      },
    );
  }

  Widget _buildSheet(
      BuildContext ctx, ChatPalette p, AppLocalizations l10n) {
    final mode = ChatThemeController.instance.mode;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          top: 10,
          left: 20,
          right: 20,
          bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                l10n.chatSettingsTitle,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Translation section (PR-3b placeholders) ─────────────
            _Section(
              palette: p,
              title: l10n.chatSettingsTranslationSection,
              children: [
                _DisabledRow(
                  palette: p,
                  icon: Icons.translate_rounded,
                  label: l10n.chatSettingsAutoTranslate,
                  trailing: _ComingSoonBadge(
                      palette: p, text: l10n.chatSettingsComingSoon),
                ),
                Divider(color: p.border, height: 1),
                _DisabledRow(
                  palette: p,
                  icon: Icons.language_rounded,
                  label: l10n.chatSettingsMyLanguage,
                  trailing: Icon(Icons.expand_more_rounded,
                      color: p.textMuted, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Appearance section ────────────────────────────────────
            _Section(
              palette: p,
              title: l10n.chatSettingsAppearanceSection,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ThemeOption(
                        palette: p,
                        icon: Icons.light_mode_rounded,
                        label: l10n.chatSettingsThemeLight,
                        selected: mode == ChatThemeMode.light,
                        onTap: () => ChatThemeController.instance
                            .setMode(ChatThemeMode.light),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ThemeOption(
                        palette: p,
                        icon: Icons.dark_mode_rounded,
                        label: l10n.chatSettingsThemeDark,
                        selected: mode == ChatThemeMode.dark,
                        onTap: () => ChatThemeController.instance
                            .setMode(ChatThemeMode.dark),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ThemeOption(
                        palette: p,
                        icon: Icons.schedule_rounded,
                        label: l10n.chatSettingsThemeAuto,
                        selected: mode == ChatThemeMode.auto,
                        onTap: () => ChatThemeController.instance
                            .setMode(ChatThemeMode.auto),
                      ),
                    ),
                  ],
                ),
                if (mode == ChatThemeMode.auto) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      l10n.chatSettingsAutoHint,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 22),

            // ── Save & close ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  l10n.chatSettingsSave,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final ChatPalette palette;
  final String title;
  final List<Widget> children;
  const _Section(
      {required this.palette,
      required this.title,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              title,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DisabledRow extends StatelessWidget {
  final ChatPalette palette;
  final IconData icon;
  final String label;
  final Widget trailing;
  const _DisabledRow({
    required this.palette,
    required this.icon,
    required this.label,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: palette.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ComingSoonBadge extends StatelessWidget {
  final ChatPalette palette;
  final String text;
  const _ComingSoonBadge({required this.palette, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: palette.accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.accent,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final ChatPalette palette;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({
    required this.palette,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.14)
                : palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? palette.accent
                  : palette.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: selected
                      ? palette.accent
                      : palette.textSecondary,
                  size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? palette.accent
                      : palette.textPrimary,
                  fontSize: 12.5,
                  fontWeight: selected
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
