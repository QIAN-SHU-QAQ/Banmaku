import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nova_play/core/config/theme.dart';
import 'package:nova_play/features/detail/detail_screen.dart';
import 'package:nova_play/features/download/download_screen.dart';
import 'package:nova_play/features/favorites/favorites_screen.dart';
import 'package:nova_play/features/settings/settings_screen.dart';
import 'package:nova_play/features/search/search_screen.dart';
import 'package:nova_play/models/bangumi_info.dart';
import 'package:nova_play/models/history_item.dart';
import 'package:nova_play/models/video_model.dart';
import 'package:nova_play/providers/bangumi_provider.dart';
import 'package:nova_play/services/bangumi_api.dart';
import 'package:nova_play/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_play/providers/favorites_provider.dart';
import 'package:nova_play/providers/theme_provider.dart';
import 'package:nova_play/providers/video_provider.dart';
import 'package:nova_play/providers/scraper_provider.dart';
import 'package:nova_play/shared/widgets/wide_media_card.dart';

import 'fakes.dart';

class _GenreScraper extends FakeScraper {
  @override
  Future<List<VideoModel>> search(String keyword, {int page = 1}) async => [
    VideoModel(id: 'one', title: '科幻片', genre: ' 动画 / 科幻 '),
    VideoModel(id: 'two', title: '剧情片', genre: '剧情'),
  ];
}

class _RetryDetailScraper extends FakeScraper {
  int requests = 0;

  @override
  Future<VideoModel> getDetail(String id) async {
    if (++requests == 1) throw StateError('片源暂不可用');
    return VideoModel(id: id, title: '重试后的作品');
  }
}

void main() {
  testWidgets('search filters normalize genre spaces and retain list toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentScraperProvider.overrideWithValue(_GenreScraper())],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('剧情片'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '科幻'));
    await tester.pumpAndSettle();
    expect(find.text('科幻片'), findsOneWidget);
    expect(find.text('剧情片'), findsNothing);
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(find.text('科幻片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme choices work and unfinished settings are disabled', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    for (final option in [
      ('深色', ThemeMode.dark),
      ('浅色', ThemeMode.light),
      ('跟随系统', ThemeMode.system),
    ]) {
      await tester.tap(find.text(option.$1));
      await tester.pump();
      expect(container.read(themeModeProvider), option.$2);
    }
    // 自动连播已接通：是 SwitchListTile，默认开启
    final autoPlayTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '自动播放下一集'),
    );
    expect(autoPlayTile.value, isTrue);
    // 弹幕账号/样式已接通；下载路径、检查更新仍是占位（需要滚动到底部）
    await tester.scrollUntilVisible(find.text('检查更新'), 300);
    expect(find.text('尚未开放'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorite remove button confirms before removing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final video = VideoModel(id: 'favorite', title: '收藏测试');
    await container.read(favoritesProvider.notifier).toggle(video);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('移除收藏'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(container.read(favoritesProvider), hasLength(1));
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(container.read(favoritesProvider), isEmpty);
    expect(find.text('暂无收藏'), findsOneWidget);
  });

  testWidgets('download page explains availability without simulated tasks', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DownloadScreen())),
    );
    expect(find.text('还没有下载任务'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('编辑'), findsNothing);
  });

  testWidgets('library row remains usable with long text at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var resumed = false;
    var removed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WideMediaCard(
            title: '很长的片名' * 20,
            subtitle: '很长的集名' * 20,
            meta: '刚刚观看',
            progress: 0.5,
            onResume: () => resumed = true,
            onRemove: () => removed = true,
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('继续观看'));
    await tester.tap(find.byTooltip('删除'));
    expect(resumed, isTrue);
    expect(removed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(616, 600), const Size(1120, 720)]) {
    testWidgets('detail keeps selection visible at ${size.width}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bangumi = Completer<BangumiLookupResult>();
      final title = '同名作品${'很长的片名' * 14}';
      final description = '很长的简介' * 200;
      final seasons = [
        for (final (id, year, source) in [
          ('season-one', '2023', 'LziApi'),
          ('season-two', '2025', '360zy'),
        ])
          VideoModel(
            id: id,
            title: title,
            year: year,
            source: source,
            rating: 8.4,
            description: description,
            episodes: [
              for (var index = 1; index <= 24; index++)
                EpisodeModel(
                  id: 'episode-$index',
                  title: '第 $index 集 · 起点',
                  url: 'episode-$index',
                ),
            ],
          ),
      ];

      for (final season in seasons) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(season.id),
            overrides: [
              currentScraperProvider.overrideWithValue(FakeScraper()),
              videoDetailProvider(
                season.id,
              ).overrideWith((ref) async => season),
              bangumiInfoProvider(
                BangumiQuery(videoId: season.id, title: season.title),
              ).overrideWith((ref) => bangumi.future),
            ],
            child: MaterialApp(
              theme: size.width == 616 ? AppTheme.dark : AppTheme.light,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(
                        size.width == 616 ? 1.6 : 1,
                      ),
                    ),
                    child: child!,
                  ),
              home: DetailScreen(id: season.id),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(title).hitTestable(), findsOneWidget);
        expect(find.text(season.year!).hitTestable(), findsOneWidget);
        expect(find.text('片源：${season.source}').hitTestable(), findsOneWidget);
        expect(find.text('共 24 集').hitTestable(), findsOneWidget);
        expect(find.byIcon(Icons.movie_outlined).hitTestable(), findsOneWidget);
        expect(find.textContaining('选集').first.hitTestable(), findsOneWidget);
        expect(find.text('第 1 集 · 起点').hitTestable(), findsOneWidget);
        expect(find.byTooltip('下载本集').first.hitTestable(), findsOneWidget);
        expect(find.text('评分 8.4').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      bangumi.complete(const BangumiLookupResult.unavailable());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下载本集').first);
      await tester.pumpAndSettle();
      expect(find.text('正在解析下载地址...'), findsOneWidget);
      final descriptionText = find.text(description);
      expect(tester.widget<Text>(descriptionText).maxLines, 3);
      final expand = find.text('展开简介');
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(descriptionText).maxLines, isNull);
      final collapse = find.text('收起简介');
      await tester.ensureVisible(collapse);
      await tester.tap(collapse);
      await tester.pumpAndSettle();
      final match = find.text('手动匹配');
      await tester.ensureVisible(match);
      expect(match.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'detail offers original-source resume only for matching history',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = DatabaseService()..resetForTest();
      await db.init();
      addTearDown(db.resetForTest);
      final original = VideoModel(
        id: '42',
        title: '同名作品',
        source: 'LziApi',
        episodes: [
          EpisodeModel(
            id: 'ep1',
            title: '第 1 集',
            url: 'original-ep1',
            playUrl: 'https://original.example/1.mp4',
          ),
          EpisodeModel(
            id: 'ep2',
            title: '第 2 集',
            url: 'original-ep2',
            playUrl: 'https://original.example/2.mp4',
          ),
        ],
      );
      final other = original.copyWith(id: '360zy:42', source: '360zy');
      await db.saveHistory(
        HistoryItem(
          videoId: db.historyIdForVideo(original),
          title: original.title,
          sourceId: original.source,
          episodes: original.episodes!,
          episodeIndex: 1,
          position: const Duration(seconds: 83),
          watchedAt: DateTime(2026, 11, 19),
        ),
      );
      Map<String, dynamic>? launch;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', redirect: (_, __) => '/detail/360zy%3A42'),
          GoRoute(
            path: '/detail/:id',
            builder:
                (_, state) => DetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              launch = state.extra! as Map<String, dynamic>;
              return const Scaffold(body: Text('播放窗口'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            for (final video in [original, other]) ...[
              videoDetailProvider(video.id).overrideWith((ref) async => video),
              bangumiInfoProvider(
                BangumiQuery(videoId: video.id, title: video.title),
              ).overrideWith(
                (ref) async => const BangumiLookupResult.unavailable(),
              ),
            ],
            originalSourceDetailProvider.overrideWithValue((id, source) async {
              expect(id, db.historyIdForVideo(original));
              expect(source, 'lziapi');
              return original.copyWith(
                episodes: original.episodes!.reversed.toList(),
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('继续观看'), findsNothing);
      expect(find.text('立即播放'), findsOneWidget);

      router.go('/detail/42');
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续观看'));
      await tester.pumpAndSettle();
      expect(launch, containsPair('currentIndex', 0));
      expect(launch, containsPair('startAt', 83));
      expect(
        launch,
        containsPair('videoUrl', 'https://original.example/2.mp4'),
      );
      expect(launch, containsPair('sourceId', 'LziApi'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail keeps favorite and information for an empty source', (
    tester,
  ) async {
    final video = VideoModel(id: 'empty', title: '作品', description: '作品简介');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoDetailProvider(video.id).overrideWith((ref) async => video),
          bangumiInfoProvider(
            BangumiQuery(videoId: video.id, title: video.title),
          ).overrideWith(
            (ref) async => const BangumiLookupResult.unavailable(),
          ),
        ],
        child: const MaterialApp(home: DetailScreen(id: 'empty')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前片源暂无剧集').hitTestable(), findsOneWidget);
    expect(find.text('收藏').hitTestable(), findsOneWidget);
    expect(find.text('作品简介'), findsOneWidget);
    expect(find.text('手动匹配'), findsOneWidget);
  });

  testWidgets('detail retries a failed request shared with search preview', (
    tester,
  ) async {
    final scraper = _RetryDetailScraper();
    final container = ProviderContainer(
      overrides: [
        currentScraperProvider.overrideWithValue(scraper),
        bangumiInfoProvider(
          const BangumiQuery(videoId: 'retry', title: '重试后的作品'),
        ).overrideWith((ref) async => const BangumiLookupResult.noMatch()),
      ],
    );
    addTearDown(container.dispose);
    final preview = container.listen(
      sourceVideoDetailProvider((scraper: scraper, id: 'retry')),
      (_, _) {},
    );
    addTearDown(preview.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DetailScreen(id: 'retry')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('加载失败'), findsOneWidget);
    expect(scraper.requests, 1);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(scraper.requests, 2);
    expect(find.text('重试后的作品'), findsOneWidget);
    expect(preview.read().valueOrNull?.title, '重试后的作品');
  });

  for (final width in [420.0, 960.0, 1440.0]) {
    testWidgets('detail retains episodes and metadata at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final video = VideoModel(
        id: 'detail',
        title: '详情测试',
        description: '简介',
        episodes: [EpisodeModel(id: 'ep', title: '第一集 起点', url: 'episode')],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoDetailProvider('detail').overrideWith((ref) async => video),
            bangumiInfoProvider(
              BangumiQuery(videoId: video.id, title: video.title),
            ).overrideWith(
              (ref) async => const BangumiLookupResult.success(
                BangumiInfo(
                  score: 8.2,
                  staff: [BangumiStaffEntry(role: '导演', name: '制作测试')],
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: DetailScreen(id: 'detail')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第一集 起点'), findsOneWidget);
      if (width < 1200) {
        await tester.ensureVisible(find.byType(ExpansionTile));
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
      }
      expect(find.text('制作测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
