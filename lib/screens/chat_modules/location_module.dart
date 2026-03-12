import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class LocationModule {
  static Future<String?> getMapUrl() async {
    try {
      // 1. בדיקה אם שירותי המיקום (GPS) דלוקים במכשיר
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled.");
        return null;
      }

      // 2. בדיקת הרשאות מהמשתמש
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permissions are denied.");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permissions are permanently denied.");
        return null;
      }

      // 3. הבאת המיקום המדויק
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      // 4. החזרת קישור תקין (QA: שימוש ב-String interpolation בטוח)
      // הוספתי את הסימן $ בצורה מפורשת לטרמינל
      return "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
    } catch (e) {
      debugPrint("QA Error - Location Module: $e");
      return null;
    }
  }
}