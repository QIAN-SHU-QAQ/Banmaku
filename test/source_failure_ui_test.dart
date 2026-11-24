import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/app.dart';
import 'package:nova_play/providers/bangumi_provider.dart';
import 'package:nova_play/services/bangumi_api.dart';

class _RecoveringAdapter implements HttpClientAdapter {
  bool online = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!online) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {'id': 123, 'name': '恢复成功', 'type': 2},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('作品库请求失败显示错误，网络恢复后可重试', (tester) async {
    final adapter = _RecoveringAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bangumiApiProvider.overrideWithValue(BangumiApi(dio: dio))],
        child: const NovaPlayApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('作品库加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    adapter.online = true;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('作品库加载失败'), findsNothing);
    expect(find.text('恢复成功'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
