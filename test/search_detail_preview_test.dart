import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nova_play/features/search/search_screen.dart';
import 'package:nova_play/features/search/widgets/search_result_preview.dart';
import 'package:nova_play/models/video_model.dart';
import 'package:nova_play/providers/scraper_provider.dart';
import 'package:nova_play/providers/search_provider.dart';
import 'package:nova_play/services/database_service.dart';
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
  testWidgets('只读取选中季的详情，迟到结果不会覆盖另一个季度', (tester) async {
    final fixture = _SearchFixture();
    final scope = await _pumpSearch(tester, fixture, const Size(1280, 800));
    expect(find.text('选择作品以预览'), findsOneWidget);
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

    fixture.delayed.complete(_seasonOne.copyWith(description: '迟到的第一季资料'));
    await tester.pumpAndSettle();
    expect(find.text('迟到的第一季资料'), findsNothing);
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    expect(fixture.details, [_seasonOne.id, _seasonTwo.id]);
    final searchCount = fixture.pages.length;

    await scope.read(searchProvider.notifier).loadMore();
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
    expect(find.text('选择作品以预览'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '全部'));
    await tester.pumpAndSettle();
    expect(find.text('选择作品以预览'), findsOneWidget);
    await tester.tap(find.text(_seasonTwo.title));
    await tester.pumpAndSettle();
    expect(find.text('第二季的完整作品资料'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('选择作品以预览'), findsOneWidget);
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
      expect(find.text('选择作品以预览'), findsOneWidget);
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
