import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_play/core/network/http_client.dart';
import 'package:nova_play/features/favorites/favorites_screen.dart';
import 'package:nova_play/features/history/history_screen.dart';
import 'package:nova_play/features/home/home_screen.dart';
import 'package:nova_play/features/search/search_screen.dart';
import 'package:nova_play/features/settings/source_management_screen.dart';
import 'package:nova_play/models/history_item.dart';
import 'package:nova_play/models/video_model.dart';
import 'package:nova_play/providers/scraper_provider.dart';
import 'package:nova_play/services/database_service.dart';
import 'package:nova_play/shared/widgets/poster_card.dart';

class _SourceResponses implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? lziResponse;

  static ResponseBody listing(List<Map<String, Object>> videos) =>
      ResponseBody.fromString(
        jsonEncode({'code': 1, 'list': videos}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.uri.host == 'cj.lziapi.com') {
      final response = lziResponse;
      if (response != null) return response(options);
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return listing([
      {'vod_id': 28, 'vod_name': '来自 360zy', 'vod_play_url': ''},
    ]);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _SourceResponses responses;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    final dio = HttpClient().dio;
    final originalAdapter = dio.httpClientAdapter;
    responses = _SourceResponses();
    dio.httpClientAdapter = responses;
    addTearDown(() => dio.httpClientAdapter = originalAdapter);
  });

  test('手动模式下，查询失败只访问所选片源', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final source = container.read(currentScraperProvider);

    await expectLater(source.search('动画'), throwsException);
    expect(responses.requests.map((request) => request.uri.host), [
      'cj.lziapi.com',
    ]);
  });

  testWidgets('搜索失败后换源，用已提交的关键词重新查第一页', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SearchScreen())),
    );
    await tester.enterText(find.byType(TextField), '芙莉莲');
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pumpAndSettle();

    expect(find.text('搜索失败'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '尚未提交的另一个关键词');
    await tester.tap(find.text('切换片源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('360zy'));
    await tester.pumpAndSettle();

    expect(DatabaseService().getActiveSourceId(), '360zy');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    );
    expect(container.read(activeSourceConfigProvider).id, '360zy');
    expect(find.text('来自 360zy'), findsOneWidget);
    expect(responses.requests.last.queryParameters, containsPair('wd', '芙莉莲'));
    expect(responses.requests.last.queryParameters, containsPair('pg', 1));
  });

  testWidgets('切源后丢弃上一个片源的迟到结果', (tester) async {
    final oldResponse = Completer<ResponseBody>();
    responses.lziResponse = (_) => oldResponse.future;
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SearchScreen())),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '动画');
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    for (var frame = 0; frame < 5 && responses.requests.isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(responses.requests.single.uri.host, 'cj.lziapi.com');
    await tester.tap(find.text('片源：LziApi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('360zy'));
    await tester.pumpAndSettle();
    expect(find.text('来自 360zy'), findsOneWidget);

    oldResponse.complete(
      _SourceResponses.listing([
        {'vod_id': 28, 'vod_name': '旧片源迟到结果'},
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧片源迟到结果'), findsNothing);
    expect(find.text('来自 360zy'), findsOneWidget);
  });

  testWidgets('自动回退显示实际片源，空结果仍只访问已选片源', (tester) async {
    await DatabaseService().setSourceAutoFallback(true);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SearchScreen())),
    );
    await tester.enterText(find.byType(TextField), '回退');
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('片源：LziApi'), findsOneWidget);
    expect(find.text('360zy'), findsOneWidget);
    expect(find.text('来自 360zy'), findsOneWidget);

    responses.requests.clear();
    responses.lziResponse = (_) async => _SourceResponses.listing([]);
    await tester.enterText(find.byType(TextField), '无结果');
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('未找到相关动漫'), findsOneWidget);
    expect(responses.requests.single.uri.host, 'cj.lziapi.com');
  });

  testWidgets('开启回退时，源管理测试仍只验证被测试的片源', (tester) async {
    await DatabaseService().setSourceAutoFallback(true);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SourceManagementScreen())),
    );
    await tester.tap(find.byIcon(Icons.speed).first);
    await tester.pumpAndSettle();
    expect(responses.requests.single.uri.host, 'cj.lziapi.com');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('LziApi：失败'), findsOneWidget);
  });

  final saved = HistoryItem(
    videoId: '28',
    title: '在原片源看过的作品',
    sourceId: 'LziApi',
    episodeIndex: 1,
    position: const Duration(minutes: 3),
    watchedAt: DateTime(2026, 11, 19),
    episodes: [
      EpisodeModel(id: 'ep_1', title: '第01集', url: 'https://old.test/one'),
      EpisodeModel(id: 'ep_2', title: '第02集', url: 'https://old.test/two'),
    ],
  );

  Future<void> pumpLibrary(
    WidgetTester tester,
    Widget page,
    void Function(Map<String, dynamic>) player,
  ) async {
    final db = DatabaseService();
    await db.setActiveSourceId('360zy');
    await db.saveHistory(saved);
    await db.addFavorite(
      VideoModel(id: '28', title: saved.title, source: 'LziApi'),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => page),
        GoRoute(
          path: '/search',
          builder:
              (_, state) =>
                  SearchScreen(initialKeyword: state.uri.queryParameters['q']),
        ),
        GoRoute(
          path: '/detail/:id',
          builder: (_, state) => Scaffold(body: Text(state.uri.toString())),
        ),
        GoRoute(
          path: '/player',
          builder: (_, state) {
            player(state.extra! as Map<String, dynamic>);
            return const Scaffold(body: Text('正在播放'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  for (final (label, page) in [
    ('发现页', const HomeScreen()),
    ('历史页', const HistoryScreen()),
    ('收藏页', const FavoritesScreen()),
  ]) {
    testWidgets('$label 从原片源的第 2 集和 180 秒继续播放', (tester) async {
      responses.lziResponse =
          (_) async => _SourceResponses.listing([
            {
              'vod_id': 28,
              'vod_name': saved.title,
              'vod_play_url':
                  '第01集\$https://lzi.test/one.m3u8#第02集\$https://lzi.test/two.m3u8',
            },
          ]);
      Map<String, dynamic>? playback;
      await pumpLibrary(tester, page, (args) => playback = args);
      responses.requests.clear();
      final resume =
          page is FavoritesScreen
              ? find.byTooltip('继续观看')
              : find.text(saved.title);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(find.text('正在播放'), findsOneWidget);
      expect(playback, containsPair('startAt', 180));
      expect(playback, containsPair('currentIndex', 1));
      expect(playback, containsPair('videoUrl', 'https://lzi.test/two.m3u8'));
      expect(responses.requests.single.uri.host, 'cj.lziapi.com');
      expect(
        responses.requests.single.queryParameters,
        containsPair('ids', '28'),
      );
      expect(DatabaseService().getActiveSourceId(), '360zy');
    });
  }

  testWidgets('原源失败后按原片名换源，结果只能先打开详情选集', (tester) async {
    await pumpLibrary(
      tester,
      const HistoryScreen(),
      (_) => fail('fell into playback'),
    );
    await tester.tap(find.text(saved.title));
    await tester.pumpAndSettle();
    expect(find.text('无法从原片源续播'), findsOneWidget);
    await tester.tap(find.text('切换片源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('360zy'));
    await tester.pumpAndSettle();
    expect(find.text(saved.title), findsOneWidget);
    expect(
      responses.requests.last.queryParameters,
      containsPair('wd', saved.title),
    );
    expect(responses.requests.last.uri.host, '360zy.com');

    final card = tester.widget<PosterCard>(find.byType(PosterCard));
    expect(card.onPlay, isNull);
    await tester.tap(find.text('来自 360zy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/detail/'), findsOneWidget);
    expect(find.textContaining('play=1'), findsNothing);
    expect(DatabaseService().getHistory().single.toJson(), saved.toJson());
  });
}
