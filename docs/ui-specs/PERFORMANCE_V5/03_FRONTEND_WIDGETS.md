# 🎨 Frontend Widgets (Flutter) - 17 Widgets for Performance V5

> **Read `01_MAIN_PROMPT_PERFORMANCE_V5.md` and `02_CLOUD_FUNCTIONS.md` first!** This file contains Flutter widget implementations.

---

## 📦 Package Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^2.27.0
  firebase_auth: ^4.17.0
  cloud_firestore: ^4.15.0
  cloud_functions: ^4.6.0
  firebase_performance: ^0.9.3+16
  firebase_crashlytics: ^3.4.18
  
  # Animation & UI
  animated_background: ^2.0.0
  fl_chart: ^0.65.0
  syncfusion_flutter_charts: ^24.1.41
  flutter_animate: ^4.5.0
  glassmorphism: ^3.0.0
  
  # AI & Voice
  speech_to_text: ^6.6.1
  flutter_tts: ^4.0.2
  
  # Utilities
  intl: ^0.19.0
  jiffy: ^6.2.2
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0
  rxdart: ^0.27.7
  sentry_flutter: ^7.18.0
```

---

## 🎨 Design System Constants

Create `lib/screens/admin/widgets/performance/performance_design_system.dart`:

```dart
import 'package:flutter/material.dart';

/// Performance Observatory V5 Design System
/// Dark premium glassmorphism - matches Datadog/New Relic quality
class PerfDesign {
  // ═══ COLORS ═══
  
  // Background gradient stops
  static const bgColor1 = Color(0xFF050816);
  static const bgColor2 = Color(0xFF0A0E1A);
  static const bgColor3 = Color(0xFF0F1420);
  static const bgColor4 = Color(0xFF1A0A2E);
  
  // Business palette (for financial impact UI)
  static const pink = Color(0xFFEC4899);
  static const rose = Color(0xFFDB2777);
  static const pinkLight = Color(0xFFF9A8D4);
  
  // Primary
  static const indigo = Color(0xFF6366F1);
  static const indigoDark = Color(0xFF4F46E5);
  static const indigoLight = Color(0xFFA5B4FC);
  
  // AI (purple)
  static const purple = Color(0xFFA855F7);
  static const purpleDark = Color(0xFF7E22CE);
  static const purpleLight = Color(0xFFC4B5FD);
  
  // Status
  static const green = Color(0xFF16A34A);
  static const greenLight = Color(0xFF4ADE80);
  static const greenSoft = Color(0xFF86EFAC);
  
  static const yellow = Color(0xFFF59E0B);
  static const yellowLight = Color(0xFFFCD34D);
  
  static const orange = Color(0xFFFB923C);
  static const orangeDark = Color(0xFFEA580C);
  static const orangeLight = Color(0xFFFDBA74);
  
  static const red = Color(0xFFDC2626);
  static const redDark = Color(0xFF991B1B);
  static const redLight = Color(0xFFFCA5A5);
  
  static const blue = Color(0xFF3B82F6);
  static const blueDark = Color(0xFF2563EB);
  static const blueLight = Color(0xFF93C5FD);

  // ═══ GLASSMORPHISM ═══
  
  static BoxDecoration glassCard({
    Color? borderColor,
    double opacity = 0.04,
  }) => BoxDecoration(
    color: Color.fromRGBO(255, 255, 255, opacity),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: borderColor ?? const Color.fromRGBO(255, 255, 255, 0.08),
      width: 1,
    ),
  );
  
  // ═══ TEXT STYLES ═══
  
  static const titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.5,
  );
  
  static const titleMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
  
  static const bodyText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.white70,
    height: 1.5,
  );
  
  static const hintText = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: Color(0xB3FFFFFF), // white 70%
  );
  
  // ═══ GRADIENTS ═══
  
  static const LinearGradient pageBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgColor1, bgColor2, bgColor3, bgColor4],
    stops: [0.0, 0.3, 0.6, 1.0],
  );
  
  static LinearGradient statusGradient(String status) {
    switch (status) {
      case 'healthy':
      case 'success':
        return const LinearGradient(colors: [green, greenLight]);
      case 'warning':
        return const LinearGradient(colors: [orange, orangeLight]);
      case 'critical':
      case 'error':
        return const LinearGradient(colors: [red, redLight]);
      case 'ai':
        return const LinearGradient(colors: [purple, purpleDark, pink]);
      case 'revenue':
        return const LinearGradient(colors: [pink, rose]);
      default:
        return const LinearGradient(colors: [indigo, indigoDark]);
    }
  }
  
  // ═══ ANIMATIONS ═══
  
  static const Duration fastDuration = Duration(milliseconds: 200);
  static const Duration normalDuration = Duration(milliseconds: 400);
  static const Duration slowDuration = Duration(milliseconds: 800);
}
```

---

## 1️⃣ Main Performance Tab

`lib/screens/admin/tabs/system/performance_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/performance/performance_design_system.dart';
import '../../widgets/performance/ai_copilot_nova_widget.dart';
import '../../widgets/performance/business_impact_widget.dart';
import '../../widgets/performance/ai_agents_swarm_widget.dart';
import '../../widgets/performance/incident_war_room_widget.dart';
import '../../widgets/performance/scale_readiness_widget.dart';
import '../../widgets/performance/architecture_live_view_widget.dart';
import '../../widgets/performance/golden_signals_widget.dart';
import '../../widgets/performance/cost_projection_widget.dart';
import '../../widgets/performance/conversion_funnel_widget.dart';
import '../../widgets/performance/cohort_analysis_widget.dart';
import '../../widgets/performance/impact_simulator_widget.dart';
import '../../widgets/performance/feature_flags_widget.dart';
import '../../widgets/performance/chaos_engineering_widget.dart';
import '../../widgets/performance/blameless_postmortem_widget.dart';

class PerformanceTabV5 extends StatefulWidget {
  const PerformanceTabV5({super.key});

  @override
  State<PerformanceTabV5> createState() => _PerformanceTabV5State();
}

class _PerformanceTabV5State extends State<PerformanceTabV5> {
  final ScrollController _scrollController = ScrollController();
  bool _showNovaChat = false;

  @override
  void initState() {
    super.initState();
    // Voice shortcut listener
    HardwareKeyboard.instance.addHandler(_handleKeyPress);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyPress);
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleKeyPress(KeyEvent event) {
    if (event is KeyDownEvent) {
      // ⌘K or Ctrl+K → command palette
      if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
          event.logicalKey == LogicalKeyboardKey.keyK) {
        _showCommandPalette();
        return true;
      }
      // ⌘J or Ctrl+J → Nova chat
      if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
          event.logicalKey == LogicalKeyboardKey.keyJ) {
        setState(() => _showNovaChat = !_showNovaChat);
        return true;
      }
    }
    return false;
  }

  void _showCommandPalette() {
    // TODO: Show command palette overlay
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(gradient: PerfDesign.pageBackground),
        child: Stack(
          children: [
            // Ambient orbs (decorative background blobs)
            _buildAmbientOrbs(),
            
            // Main content
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(child: const ScaleReadinessWidget()),
                SliverToBoxAdapter(child: const ArchitectureLiveViewWidget()),
                SliverToBoxAdapter(child: const CostProjectionWidget()),
                SliverToBoxAdapter(child: _buildTopKpiStrip()),
                SliverToBoxAdapter(child: const BusinessImpactWidget()),
                SliverToBoxAdapter(child: const AiAgentsSwarmWidget()),
                SliverToBoxAdapter(child: const IncidentWarRoomWidget()),
                SliverToBoxAdapter(child: const GoldenSignalsWidget()),
                // ... all other sections
                SliverToBoxAdapter(child: const ImpactSimulatorWidget()),
                SliverToBoxAdapter(child: const ConversionFunnelWidget()),
                SliverToBoxAdapter(child: const CohortAnalysisWidget()),
                SliverToBoxAdapter(child: const ChaosEngineeringWidget()),
                SliverToBoxAdapter(child: const FeatureFlagsWidget()),
                SliverToBoxAdapter(child: const BlamelessPostmortemWidget()),
                SliverToBoxAdapter(child: _buildFooter()),
              ],
            ),
            
            // Nova AI Copilot overlay
            if (_showNovaChat)
              Positioned(
                right: 20,
                bottom: 20,
                child: AiCopilotNovaWidget(
                  onClose: () => setState(() => _showNovaChat = false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmbientOrbs() {
    return Stack(
      children: [
        // 5 decorative orbs - match V5 mockup
        Positioned(
          top: -100, right: -60,
          child: Container(
            width: 320, height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [PerfDesign.indigo.withOpacity(0.22), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          top: 500, left: -80,
          child: Container(
            width: 280, height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [PerfDesign.greenLight.withOpacity(0.18), Colors.transparent],
              ),
            ),
          ),
        ),
        // ... 3 more orbs
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PerfDesign.bgColor2.withOpacity(0.98),
            PerfDesign.bgColor3.withOpacity(1),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          // Logo + title
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [PerfDesign.indigo, PerfDesign.purple, PerfDesign.pink],
              ),
            ),
            child: const Icon(Icons.satellite_alt, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Performance Observatory',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('v5.0 SCALE-READY · 10M users · \$0.02/user',
                style: TextStyle(fontSize: 8, color: Colors.white54)),
            ],
          ),
          const Spacer(),
          // Live indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: PerfDesign.greenLight.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: PerfDesign.greenLight.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5, height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: PerfDesign.greenLight,
                    boxShadow: [BoxShadow(color: PerfDesign.greenLight, blurRadius: 10)],
                  ),
                ),
                const SizedBox(width: 5),
                const Text('LIVE · 2s',
                  style: TextStyle(fontSize: 9, color: PerfDesign.greenLight, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Voice button
          _iconButton(Icons.mic, 'Voice', PerfDesign.purpleLight, () {
            // TODO: Start voice recognition
          }),
          const SizedBox(width: 6),
          // Nova AI button
          _novaButton(),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, String label, Color color, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _novaButton() {
    return InkWell(
      onTap: () => setState(() => _showNovaChat = !_showNovaChat),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            colors: [PerfDesign.purple, PerfDesign.purpleDark, PerfDesign.pink],
          ),
          boxShadow: [
            BoxShadow(
              color: PerfDesign.purple.withOpacity(0.5),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          children: [
            Text('🤖', style: TextStyle(fontSize: 14)),
            SizedBox(width: 5),
            Text('Nova · Scale-Aware',
              style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopKpiStrip() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('health_metrics')
          .doc('current')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(child: _kpiCard('💚 HEALTH', '${data['healthScore'] ?? 87}/100', '↗ +3', PerfDesign.greenLight)),
              const SizedBox(width: 10),
              Expanded(child: _kpiCard('🌊 APDEX', '${data['apdex'] ?? 0.91}', 'מצוין', PerfDesign.indigoLight)),
              const SizedBox(width: 10),
              Expanded(child: _kpiCard('⏰ MTTR', '14 דק\'', '↘ −6', PerfDesign.redLight)),
              const SizedBox(width: 10),
              Expanded(child: _kpiCard('🚀 DEPLOY', '3.2/day', 'Elite DORA', PerfDesign.purpleLight)),
              const SizedBox(width: 10),
              Expanded(child: _kpiCard('💰 MRR', '₪47K', '↗ +12%', PerfDesign.pinkLight)),
              const SizedBox(width: 10),
              Expanded(child: _kpiCard('👥 DAU', '${data['dau'] ?? 1247}', '↗ +23%', PerfDesign.blueLight)),
            ],
          ),
        );
      },
    );
  }

  Widget _kpiCard(String label, String value, String trend, Color color) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.03)],
        ),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 8, color: Colors.white70, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(trend, style: const TextStyle(fontSize: 7, color: PerfDesign.greenSoft)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Wrap(
        spacing: 6, runSpacing: 6,
        children: [
          const Text('🏗️ Stack:', style: TextStyle(fontSize: 9, color: Colors.white54)),
          _stackBadge('Cloud Run', PerfDesign.greenLight),
          _stackBadge('Redis', PerfDesign.pinkLight),
          _stackBadge('Firestore (sharded)', PerfDesign.orangeLight),
          _stackBadge('BigQuery', PerfDesign.blueLight),
          _stackBadge('Pub/Sub', PerfDesign.indigoLight),
          _stackBadge('CloudFlare', PerfDesign.purpleLight),
        ],
      ),
    );
  }

  Widget _stackBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
```

---

## 2️⃣ AI Copilot Nova Widget

`lib/screens/admin/widgets/performance/ai_copilot_nova_widget.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'performance_design_system.dart';

class AiCopilotNovaWidget extends StatefulWidget {
  final VoidCallback? onClose;
  
  const AiCopilotNovaWidget({super.key, this.onClose});

  @override
  State<AiCopilotNovaWidget> createState() => _AiCopilotNovaWidgetState();
}

class _AiCopilotNovaWidgetState extends State<AiCopilotNovaWidget> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final _conversationId = const Uuid().v4();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
    _addWelcomeMessage();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('he-IL');
    await _tts.setSpeechRate(1.0);
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      role: 'nova',
      content: 'שלום! אני Nova, עוזר AI לניטור המערכת. שאל אותי על כל דבר - מונחים טכניים, בעיות במערכת, המלצות לשיפור. איך אני יכול לעזור?',
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _sendMessage({String? text}) async {
    final message = text ?? _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;
    
    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        content: message,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
      _messageController.clear();
    });
    _scrollToBottom();

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('askPerformanceCopilot')
          .call({
            'message': message,
            'conversationId': _conversationId,
          });

      final response = result.data as Map;
      
      setState(() {
        _messages.add(ChatMessage(
          role: 'nova',
          content: response['response'],
          actions: List<Map>.from(response['actions'] ?? []),
          confidence: response['confidence'],
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();

      // Speak response if user used voice input
      if (_isListening) {
        await _tts.speak(response['response']);
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          role: 'nova',
          content: 'סליחה, לא הצלחתי לענות. נסה שוב?',
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
    }
  }

  Future<void> _startListening() async {
    if (!_speech.isAvailable) return;
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'he_IL',
      onResult: (result) {
        if (result.finalResult) {
          _sendMessage(text: result.recognizedWords);
          setState(() => _isListening = false);
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: 420, height: 600,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              PerfDesign.purple.withOpacity(0.18),
              PerfDesign.purpleDark.withOpacity(0.06),
            ],
          ),
          border: Border.all(color: PerfDesign.purple.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: PerfDesign.purple.withOpacity(0.2),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildChatList()),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [PerfDesign.purple, PerfDesign.purpleDark, PerfDesign.pink],
                  ),
                ),
                child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 20)),
                ),
              ),
              Positioned(
                right: -2, bottom: -2,
                child: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PerfDesign.greenLight,
                    border: Border.all(color: PerfDesign.bgColor2, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nova · AI Copilot', 
                  style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w800)),
                Text('Gemini 2.5 Pro · מבינה עברית · כל דבר במערכת',
                  style: TextStyle(fontSize: 10, color: PerfDesign.purpleLight)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(10),
        itemCount: _messages.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length) return _buildTypingIndicator();
          return _buildMessage(_messages[index]);
        },
      ),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.start : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: isUser ? PerfDesign.indigo : PerfDesign.purple,
            child: Text(
              isUser ? 'א' : '🤖',
              style: TextStyle(
                fontSize: isUser ? 10 : 12,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUser
                    ? PerfDesign.indigo.withOpacity(0.15)
                    : PerfDesign.purple.withOpacity(0.15),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: isUser ? const Radius.circular(12) : const Radius.circular(3),
                  bottomRight: isUser ? const Radius.circular(3) : const Radius.circular(12),
                ),
                border: Border.all(
                  color: isUser
                      ? PerfDesign.indigo.withOpacity(0.25)
                      : PerfDesign.purple.withOpacity(0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.content,
                    style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.5),
                  ),
                  if (msg.actions != null && msg.actions!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5, runSpacing: 5,
                      children: msg.actions!.map((action) {
                        return InkWell(
                          onTap: () => _executeAction(action),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: PerfDesign.greenLight.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: PerfDesign.greenLight.withOpacity(0.4)),
                            ),
                            child: Text(
                              action['label'] ?? 'פעולה',
                              style: const TextStyle(fontSize: 9, color: PerfDesign.greenSoft, fontWeight: FontWeight.w700),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(8),
      child: Row(
        children: [
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: PerfDesign.purpleLight,
            ),
          ),
          SizedBox(width: 8),
          Text('Nova חושבת...', 
            style: TextStyle(fontSize: 10, color: PerfDesign.purpleLight, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _messageController,
                style: const TextStyle(fontSize: 11, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'שאל את Nova על כל דבר...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.mic, 
              color: _isListening ? PerfDesign.redLight : Colors.white70),
            onPressed: _startListening,
          ),
          const SizedBox(width: 2),
          ElevatedButton(
            onPressed: _isLoading ? null : _sendMessage,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              backgroundColor: PerfDesign.purple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('שלח →', 
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _executeAction(Map action) {
    // TODO: Route action to correct handler
    // action['type'] could be: 'rollback', 'add_index', 'scale_up', 'mute', etc.
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}

class ChatMessage {
  final String role; // 'user' | 'nova'
  final String content;
  final List<Map>? actions;
  final int? confidence;
  final DateTime timestamp;
  final bool isError;

  ChatMessage({
    required this.role,
    required this.content,
    this.actions,
    this.confidence,
    required this.timestamp,
    this.isError = false,
  });
}
```

---

## 3️⃣ Business Impact Widget

Full widget code in `lib/screens/admin/widgets/performance/business_impact_widget.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'performance_design_system.dart';

class BusinessImpactWidget extends StatelessWidget {
  const BusinessImpactWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('business_metrics')
          .doc('current')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                PerfDesign.pink.withOpacity(0.12),
                PerfDesign.purple.withOpacity(0.05),
              ],
            ),
            border: Border.all(color: PerfDesign.pink.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: const LinearGradient(colors: [PerfDesign.pink, PerfDesign.rose]),
                    ),
                    child: const Center(child: Text('💼', style: TextStyle(fontSize: 18))),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Business Impact · עכשיו',
                          style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w800)),
                        Text('מקשר בעיות טכניות להפסד כסף אמיתי',
                          style: TextStyle(fontSize: 9, color: PerfDesign.pinkLight)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 5 impact metrics
              Row(
                children: [
                  Expanded(child: _metric('💸 הפסד/דקה', '₪${data['lossPerMinute'] ?? 142}', 
                    'מצטבר: ₪${(data['lossPerMinute'] ?? 142) * 12}', PerfDesign.redLight)),
                  const SizedBox(width: 10),
                  Expanded(child: _metric('📉 Conversion Drop', '-34%', 
                    '14/41 → 6/41', PerfDesign.orangeLight)),
                  const SizedBox(width: 10),
                  Expanded(child: _metric('😊 Happiness', '${data['happinessScore'] ?? 62}/100',
                    '↘ −18 השעה', PerfDesign.pinkLight)),
                  const SizedBox(width: 10),
                  Expanded(child: _metric('🚪 Churn Risk', '${data['vipsAtRisk'] ?? 3} VIPs',
                    '₪${data['vipRevenueAtRisk'] ?? 4200}/ח', PerfDesign.yellowLight)),
                  const SizedBox(width: 10),
                  Expanded(child: _metric('🎯 NPS', '+${data['nps'] ?? 42}',
                    '↘ מ-+58', PerfDesign.indigoLight)),
                ],
              ),
              const SizedBox(height: 12),
              // Gemini correlation
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: PerfDesign.pink.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Text('🧠', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Gemini Correlation Engine:',
                            style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            'ה-latency ב-Search Service גורם ל-34% drop בהזמנות · פתרון ב-10 דק\' יחסוך ~₪1,420',
                            style: const TextStyle(fontSize: 9, color: Colors.white70, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {}, // TODO: Trigger fix
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PerfDesign.pink,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      child: const Text('💸 פתור', 
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metric(String label, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.white54, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 8, color: color)),
        ],
      ),
    );
  }
}
```

---

## 4️⃣-1️⃣7️⃣ Remaining Widgets Summary

Due to space limits, here's the pattern to follow for the rest. **Each widget should:**
1. Use `StreamBuilder` for Firestore/BigQuery data
2. Apply `PerfDesign` constants consistently
3. Include loading/error/empty states
4. Be fully RTL with Hebrew strings
5. Add `flutter_animate` entrance animations
6. Have `semanticLabel` for accessibility

### 4. AI Agents Swarm Widget
Show 5 agent cards in grid. Each card:
- Agent name + icon (🔍 Detective / 🔧 Healer / 🔮 Oracle / 🛡️ Guardian / 📝 Chronicler)
- Status dot (green/yellow/red)
- Current task description
- Actions/predictions count for today
- Click to see full agent log

Data source: `ai_agents_state` Firestore collection (small, 5 docs)

### 5. Incident War Room Widget
Appears when P1 active incident exists. Sections:
- Incident header with timer
- AI Investigation status (5 agents coordinating)
- Resolution Options (Top 3 with confidence scores)
- Team Chat (shows Nova + team members in real-time)

### 6. Scale Readiness Widget
Big circular score (0-100) using CustomPainter.
5 sub-items with status (✓ OK / ⚠ Partial / ✗ Missing):
- Firestore Auto-scaling
- CDN Multi-Region
- Redis Cache Layer
- Firestore Sharding (CRITICAL!)
- BigQuery Pipeline (CRITICAL!)

### 7. Architecture Live View Widget
Custom painter draws animated data flow:
- Users → CDN → Cloud Run → Redis/Firestore/Pub-Sub → BigQuery → Dashboard
- Animated circles move along paths (showing data packets)
- Labels show hit rates per layer

Use `AnimatedBuilder` with `AnimationController`.

### 8. Golden Signals Widget
4 cards: Latency / Traffic / Errors / Saturation
Each with:
- Big number + trend arrow
- Sparkline (use `fl_chart` LineChart)
- Percentile breakdown (p50, p95, p99 for Latency)

### 9. Cost Projection Widget
4 columns: Today / 100K DAU / 1M DAU / 10M DAU
Each with: daily cost, monthly cost, cost/user/month

### 10. Conversion Funnel Widget  
6-step bar chart (Home → Search → Book → Chat → Pay → Done)
Use `fl_chart` `BarChart`.

### 11. Cohort Analysis Widget
Retention heatmap table (cohort × week)
Use `Table` widget with custom cell colors.

### 12. Impact Simulator Widget
Interactive scenario picker + results display
Calls `simulateImpactScenario` Cloud Function.

### 13. Feature Flags Widget
List of flags with toggle switches (ON/DARK/OFF).
Update Firestore `feature_flags` collection on toggle.

### 14. Chaos Engineering Widget
4 chaos test cards (DB Slowdown / CF Timeout / Network Drop / Traffic Storm)
Each with "▶ הרץ" button that calls `triggerChaosTest` CF.

### 15. Blameless Postmortem Widget
Fetch from `post_mortems` Firestore collection.
Show drafts with AI-generated content + "Edit" / "Send" buttons.

### 16. Performance Observatory Service
`lib/services/performance_observatory_service.dart`:

```dart
class PerformanceObservatoryService {
  final _functions = FirebaseFunctions.instance;
  final _firestore = FirebaseFirestore.instance;

  Stream<Map<String, dynamic>> streamHealthMetrics() {
    return _firestore.collection('health_metrics').doc('current')
        .snapshots()
        .map((doc) => doc.data() ?? {});
  }

  Stream<List<Map<String, dynamic>>> streamActiveIncidents() {
    return _firestore.collection('incidents')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<Map<String, dynamic>> simulateScenario(String scenario) async {
    final result = await _functions.httpsCallable('simulateImpactScenario')
        .call({'scenario': scenario});
    return result.data as Map<String, dynamic>;
  }

  Future<void> rollbackDeployment(String reason) async {
    await _functions.httpsCallable('rollbackDeployment').call({'reason': reason});
  }

  Future<void> triggerChaosTest(String testType, int duration) async {
    await _functions.httpsCallable('triggerChaosTest').call({
      'testType': testType,
      'duration': duration,
      'blastRadius': 'small',
    });
  }

  // ... more methods
}
```

### 17. Nova AI Copilot Service
`lib/services/nova_ai_copilot_service.dart`:

```dart
class NovaAiCopilotService {
  final _functions = FirebaseFunctions.instance;

  Future<NovaResponse> askNova(String message, String conversationId) async {
    final result = await _functions.httpsCallable('askPerformanceCopilot')
        .call({'message': message, 'conversationId': conversationId});
    
    final data = result.data as Map;
    return NovaResponse(
      response: data['response'],
      actions: List<Map>.from(data['actions'] ?? []),
      confidence: data['confidence'] ?? 85,
      tokensUsed: data['tokensUsed'] ?? 0,
    );
  }
}

class NovaResponse {
  final String response;
  final List<Map> actions;
  final int confidence;
  final int tokensUsed;

  NovaResponse({
    required this.response,
    required this.actions,
    required this.confidence,
    required this.tokensUsed,
  });
}
```

---

## ✅ Widget Testing Checklist

Before merging each widget, verify:

- [ ] Renders correctly in RTL
- [ ] Hebrew strings display properly
- [ ] Loading state implemented
- [ ] Error state implemented
- [ ] Empty state implemented
- [ ] Real-time updates work (StreamBuilder)
- [ ] Dark theme + glassmorphism applied
- [ ] Animations smooth (no jank)
- [ ] Mobile responsive (test at 375px width)
- [ ] No overflow errors
- [ ] Semantic labels for accessibility
- [ ] `flutter analyze`: 0 issues
- [ ] `flutter test`: all tests pass

---

## 🚀 Next Steps

1. Read `04_INFRASTRUCTURE.md` for BigQuery schema, Pub/Sub, Redis setup
2. Read `05_LOCALIZATION.md` for Hebrew strings
3. Follow implementation order in `01_MAIN_PROMPT_PERFORMANCE_V5.md`

---

**Remember: Dashboard reads from BigQuery, NOT Firestore for metrics! This is the #1 scale requirement.**
