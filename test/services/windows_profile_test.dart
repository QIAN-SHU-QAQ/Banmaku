import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:banmaku/services/windows_profile.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory current;
  late Directory legacy;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('banmaku-profile');
    current = Directory(p.join(root.path, 'current'));
    legacy = await Directory(p.join(root.path, 'legacy')).create();
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'copies preferences and pending operations into the renamed profile',
    () async {
      final oldPrefs = File(p.join(legacy.path, 'shared_preferences.json'));
      await oldPrefs.writeAsString('{"flutter.theme_mode":2}');
      final oldJournal = File(
        p.join(legacy.path, 'pending_ops', 'pending_ops.12.json'),
      );
      await oldJournal.create(recursive: true);
      await oldJournal.writeAsString('[]');
      await File(
        p.join(legacy.path, 'bridge_endpoint.json'),
      ).writeAsString('{}');

      await migrateWindowsProfile(legacy: legacy, current: current);

      expect(
        await File(
          p.join(current.path, 'shared_preferences.json'),
        ).readAsString(),
        await oldPrefs.readAsString(),
      );
      expect(
        await File(
          p.join(current.path, 'pending_ops', 'pending_ops.12.json'),
        ).readAsString(),
        '[]',
      );
      expect(
        await File(p.join(current.path, 'bridge_endpoint.json')).exists(),
        isFalse,
      );
      expect(await oldJournal.exists(), isTrue);
    },
  );

  test('keeps newer preferences when the application starts again', () async {
    final oldPrefs = File(p.join(legacy.path, 'shared_preferences.json'));
    await oldPrefs.writeAsString('{"flutter.theme_mode":2}');
    await current.create();
    final prefs = File(p.join(current.path, 'shared_preferences.json'));
    await prefs.writeAsString('{"flutter.theme_mode":1}');

    await migrateWindowsProfile(legacy: legacy, current: current);

    expect(await prefs.readAsString(), '{"flutter.theme_mode":1}');
    expect(await oldPrefs.readAsString(), '{"flutter.theme_mode":2}');
  });
}
