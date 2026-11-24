import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/core/config/theme.dart';
import 'package:nova_play/features/home/widgets/video_card.dart';
import 'package:nova_play/models/video_model.dart';
import 'package:nova_play/shared/widgets/poster_card.dart';

void main() {
  test('dark discovery colors use mulberry surfaces and iris progress', () {
    final dark = AppTheme.dark;

    expect(dark.colorScheme.surface, const Color(0xFF191621));
    expect(dark.colorScheme.surfaceContainerLowest, const Color(0xFF12101A));
    expect(dark.progressIndicatorTheme.color, const Color(0xFFC8BCFF));
    expect(
      dark.textTheme.bodyMedium?.fontFamilyFallback,
      contains('Microsoft YaHei UI'),
    );
    expect(AppTheme.light.colorScheme.surface, const Color(0xFFFBF8F4));
  });

  testWidgets(
    'poster reserves 2:3 artwork, two title lines and one metadata line',
    (tester) async {
      await tester.pumpWidget(
        _posterFrame(
          scale: 1.6,
          child: PosterCard(
            video: VideoModel(
              id: 'poster',
              title: _longTitle,
              year: '2026',
              genre: '动画',
            ),
          ),
        ),
      );

      final artwork = find.ancestor(
        of: find.byIcon(Icons.movie_outlined),
        matching: find.byType(ClipRRect),
      );
      expect(artwork, findsOneWidget);
      final artSize = tester.getSize(artwork);
      expect(artSize.width / artSize.height, closeTo(2 / 3, 0.001));
      expect(tester.widget<Text>(find.text(_longTitle)).maxLines, 2);
      expect(tester.widget<Text>(find.text('2026 · 动画')).maxLines, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hover and Tab expose the primary action and Enter activates it',
    (tester) async {
      var activations = 0;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await tester.pumpWidget(
        _posterFrame(
          child: VideoCard(
            video: VideoModel(id: 'poster', title: _longTitle),
            onTap: () => activations++,
          ),
        ),
      );

      final play = find.byTooltip('打开详情');
      expect(play, findsNothing);

      await mouse.moveTo(tester.getCenter(find.byType(PosterCard)));
      await tester.pumpAndSettle();
      expect(play, findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(play, findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(play, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activations, 1);

      await tester.tap(play);
      expect(activations, 2);

      await tester.tap(find.text(_longTitle));
      expect(activations, 3);
    },
  );

  testWidgets('a separate play action preserves the details click', (
    tester,
  ) async {
    var opens = 0;
    var plays = 0;
    await tester.pumpWidget(
      _posterFrame(
        child: VideoCard(
          video: VideoModel(id: 'poster', title: _longTitle),
          onTap: () => opens++,
          onPlay: () => plays++,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final play = find.byTooltip('播放');
    expect(play, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(play);
    await tester.tap(find.text(_longTitle));
    expect(plays, 2);
    expect(opens, 1);
  });

  testWidgets('preview card and quick play each have their own Enter action', (
    tester,
  ) async {
    var previews = 0;
    var plays = 0;
    await tester.pumpWidget(
      _posterFrame(
        child: PosterCard(
          video: VideoModel(id: 'poster', title: _longTitle),
          previewsOnEnter: true,
          onTap: () => previews++,
          onPlay: () => plays++,
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(previews, 1);
    expect(plays, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(previews, 1);
    expect(plays, 1);
  });

  testWidgets('discovery rows fit the artwork and a scaled caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      _posterFrame(
        scale: 1.6,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final delegate = posterGridDelegate(
              context,
              390,
              maxTileWidth: 180,
              spacing: 16,
            );
            final tileWidth = (390 - 2 * 16) / 3;
            expect(delegate.crossAxisCount, 3);
            expect(delegate.crossAxisSpacing, 16);
            expect(delegate.mainAxisSpacing, 16);
            expect(
              delegate.mainAxisExtent,
              closeTo(
                tileWidth * 1.5 + PosterCard.captionHeight(context),
                0.001,
              ),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('fallback posters show the source before year and genre', (
    tester,
  ) async {
    final video = VideoModel(
      id: 'poster',
      title: _longTitle,
      year: '2026',
      genre: '动画',
      source: '备用影视',
    );
    await tester.pumpWidget(_posterFrame(child: VideoCard(video: video)));
    expect(find.text('2026 · 动画'), findsOneWidget);

    await tester.pumpWidget(
      _posterFrame(child: VideoCard(video: video, showSource: true)),
    );
    expect(find.text('备用影视 · 2026 · 动画'), findsOneWidget);
  });
}

const _longTitle = '一部片名相当长的动画作品，包含很多字的标题用来验证海报和说明仍能对齐';

Widget _posterFrame({required Widget child, double scale = 1}) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: Center(
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: SizedBox(width: 120, height: 275, child: child),
      ),
    ),
  ),
);
