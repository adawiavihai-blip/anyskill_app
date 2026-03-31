import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/stripe_service.dart';

/// Stripe Custom onboarding flow for providers.
/// שומר על כל הלוגיקה הקיימת ומוסיף טופס איסוף פרטים פנימי מפורט
class ProviderStripeOnboardingScreen extends StatefulWidget {
  const ProviderStripeOnboardingScreen({super.key});

  @override
  State<ProviderStripeOnboardingScreen> createState() =>
      _ProviderStripeOnboardingScreenState();
}

class _ProviderStripeOnboardingScreenState
    extends State<ProviderStripeOnboardingScreen> {
  // --- שדות הטופס המורחבים ---
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();

  // שדות בנק מפורטים
  final _bankNameCtrl = TextEditingController();
  final _bankNumberCtrl = TextEditingController();
  final _branchNumberCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();

  bool _showCustomForm = true; // מתחילים בטופס שלנו

  // --- שדות קיימים (WebView & Native) ---
  WebViewController? _controller;
  bool _loading = false;
  String? _error;
  bool _webBrowserOpened = false;

  static const _returnUrl = 'https://anyskill-6fdf3.web.app/stripe-return';
  static const _refreshUrl = 'https://anyskill-6fdf3.web.app/stripe-refresh';

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _idCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankNumberCtrl.dispose();
    _branchNumberCtrl.dispose();
    _accountNumberCtrl.dispose();
    super.dispose();
  }

  // הפונקציה שמתבצעת כשלוחצים על אישור בטופס הפנימי
  Future<void> _handleCustomSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // שליחת הפרטים המפורטים לסטריפ דרך ה-Service המעודכן
      final result = await StripeService.startProviderOnboarding(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        dobDay: 1,
        dobMonth: 1,
        dobYear: 1990,
        idNumber: _idCtrl.text.trim(),
        bankName: _bankNameCtrl.text.trim(),
        bankNumber: _bankNumberCtrl.text.trim(),
        branchNumber: _branchNumberCtrl.text.trim(),
        accountNumber: _accountNumberCtrl.text.trim(),
      );

      if (result == "success") {
        if (mounted) Navigator.of(context).pop(true);
      }
      // שדרוג: אם התוצאה היא URL (כמו שראינו ב-Response), נפתח אותו
      else if (result != null && result.startsWith('https://')) {
        final launched = await launchUrl(
          Uri.parse(result),
          mode: LaunchMode.externalApplication,
        );
        if (mounted) {
          if (launched) {
            setState(() {
              _loading = false;
              _showCustomForm = false;
              _webBrowserOpened = true; // מציג את מסך ה-"סיימתי"
            });
          } else {
            setState(() {
              _loading = false;
              _error = 'לא ניתן לפתוח את עמוד האימות. נסה שוב.';
            });
          }
        }
      } else {
        // אם סטריפ דורש אימות נוסף ואין לנו URL ישיר, עוברים ללוגיקה המקורית
        setState(() => _showCustomForm = false);
        _initOriginalFlow();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = "שגיאה בתהליך: $e";
      });
    }
  }

  // --- הלוגיקה המקורית שלך (ללא שינוי) ---
  Future<void> _initOriginalFlow() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _webBrowserOpened = false;
    });

    final url = await StripeService.startProviderOnboarding(
      firstName: _firstNameCtrl.text,
      lastName: _lastNameCtrl.text,
      dobDay: 1,
      dobMonth: 1,
      dobYear: 1990,
      idNumber: _idCtrl.text,
      bankName: _bankNameCtrl.text,
      bankNumber: _bankNumberCtrl.text,
      branchNumber: _branchNumberCtrl.text,
      accountNumber: _accountNumberCtrl.text,
    );

    if (!mounted) return;

    if (url == null || url.isEmpty || url == "success") {
      if (url == "success") {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _loading = false;
          _error = 'לא ניתן להשלים את האימות. פנה לתמיכה.';
        });
      }
      return;
    }

    if (kIsWeb) {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!launched) {
        setState(() {
          _loading = false;
          _error = 'לא ניתן לפתוח את עמוד ההגדרה.';
        });
        return;
      }
      setState(() {
        _loading = false;
        _webBrowserOpened = true;
      });
      return;
    }

    final controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) {
                if (request.url.startsWith(_returnUrl)) {
                  if (mounted) Navigator.of(context).pop(true);
                  return NavigationDecision.prevent;
                }
                if (request.url.startsWith(_refreshUrl)) {
                  _initOriginalFlow();
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
              onPageStarted: (_) => setState(() => _loading = true),
              onPageFinished: (_) => setState(() => _loading = false),
            ),
          )
          ..loadRequest(Uri.parse(url));

    if (mounted) {
      setState(() {
        _controller = controller;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          _showCustomForm ? 'הגדרת חשבון בנק' : 'אימות חשבון',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              )
              : _showCustomForm
              ? _buildCustomForm()
              : _buildOriginalBody(),
    );
  }

  // הטופס הפנימי החדש עם השדות המפורטים
  Widget _buildCustomForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'פרטי בעל החשבון',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildTextField('שם משפחה', _lastNameCtrl)),
                const SizedBox(width: 12),
                Expanded(child: _buildTextField('שם פרטי', _firstNameCtrl)),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField('מספר תעודת זהות', _idCtrl, isNumber: true),
            const SizedBox(height: 24),
            const Text(
              'פרטי חשבון בנק (לקבלת תשלומים)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              'שם הבנק',
              _bankNameCtrl,
              hint: 'למשל: לאומי, הפועלים',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    'מספר סניף',
                    _branchNumberCtrl,
                    isNumber: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    'קוד בנק',
                    _bankNumberCtrl,
                    isNumber: true,
                    hint: 'למשל: 10',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTextField('מספר חשבון', _accountNumberCtrl, isNumber: true),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _handleCustomSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'אישור וסיום הגדרה',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController ctrl, {
    bool isNumber = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          textAlign: TextAlign.right,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF8F9FE),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (v) => v == null || v.isEmpty ? 'חובה' : null,
        ),
      ],
    );
  }

  Widget _buildOriginalBody() {
    if (_error != null) return _buildError();
    if (kIsWeb && _webBrowserOpened) return _buildWebWaiting();
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildWebWaiting() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.open_in_browser_rounded,
            color: Color(0xFF6366F1),
            size: 60,
          ),
          const SizedBox(height: 24),
          const Text(
            'השלם את ההגדרה בדף שנפתח',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'לאחר סיום הפעולה בדפדפן, חזור לכאן ולחץ על הכפתור.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('סיימתי את ההגדרה'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 50, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error!),
          TextButton(
            onPressed: _initOriginalFlow,
            child: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }
}

/// Pushes [ProviderStripeOnboardingScreen] and returns true if the user
/// completed onboarding, false if they cancelled.
Future<bool> showStripeOnboardingPrompt(BuildContext context) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => const ProviderStripeOnboardingScreen(),
    ),
  );
  return result == true;
}
