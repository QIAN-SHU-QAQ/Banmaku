import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/services/portable_profile.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('banmaku_'));
  tearDown(() async => root.delete(recursive: true));

  test('marker opts in, and restored program shares the same data', () async {
    final app = await Directory(p.join(root.path, 'app')).create();
    final executable = p.join(app.path, 'nova_play.exe');
    expect(PortableProfile.detect(executable), isNull);

    await File(p.join(app.path, 'portable.ini')).create();
    final profile = PortableProfile.detect(executable)!;
    final previous = await app.rename(p.join(root.path, 'app.previous'));
    final restored =
        PortableProfile.detect(p.join(previous.path, 'nova_play.exe'))!;
    expect(profile.data.path, p.join(root.path, 'UserData'));
    expect(restored.preferences.path, profile.preferences.path);
    expect(restored.bridgeEndpoint.path, profile.bridgeEndpoint.path);
  });

  test('concurrent writes persist a single compatible profile', () async {
    final profile = PortableProfile(root);
    await profile.data.create();
    final store = PortablePreferences(profile.preferences);
    await Future.wait([
      store.setValue('String', 'flutter.theme_mode', 'dark'),
      store.setValue('String', 'flutter.history_v1', '[]'),
    ]);

    final anotherProcess = PortablePreferences(profile.preferences);
    expect(await anotherProcess.getAll(), {
      'flutter.theme_mode': 'dark',
      'flutter.history_v1': '[]',
    });
  });

  test('initial import copies settings and completed media once', () async {
    final legacy = await Directory(p.join(root.path, 'old')).create();
    final oldMedia = File(p.join(legacy.path, 'episode.ts'));
    await oldMedia.writeAsBytes([1, 2, 3]);
    final source = File(p.join(legacy.path, 'shared_preferences.json'));
    await source.writeAsString(
      jsonEncode({
        'flutter.theme_mode': 'dark',
        'flutter.downloads_v1': jsonEncode([
          {'savePath': oldMedia.path, 'status': 'completed'},
        ]),
      }),
    );
    final profile = PortableProfile(root);

    expect(await profile.importLegacy(source, legacy), isTrue);
    final imported = await PortablePreferences(profile.preferences).getAll();
    expect(imported['flutter.theme_mode'], 'dark');
    expect(jsonDecode(imported['flutter.downloads_v1'] as String), [
      {'savePath': 'episode.ts', 'status': 'completed'},
    ]);
    expect(
      await File(p.join(profile.downloads.path, 'episode.ts')).readAsBytes(),
      [1, 2, 3],
    );
    expect(await oldMedia.exists(), isTrue);
    expect(await profile.importLegacy(source, legacy), isFalse);
  });
}
