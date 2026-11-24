import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:banmaku/core/utils/play_launcher.dart';
import 'package:banmaku/features/download/download_screen.dart';
import 'package:banmaku/features/player/player_screen.dart';
import 'package:banmaku/features/player/player_window.dart';
import 'package:banmaku/models/history_item.dart';
import 'package:banmaku/models/video_model.dart';
import 'package:banmaku/providers/scraper_provider.dart';
import 'package:banmaku/services/database_service.dart';
import 'package:banmaku/services/download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'playback_session_test.dart' show FakePlatform;

void main() {
  group('播放窗口来源', () {
    late FakePlatform platform;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      platform = FakePlatform();
    });

    Future<void> pumpPlayback(
      WidgetTester tester,
      Widget app, {
      List<Override> overrides = const [],
    }) async {
      tester.view.physicalSize = const Size(616, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerFactoryProvider.overrideWithValue(
              () => Player(platformPlayer: platform),
            ),
            playerSurfaceProvider.overrideWithValue(
              (_) => const ColoredBox(color: Colors.black),
            ),
            ...overrides,
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();
    }

    // Exercise the same argument decoding as the detached Windows process.
    MaterialApp routeToPlayerWindow(Widget home) {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => home),
          GoRoute(
            path: '/player',
            builder:
                (_, state) => PlayerWindowApp(
                  arguments:
                      jsonDecode(jsonEncode(state.extra))
                          as Map<String, dynamic>,
                ),
          ),
        ],
      );
      addTearDown(router.dispose);
      return MaterialApp.router(routerConfig: router);
    }

    testWidgets('搜索源 B 时显示历史续播确认的源 A，窗口和全屏都保留标题与来源', (tester) async {
      final db = DatabaseService()..resetForTest();
      await db.init();
      addTearDown(db.resetForTest);
      await db.setActiveSourceId('360zy');
      const sourceName = '片源 A · 这是重新命名后确认的完整片库名称与说明';
      const title = '这是一个需要在窄播放器窗口里完整处理截断的作品名称与相关动画长标题';
      final saved = HistoryItem(
        videoId: 'lziapi:28',
        title: title,
        sourceId: '片源 A 的旧名称',
        episodes: [
          EpisodeModel(id: 'old_2', title: '第 2 集', url: 'https://old.test/2'),
        ],
        episodeIndex: 0,
        position: const Duration(seconds: 180),
        watchedAt: DateTime(2026, 11, 19),
      );
      const url = 'https://source-a.test/2.m3u8';
      const fullscreenChannel = MethodChannel(
        'com.alexmercerind/media_kit_video',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final fullscreenCalls = <String>[];
      messenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
        fullscreenCalls.add(call.method);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      await pumpPlayback(
        tester,
        routeToPlayerWindow(
          Consumer(
            builder:
                (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () {
                      expect(ref.read(activeSourceConfigProvider).id, '360zy');
                      resumeFromOriginalSource(context, ref, saved);
                    },
                    child: const Text('续播历史'),
                  ),
                ),
          ),
        ),
        overrides: [
          originalSourceDetailProvider.overrideWithValue((
            id,
            sourceConfigId,
          ) async {
            expect(id, saved.videoId);
            expect(sourceConfigId, 'lziapi');
            return VideoModel(
              id: '28',
              title: title,
              source: sourceName,
              episodes: [EpisodeModel(id: 'fresh_2', title: '第 2 集', url: url)],
            );
          }),
        ],
      );
      await tester.tap(find.text('续播历史'));
      await tester.pumpAndSettle();

      final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
      expect(player.videoId, saved.videoId);
      expect(player.sourceId, saved.sourceId);
      expect(platform.opened, [url]);
      expect(platform.starts, [saved.position]);
      final heading = find.text('$title - 第 2 集');
      final source = find.byTooltip(sourceName);
      expect(heading, findsOneWidget);
      expect(source, findsOneWidget);
      expect(tester.getSize(heading).width, greaterThan(0));
      expect(tester.getCenter(source).dy, tester.getCenter(heading).dy);
      expect(find.text('360zy'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(heading, findsOneWidget);
      expect(source, findsOneWidget);
      expect(find.byTooltip('退出全屏 (Esc)'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fullscreenCalls, [
        'Utils.EnterNativeFullscreen',
        'Utils.ExitNativeFullscreen',
      ]);

      platform.emitPosition(const Duration(seconds: 181));
      platform.emitPosition(const Duration(seconds: 182));
      await tester.pump(const Duration(seconds: 5));
      final history = db.getHistory().single;
      expect(history.videoId, saved.videoId);
      expect(history.sourceId, saved.sourceId);
      expect(history.position, const Duration(seconds: 182));
      expect(platform.opened, [url]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('下载页播放已有文件时，播放窗口显示本地文件', (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'banmaku-player-test-',
      );
      final file = File('${directory.path}/episode.ts')..writeAsBytesSync([1]);
      addTearDown(() {
        file.deleteSync();
        directory.deleteSync();
      });
      final task = DownloadTask(
        id: 'downloaded-episode',
        title: '已下载作品',
        url: 'https://example.test/episode.m3u8',
        savePath: file.path,
        status: DownloadStatus.completed,
        createdAt: DateTime(2026, 11, 19),
      );
      SharedPreferences.setMockInitialValues({
        'downloads_v1': jsonEncode([task.toJson()]),
      });
      await pumpPlayback(tester, routeToPlayerWindow(const DownloadScreen()));
      await tester.tap(find.text(task.title));
      await tester.pumpAndSettle();

      final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
      expect(player.videoUrl, file.path);
      expect(find.text('本地文件'), findsOneWidget);
    });

    testWidgets('旧播放窗口参数缺少来源时省略标签', (tester) async {
      await pumpPlayback(
        tester,
        const PlayerWindowApp(
          arguments: {
            'videoUrl': 'https://example.test/episode.m3u8',
            'title': '来源未知的作品',
          },
        ),
      );

      final heading = find.text('来源未知的作品');
      expect(heading, findsOneWidget);
      final headingRow = find.ancestor(of: heading, matching: find.byType(Row));
      expect(
        find.descendant(of: headingRow.first, matching: find.byType(Tooltip)),
        findsNothing,
      );
    });
  });

  testWidgets('error retry, episode title and Esc fullscreen restore', (
    tester,
  ) async {
    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = FakePlatform()..fail = true;
    final calls = <String>[];
    const channel = MethodChannel('com.alexmercerind/media_kit_video');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/1.m3u8',
            title: 'Show - One',
            videoTitle: 'Show',
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final episodeLabel = find.text('选集 (2)');
    final panel = tester.widget<Container>(
      find.ancestor(of: episodeLabel, matching: find.byType(Container)).first,
    );
    expect(
      panel.color,
      Theme.of(tester.element(episodeLabel)).colorScheme.surfaceContainerLow,
      reason: '播放器控件应使用内部深色主题，即使应用外层是浅色主题',
    );
    expect(find.text('播放失败'), findsOneWidget);
    final danmakuButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.subtitles_rounded),
    );
    expect(danmakuButton.tooltip, '关闭弹幕');
    expect(danmakuButton.onPressed, isNotNull);
    platform.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('播放失败'), findsNothing);
    await tester.tap(find.byTooltip('倍速'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x'));
    await tester.pumpAndSettle();
    expect(find.text('1.5x'), findsOneWidget);
    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    final slider = find.byType(Slider);
    (tester.widget<Slider>(slider)).onChanged!(35);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 35);
    await tester.tapAt(const Offset(50, 50));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一集'));
    await tester.pumpAndSettle();
    expect(find.text('Show - Two'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(calls, ['Utils.EnterNativeFullscreen']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(calls, [
      'Utils.EnterNativeFullscreen',
      'Utils.ExitNativeFullscreen',
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(calls.last, 'Utils.ExitNativeFullscreen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('续播确认前历史保持原进度，确认后才向前写入', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);

    final seededAt = DateTime.now().subtract(const Duration(minutes: 1));
    await db.saveHistory(
      HistoryItem(
        videoId: 'v1',
        title: 'Show',
        episodes: [
          EpisodeModel(id: 'ep_1', title: 'One', url: 'u1'),
          EpisodeModel(id: 'ep_2', title: 'Two', url: 'u2'),
        ],
        episodeIndex: 1,
        position: const Duration(seconds: 180),
        duration: const Duration(minutes: 10),
        watchedAt: seededAt,
      ),
    );

    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final platform = FakePlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/2.m3u8',
            title: 'Show - Two',
            videoTitle: 'Show',
            videoId: 'v1',
            currentIndex: 1,
            startAt: 180,
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(db.getHistory().single.position, const Duration(seconds: 180));

    // 加载初期先出现的 0/5 秒位置不能覆盖历史。
    platform.emitPosition(Duration.zero);
    platform.emitPosition(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(
      db.getHistory().single.position,
      const Duration(seconds: 180),
      reason: '续播确认前必须暂停历史写入',
    );

    // 抵达目标后需要连续两次有效位置事件才确认，历史才允许向前更新。
    platform.emitPosition(const Duration(seconds: 181));
    platform.emitPosition(const Duration(seconds: 182));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    final recorded = db.getHistory().single.position;
    expect(recorded.inSeconds, greaterThanOrEqualTo(178));
    expect(recorded.inSeconds, lessThanOrEqualTo(185));

    // 等待挂起的异步历史写入完成后再销毁 ProviderScope。
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('续播目标不可达时不自动切集、不覆盖历史，并显示恢复入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);
    await db.saveHistory(
      HistoryItem(
        videoId: 'v1',
        title: 'Show',
        episodes: [
          EpisodeModel(id: 'ep_1', title: 'One', url: 'u1'),
          EpisodeModel(id: 'ep_2', title: 'Two', url: 'u2'),
          EpisodeModel(id: 'ep_3', title: 'Three', url: 'u3'),
        ],
        episodeIndex: 1,
        position: const Duration(seconds: 180),
        duration: const Duration(seconds: 120),
        watchedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 刷新后的媒体只有 120 秒，无法到达 180 秒续播点。
    final platform =
        FakePlatform()..mediaDuration = const Duration(seconds: 120);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/2.m3u8',
            title: 'Show - Two',
            videoTitle: 'Show',
            videoId: 'v1',
            currentIndex: 1,
            startAt: 180,
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
              {'title': 'Three', 'url': 'https://example.test/3.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('播放失败'), findsOneWidget);
    expect(find.text('从头播放'), findsOneWidget);

    platform.emitPosition(const Duration(seconds: 119));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    platform.emitCompleted();
    await tester.pumpAndSettle();
    expect(db.getHistory().single.episodeIndex, 1);
    expect(db.getHistory().single.position, const Duration(seconds: 180));
    expect(find.text('Show - Three'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('瞬时命中后提前结束不自动切集，历史保持第 2 集 180 秒', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);
    await db.saveHistory(
      HistoryItem(
        videoId: 'v1',
        title: 'Show',
        episodes: [
          EpisodeModel(id: 'ep_1', title: 'One', url: 'u1'),
          EpisodeModel(id: 'ep_2', title: 'Two', url: 'u2'),
          EpisodeModel(id: 'ep_3', title: 'Three', url: 'u3'),
        ],
        episodeIndex: 1,
        position: const Duration(seconds: 180),
        duration: const Duration(seconds: 600),
        watchedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final platform =
        FakePlatform()..mediaDuration = const Duration(seconds: 600);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/2.m3u8',
            title: 'Show - Two',
            videoTitle: 'Show',
            videoId: 'v1',
            currentIndex: 1,
            startAt: 180,
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
              {'title': 'Three', 'url': 'https://example.test/3.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 单次 181 秒命中后立刻回落到 5 秒并结束：不能确认，也不能切下一集。
    platform.emitPosition(const Duration(seconds: 181));
    platform.emitPosition(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    platform.emitCompleted();
    await tester.pumpAndSettle();
    expect(db.getHistory().single.episodeIndex, 1);
    expect(db.getHistory().single.position, const Duration(seconds: 180));
    expect(find.text('Show - Three'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('主动 seek 未生效时结束不切集，历史保持第 2 集 180 秒', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);
    await db.saveHistory(
      HistoryItem(
        videoId: 'v1',
        title: 'Show',
        episodes: [
          EpisodeModel(id: 'ep_1', title: 'One', url: 'u1'),
          EpisodeModel(id: 'ep_2', title: 'Two', url: 'u2'),
          EpisodeModel(id: 'ep_3', title: 'Three', url: 'u3'),
        ],
        episodeIndex: 1,
        position: const Duration(seconds: 180),
        duration: const Duration(seconds: 600),
        watchedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final platform =
        FakePlatform()..mediaDuration = const Duration(seconds: 600);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/2.m3u8',
            title: 'Show - Two',
            videoTitle: 'Show',
            videoId: 'v1',
            currentIndex: 1,
            startAt: 180,
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
              {'title': 'Three', 'url': 'https://example.test/3.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 先确认续播，再按右键发起 seek（替身不会移动位置）。
    platform.emitPosition(const Duration(seconds: 181));
    platform.emitPosition(const Duration(seconds: 182));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(platform.seeks, isNotEmpty);

    // seek 尚未生效时媒体结束：不能自动切集，也不能覆盖旧历史。
    platform.emitCompleted();
    await tester.pumpAndSettle();
    expect(db.getHistory().single.episodeIndex, 1);
    expect(db.getHistory().single.position, const Duration(seconds: 180));
    expect(find.text('Show - Three'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('seek 取代未确认续播后超时，再结束仍不切集/不写历史', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);
    await db.saveHistory(
      HistoryItem(
        videoId: 'v1',
        title: 'Show',
        episodes: [
          EpisodeModel(id: 'ep_1', title: 'One', url: 'u1'),
          EpisodeModel(id: 'ep_2', title: 'Two', url: 'u2'),
          EpisodeModel(id: 'ep_3', title: 'Three', url: 'u3'),
        ],
        episodeIndex: 1,
        position: const Duration(seconds: 180),
        duration: const Duration(seconds: 600),
        watchedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final platform =
        FakePlatform()..mediaDuration = const Duration(seconds: 600);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/2.m3u8',
            title: 'Show - Two',
            videoTitle: 'Show',
            videoId: 'v1',
            currentIndex: 1,
            startAt: 180,
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
              {'title': 'Three', 'url': 'https://example.test/3.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 续播尚未确认时先报 5 秒，再按右键 seek 到 10 秒（替身不移动位置）。
    platform.emitPosition(const Duration(seconds: 5));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(platform.seeks, isNotEmpty);

    // 等待 seek 超时（默认 8 秒），此时应进入可恢复失败。
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('播放失败'), findsOneWidget);

    // 超时后再收到 completed：不能自动切集，不能覆盖旧历史。
    platform.emitCompleted();
    await tester.pumpAndSettle();
    expect(db.getHistory().single.episodeIndex, 1);
    expect(db.getHistory().single.position, const Duration(seconds: 180));
    expect(find.text('Show - Three'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('连续两次 seek 未生效后超时，completed 仍不切集/不覆盖历史', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);
    await db.saveHistory(
      HistoryItem(
        videoId: 'v1',
        title: 'Show',
        episodes: [
          EpisodeModel(id: 'ep_1', title: 'One', url: 'u1'),
          EpisodeModel(id: 'ep_2', title: 'Two', url: 'u2'),
          EpisodeModel(id: 'ep_3', title: 'Three', url: 'u3'),
        ],
        episodeIndex: 1,
        position: const Duration(seconds: 180),
        duration: const Duration(seconds: 600),
        watchedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final platform =
        FakePlatform()..mediaDuration = const Duration(seconds: 600);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/2.m3u8',
            title: 'Show - Two',
            videoTitle: 'Show',
            videoId: 'v1',
            currentIndex: 1,
            startAt: 180,
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
              {'title': 'Three', 'url': 'https://example.test/3.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 续播未确认时只报 5 秒，连续两次右键（替身不移动位置）。
    platform.emitPosition(const Duration(seconds: 5));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(platform.seeks.length, greaterThanOrEqualTo(2));

    // 两次 seek 均未生效，等待超时后再结束：仍不能切集/覆盖历史。
    await tester.pump(const Duration(seconds: 9));
    platform.emitCompleted();
    await tester.pumpAndSettle();
    expect(db.getHistory().single.episodeIndex, 1);
    expect(db.getHistory().single.position, const Duration(seconds: 180));
    expect(find.text('Show - Three'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('两条旧集位置晚到且新集未播出：历史保持第 2 集 182 秒', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService()..resetForTest();
    await db.init();
    addTearDown(db.resetForTest);
    await db.saveHistory(
      HistoryItem(
        videoId: 'v1',
        title: 'Show',
        episodes: [
          EpisodeModel(id: 'ep_1', title: 'One', url: 'u1'),
          EpisodeModel(id: 'ep_2', title: 'Two', url: 'u2'),
          EpisodeModel(id: 'ep_3', title: 'Three', url: 'u3'),
        ],
        episodeIndex: 1,
        position: const Duration(seconds: 182),
        duration: const Duration(seconds: 600),
        watchedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(
      () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final platform =
        FakePlatform()..mediaDuration = const Duration(seconds: 600);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerFactoryProvider.overrideWithValue(
            () => Player(platformPlayer: platform),
          ),
          playerSurfaceProvider.overrideWithValue(
            (_) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: const MaterialApp(
          home: PlayerScreen(
            videoUrl: 'https://example.test/2.m3u8',
            title: 'Show - Two',
            videoTitle: 'Show',
            videoId: 'v1',
            currentIndex: 1,
            episodes: [
              {'title': 'One', 'url': 'https://example.test/1.m3u8'},
              {'title': 'Two', 'url': 'https://example.test/2.m3u8'},
              {'title': 'Three', 'url': 'https://example.test/3.m3u8'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第 3 集加载：无 URL 错误、open 正常返回但没有时长/有效播放。
    platform.gate = Completer<void>();
    platform.mediaDuration = Duration.zero;
    await tester.tap(find.byTooltip('下一集'));
    await tester.pump();
    platform.emitError('Failed to recognize file format.');
    await tester.pump();
    platform.gate!.complete();
    await tester.pumpAndSettle();

    // 第 2 集连续迟到的两个位置都不能当成第 3 集证据。
    platform.emitPosition(const Duration(seconds: 183));
    await tester.pump();
    platform.emitPosition(const Duration(seconds: 184));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    final history = db.getHistory().single;
    expect(history.episodeIndex, 1);
    expect(history.position, const Duration(seconds: 182));
    expect(find.text('播放失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
