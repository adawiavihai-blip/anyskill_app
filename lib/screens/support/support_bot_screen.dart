import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../support_center_screen.dart' show TicketChatScreen;

/// Phase 5 — Customer-facing self-service bot.
///
/// Entry point for support requests. Tries to auto-resolve simple issues
/// via Gemini, and only escalates to a human agent when the bot decides it.
/// On escalation the CF creates a `support_tickets` doc and we navigate the
/// user into the existing TicketChatScreen so an agent can take over.
class SupportBotScreen extends StatefulWidget {
  const SupportBotScreen({super.key});

  @override
  State<SupportBotScreen> createState() => _SupportBotScreenState();
}

class _SupportBotScreenState extends State<SupportBotScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_BotMessage> _history = [
    _BotMessage(
      role: 'bot',
      text:
          'שלום! אני בוט התמיכה של AnySkill 🤖\nאיך אני יכול לעזור היום?',
      suggestions: [
        'איפה ההזמנה שלי?',
        'נותן השירות לא הגיע',
        'בעיה בתשלום',
        'איפוס סיסמה',
      ],
    ),
  ];
  bool _busy = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _history.add(_BotMessage(role: 'user', text: clean));
      _msgCtrl.clear();
    });
    _scrollToBottom();

    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('handleBotConversation');
      final res = await fn.call({
        'conversation': _history
            .map((m) => {'role': m.role, 'text': m.text})
            .toList(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'language': 'he',
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final reply = data['reply'] as String? ?? '';
      final suggestions = (data['suggestions'] as List?)
              ?.cast<dynamic>()
              .map((e) => e.toString())
              .toList() ??
          const <String>[];
      final escalate = data['escalate'] == true;
      final ticketId = data['ticketId'] as String?;

      if (mounted) {
        setState(() {
          _history.add(_BotMessage(
            role: 'bot',
            text: reply,
            suggestions: suggestions,
          ));
          _busy = false;
        });
        _scrollToBottom();
      }

      if (escalate && ticketId != null && mounted) {
        // Smooth handoff: small pause so the customer sees the bot's last
        // line, then push them into the agent chat.
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TicketChatScreen(
              ticketId: ticketId,
              category: 'other',
              isAdmin: false,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _history.add(_BotMessage(
            role: 'bot',
            text:
                'משהו השתבש בצד שלי. אתה רוצה שאעביר אותך ישר לסוכן אנושי?',
            suggestions: const ['כן, העבר לסוכן'],
          ));
          _busy = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A1A2E),
          elevation: 0.5,
          title: Row(
            children: const [
              Icon(Icons.smart_toy_rounded, color: Color(0xFF6366F1)),
              SizedBox(width: 8),
              Text('בוט התמיכה',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _history.length,
                itemBuilder: (_, i) => _bubbleFor(_history[i]),
              ),
            ),
            if (_busy) _buildTypingIndicator(),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      textDirection: TextDirection.rtl,
                      onSubmitted: _busy ? null : _send,
                      decoration: InputDecoration(
                        hintText: 'תכתוב כאן את השאלה שלך…',
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(14),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    onPressed: _busy ? null : () => _send(_msgCtrl.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubbleFor(_BotMessage m) {
    final isUser = m.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF6366F1) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border:
                  isUser ? null : Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              m.text,
              style: TextStyle(
                fontSize: 13.5,
                color: isUser ? Colors.white : const Color(0xFF1A1A2E),
                height: 1.45,
              ),
            ),
          ),
          if (!isUser && m.suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: m.suggestions
                  .map((s) => ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 11)),
                        onPressed: _busy ? null : () => _send(s),
                        backgroundColor:
                            const Color(0xFF6366F1).withValues(alpha: 0.06),
                        side: BorderSide(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.25)),
                        labelStyle:
                            const TextStyle(color: Color(0xFF6366F1)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.smart_toy_rounded,
              size: 16, color: Color(0xFF6366F1)),
          const SizedBox(width: 6),
          Text(
            'הבוט מקליד…',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _BotMessage {
  final String role; // 'user' | 'bot'
  final String text;
  final List<String> suggestions;
  _BotMessage({
    required this.role,
    required this.text,
    this.suggestions = const [],
  });
}
