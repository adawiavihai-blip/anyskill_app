import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Bottom input area: text field + send button + attachment menu.
///
/// PR-2a of the messages-upgrade restored the attachment options that PR-1
/// removed (the legacy quick-reply chip row), this time as a 4-item popup
/// menu anchored to a paperclip button — matching `messages_upgrade_final.html`.
///
/// Items: 📍 location · 📷 image · 🎥 video (placeholder) · 💰 offer.
/// The offer item label adapts to role: provider sees "הצעת מחיר",
/// customer sees "בקש תשלום". The two flows still call the same legacy
/// dialogs (`_showQuoteDialog` / `_showRequestPaymentDialog`) on
/// `_ChatScreenState` — PR-2b will redesign the provider's modal per spec
/// (3 fields + 4 expiry chips + countdown card).
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isUploading;
  final bool guardFlagged;
  final bool isProvider;
  final VoidCallback onSend;
  final VoidCallback onSendLocation;
  final VoidCallback onSendImage;
  final VoidCallback onSendVideoComingSoon;
  final VoidCallback onShowOfferDialog;
  final ValueChanged<String> onTextChanged;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isUploading,
    required this.guardFlagged,
    required this.isProvider,
    required this.onSend,
    required this.onSendLocation,
    required this.onSendImage,
    required this.onSendVideoComingSoon,
    required this.onShowOfferDialog,
    required this.onTextChanged,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final GlobalKey _attachKey = GlobalKey();
  OverlayEntry? _menu;

  @override
  void dispose() {
    _menu?.remove();
    _menu = null;
    super.dispose();
  }

  void _toggleMenu() {
    if (_menu != null) {
      _hideMenu();
    } else {
      _showMenu();
    }
  }

  void _hideMenu() {
    _menu?.remove();
    _menu = null;
    if (mounted) setState(() {});
  }

  void _showMenu() {
    final btnCtx = _attachKey.currentContext;
    if (btnCtx == null) return;
    final box = btnCtx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final pos = box.localToGlobal(Offset.zero);
    final btnSize = box.size;
    final l10n = AppLocalizations.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    _menu = OverlayEntry(
      builder: (octx) {
        final screen = MediaQuery.of(octx).size;
        const menuW = 280.0;
        // Anchor menu's leading edge to the button's leading edge so it
        // sits just above the paperclip — works in both RTL and LTR.
        final rawLeft = isRtl
            ? (pos.dx + btnSize.width - menuW)
            : pos.dx;
        final menuLeft =
            rawLeft.clamp(8.0, screen.width - menuW - 8.0).toDouble();
        final menuBottom = (screen.height - pos.dy + 8).toDouble();

        return Stack(children: [
          // Tap-outside dismiss layer (transparent, swallows taps).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hideMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: menuLeft,
            bottom: menuBottom,
            child: _AttachMenu(
              isProvider: widget.isProvider,
              l10n: l10n,
              onLocation: () {
                _hideMenu();
                widget.onSendLocation();
              },
              onImage: () {
                _hideMenu();
                widget.onSendImage();
              },
              onVideo: () {
                _hideMenu();
                widget.onSendVideoComingSoon();
              },
              onOffer: () {
                _hideMenu();
                widget.onShowOfferDialog();
              },
            ),
          ),
        ]);
      },
    );
    Overlay.of(context).insert(_menu!);
    setState(() {}); // refresh active state on the paperclip button
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final menuOpen = _menu != null;
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isUploading) ...[
            const LinearProgressIndicator(color: Color(0xFF6366F1)),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AttachButton(
                buttonKey: _attachKey,
                active: menuOpen,
                tooltip: l10n.chatAttachTooltip,
                onTap: _toggleMenu,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 44, maxHeight: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: widget.guardFlagged
                          ? const Color(0xFFDC2626)
                          : Colors.grey.shade200,
                      width: widget.guardFlagged ? 1.5 : 1.0,
                    ),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    onChanged: widget.onTextChanged,
                    decoration: InputDecoration(
                      hintText: 'הקלד הודעה...',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      hasText ? const Color(0xFF6366F1) : Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: hasText ? Colors.white : Colors.grey[400],
                  ),
                  onPressed: widget.onSend,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  final GlobalKey buttonKey;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _AttachButton({
    required this.buttonKey,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        key: buttonKey,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEDE9FE) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: AnimatedRotation(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            turns: active ? 0.125 : 0,
            child: Icon(
              Icons.attach_file_rounded,
              size: 22,
              color: active
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF6B7280),
            ),
          ),
          onPressed: onTap,
        ),
      ),
    );
  }
}

class _AttachMenu extends StatefulWidget {
  final bool isProvider;
  final AppLocalizations l10n;
  final VoidCallback onLocation;
  final VoidCallback onImage;
  final VoidCallback onVideo;
  final VoidCallback onOffer;

  const _AttachMenu({
    required this.isProvider,
    required this.l10n,
    required this.onLocation,
    required this.onImage,
    required this.onVideo,
    required this.onOffer,
  });

  @override
  State<_AttachMenu> createState() => _AttachMenuState();
}

class _AttachMenuState extends State<_AttachMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 0.95, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final offerLabel = widget.isProvider
        ? l10n.chatAttachOffer
        : l10n.chatAttachPaymentRequest;

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: _AttachItem(
                        emoji: '📍',
                        label: l10n.chatAttachLocation,
                        gradient: const [
                          Color(0xFF3B82F6),
                          Color(0xFF1D4ED8)
                        ],
                        onTap: widget.onLocation,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _AttachItem(
                        emoji: '📷',
                        label: l10n.chatAttachImage,
                        gradient: const [
                          Color(0xFFF59E0B),
                          Color(0xFFD97706)
                        ],
                        onTap: widget.onImage,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: _AttachItem(
                        emoji: '🎥',
                        label: l10n.chatAttachVideo,
                        gradient: const [
                          Color(0xFFEF4444),
                          Color(0xFFDC2626)
                        ],
                        onTap: widget.onVideo,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _AttachItem(
                        emoji: '💰',
                        label: offerLabel,
                        gradient: const [
                          Color(0xFF818CF8),
                          Color(0xFF4F46E5)
                        ],
                        onTap: widget.onOffer,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachItem extends StatelessWidget {
  final String emoji;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _AttachItem({
    required this.emoji,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
