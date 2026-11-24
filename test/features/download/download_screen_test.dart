import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/features/download/download_screen.dart';
import 'package:nova_play/providers/download_provider.dart';
import 'package:nova_play/services/download_service.dart';

class _Downloads extends DownloadService {
  _Downloads(this.tasks);

  @override
  final List<DownloadTask> tasks;

  final List<String> actions = [];

  @override
  Future<void> init() async {}

  @override
  void pauseTask(String id) => actions.add('pause:$id');

  @override
  void resumeTask(String id) => actions.add('resume:$id');

  @override
  Future<void> removeTask(String id) async => actions.add('remove:$id');

  @override
  Future<void> clearCompleted() async => actions.add('clear');
}

DownloadTask _task(
  String id,
  String title, {
  String? videoId,
  DownloadStatus status = DownloadStatus.paused,
  double progress = 0,
}) {
  return DownloadTask(
    id: id,
    title: title,
    url: 'https://example.test/$id',
    videoId: videoId,
    savePath: 'downloads/$id.ts',
    status: status,
    progress: progress,
    createdAt: DateTime(2026),
  );
}

void main() {
  late _Downloads service;

  setUp(() {
    service = _Downloads([
      _task(
        'a2',
        '作品 A - 第 2 集 - 续篇',
        videoId: 'a',
        status: DownloadStatus.downloading,
        progress: .42,
      ),
      _task(
        'a1',
        '作品 A - 第 1 集',
        videoId: 'a',
        status: DownloadStatus.completed,
      ),
      _task('b1', '作品 B - 第 1 集', videoId: 'b'),
      _task('legacy1', '独立记录'),
      _task('legacy2', '独立记录', videoId: ' '),
    ]);
  });
  tearDown(() => service.dispose());

  Future<void> pumpDownloads(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [downloadServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: DownloadScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wide download view selects groups by the persisted video ID', (
    tester,
  ) async {
    await pumpDownloads(tester, 1120);

    expect(find.text('独立记录'), findsNWidgets(2));
    expect(find.text('2 个任务'), findsOneWidget);
    expect(find.text('第 2 集 - 续篇'), findsOneWidget);
    expect(find.text('下载中 · 42%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    await tester.tap(find.byTooltip('暂停'));

    await tester.tap(find.text('作品 B'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 集 - 续篇'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('继续'));
    expect(service.actions, ['pause:a2', 'resume:b1']);
  });

  testWidgets('narrow download list keeps full titles and confirms deletion', (
    tester,
  ) async {
    await pumpDownloads(tester, 420);

    expect(find.text('作品 A - 第 2 集 - 续篇'), findsOneWidget);
    expect(find.text('作品 B - 第 1 集'), findsOneWidget);
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('删除下载'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.actions, isEmpty);

    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(service.actions, ['remove:a2']);

    await tester.tap(find.text('清除已完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(service.actions, ['remove:a2', 'clear']);
    expect(tester.takeException(), isNull);
  });
}
