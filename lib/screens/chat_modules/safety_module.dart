import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class SafetyModule {
  // 1. בדיקת חיבור לאינטרנט
  static Future<bool> hasInternet() async {
    var results = await Connectivity().checkConnectivity();
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return false;
    }
    return true;
  }

  // 2. בדיקת גודל קובץ (QA: מונע העלאות כבדות ששורפות כסף ב-Storage)
  static bool isFileSizeValid(int bytes, {int maxMb = 5}) {
    double sizeInMb = bytes / (1024 * 1024);
    return sizeInMb <= maxMb;
  }

  // 3. הצגת התראה מהירה למשתמש (SnackBar)
  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Heebo')),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}