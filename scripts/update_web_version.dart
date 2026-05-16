import 'dart:io';

/// Syncs `REQUIRED_VERSION` in app_init.js with the version in pubspec.yaml.
///
/// Wired as a Firebase Hosting `predeploy` hook (see firebase.json), so it
/// runs automatically before every `firebase deploy`. A predeploy hook runs
/// AFTER `flutter build web`, so it patches BOTH:
///   * web/app_init.js        — the source of truth (kept in sync for git)
///   * build/web/app_init.js  — the built artifact that actually gets uploaded
///
/// Exits non-zero on hard failure so a broken sync ABORTS the deploy rather
/// than silently shipping a stale REQUIRED_VERSION (which would leave every
/// installed PWA stuck on the old build).
void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('❌ Error: pubspec.yaml not found');
    exit(1);
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final versionMatch = RegExp(r'version:\s*(.+)').firstMatch(pubspecContent);
  if (versionMatch == null) {
    print('❌ Error: Version not found in pubspec.yaml');
    exit(1);
  }

  // Keep the FULL version+build string (e.g. "11.9.0+1") so that bumping
  // only the build number still changes REQUIRED_VERSION and fires the
  // web cache-bust / nuclear purge.
  final fullVersion = versionMatch.group(1)?.trim() ?? '';
  if (fullVersion.isEmpty) {
    print('❌ Error: pubspec.yaml version is empty');
    exit(1);
  }

  final pattern = RegExp(r"var REQUIRED_VERSION = '.*';");
  final replacement = "var REQUIRED_VERSION = '$fullVersion';";

  // Source first, then the built artifact (only present after `flutter build web`).
  const targets = ['web/app_init.js', 'build/web/app_init.js'];

  var updated = 0;
  for (final path in targets) {
    final file = File(path);
    if (!file.existsSync()) continue;

    final content = file.readAsStringSync();
    if (!pattern.hasMatch(content)) {
      print('⚠️  Warning: REQUIRED_VERSION line not found in $path — skipped');
      continue;
    }

    file.writeAsStringSync(content.replaceAll(pattern, replacement));
    print('✅ $path → REQUIRED_VERSION = $fullVersion');
    updated++;
  }

  if (updated == 0) {
    print('❌ Error: no patchable app_init.js found (looked in web/ and build/web/)');
    exit(1);
  }
}
