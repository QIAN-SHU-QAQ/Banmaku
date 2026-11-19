import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/features/schedule/airing_schedule.dart';

void main() {
  test(
    'loads all pages and keeps only the requested local date range',
    () async {
      final start = DateTime(2026, 11, 19);
      final end = DateTime(2026, 11, 26);
      final startSeconds = start.millisecondsSinceEpoch ~/ 1000;
      final endSeconds = end.millisecondsSinceEpoch ~/ 1000;
      final variables = <Map<String, dynamic>>[];
      final dio =
          Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (request, handler) {
                  final params =
                      request.data['variables'] as Map<String, dynamic>;
                  variables.add(params);
                  final firstPage = params['page'] == 1;
                  handler.resolve(
                    Response(
                      requestOptions: request,
                      data: {
                        'data': {
                          'Page': {
                            'pageInfo': {'hasNextPage': firstPage},
                            'airingSchedules':
                                firstPage
                                    ? [
                                      _entry(startSeconds + 500, '第二部'),
                                      _entry(startSeconds - 1, '范围外'),
                                      _entry(startSeconds, '成人条目', adult: true),
                                    ]
                                    : [
                                      _entry(startSeconds, '第一部'),
                                      _entry(endSeconds, '范围外'),
                                    ],
                          },
                        },
                      },
                    ),
                  );
                },
              ),
            );

      final result = await AiringScheduleRepository(dio: dio).load(start, end);

      expect(variables.map((page) => page['page']), [1, 2]);
      expect(variables.first['after'], startSeconds - 1);
      expect(variables.first['before'], endSeconds);
      expect(result.map((entry) => entry.title), ['第一部', '第二部']);
      expect(result.first.airingAt, start);
      expect(result.first.episode, 4);
      expect(result.first.coverUrl, 'https://example.com/cover.jpg');
    },
  );

  test('reports a GraphQL error instead of an empty schedule', () async {
    final dio =
        Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (request, handler) {
                handler.resolve(
                  Response(
                    requestOptions: request,
                    data: {
                      'errors': [
                        {'message': 'Unavailable'},
                      ],
                      'data': null,
                    },
                  ),
                );
              },
            ),
          );

    await expectLater(
      AiringScheduleRepository(
        dio: dio,
      ).load(DateTime(2026, 11, 19), DateTime(2026, 11, 26)),
      throwsFormatException,
    );
  });
}

Map<String, Object> _entry(int seconds, String title, {bool adult = false}) => {
  'airingAt': seconds,
  'episode': 4,
  'media': {
    'isAdult': adult,
    'title': {'native': title},
    'coverImage': {'medium': 'https://example.com/cover.jpg'},
  },
};
