import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/content_management_service.dart';

/// Admin Design Tab — A self-contained CMS for managing application text.
/// Only visible to adawiavihai@gmail.com.
///
/// Two-pane layout:
/// - Left: Tree of screens/features to edit
/// - Right: Dynamic editor with TextFormFields for each text key
class AdminDesignTab extends StatefulWidget {
  const AdminDesignTab({super.key});

  @override
  State<AdminDesignTab> createState() => _AdminDesignTabState();
}

class _AdminDesignTabState extends State<AdminDesignTab> {
  String? _selectedScreen;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _originalValues = {};
  String _selectedLocale = 'he';
  bool _saving = false;
  bool _resetting = false;
  StreamSubscription<Map<String, String>>? _overridesSub;
  Map<String, String> _currentOverrides = {};

  @override
  void initState() {
    super.initState();
    _selectedScreen = ContentManagementService.screenGroups.keys.first;
    _loadOverrides();
  }

  @override
  void dispose() {
    _overridesSub?.cancel();
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _loadOverrides() {
    _overridesSub?.cancel();
    _overridesSub = ContentManagementService.streamOverrides(_selectedLocale)
        .listen((overrides) {
          if (mounted) {
            setState(() => _currentOverrides = overrides);
            _refreshControllers();
          }
        });
  }

  void _refreshControllers() {
    // Dispose old controllers
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _controllers.clear();
    _originalValues.clear();

    final keys = ContentManagementService.screenGroups[_selectedScreen] ?? [];
    for (final key in keys) {
      final override = _currentOverrides[key];
      final original = AppLocalizations.getDefault(key, _selectedLocale);

      _originalValues[key] = original;
      final ctrl = TextEditingController(text: override ?? original);
      _controllers[key] = ctrl;
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    try {
      final keys = ContentManagementService.screenGroups[_selectedScreen] ?? [];
      for (final key in keys) {
        final ctrl = _controllers[key];
        if (ctrl != null) {
          final newValue = ctrl.text.trim();
          final originalValue = _originalValues[key] ?? '';

          if (newValue.isEmpty || newValue == originalValue) {
            // Reset to default
            await ContentManagementService.resetOverride(_selectedLocale, key);
          } else {
            // Save override
            await ContentManagementService.setOverride(
              _selectedLocale,
              key,
              newValue,
            );
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ השינויים נשמרו')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _resetScreen() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אפס את כל הטקסטים בקטגוריה זו?'),
        content: const Text('פעולה זו תחזיר את כל הטקסטים לברירות המחדל'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('אפס'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _resetting = true);
    try {
      final keys = ContentManagementService.screenGroups[_selectedScreen] ?? [];
      for (final key in keys) {
        await ContentManagementService.resetOverride(_selectedLocale, key);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ כל הטקסטים חזרו לברירות המחדל')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  void _onScreenSelected(String? screen) {
    if (screen != null && screen != _selectedScreen) {
      setState(() => _selectedScreen = screen);
      _refreshControllers();
    }
  }

  void _onLocaleChanged(String locale) {
    setState(() => _selectedLocale = locale);
    _loadOverrides();
  }

  @override
  Widget build(BuildContext context) {
    // Permission check
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser?.email != 'adawiavihai@gmail.com') {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('הגישה מוגבלת', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final keys = ContentManagementService.screenGroups[_selectedScreen] ?? [];

    return Scaffold(
      body: Row(
        children: [
          // ─── Left Pane: Screen Selector ──────────────────────────────────
          SizedBox(
            width: 250,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: const Text(
                    'עיצוב תוכן',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Screen list
                Expanded(
                  child: ListView.builder(
                    itemCount:
                        ContentManagementService.screenGroups.keys.length,
                    itemBuilder: (ctx, idx) {
                      final screen =
                          ContentManagementService.screenGroups.keys.elementAt(
                        idx,
                      );
                      final isSelected = screen == _selectedScreen;
                      return ListTile(
                        selected: isSelected,
                        title: Text(screen),
                        onTap: () => _onScreenSelected(screen),
                        selectedTileColor: Colors.blue[100],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),

          // ─── Right Pane: Editor ──────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // Header with locale selector
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedScreen ?? 'בחר קטגוריה',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Locale selector
                      Wrap(
                        spacing: 8,
                        children: ['he', 'en', 'es'].map((locale) {
                          final isActive = locale == _selectedLocale;
                          return FilterChip(
                            selected: isActive,
                            label: Text(locale.toUpperCase()),
                            onSelected: isActive
                                ? null
                                : (_) => _onLocaleChanged(locale),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                // Editor fields
                Expanded(
                  child: keys.isEmpty
                      ? const Center(
                          child: Text('בחר קטגוריה לעריכה'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: keys.length,
                          itemBuilder: (ctx, idx) {
                            final key = keys[idx];
                            final ctrl = _controllers[key];
                            final originalValue = _originalValues[key] ?? '';

                            if (ctrl == null) return const SizedBox.shrink();

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Key label
                                  Text(
                                    key,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Input field
                                  TextFormField(
                                    controller: ctrl,
                                    minLines: 1,
                                    maxLines: originalValue.length > 50 ? 3 : 2,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      hintText: originalValue,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                // Bottom buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _resetting ? null : _resetScreen,
                        icon: const Icon(Icons.refresh),
                        label: const Text('אפס הכל'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _saveChanges,
                        icon: const Icon(Icons.save),
                        label: const Text('שמור שינויים'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
