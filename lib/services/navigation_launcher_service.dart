import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// v10.0.0: Launches external navigation apps (Waze / Google Maps) to a destination.
///
/// Usage:
///   NavigationLauncherService.showPicker(context, lat: 32.08, lng: 34.78);
class NavigationLauncherService {
  NavigationLauncherService._();

  /// Shows a bottom sheet letting the user pick Waze or Google Maps,
  /// then launches the chosen app with the destination coordinates.
  static Future<void> showPicker(
    BuildContext context, {
    required double lat,
    required double lng,
    String? destinationName,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('נווט עם...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Waze
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF33CCFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.navigation_rounded,
                    color: Color(0xFF33CCFF), size: 24),
              ),
              title: const Text('Waze',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('ניווט בזמן אמת'),
              trailing: const Icon(Icons.chevron_left_rounded),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: () => Navigator.pop(sheetCtx,'waze'),
            ),
            const SizedBox(height: 8),

            // Google Maps
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.map_rounded,
                    color: Color(0xFF4285F4), size: 24),
              ),
              title: const Text('Google Maps',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('מפות גוגל'),
              trailing: const Icon(Icons.chevron_left_rounded),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: () => Navigator.pop(sheetCtx,'google'),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );

    if (choice == null) return;

    Uri uri;
    if (choice == 'waze') {
      uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    } else {
      final nameParam = destinationName != null
          ? '&query=${Uri.encodeComponent(destinationName)}'
          : '';
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng$nameParam');
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('לא ניתן לפתוח את אפליקציית הניווט'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
    }
  }

  /// Launches a phone call.
  static Future<void> call(BuildContext context, String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    try {
      await launchUrl(uri);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('לא ניתן לבצע שיחה'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
    }
  }
}
