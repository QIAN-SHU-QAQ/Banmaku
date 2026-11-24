import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:banmaku/app.dart';
import 'package:banmaku/providers/home_provider.dart';
import 'package:banmaku/providers/scraper_provider.dart';

import 'fakes.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 用 Fake 数据源覆盖，避免冒烟测试依赖真实网络（dio 超时 Timer 会挂起）
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentScraperProvider.overrideWithValue(FakeScraper()),
          discoveryPageLoaderProvider.overrideWithValue(emptyDiscoveryPage),
        ],
        child: const BanmakuApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Banmaku'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => switch (widget) {
          Image(
            image: ResizeImage(
              imageProvider: AssetImage(
                assetName: 'windows/runner/resources/banmaku_icon.png',
              ),
            ),
          ) =>
            true,
          _ => false,
        },
      ),
      findsOneWidget,
    );
    expect(find.text('发现'), findsWidgets);
  });
}
