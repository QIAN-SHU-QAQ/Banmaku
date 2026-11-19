import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nova_play/core/config/theme.dart';
import 'package:nova_play/features/home/home_screen.dart';
import 'package:nova_play/features/home/widgets/category_tabs.dart';
import 'package:nova_play/models/video_model.dart';
import 'package:nova_play/models/history_item.dart';
import 'package:nova_play/providers/history_provider.dart';
import 'package:nova_play/providers/scraper_provider.dart';
import 'package:nova_play/shared/widgets/poster_card.dart';

import 'fakes.dart';

class LibraryScraper extends FakeScraper {
  final homePages = <int>[];
  bool failHome = false;
  bool failCategories = false;
  bool empty = false;
  Completer<VideoModel>? detailCompleter;

  List<VideoModel> get videos => List.generate(
    24,
    (i) =>
        VideoModel(id: 'video-$i', title: '作品 $i', year: '2026', genre: '动画'),
  );

  @override
  Future<List<String>> getCategories() async {
    if (failCategories) throw StateError('测试分类加载失败');
    return ['全部', '动画'];
  }

  @override
  Future<List<VideoModel>> getHome({int page = 1}) async {
    homePages.add(page);
    if (failHome) throw StateError('测试数据加载失败');
    return page == 1 && !empty ? videos : [];
  }

  @override
  Future<List<VideoModel>> getByCategory(
    String category, {
    int page = 1,
  }) async => videos;

  /// R4：续播会先刷新详情，这里返回与历史快照对应的新剧集地址。
  @override
  @override
  Future<VideoModel> getDetail(String url) async {
    final completer = detailCompleter;
    if (completer != null) return completer.future;
    return VideoModel(
      id: url,
      title: '昨日观看',
      episodes: [
        EpisodeModel(
          id: 'ep',
          title: '第 1 集',
          url: 'https://fake.local/ep',
          playUrl: 'https://fake.local/ep-new',
        ),
      ],
    );
  }
}

class SeededHistory extends HistoryNotifier {
  SeededHistory(List<HistoryItem> items) {
    state = items;
  }
}

HistoryItem _savedHistory() => HistoryItem(
  videoId: 'saved',
  title: '昨日观看',
  episodeIndex: 0,
  position: const Duration(seconds: 125),
  duration: const Duration(minutes: 24),
  watchedAt: DateTime(2026),
  episodes: [
    EpisodeModel(id: 'ep', title: '第 1 集', url: 'https://fake.local/ep'),
  ],
);

VideoModel _refreshedDetail() => VideoModel(
  id: 'saved',
  title: '昨日观看',
  episodes: [
    EpisodeModel(
      id: 'ep',
      title: '第 1 集',
      url: 'https://fake.local/ep',
      playUrl: 'https://fake.local/ep-new',
    ),
  ],
);

Future<GoRouter> pumpHome(
  WidgetTester tester,
  LibraryScraper scraper,
  Size size, {
  List<HistoryItem> history = const [],
  ThemeData? theme,
  OriginalSourceDetail? originalDetail,
  ValueChanged<Map<String, dynamic>>? onPlayback,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/search',
        builder: (_, __) => const Scaffold(body: Text('搜索页面')),
      ),
      GoRoute(
        path: '/detail/:id',
        builder:
            (_, state) =>
                Scaffold(body: Text('详情 ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/player',
        builder: (_, state) {
          final extra = state.extra! as Map<String, dynamic>;
          onPlayback?.call(extra);
          return Scaffold(
            body: Text('续播 ${extra['videoId']} ${extra['startAt']}'),
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentScraperProvider.overrideWithValue(scraper),
        historyProvider.overrideWith((ref) => SeededHistory(history)),
        if (originalDetail != null)
          originalSourceDetailProvider.overrideWithValue(originalDetail),
      ],
      child: MaterialApp.router(routerConfig: router, theme: theme),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

HistoryItem _sameEpisodeHistory(String videoId, String source, int seconds) =>
    HistoryItem(
      videoId: videoId,
      title: '同名作品',
      sourceId: source,
      episodeIndex: 0,
      position: Duration(seconds: seconds),
      duration: const Duration(minutes: 24),
      watchedAt: DateTime(2026),
      episodes: [
        EpisodeModel(id: 'ep', title: '第 1 集', url: 'https://fake.local/ep'),
      ],
    );

Future<void> _tabTo(WidgetTester tester, Finder label) async {
  for (var step = 0; step < 8; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    if (Focus.of(tester.element(label)).hasPrimaryFocus) return;
  }
  fail('Tab did not focus the card containing $label');
}

void main() {
  testWidgets('已确认的续播片源显示配置中的当前名称', (tester) async {
    final saved = _sameEpisodeHistory('360zy:28', '旧片源名', 242);
    await pumpHome(
      tester,
      LibraryScraper(),
      const Size(1120, 720),
      history: [saved],
    );
    expect(find.text('360zy'), findsOneWidget);
    expect(find.text('旧片源名'), findsNothing);
  });

  testWidgets('Refreshing an available source also retries its category list', (
    tester,
  ) async {
    final scraper = LibraryScraper()..failCategories = true;
    await pumpHome(tester, scraper, const Size(1120, 720));
    expect(find.byType(CategoryTabs), findsNothing);

    scraper.failCategories = false;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CategoryTabs, '动画'), findsOneWidget);
  });

  testWidgets('Empty feed offers retry', (tester) async {
    final scraper = LibraryScraper()..empty = true;
    await pumpHome(tester, scraper, const Size(1120, 720));
    expect(find.text('暂无内容'), findsOneWidget);
    scraper.empty = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('作品 0'), findsOneWidget);
  });

  testWidgets('Compact continuation preserves the saved episode position', (
    tester,
  ) async {
    await pumpHome(
      tester,
      LibraryScraper(),
      const Size(1120, 720),
      history: [
        HistoryItem(
          videoId: 'saved',
          title: '昨日观看',
          episodeIndex: 0,
          position: const Duration(seconds: 125),
          duration: const Duration(minutes: 24),
          watchedAt: DateTime(2026),
          episodes: [
            EpisodeModel(
              id: 'ep',
              title: '第 1 集',
              url: 'https://fake.local/ep',
            ),
          ],
        ),
      ],
    );
    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('第 1 集'), findsOneWidget);
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('昨日观看'), matching: find.byType(InkWell))
                .first,
          )
          .height,
      lessThanOrEqualTo(100),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('昨日观看'));
    await tester.pumpAndSettle();
    expect(find.text('续播 saved 125'), findsOneWidget);
  });

  testWidgets('R4：切换分支后迟到的成功续播不抢走导航', (tester) async {
    final scraper = LibraryScraper();
    final router = await pumpHome(
      tester,
      scraper,
      const Size(1120, 720),
      history: [_savedHistory()],
    );
    final completer = Completer<VideoModel>();
    scraper.detailCompleter = completer;

    await tester.tap(find.text('昨日观看'));
    await tester.pump();
    router.push('/search');
    await tester.pumpAndSettle();
    expect(find.text('搜索页面'), findsOneWidget);

    completer.complete(_refreshedDetail());
    await tester.pumpAndSettle();

    expect(find.text('搜索页面'), findsOneWidget);
    expect(find.textContaining('续播'), findsNothing);
  });

  testWidgets('R4：切换分支后迟到的失败续播不跳到详情页', (tester) async {
    final scraper = LibraryScraper();
    final router = await pumpHome(
      tester,
      scraper,
      const Size(1120, 720),
      history: [_savedHistory()],
    );
    final completer = Completer<VideoModel>();
    scraper.detailCompleter = completer;

    await tester.tap(find.text('昨日观看'));
    await tester.pump();
    router.push('/search');
    await tester.pumpAndSettle();
    expect(find.text('搜索页面'), findsOneWidget);

    completer.completeError(Exception('network down'));
    await tester.pumpAndSettle();

    expect(find.text('搜索页面'), findsOneWidget);
    expect(find.textContaining('详情 saved'), findsNothing);
  });

  for (final size in [
    const Size(616, 600),
    const Size(800, 600),
    const Size(1120, 720),
    const Size(1280, 800),
  ]) {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      testWidgets(
        'Continuation distinguishes sources at $size in ${theme.brightness}',
        (tester) async {
          final history = [
            _sameEpisodeHistory('28', 'LziApi', 125),
            _sameEpisodeHistory('360zy:28', '360zy', 242),
          ];
          final playback = <Map<String, dynamic>>[];
          final requests = <(String, String?)>[];
          final router = await pumpHome(
            tester,
            LibraryScraper(),
            size,
            history: history,
            theme: theme,
            originalDetail: (id, sourceConfigId) async {
              requests.add((id, sourceConfigId));
              final item = history.singleWhere((item) => item.videoId == id);
              return VideoModel(
                id: id,
                title: item.title,
                source: item.sourceId,
                episodes: [
                  EpisodeModel(
                    id: 'ep',
                    title: '第 1 集',
                    url: 'https://$sourceConfigId.test/refreshed.m3u8',
                  ),
                ],
              );
            },
            onPlayback: playback.add,
          );
          for (final (index, timestamp, configId) in [
            (0, '已看 2:05', 'lziapi'),
            (1, '已看 4:02', '360zy'),
          ]) {
            final item = history[index];
            final label = find.text(item.sourceId!);
            expect(label, findsOneWidget);
            final card = find.ancestor(
              of: label,
              matching: find.byType(InkWell),
            );
            final viewport = tester.getRect(
              find.ancestor(of: card, matching: find.byType(ListView)),
            );
            expect(
              find.descendant(of: card, matching: find.text(item.title)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: card, matching: find.text('第 1 集')),
              findsOneWidget,
            );
            expect(
              find.descendant(of: card, matching: find.text(timestamp)),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: card,
                matching: find.byIcon(Icons.movie_outlined),
              ),
              findsOneWidget,
            );
            final progress = tester.widget<LinearProgressIndicator>(
              find.descendant(
                of: card,
                matching: find.byType(LinearProgressIndicator),
              ),
            );
            expect(progress.value, item.progress);

            if (index == 0) {
              expect(
                viewport.intersect(tester.getRect(card)),
                tester.getRect(card),
              );
            }
            await _tabTo(tester, label);
            expect(
              viewport.intersect(tester.getRect(card)),
              tester.getRect(card),
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(requests.last, (item.videoId, configId));
            expect(
              playback.last,
              containsPair('videoUrl', 'https://$configId.test/refreshed.m3u8'),
            );
            expect(playback.last, containsPair('sourceId', item.sourceId));
            expect(
              playback.last,
              containsPair('startAt', item.position.inSeconds),
            );
            expect(playback.last, containsPair('currentIndex', 0));
            router.pop();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('One discovery grid fits $size and opens a title', (
      tester,
    ) async {
      await pumpHome(tester, LibraryScraper(), size);
      expect(find.text('发现'), findsOneWidget);
      expect(find.text('继续观看'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(CategoryTabs)).dy -
            tester.getBottomLeft(find.byTooltip('刷新')).dy,
        inInclusiveRange(0, 32),
      );
      expect(
        tester.getTopLeft(find.byType(PosterCard).first).dy -
            tester.getBottomLeft(find.byType(CategoryTabs)).dy,
        inInclusiveRange(0, 24),
      );
      expect(find.text('热门推荐'), findsNothing);
      expect(find.byType(PosterCard), findsWidgets);
      expect(find.text('作品 0'), findsOneWidget);
      expect(find.text('2026 · 动画'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('作品 0'));
      await tester.pumpAndSettle();
      expect(find.text('详情 video-0'), findsOneWidget);
    });
  }

  testWidgets('Category scroll never paginates the hidden home feed', (
    tester,
  ) async {
    final scraper = LibraryScraper();
    await pumpHome(tester, scraper, const Size(1120, 720));
    await tester.tap(find.text('动画'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(scraper.homePages, [1]);
  });

  testWidgets('Refresh action recovers an error and search opens', (
    tester,
  ) async {
    final scraper = LibraryScraper()..failHome = true;
    await pumpHome(tester, scraper, const Size(1120, 720));
    expect(find.text('加载失败'), findsOneWidget);
    scraper.failHome = false;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('作品 0'), findsOneWidget);
    await tester.tap(find.text('搜索作品'));
    await tester.pumpAndSettle();
    expect(find.text('搜索页面'), findsOneWidget);
  });

  testWidgets('Category tabs support keyboard activation', (tester) async {
    String? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryTabs(
            categories: const ['全部', '动画'],
            selectedCategory: '全部',
            onCategorySelected: (value) => selection = value,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selection, '全部');
  });
}
