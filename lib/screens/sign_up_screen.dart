import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;
  bool _termsAccepted = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$', caseSensitive: false)
        .hasMatch(email.trim());
  }

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("חובה לאשר את תנאי השימוש כדי להירשם"),
          backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // 1. יצירת המשתמש ב-Authentication
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      String uid = userCredential.user!.uid;

      // 2. יצירת מסמך המשתמש ב-Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'balance': 0.0,
        'rating': 5.0,
        'reviewsCount': 0,
        'pricePerHour': 0.0,
        'serviceType': 'אחר',
        'aboutMe': 'מומחה חדש בקהילת AnySkill',
        'profileImage': '',
        'isOnline': true,
        'isAdmin': false,         
        'isVerified': false,      
        'isCustomer': true,       
        'isProvider': false,
        'termsAccepted': true,
        'onboardingComplete': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text("החשבון נוצר בהצלחה! ברוכים הבאים.")),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMsg = "שגיאה ברישום";
      if (e.code == 'email-already-in-use') errorMsg = "האימייל הזה כבר תפוס";
      if (e.code == 'invalid-email') errorMsg = "כתובת האימייל אינה תקינה";

      messenger.showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // חלון קופץ שמציג את התקנון (Legal Dialog)
  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("תנאי שימוש ומדיניות", textAlign: TextAlign.right),
        content: const SingleChildScrollView(
          child: Text(
            "1. AnySkill היא פלטפורמת תיווך בלבד.\n"
            "2. המערכת גובה עמלת שירות מכל עסקה מוצלחת.\n"
            "3. הכסף מוחזק בנאמנות (Escrow) עד לסיום הביצוע.\n"
            "4. חל איסור על הטרדה או ביצוע עסקאות מחוץ למערכת.\n"
            "5. המשתמש מאשר שמיקומו יוצג על המפה לצרכי שירות.",
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("הבנתי")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0D47A1),
        title: const Text("יצירת חשבון", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Form(
            key: _formKey,
            child: Column(
            children: [
              const Icon(Icons.person_add_outlined, size: 70, color: Color(0xFF0D47A1)),
              const SizedBox(height: 10),
              const Text("הצטרפו ל-AnySkill Elite", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Text("מצא מומחים או התחל לתת שירות", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),

              TextFormField(
                controller: _nameCtrl,
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'נא להזין שם';
                  if (s.length < 2) return 'השם חייב להכיל לפחות 2 תווים';
                  return null;
                },
                decoration: InputDecoration(
                  labelText: "שם מלא",
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'נא להזין אימייל';
                  if (!_isValidEmail(v)) return 'כתובת אימייל אינה תקינה';
                  return null;
                },
                decoration: InputDecoration(
                  labelText: "אימייל",
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _passCtrl,
                obscureText: _obscureText,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'נא להזין סיסמה';
                  if (v.length < 6) return 'הסיסמה חייבת להכיל לפחות 6 תווים';
                  return null;
                },
                decoration: InputDecoration(
                  labelText: "סיסמה (מינימום 6 תווים)",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              
              const SizedBox(height: 25),

              // --- WIDGET תנאי שימוש ---
              Row(
                children: [
                  Checkbox(
                    value: _termsAccepted,
                    onChanged: (val) => setState(() => _termsAccepted = val!),
                    activeColor: const Color(0xFF0D47A1),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showTermsDialog,
                      child: const Text(
                        "אני מאשר את תנאי השימוש ומדיניות הפרטיות",
                        style: TextStyle(fontSize: 13, decoration: TextDecoration.underline, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              _isLoading 
                ? const CircularProgressIndicator() 
                : ElevatedButton(
                    onPressed: _signUp,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 60),
                      backgroundColor: const Color(0xFF0D47A1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 3,
                    ),
                    child: const Text("צור חשבון והתחל", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
              const SizedBox(height: 20),
            ],
          ),
          ),
        ),
      ),
    );
  }
}