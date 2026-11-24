import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_windows/path_provider_windows.dart';

const _preferences = 'shared_preferences.json';

// FOLDERID_RoamingAppData. Use the GUID so the path provider's analysis stub
// can type-check this call alongside the native implementation.
Future<String?> _roamingAppData() =>
    PathProviderWindows().getPath('{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}');

// The preview executable used these names in its Windows version resource.
Future<Directory?> legacyWindowsSupportDirectory() async {
  final roaming = await _roamingAppData();
  return roaming == null
      ? null
      : Directory(p.join(roaming, 'com.novaplay', 'nova_play'));
}

Directory legacyWindowsDownloads(Directory documents) =>
    Directory(p.join(documents.path, 'NovaPlay', 'Downloads'));

/// Transfer the old profile once, preserving the source for rollback.
Future<void> migrateWindowsProfile({
  required Directory legacy,
  required Directory current,
}) async {
  if (!await legacy.exists()) return;
  await current.create(recursive: true);
  final marker = File(p.join(current.path, '.legacy-import-complete'));
  final preferences = File(p.join(current.path, _preferences));
  if (await marker.exists() || await preferences.exists()) return;

  // Keep a simultaneous startup from replacing the newly migrated profile.
  final lock = await File(
    p.join(current.path, '.legacy-import.lock'),
  ).open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    if (await marker.exists() || await preferences.exists()) return;
    final oldJournals = Directory(p.join(legacy.path, 'pending_ops'));
    if (await oldJournals.exists()) {
      final journals = await Directory(
        p.join(current.path, 'pending_ops'),
      ).create(recursive: true);
      await for (final entry in oldJournals.list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (entry is File &&
            RegExp(
              r'^pending_ops\.\d+(?:\.oversized)?\.json(?:\.processing)?$',
            ).hasMatch(name)) {
          final target = File(p.join(journals.path, name));
          if (!await target.exists()) await _copyAtomically(entry, target);
        }
      }
    }
    final oldPreferences = File(p.join(legacy.path, _preferences));
    if (await oldPreferences.exists()) {
      await _copyAtomically(oldPreferences, preferences);
    }
    await marker.create();
  } finally {
    await lock.close();
  }
}

Future<void> _copyAtomically(File source, File target) async {
  final temporary = await source.copy('${target.path}.migration-tmp');
  await temporary.rename(target.path);
}
