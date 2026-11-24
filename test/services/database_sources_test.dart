import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:banmaku/models/history_item.dart';
import 'package:banmaku/models/video_model.dart';
import 'package:banmaku/services/database_service.dart';
import 'package:banmaku/services/scraper/source_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = DatabaseService()..resetForTest();
    await db.init();
  });

  HistoryItem history(String videoId, DateTime watchedAt) => HistoryItem(
    videoId: videoId,
    title: '视频-$videoId',
    episodeIndex: 0,
    position: const Duration(seconds: 30),
    duration: const Duration(minutes: 24),
    watchedAt: watchedAt,
  );

  test('数据源配置：默认值、持久化、主源 id', () async {
    expect(db.getSources().length, 2);
    expect(db.getActiveSourceId(), isNull);

    const custom = SourceConfig(
      id: 'custom_1',
      name: '自定义源',
      baseUrl: 'https://example.com/api.php/provide/vod/',
    );
    await db.saveSources([custom]);
    expect(db.getSources().single.name, '自定义源');

    await db.setActiveSourceId('custom_1');
    expect(db.getActiveSourceId(), 'custom_1');
  });

  test('配置桥接受自动回退的布尔值', () {
    expect(
      db.validateRemotePayload({
        'set': {'source_auto_fallback_v1': true},
      }),
      isNull,
    );
    expect(
      db.validateRemotePayload({
        'set': {'source_auto_fallback_v1': 'true'},
      }),
      'bad_value',
    );
  });

  test('自动回退默认关闭且重启后保留设置', () async {
    expect(db.getSourceAutoFallback(), isFalse);
    await db.setSourceAutoFallback(true);
    db.resetForTest();
    await db.init();
    expect(db.getSourceAutoFallback(), isTrue);
  });

  test('并发写历史不会丢更新（写队列串行化）', () async {
    await Future.wait([
      db.saveHistory(history('a', DateTime(2026, 1, 1))),
      db.saveHistory(history('b', DateTime(2026, 1, 2))),
      db.saveHistory(history('c', DateTime(2026, 1, 3))),
    ]);

    final ids = db.getHistory().map((h) => h.videoId).toSet();
    expect(ids, {'a', 'b', 'c'});
  });

  test('并发写收藏不会丢更新', () async {
    await Future.wait([
      db.addFavorite(VideoModel(id: 'a', title: 'A')),
      db.addFavorite(VideoModel(id: 'b', title: 'B')),
    ]);

    final ids = db.getFavorites().map((v) => v.id).toSet();
    expect(ids, {'a', 'b'});
  });
}
