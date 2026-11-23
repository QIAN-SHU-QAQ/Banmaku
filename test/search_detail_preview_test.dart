import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nova_play/app.dart';
import 'package:nova_play/core/network/http_client.dart';
import 'package:nova_play/features/search/search_screen.dart';
import 'package:nova_play/features/search/widgets/search_result_preview.dart';
import 'package:nova_play/models/video_model.dart';
import 'package:nova_play/providers/bangumi_provider.dart';
import 'package:nova_play/providers/home_provider.dart';
import 'package:nova_play/providers/scraper_provider.dart';
import 'package:nova_play/providers/search_provider.dart';
import 'package:nova_play/services/database_service.dart';
import 'package:nova_play/services/bangumi_api.dart';
import 'package:nova_play/shared/widgets/poster_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

final _seasonOne = VideoModel(
  id: '11',
  title: '星际番剧 第一季',
  year: '2023',
  genre: '冒险',
  source: 'LziApi',
);
final _seasonTwo = VideoModel(
  id: 'alt:11',
  title: '星际番剧 第二季',
  year: '2026',
  genre: '科幻',
  source: '同名备用源',
);

class _CatalogFixture extends BangumiApi {
  final queries = <String>[];

  @override
  Future<List<VideoModel>> searchCatalog(String keyword, {int page = 1}) async {
    queries.add(keyword);
    return [
      VideoModel(
        id: 'bangumi:123',
        title: '资料库作品 第二季',
        description: '来自资料库的简介',
      ),
    ];
  }
}

class _EmptyPlaybackSource extends FakeScraper {
  final queries = <String>[];

  @override
  Future<List<VideoModel>> search(String keyword, {int page = 1}) async {
    queries.add(keyword);
    return [];
  }
}

class _PlaybackProbeAdapter implements HttpClientAdapter {
  final paths = <String>[];
  bool secondSourceRecovered = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    paths.add(path);
    if (path == '/slow.m3u8' && !secondSourceRecovered) {
      await cancelFuture;
      return ResponseBody.fromString('', 499);
    }
    return switch (path) {
      '/master.m3u8' => ResponseBody.fromString(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=10000\nvideo/index.m3u8\n',
        200,
      ),
      '/video/index.m3u8' ||
      '/second.m3u8' ||
      '/slow.m3u8' => ResponseBody.fromString(
        '#EXTM3U\n#EXTINF:5,\nsegment.ts\n#EXT-X-ENDLIST\n',
        200,
      ),
      '/video/segment.ts' => _mediaResponse(options),
      '/segment.ts' when secondSourceRecovered => _mediaResponse(options),
      '/segment.ts' => ResponseBody.fromString('access denied', 200),
      _ => ResponseBody.fromString('<html>错误页面</html>', 200),
    };
  }

  ResponseBody _mediaResponse(RequestOptions options) {
    expect(options.headers['range'], 'bytes=0-1023');
    return ResponseBody.fromBytes(
      [0x47, 0x00, 0x00, 0x10],
      206,
      headers: {
        Headers.contentTypeHeader: ['video/mp2t'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SearchFixture extends FakeScraper {
  final delayed = Completer<VideoModel>();
  final details = <String>[];
  final pages = <int>[];
  bool failSecond = false;

  @override
  Future<List<VideoModel>> search(String keyword, {int page = 1}) async {
    pages.add(page);
    return page == 1 ? [_seasonOne, _seasonTwo] : [];
  }

  @override
  Future<VideoModel> getDetail(String url) async {
    details.add(url);
    if (url == _seasonOne.id) return delayed.future;
    if (failSecond) throw StateError('源暂时不可用');
    return _seasonTwo.copyWith(description: '第二季的完整作品资料');
  }
}

Future<ProviderContainer> _pumpSearch(
  WidgetTester tester,
  _SearchFixture fixture,
  Size size, {
  double textScale = 1,
  String? initialKeyword,
  _SearchFixture? secondSource,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => SearchScreen(initialKeyword: initialKeyword),
      ),
      GoRoute(
        path: '/detail/:id',
        builder:
            (context, state) => Scaffold(
              body: Column(
                children: [
                  Text('作品路由 ${state.uri}'),
                  TextButton(onPressed: context.pop, child: const Text('返回测试')),
                ],
              ),
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  final box = ProviderContainer(
    overrides: [
      currentScraperProvider.overrideWith(
        (ref) =>
            ref.watch(activeSourceConfigProvider).id == '360zy'
                ? secondSource ?? fixture
                : fixture,
      ),
    ],
  );
  addTearDown(box.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: box,
      child: MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: textScale,
              maxScaleFactor: textScale,
              child: child!,
            ),
      ),
    ),
  );
  if (initialKeyword == null) {
    await tester.enterText(find.byType(TextField), '星际番剧');
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
  }
  await tester.pumpAndSettle();
  return box;
}

void main() {
  testWidgets('片源弹窗按实际媒体响应显示首集可用性并支持重测', (tester) async {
    final dio = HttpClient().dio;
    final previous = dio.httpClientAdapter;
    final adapter = _PlaybackProbeAdapter();
    dio.httpClientAdapter = adapter;
    addTearDown(() => dio.httpClientAdapter = previous);
    VideoModel version(String source, String id, String path) {
      final url = 'https://probe.example.test/$path';
      return VideoModel(
        id: id,
        title: '雾山五行',
        source: source,
        episodes: [
          EpisodeModel(id: 'ep_1', title: '第1集', url: url, playUrl: url),
        ],
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackSearchPageLoaderProvider.overrideWithValue(
            (_, {page = 1}) async => SearchPage([
              version('LziApi', '1', 'master.m3u8'),
              version('360zy', '360zy:1', 'second.m3u8'),
              version('慢速片源', 'slow:1', 'slow.m3u8'),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: SearchScreen(initialKeyword: '雾山五行', allSources: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();
    expect(adapter.paths, isEmpty);
    await tester.tap(find.text('测试全部'));
    await tester.pumpAndSettle();

    final first = find.widgetWithText(ListTile, 'LziApi');
    final second = find.widgetWithText(ListTile, '360zy');
    final slow = find.widgetWithText(ListTile, '慢速片源');
    expect(
      find.descendant(of: first, matching: find.text('首集可用')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text('首集不可用')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slow, matching: find.text('检测中…')),
      findsOneWidget,
    );
    expect(
      adapter.paths,
      unorderedEquals([
        '/master.m3u8',
        '/video/index.m3u8',
        '/video/segment.ts',
        '/second.m3u8',
        '/segment.ts',
        '/slow.m3u8',
      ]),
    );

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: slow, matching: find.text('检测超时')),
      findsOneWidget,
    );
    adapter.secondSourceRecovered = true;
    await tester.tap(find.text('重新测试'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: second, matching: find.text('首集可用')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slow, matching: find.text('首集可用')),
      findsOneWidget,
    );
  });

  testWidgets('聚合搜索只显示一张作品卡片，选择片源后进入该源的详情', (tester) async {
    final results = [
      VideoModel(id: '1', title: '雾山五行', year: '2020', source: 'LziApi'),
      VideoModel(id: '360zy:1', title: '雾山五行', year: '2020', source: '360zy'),
      VideoModel(
        id: '360zy:9',
        title: '雾山五行 粤语',
        year: '2020',
        source: '360zy',
      ),
      VideoModel(
        id: '360zy:2',
        title: '雾山五行之犀川幻紫林篇',
        year: '2023',
        source: '360zy',
      ),
      VideoModel(
        id: 'modu:4',
        title: '雾山五行·犀川幻紫林',
        year: '2023',
        source: '魔都资源',
      ),
      VideoModel(id: 'modu:5', title: '雾山五行', year: '2025', source: '魔都资源'),
      VideoModel(id: '7', title: '雾山五行 第二季', year: '2023', source: 'LziApi'),
    ];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (_, _) =>
                  const SearchScreen(initialKeyword: '雾山五行', allSources: true),
        ),
        GoRoute(
          path: '/detail/:id',
          builder:
              (_, state) => Scaffold(
                body: Text(
                  '详情 ${state.pathParameters['id']} ${state.uri.query}',
                ),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackSearchPageLoaderProvider.overrideWithValue(
            (_, {page = 1}) async => SearchPage(switch (page) {
              1 => results,
              2 => [
                VideoModel(
                  id: 'ff:13',
                  title: '雾山五行 · 犀川幻紫林篇',
                  year: '2023',
                  source: '非凡资源',
                ),
              ],
              _ => [],
            }),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('共 4 部作品'), findsOneWidget);
    expect(find.byType(PosterCard), findsNWidgets(4));
    expect(find.textContaining('360zy'), findsNothing);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PosterCard && widget.video.id == '1',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择片源'), findsOneWidget);
    expect(find.text('LziApi'), findsOneWidget);
    expect(find.text('360zy'), findsNWidgets(2));
    expect(find.text('雾山五行 粤语'), findsOneWidget);
    expect(find.text('魔都资源'), findsNothing);
    await tester.tap(find.text('360zy').first);
    await tester.pumpAndSettle();
    expect(find.text('详情 360zy:1 chooseEpisode=1'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多作品'));
    await tester.pumpAndSettle();
    expect(find.text('共 4 部作品'), findsOneWidget);
    expect(find.text('雾山五行之犀川幻紫林篇'), findsOneWidget);
    expect(find.text('雾山五行·犀川幻紫林'), findsNothing);
    await tester.tap(find.text('雾山五行之犀川幻紫林篇'));
    await tester.pumpAndSettle();
    expect(find.text('360zy'), findsOneWidget);
    expect(find.text('魔都资源'), findsOneWidget);
    expect(find.text('非凡资源'), findsOneWidget);
    await tester.tap(find.text('魔都资源'));
    await tester.pumpAndSettle();
    expect(find.text('详情 modu:4 chooseEpisode=1'), findsOneWidget);
  });

  testWidgets('默认搜索资料库，选中作品后才向片源查找版本', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final catalog = _CatalogFixture();
    final playback = _EmptyPlaybackSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bangumiApiProvider.overrideWithValue(catalog),
          currentScraperProvider.overrideWithValue(playback),
          playbackSearchPageLoaderProvider.overrideWithValue(
            (keyword, {page = 1}) async =>
                SearchPage(await playback.search(keyword, page: page)),
          ),
          discoveryPageLoaderProvider.overrideWithValue(emptyDiscoveryPage),
        ],
        child: const NovaPlayApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索作品'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '资料库作品');
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('资料库作品 第二季'), findsOneWidget);
    expect(catalog.queries, ['资料库作品']);
    expect(playback.queries, isEmpty);

    await tester.tap(find.text('资料库作品 第二季'));
    await tester.pumpAndSettle();
    final previewDescription = find.descendant(
      of: find.byType(SearchResultPreview),
      matching: find.text('来自资料库的简介'),
    );
    expect(previewDescription, findsOneWidget);
    await tester.tap(find.text('查找片源'));
    await tester.pumpAndSettle();
    expect(find.text('全部已启用片源'), findsOneWidget);
    expect(playback.queries, ['资料库作品第二季']);
    expect(find.text('未找到相关动漫'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(previewDescription, findsOneWidget);
  });

  testWidgets('只读取选中季的详情，迟到结果不会覆盖另一个季度', (tester) async {
    final fixture = _SearchFixture();
    final scope = await _pumpSearch(tester, fixture, const Size(1280, 800));
    expect(find.byType(SearchResultPreview), findsNothing);
    expect(tester.getSize(find.byType(GridView)).width, 1280);
    expect(fixture.details, isEmpty);

    await tester.tap(find.text(_seasonOne.title));
    await tester.pump();
    expect(fixture.details, [_seasonOne.id]);
    await tester.tap(find.text(_seasonTwo.title));
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    expect(find.text('片源：同名备用源'), findsOneWidget);
    final preview = tester.getRect(find.byType(SearchResultPreview));
    final divider = tester.getRect(find.byType(VerticalDivider));
    expect(preview.top, divider.top);
    expect(preview.bottom, divider.bottom);
    expect(
      preview.width,
      lessThan(tester.getSize(find.byType(GridView)).width),
    );

    fixture.delayed.complete(_seasonOne.copyWith(description: '迟到的第一季资料'));
    await tester.pumpAndSettle();
    expect(find.text('迟到的第一季资料'), findsNothing);
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    expect(fixture.details, [_seasonOne.id, _seasonTwo.id]);
    final searchCount = fixture.pages.length;

    final search = searchProvider((
      session: tester.state(find.byType(SearchScreen)),
      mode: SearchMode.source,
    ));
    await scope.read(search.notifier).loadMore();
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('作品路由 /detail/'), findsOneWidget);
    await tester.tap(find.text('返回测试'));
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    expect(fixture.pages.length, searchCount + 1);

    await tester.tap(find.widgetWithText(FilterChip, '冒险'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultPreview), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, '全部'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultPreview), findsNothing);
    await tester.tap(find.text(_seasonTwo.title));
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭预览'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultPreview), findsNothing);
    expect(find.text(_seasonTwo.title), findsOneWidget);
    expect(fixture.pages.length, searchCount + 1);

    await tester.tap(find.text(_seasonTwo.title));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预览错误只重试作品详情，160% 字体不溢出', (tester) async {
    final fixture = _SearchFixture()..failSecond = true;
    await _pumpSearch(tester, fixture, const Size(1120, 720), textScale: 1.6);
    await tester.tap(find.text(_seasonTwo.title));
    await tester.pumpAndSettle();
    expect(find.text('详情读取失败'), findsOneWidget);
    expect(find.text(_seasonOne.title), findsOneWidget);
    final searches = fixture.pages.length;

    fixture.failSecond = false;
    await tester.tap(find.text('重试详情'));
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    expect(fixture.details, [_seasonTwo.id, _seasonTwo.id]);
    expect(fixture.pages.length, searches);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏列表保留独立的快捷播放操作', (tester) async {
    final fixture = _SearchFixture();
    await _pumpSearch(tester, fixture, const Size(1280, 800));
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('播放 ${_seasonTwo.title}'));
    await tester.pumpAndSettle();
    expect(find.textContaining('play=1'), findsOneWidget);
    expect(fixture.details, isEmpty);
  });

  testWidgets('重复切换片库时清除预览并重新查询已提交的关键词', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService()..resetForTest();
    await database.init();
    addTearDown(database.resetForTest);
    final primary = _SearchFixture();
    final secondary = _SearchFixture();
    await _pumpSearch(
      tester,
      primary,
      const Size(1280, 800),
      secondSource: secondary,
    );
    await tester.tap(find.text(_seasonTwo.title));
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);

    Future<void> switchTo(String active, String source) async {
      await tester.tap(find.text('片源：$active'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source));
      await tester.pumpAndSettle();
      expect(find.byType(SearchResultPreview), findsNothing);
      expect(find.text('第二季的完整作品资料'), findsNothing);
    }

    await switchTo('LziApi', '360zy');
    expect(secondary.pages, [1]);
    expect(secondary.details, isEmpty);
    await switchTo('360zy', 'LziApi');
    expect(primary.pages, [1, 1]);
    expect(database.getActiveSourceId(), 'lziapi');
  });

  for (final size in [const Size(616, 600), const Size(800, 600)]) {
    testWidgets('换源恢复在 ${size.width} 保留选集路由', (tester) async {
      final fixture = _SearchFixture();
      await _pumpSearch(tester, fixture, size, initialKeyword: '星际番剧');
      await tester.tap(find.text(_seasonTwo.title));
      await tester.pumpAndSettle();
      expect(find.textContaining('chooseEpisode=1'), findsOneWidget);
      expect(find.textContaining('play=1'), findsNothing);
      expect(fixture.details, isEmpty);
    });
  }
}
