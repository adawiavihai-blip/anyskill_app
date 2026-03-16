import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/help_knowledge_base.dart';

// ── Brand tokens ─────────────────────────────────────────────────────────────
const Color _kPurple     = Color(0xFF6366F1);
const Color _kPurpleSoft = Color(0xFFF0F0FF);

// ── Screen ────────────────────────────────────────────────────────────────────
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final List<_ChatMessage> _messages = [];
  bool _isProvider = false;
  bool _isTyping   = false;
  bool _loaded     = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data = doc.data() ?? {};
        if (mounted) {
          setState(() => _isProvider = (data['isProvider'] as bool?) == true);
        }
      } catch (_) {}
    }

    // Welcome message
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    _addBot(
      _isProvider
          ? 'שלום! אני עוזר המומחים של AnySkill 👋\n'
            'כאן תמצאו טיפים לניהול הפרופיל, השגת הזמנות, ועוד.\n\n'
            'במה אוכל לעזור היום?'
          : 'שלום! אני עוזר הלקוחות של AnySkill 👋\n'
            'יש לי תשובות לכל שאלה — בחרו מהרשימה או כתבו בחופשיות.\n\n'
            'במה אוכל לעזור?',
    );
    if (mounted) setState(() => _loaded = true);
  }

  void _addBot(String text) {
    if (!mounted) return;
    setState(() => _messages.insert(0, _ChatMessage(text: text, isBot: true)));
  }

  Future<void> _onQuestion(String question) async {
    if (!mounted) return;
    setState(() {
      _messages.insert(0, _ChatMessage(text: question, isBot: false));
      _isTyping = true;
    });

    // Simulate thinking delay (feels more natural).
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final answer = HelpKnowledgeBase.findAnswer(question);
    setState(() {
      _isTyping = false;
      _messages.insert(0, _ChatMessage(text: answer, isBot: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    final chips = _isProvider
        ? HelpKnowledgeBase.providerQuickActions
        : HelpKnowledgeBase.clientQuickActions;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Chat list ──────────────────────────────────────────────────────
          Expanded(
            child: _loaded
                ? ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_isTyping && i == 0) {
                        return const _TypingIndicator();
                      }
                      return _MessageBubble(
                        message: _messages[_isTyping ? i - 1 : i],
                      );
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
          ),

          // ── Input area ─────────────────────────────────────────────────────
          _buildInputArea(chips),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _kPurple,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 4),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'מרכז העזרה',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4ADE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isProvider ? 'תמיכת ספקים' : 'תמיכת לקוחות',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(List<String> chips) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Section label
          Text(
            _isProvider ? 'שאלות נפוצות לספקים' : 'שאלות נפוצות ללקוחות',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // Quick action chips
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                label: Text(chips[i],
                    style: const TextStyle(fontSize: 12, height: 1)),
                backgroundColor: _kPurpleSoft,
                labelStyle: const TextStyle(color: _kPurple),
                side: const BorderSide(color: _kPurple, width: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => _onQuestion(chips[i]),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Free-text input
          _FreeTextInput(onSend: _onQuestion),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isBot});
  final String text;
  final bool   isBot;
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isBot = message.isBot;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        // Bot: right (in RTL = visual right, matching "system" messages)
        // User: left  (in RTL = visual left, matching "my question" look)
        alignment: isBot ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // User avatar — shown on the left of user bubbles
            if (!isBot) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: _kPurpleSoft,
                child: const Icon(Icons.person_rounded,
                    size: 16, color: _kPurple),
              ),
              const SizedBox(width: 8),
            ],

            // Bubble
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: isBot ? _kPurple : Colors.white,
                  borderRadius: BorderRadius.only(
                    topRight:   const Radius.circular(18),
                    topLeft:    const Radius.circular(18),
                    bottomLeft: Radius.circular(isBot ? 18 : 4),
                    bottomRight: Radius.circular(isBot ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message.text,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isBot ? Colors.white : Colors.black87,
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),

            // Bot avatar — shown on the right of bot bubbles
            if (isBot) ...[
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _kPurple.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.support_agent_rounded,
                    size: 15, color: _kPurple),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (i) => _AnimatedDot(ctrl: _ctrl, delay: i * 0.3),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_rounded,
                  size: 15, color: _kPurple),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDot extends StatelessWidget {
  const _AnimatedDot({required this.ctrl, required this.delay});
  final AnimationController ctrl;
  final double              delay;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t       = ((ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
        final opacity = (t < 0.5 ? t * 2 : (1.0 - t) * 2).clamp(0.25, 1.0);
        return Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _kPurple.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

// ── Free-text input ───────────────────────────────────────────────────────────

class _FreeTextInput extends StatefulWidget {
  const _FreeTextInput({required this.onSend});
  final ValueChanged<String> onSend;

  @override
  State<_FreeTextInput> createState() => _FreeTextInputState();
}

class _FreeTextInputState extends State<_FreeTextInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    _ctrl.clear();
    widget.onSend(q);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Send button
        GestureDetector(
          onTap: _submit,
          child: Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.only(left: 8),
            decoration: const BoxDecoration(
              color: _kPurple,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_rounded,
                color: Colors.white, size: 20),
          ),
        ),

        // Text field
        Expanded(
          child: TextField(
            controller: _ctrl,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'כתוב שאלה חופשית...',
              hintStyle:
                  TextStyle(color: Colors.grey[400], fontSize: 13),
              filled: true,
              fillColor: const Color(0xFFF5F5FF),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide:
                    const BorderSide(color: _kPurple, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
