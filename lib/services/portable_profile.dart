import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// The installer and rollback copy keep their program files in sibling folders.
/// Both copies use the UserData directory next to those folders.
class PortableProfile {
  PortableProfile(this.root);

  static PortableProfile? detect(String executable) {
    final app = p.dirname(executable);
    if (!File(p.join(app, 'portable.ini')).existsSync()) return null;
    return PortableProfile(Directory(p.dirname(app)));
  }

  final Directory root;

  Directory get data => Directory(p.join(root.path, 'UserData'));
  Directory get downloads => Directory(p.join(data.path, 'Downloads'));
  Directory get journals => Directory(p.join(data.path, 'pending_ops'));
  File get preferences => File(p.join(data.path, 'shared_preferences.json'));
  File get bridgeEndpoint => File(p.join(data.path, 'bridge_endpoint.json'));
  File get importRequest => File(p.join(data.path, 'import-local-profile'));

  /// Preserve the already initialized portable profile and the original files.
  /// Write preferences last so an interrupted import can safely be retried.
  Future<bool> importLegacy(File source, Directory legacyDownloads) async {
    if (await preferences.exists() || !await source.exists()) return false;
    final values = await PortablePreferences.read(source);
    values.remove('flutter.danmaku_app_id');
    values.remove('flutter.danmaku_app_secret');
    const downloadsKey = 'flutter.downloads_v1';
    final savedDownloads = values[downloadsKey];
    if (savedDownloads is String) {
      final legacyTasks = jsonDecode(savedDownloads) as List<dynamic>;
      final imported = <Map<String, dynamic>>[];
      for (final task in legacyTasks.whereType<Map<String, dynamic>>()) {
        final savePath = task['savePath'];
        if (savePath is! String ||
            !p.isAbsolute(savePath) ||
            !p.equals(p.dirname(p.normalize(savePath)), legacyDownloads.path)) {
          continue;
        }
        final name = p.basename(savePath);
        if (!isPortableDownloadName(name)) continue;
        final file = File(savePath);
        final isFile =
            await FileSystemEntity.type(savePath, followLinks: false) ==
            FileSystemEntityType.file;
        if (!isFile && task['status'] == 'completed') continue;
        await downloads.create(recursive: true);
        final target = p.join(downloads.path, name);
        if (isFile) await file.copy(target);
        await _copySegments(
          Directory('$savePath.segments'),
          Directory('$target.segments'),
        );
        imported.add({...task, 'savePath': name});
      }
      values[downloadsKey] = jsonEncode(imported);
    }
    await PortablePreferences.write(preferences, values);
    return true;
  }

  static Future<void> _copySegments(Directory from, Directory to) async {
    if (await FileSystemEntity.type(from.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final target = File(
        p.join(to.path, p.relative(entity.path, from: from.path)),
      );
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    }
  }
}

bool isPortableDownloadName(String name) =>
    !RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(name) &&
    name.toLowerCase().endsWith('.ts') &&
    name.length > 3;

/// Keeps the same JSON representation as Windows SharedPreferences. The main
/// process remains the only writer, including writes received via PrefsBridge.
class PortablePreferences extends SharedPreferencesStorePlatform {
  PortablePreferences(this.file);

  final File file;
  Future<void> _writes = Future<void>.value();

  static Future<Map<String, Object>> read(File file) async {
    if (!await file.exists()) return {};
    return Map<String, Object>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  static Future<void> write(File file, Map<String, Object> values) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(values), flush: true);
    await temporary.rename(file.path);
  }

  Future<bool> _update(void Function(Map<String, Object>) change) {
    final operation = _writes.then((_) async {
      final values = await read(file);
      change(values);
      await write(file, values);
      return true;
    });
    // Keep accepting writes after a transient error and report the error to
    // the caller that requested the failed write.
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithPrefix('flutter.');

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    await _writes;
    return (await read(file))
      ..removeWhere((key, _) => !_matches(key, parameters.filter));
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _update((values) => values[key] = value);

  @override
  Future<bool> remove(String key) => _update((values) => values.remove(key));

  @override
  Future<bool> clear() => clearWithPrefix('flutter.');

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) => _update(
    (values) =>
        values.removeWhere((key, _) => _matches(key, parameters.filter)),
  );

  static bool _matches(String key, PreferencesFilter filter) =>
      key.startsWith(filter.prefix) &&
      (filter.allowList?.contains(key) ?? true);
}
