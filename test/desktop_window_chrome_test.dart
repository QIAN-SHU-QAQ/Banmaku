import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:banmaku/core/window/main_window_chrome.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  const channel = MethodChannel('window_manager');
  const dragArea = Key('drag-area');
  const header = MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          Expanded(
            child: DesktopDragRegion(
              child: ColoredBox(
                key: dragArea,
                color: Colors.transparent,
                child: SizedBox(height: 48),
              ),
            ),
          ),
          DesktopWindowControls(),
        ],
      ),
    ),
  );

  testWidgets('headers work in apps without desktop window integration', (
    tester,
  ) async {
    await tester.pumpWidget(header);
    await tester.drag(find.byKey(dragArea), const Offset(75, 0));

    expect(find.byTooltip('关闭'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caption actions follow the native window state', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    var maximized = false;

    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'isMaximized' => maximized,
        'isFullScreen' => false,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      DesktopWindowChrome(manager: windowManager, child: header),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('最小化'));
    await tester.tap(find.byTooltip('最大化'));
    await tester.pump();

    expect(calls, containsAllInOrder(['minimize', 'maximize']));

    maximized = true;
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('onEvent', {'eventName': 'maximize'}),
      ),
      (_) {},
    );
    await tester.pump();

    await tester.tap(find.byTooltip('还原'));
    await tester.pump();
    expect(calls, contains('unmaximize'));

    calls.clear();
    final area = find.byKey(dragArea);
    await tester.tap(area);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(area);
    await tester.drag(area, const Offset(75, 0));
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(calls, containsAllInOrder(['unmaximize', 'startDragging', 'close']));
  });
}
