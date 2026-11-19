import 'package:dio/dio.dart';

class AiringEpisode {
  const AiringEpisode({
    required this.airingAt,
    required this.title,
    required this.episode,
    this.coverUrl,
  });

  final DateTime airingAt;
  final String title;
  final int episode;
  final String? coverUrl;
}

typedef AiringScheduleLoader =
    Future<List<AiringEpisode>> Function(
      DateTime start,
      DateTime end, {
      CancelToken? cancelToken,
    });

class AiringScheduleRepository {
  AiringScheduleRepository({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

  static const _url = 'https://graphql.anilist.co';
  static const _query = r'''
    query AiringWeek($page: Int!, $after: Int!, $before: Int!) {
      Page(page: $page, perPage: 50) {
        pageInfo { hasNextPage }
        airingSchedules(airingAt_greater: $after, airingAt_lesser: $before, sort: [TIME]) {
          airingAt
          episode
          media {
            isAdult
            title { native romaji english }
            coverImage { medium }
          }
        }
      }
    }
  ''';

  final Dio _dio;

  /// Fetches [start, end), converting AniList Unix timestamps to local time.
  Future<List<AiringEpisode>> load(
    DateTime start,
    DateTime end, {
    CancelToken? cancelToken,
  }) async {
    final entries = <AiringEpisode>[];
    final after = start.millisecondsSinceEpoch ~/ 1000 - 1;
    final before = end.millisecondsSinceEpoch ~/ 1000;
    for (var page = 1; ; page++) {
      final response = await _dio.post<Map<String, dynamic>>(
        _url,
        data: {
          'query': _query,
          'variables': {'page': page, 'after': after, 'before': before},
        },
        options: Options(contentType: Headers.jsonContentType),
        cancelToken: cancelToken,
      );
      final data = response.data;
      final payload = data?['data'];
      final result = payload is Map ? payload['Page'] : null;
      final pageInfo = result is Map ? result['pageInfo'] : null;
      final rawEntries = result is Map ? result['airingSchedules'] : null;
      final hasNextPage = pageInfo is Map ? pageInfo['hasNextPage'] : null;
      if (data?['errors'] != null ||
          rawEntries is! List ||
          hasNextPage is! bool) {
        throw const FormatException('Invalid AniList airing schedule');
      }

      for (final raw in rawEntries.whereType<Map>()) {
        final entry = _parse(raw);
        if (entry != null &&
            !entry.airingAt.isBefore(start) &&
            entry.airingAt.isBefore(end)) {
          entries.add(entry);
        }
      }
      if (!hasNextPage) break;
    }
    entries.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    return entries;
  }

  static AiringEpisode? _parse(Map raw) {
    final timestamp = raw['airingAt'];
    final episode = raw['episode'];
    final media = raw['media'];
    if (timestamp is! int ||
        episode is! int ||
        episode < 1 ||
        media is! Map ||
        media['isAdult'] != false) {
      return null;
    }
    final names = media['title'];
    if (names is! Map) return null;
    final titles = [names['native'], names['romaji'], names['english']]
        .whereType<String>()
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty);
    if (titles.isEmpty) return null;
    final cover = media['coverImage'];
    final coverUrl = cover is Map ? cover['medium'] : null;
    return AiringEpisode(
      airingAt: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      title: titles.first,
      episode: episode,
      coverUrl: coverUrl is String && coverUrl.isNotEmpty ? coverUrl : null,
    );
  }
}
