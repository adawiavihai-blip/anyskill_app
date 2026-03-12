import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;

  // תרגום שגיאות Firebase לעברית לשיפור ה-QA
  String _translateError(String code) {
    switch (code) {
      case 'user-not-found': return 'לא נמצא משתמש עם האימייל הזה';
      case 'wrong-password': return 'הסיסמה שהזנת שגויה';
      case 'invalid-email': return 'כתובת האימייל אינה תקינה';
      case 'user-disabled': return 'חשבון זה הושבת על ידי המערכת';
      default: return 'שגיאה בהתחברות, נסה שנית';
    }
  }

  Future<void> _login() async {
    // ולידציה בסיסית לפני פנייה לשרת
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("נא למלא אימייל וסיסמה"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_translateError(e.code)), 
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView( // QA FIXED: מונע באג שבו המקלדת מסתירה את השדות
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // לוגו מעוצב
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_outlined, size: 80, color: Color(0xFF0D47A1)),
              ),
              const SizedBox(height: 20),
              const Text("AnySkill", style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), letterSpacing: 1.5)),
              const Text("Elite Experts Marketplace", style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 50),

              // שדה אימייל
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "אימייל",
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 20),

              // שדה סיסמה עם כפתור עין
              TextField(
                controller: _passCtrl,
                obscureText: _obscureText,
                decoration: InputDecoration(
                  labelText: "סיסמה",
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
              const SizedBox(height: 35),

              // כפתור התחברות
              _isLoading 
                ? const CircularProgressIndicator() 
                : ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 60),
                      backgroundColor: const Color(0xFF0D47A1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 5,
                    ),
                    child: const Text("התחבר למערכת", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
              
              const SizedBox(height: 25),
              
              // מעבר להרשמה
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SignUpScreen()),
                  );
                },
                child: RichText(
                  text: const TextSpan(
                    text: "אין לך חשבון? ",
                    style: TextStyle(color: Colors.black54, fontSize: 16),
                    children: [
                      TextSpan(text: "הירשם כאן בחינם", style: TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}