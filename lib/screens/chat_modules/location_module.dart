import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import '../../services/permission_service.dart';

class LocationModule {
  static Future<String?> getMapUrl() async {
    try {
      // 1. בדיקה אם שירותי המיקום (GPS) דלוקים במכשיר
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled.");
        return null;
      }

      // 2. בדיקת הרשאות מהמשתמש — עם זיכרון קבוע
      final stored = await PermissionService.getLocationStatus();

      if (stored == PermissionService.denied) {
        // User already declined via LocationService — don't re-prompt here.
        debugPrint("Location: stored as denied — skipping prompt.");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        await PermissionService.saveLocationStatus(PermissionService.denied);
        debugPrint("Location permissions are permanently denied.");
        return null;
      }

      if (permission == LocationPermission.denied) {
        if (stored == null) {
          // Only ask the OS if we've never recorded a choice. The main
          // permission dialog (LocationService.requestAndGet) handles the
          // branded pre-prompt; here we go straight to the OS.
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          await PermissionService.saveLocationStatus(PermissionService.denied);
          debugPrint("Location permissions are denied.");
          return null;
        }
      }

      // Permission granted — record it if not already stored.
      if (stored != PermissionService.granted) {
        await PermissionService.saveLocationStatus(PermissionService.granted);
      }

      // 3. הבאת המיקום המדויק
      Position pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));

      // 4. החזרת קישור תקין (QA: שימוש ב-String interpolation בטוח)
      // הוספתי את הסימן $ בצורה מפורשת לטרמינל
      return "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
    } catch (e) {
      debugPrint("QA Error - Location Module: $e");
      return null;
    }
  }
}