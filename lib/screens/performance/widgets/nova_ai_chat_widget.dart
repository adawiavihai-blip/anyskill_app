import 'package:flutter/material.dart';

import '../services/nova_chat_service.dart';
import '_design.dart';

/// Nova — the Performance Observatory's conversational AI.
/// Backed by Gemini 2.5 Flash Lite via the `askNovaChat` Cloud Function.
/// Never calls Claude — Claude is reserved for the AI CEO tab.
///
/// The chat has 3 quick-suggestion chips to bootstrap new admins:
/// "מה קורה עכשיו?" / "מה עולה לי הכי הרבה?" / "איך משפרים Happiness Score?"
class NovaAiChatWidget extends StatefulWidget {
  const NovaAiChatWidget({super.key});

  @override
  State<NovaAiChatWidget> createState() => _NovaAiChatWidgetState();
}

class _NovaAiChatWidgetState extends State<NovaAiChatWidget> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<NovaMessage> _messages = [
    NovaMessage(
      role: 'assistant',
      text:
          'היי! אני Nova 🤖 — האסיסטנטית של הדשבורד. שאלי אותי מה שתרצי על '
          'המטריקות: הכנסות, עומסים, סיכוני עזיבה, טריגרים לשדרוג. אני עובדת '
          'בעברית ומסתכלת על הנתונים החיים.',
    ),
  ];
  bool _sending = false;

  final _suggestions = const [
    'מה קורה עכשיו?',
    'איזה Milestone מומלץ לי?',
    'איך משפרים Happiness Score?',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final question = (text ?? _ctrl.text).trim();
    if (question.isEmpty || _sending) return;
    _ctrl.clear();

    setState(() {
      _messages.add(NovaMessage(role: 'user', text: question));
      _sending = true;
    });
    _scrollToEnd();

    final answer = await NovaChatService.instance.ask(question);

    if (!mounted) return;
    setState(() {
      _messages.add(NovaMessage(role: 'assistant', text: answer));
      _sending = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PerfDesign.glassCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PerfDesign.purple, PerfDesign.pink],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: PerfDesign.purple.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Gemini 2.5 Flash Lite',
                  style: TextStyle(
                    color: PerfDesign.purple,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Nova · עוזרת AI',
                style: TextStyle(
                  color: PerfDesign.textHi,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= _messages.length) return const _TypingBubble();
                return _MessageBubble(msg: _messages[i]);
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              children: [
                for (final s in _suggestions) ...[
                  _SuggestionChip(
                    label: s,
                    onTap: () => _send(s),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SendButton(
                enabled: !_sending,
                onTap: _send,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: PerfDesign.glassFillStrong,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: PerfDesign.textHi),
                    decoration: InputDecoration(
                      hintText: 'שאלי את Nova…',
                      hintStyle: TextStyle(
                        color: PerfDesign.textLo,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _send(),
                    enabled: !_sending,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final NovaMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Align(
      alignment:
          isUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [PerfDesign.indigo, PerfDesign.purple],
                )
              : null,
          color: isUser ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: isUser
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Text(
          msg.text,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: isUser ? Colors.white : PerfDesign.textHi,
            fontSize: 13.5,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = ((t * 3 + i) % 1.0);
                final s = 4.0 + 2.0 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: s,
                    height: s,
                    decoration: const BoxDecoration(
                      color: PerfDesign.purple,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: PerfDesign.purple.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: PerfDesign.purple.withValues(alpha: 0.30),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: PerfDesign.purple,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [PerfDesign.purple, PerfDesign.pink],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: PerfDesign.purple.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
