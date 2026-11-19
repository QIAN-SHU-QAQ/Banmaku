import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/models/history_item.dart';
import 'package:nova_play/models/video_model.dart';
import 'package:nova_play/services/database_service.dart';
import 'package:nova_play/services/scraper/source_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lziUrl = 'https://cj.lziapi.com/api.php/provide/vod/';
  const otherUrl = 'https://360zy.com/api.php/provide/vod/';
  final oldDate = DateTime(2026, 11, 10);
  final newDate = DateTime(2026, 11, 12);

  HistoryItem history(VideoModel video, DateTime at, {int seconds = 180}) =>
      HistoryItem(
        videoId: video.id,
        title: video.title,
        sourceId: video.source,
        episodeIndex: 1,
        position: Duration(seconds: seconds),
        watchedAt: at,
      );

  Future<DatabaseService> seedLegacy(
    VideoModel favorite,
    HistoryItem item,
  ) async {
    SharedPreferences.setMockInitialValues({
      'favorites_v1': jsonEncode([favorite.toJson()]),
      'history_v1': jsonEncode([item.toJson()]),
    });
    final db = DatabaseService()..resetForTest();
    await db.init();
    return db;
  }

  final oldPrimary = VideoModel(
    id: '42',
    title: '旧收藏',
    source: '360zy',
    sourceUrl: otherUrl,
  );
  final lzi = VideoModel(
    id: '42',
    title: '荔枝作品',
    source: 'LziApi',
    sourceUrl: lziUrl,
  );

  test('旧主源 ID 与备用源同号 ID 在收藏和历史中独立保存', () async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    for (final id in ['42', '360zy:42']) {
      await db.addFavorite(VideoModel(id: id, title: id));
      await db.saveHistory(
        HistoryItem(
          videoId: id,
          title: id,
          episodeIndex: 0,
          position: const Duration(seconds: 60),
          watchedAt: DateTime(2026, 10, 29),
        ),
      );
    }
    db.resetForTest();
    await db.init();
    expect(db.getFavorites().map((v) => v.id).toSet(), {'42', '360zy:42'});
    expect(db.getHistory().map((v) => v.videoId).toSet(), {'42', '360zy:42'});
    await db.removeFavorite('360zy:42');
    await db.removeHistory('360zy:42');
    expect(db.getFavorites().single.id, '42');
    expect(db.getHistory().single.videoId, '42');
  });

  test('旧版非默认主源记录按来源复用原有存储键', () async {
    final db = await seedLegacy(
      oldPrimary.copyWith(source: '以前的显示名称'),
      history(oldPrimary, oldDate),
    );
    final current = oldPrimary.copyWith(id: '360zy:42');

    expect(db.sourceIdForFavorite(db.getFavorites().single), '360zy');
    expect(db.sourceIdForHistory(db.getHistory().single), '360zy');
    expect(db.favoriteForVideo(current)?.id, '42');
    expect(db.historyForVideo(current)?.position.inSeconds, 180);
    expect(db.historyIdForVideo(current), '42');

    await db.addFavorite(current);
    await db.saveHistory(history(current, newDate, seconds: 200));
    expect(db.getFavorites().single.id, '42');
    expect(db.getHistory().single.videoId, '42');
    expect(db.getHistory().single.position.inSeconds, 200);
  });

  test('新增的荔枝同号作品保留旧版非默认主源记录', () async {
    final db = await seedLegacy(oldPrimary, history(oldPrimary, oldDate));

    await db.addFavorite(lzi);
    await db.saveHistory(history(lzi, newDate, seconds: 100));

    expect(db.getFavorites().map((v) => v.id).toSet(), {'42', 'lziapi:42'});
    expect(db.getHistory().map((h) => h.videoId).toSet(), {'42', 'lziapi:42'});
    expect(db.getHistory().last.position.inSeconds, 180);
    expect(db.favoriteForVideo(lzi)?.id, 'lziapi:42');
    expect(db.historyForVideo(lzi)?.position.inSeconds, 100);
    expect(db.favoriteForVideo(oldPrimary.copyWith(id: '360zy:42'))?.id, '42');
    expect(
      db.historyForVideo(oldPrimary.copyWith(id: '360zy:42'))?.videoId,
      '42',
    );
  });

  test('无法确认作品时保留同片源同裸号的旧记录', () async {
    final db = await seedLegacy(oldPrimary, history(oldPrimary, oldDate));
    final reusedId = oldPrimary.copyWith(id: '360zy:42', title: '另一部作品');

    await db.addFavorite(reusedId);
    await db.saveHistory(history(reusedId, newDate));

    expect(db.getFavorites().map((v) => v.id).toSet(), {'42', '360zy:42'});
    expect(db.getHistory().map((h) => h.videoId).toSet(), {'42', '360zy:42'});
  });

  test('删除旧键后迟到的带前缀写入不能恢复记录', () async {
    final db = await seedLegacy(oldPrimary, history(oldPrimary, oldDate));
    final current = oldPrimary.copyWith(id: '360zy:42');
    final deletedAt = DateTime(2026, 11, 14).toIso8601String();

    await db.applyRemoteOps([
      {'op': 'favorites.remove', 'videoId': '42', 'at': deletedAt},
      {'op': 'history.remove', 'videoId': '42', 'at': deletedAt},
      {
        'op': 'favorites.add',
        'item': current.toJson(),
        'at': newDate.toIso8601String(),
      },
      {'op': 'history.upsert', 'item': history(current, newDate).toJson()},
    ]);

    expect(db.getFavorites(), isEmpty);
    expect(db.getHistory(), isEmpty);
  });

  test('旧历史名称有歧义时，仅旧收藏可按实际 API 地址确认来源', () async {
    final db = await seedLegacy(oldPrimary, history(oldPrimary, oldDate));
    final configs = SourceConfig.defaults();
    await db.saveSources([configs.first.copyWith(name: '360zy'), configs.last]);
    final lziWithSharedName = lzi.copyWith(source: '360zy');

    expect(db.favoriteForVideo(oldPrimary.copyWith(id: '360zy:42'))?.id, '42');
    expect(db.historyForVideo(oldPrimary.copyWith(id: '360zy:42')), isNull);
    expect(db.sourceIdForHistory(db.getHistory().single), isNull);
    expect(db.historyIdForVideo(lziWithSharedName), 'lziapi:42');
  });

  test('迟到的旧源裸号删除不会误删新写入的荔枝作品', () async {
    final db = await seedLegacy(oldPrimary, history(oldPrimary, oldDate));
    final deletedAt = DateTime(2026, 11, 14).toIso8601String();
    await db.applyRemoteOps([
      {'op': 'favorites.remove', 'videoId': '42', 'at': deletedAt},
      {'op': 'history.remove', 'videoId': '42', 'at': deletedAt},
      {
        'op': 'favorites.add',
        'item': lzi.toJson(),
        'at': newDate.toIso8601String(),
      },
      {'op': 'history.upsert', 'item': history(lzi, newDate).toJson()},
      {'op': 'favorites.remove', 'videoId': '42', 'at': deletedAt},
      {'op': 'history.remove', 'videoId': '42', 'at': deletedAt},
    ]);

    expect(db.favoriteForVideo(lzi)?.id, 'lziapi:42');
    expect(db.historyForVideo(lzi)?.videoId, 'lziapi:42');
  });

  test('旧客户端重加后，来源不明的迟到写入无法恢复已删除裸号', () async {
    final db = await seedLegacy(oldPrimary, history(oldPrimary, oldDate));
    final deletedAt = DateTime(2026, 11, 14).toIso8601String();
    final addedAt = DateTime(2026, 11, 15);
    final anonymous = VideoModel(id: '42', title: oldPrimary.title);
    await db.applyRemoteOps([
      {'op': 'favorites.remove', 'videoId': '42', 'at': deletedAt},
      {'op': 'history.remove', 'videoId': '42', 'at': deletedAt},
      {
        'op': 'favorites.add',
        'item': oldPrimary.toJson(),
        'at': addedAt.toIso8601String(),
      },
      {'op': 'history.upsert', 'item': history(oldPrimary, addedAt).toJson()},
      {
        'op': 'favorites.add',
        'item': anonymous.toJson(),
        'at': oldDate.toIso8601String(),
      },
      {'op': 'history.upsert', 'item': history(anonymous, oldDate).toJson()},
    ]);

    expect(db.getFavorites().single.id, '360zy:42');
    expect(db.getHistory().single.videoId, '360zy:42');
  });
}
