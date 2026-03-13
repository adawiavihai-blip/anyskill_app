import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  bool _isLoginView = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isLoginView) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        UserCredential userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        await userCred.user!.sendEmailVerification();

        await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).set({
          'name': _nameController.text.trim(),
          'city': _cityController.text.trim(),
          'email': _emailController.text.trim(),
          'isOnline': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        _showVerifyInfo();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("שגיאה: ${e.toString()}")));
    }
  }

  void _showVerifyInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("שלב אחרון!"),
        content: const Text("שלחנו לך קישור אימות למייל. אשר אותו כדי להתחבר."),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("הבנתי"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield, size: 60, color: Color(0xFF0D47A1)),
                const SizedBox(height: 10),
                Text(_isLoginView ? "כניסה למערכת" : "הרשמה למשתמש חדש", 
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                if (!_isLoginView) ...[
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: "שם מלא", border: OutlineInputBorder())),
                  const SizedBox(height: 15),
                  TextField(controller: _cityController, decoration: const InputDecoration(labelText: "עיר", border: OutlineInputBorder())),
                  const SizedBox(height: 15),
                ],
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: "אימייל", border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: "סיסמה", border: OutlineInputBorder())),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(_isLoginView ? "התחבר" : "צור חשבון ושלח אימות"),
                ),
                const SizedBox(height: 15),
                TextButton(
                  onPressed: () => setState(() => _isLoginView = !_isLoginView),
                  child: Text(_isLoginView ? "אין לך חשבון? הירשם כאן" : "כבר רשום? עבור להתחברות"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}