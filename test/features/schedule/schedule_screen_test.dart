import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nova_play/features/schedule/airing_schedule.dart';
import 'package:nova_play/features/schedule/schedule_screen.dart';

void main() {
  final today = DateTime(2026, 11, 19, 10);

  testWidgets('shows today in a narrow window and searches the chosen title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(616, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (_, _) => ScheduleScreen(
                now: () => today,
                load:
                    (_, _, {cancelToken}) async => [
                      AiringEpisode(
                        airingAt: DateTime(2026, 11, 19, 20, 30),
                        title: '今日作品 & 特别篇',
                        episode: 3,
                      ),
                      AiringEpisode(
                        airingAt: DateTime(2026, 11, 19, 9, 15),
                        title: '早间节目',
                        episode: 7,
                      ),
                    ],
              ),
        ),
        GoRoute(
          path: '/search',
          builder:
              (_, state) => Scaffold(
                body: Text(
                  '${state.uri.queryParameters['from']} '
                  '${state.uri.queryParameters['q']}',
                ),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('11月19日'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(find.text('第 3 集'), findsOneWidget);
    final marker = tester.getTopLeft(find.text('10:00')).dy;
    expect(tester.getTopLeft(find.text('早间节目')).dy, lessThan(marker));
    expect(tester.getTopLeft(find.text('今日作品 & 特别篇')).dy, greaterThan(marker));

    final lastDate = find.text('11月25日');
    expect(lastDate.hitTestable(), findsNothing);
    await tester.fling(find.text('11月19日'), const Offset(-260, 0), 3000);
    await tester.pumpAndSettle();
    expect(lastDate.hitTestable(), findsOneWidget);
    await tester.fling(lastDate, const Offset(260, 0), 3000);
    await tester.pumpAndSettle();

    await tester.tap(find.text('今日作品 & 特别篇'));
    await tester.pumpAndSettle();
    expect(find.text('schedule 今日作品 & 特别篇'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offers retry for failure and changes the requested date range', (
    tester,
  ) async {
    final pending = Completer<List<AiringEpisode>>();
    final requests = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          now: () => today,
          load: (start, _, {cancelToken}) {
            requests.add(start);
            return requests.length == 1 ? pending.future : Future.value([]);
          },
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('无法加载放送时间表'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('这 7 天暂无放送安排'), findsOneWidget);
    expect(requests, [DateTime(2026, 11, 19), DateTime(2026, 11, 19)]);

    await tester.tap(find.byTooltip('后 7 天'));
    await tester.pumpAndSettle();
    expect(requests.last, DateTime(2026, 11, 26));

    await tester.tap(find.byTooltip('前 7 天'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('前 7 天'));
    await tester.pumpAndSettle();
    expect(requests.last, DateTime(2026, 11, 12));

    await tester.tap(find.text('回到今天'));
    await tester.pumpAndSettle();
    expect(requests.last, DateTime(2026, 11, 19));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
