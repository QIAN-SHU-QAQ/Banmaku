import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import '../../core/network/http_client.dart';
import '../../models/video_model.dart';
import 'base_scraper.dart';
import 'source_config.dart';
import 'source_identity.dart';

typedef _Category = ({String id, String? parentId});

enum _AnimeRegion {
  domestic('国产动漫'),
  japanese('日本动漫');

  const _AnimeRegion(this.label);
  final String label;

  static _AnimeRegion? fromCategory(String name) => switch (name.trim()) {
    '国产动漫' || '国产动画' || '中国动漫' || '大陆动漫' || '国漫' => domestic,
    '日本动漫' || '日本动画' || '日漫' || '日韩动漫' || '日韩动画' => japanese,
    _ => null,
  };
}

class _AnimeFeed {
  _AnimeFeed(this.keyword);

  final String? keyword;
  // One upstream page cursor per category ID for each displayed page.
  final positions = <int, Map<String, int>>{};
}

/// maccms 风格 API 数据源。
///
/// 默认使用内置的两个源（LziApi 主源、360zy 备用源），但源本身由
/// [SourceConfig] 驱动：用户可以新增/启停/切换数据源（见设置页）。
/// 列表可选回退到其余启用的源。LziApi 保留旧数字 ID，其他源的作品 ID
/// 使用固定的 `<sourceId>:` 前缀。
class LziApiScraper extends BaseScraper {
  LziApiScraper({
    SourceConfig? primary,
    List<SourceConfig>? fallbacks,
    this.allowDetailPlaybackSubstitution = true,
    this.allowListFallback = true,
    this.animeCatalogOnly = false,
  }) : primary = primary ?? SourceConfig.defaults().first,
       _fallbacks = fallbacks ?? SourceConfig.defaults().skip(1).toList();

  /// 主源
  final SourceConfig primary;

  /// 其余数据源（仅启用的会参与详情和列表请求）
  final List<SourceConfig> _fallbacks;

  final bool allowDetailPlaybackSubstitution;
  final bool allowListFallback;
  final bool animeCatalogOnly;

  final HttpClient _httpClient = HttpClient();

  /// 实际参与请求的源顺序：[primary, ...启用的 fallbacks]
  late final List<SourceConfig> _sources = [
    primary,
    ..._fallbacks.where((s) => s.enabled && s.id != primary.id),
  ];

  @override
  String get name => primary.name;

  @override
  String get baseUrl => primary.baseUrl;

  @override
  String get icon => '🎬';

  static const _defaultCategory = '日韩动漫';
  static const _allCategories = '全部';
  static const _lziCategories = {
    _defaultCategory: '30',
    '国产动漫': '29',
    '欧美动漫': '31',
    '港台动漫': '32',
    '海外动漫': '33',
  };

  /// 快速 CDN 域名列表（按速度排序）
  static const List<String> _fastCdnDomains = [
    'vod1.maowushi.com', // 360zy.com 的 CDN，速度快
    'v.cdnlz22.com',
    'v.lzcdn27.com',
    'v.lzcdn31.com',
  ];

  /// 解析 JSON 响应
  Map<String, dynamic> _parseJson(String jsonStr) {
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchData(
    Map<String, dynamic> params, {
    int source = 0,
  }) async {
    final response = await _httpClient.get(
      _sources[source].baseUrl,
      queryParameters: params,
      options: Options(
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final data =
        response.data is String
            ? _parseJson(response.data as String)
            : response.data as Map<String, dynamic>;
    if (data['code'].toString() != '1') {
      throw const FormatException('数据源返回失败状态');
    }
    return data;
  }

  /// 同源的分类菜单与列表请求共用一次分类查询。
  final _categoryCache = <int, Future<Map<String, _Category>>>{};
  final _animeFeeds = <(int, String?, bool), _AnimeFeed>{};

  Future<Map<String, _Category>> _sourceCategories(int source) async {
    if (_sources[source].id == lziApiSourceId) {
      return {
        for (final entry in _lziCategories.entries)
          entry.key: (id: entry.value, parentId: null),
      };
    }

    final pending = _categoryCache.putIfAbsent(source, () async {
      final data = await _fetchData({'ac': 'list'}, source: source);
      return {
        for (final entry
            in (data['class'] as List? ?? const []).whereType<Map>())
          if (entry case {
            'type_name': final String name,
            'type_id': final id,
          } when name.isNotEmpty && name != _allCategories && id != null)
            name: (id: id.toString(), parentId: entry['type_pid']?.toString()),
      };
    });
    try {
      return await pending;
    } catch (_) {
      if (identical(_categoryCache[source], pending)) {
        _categoryCache.remove(source);
      }
      rethrow;
    }
  }

  int get _listSourceCount {
    if (!primary.enabled) return 0;
    return allowListFallback ? _sources.length : 1;
  }

  Future<List<Map<String, dynamic>>> _listItems(
    Map<String, dynamic> query,
    int source,
  ) async {
    final data = await _fetchData(query, source: source);
    return (data['list'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _categoryItems(
    Map<String, dynamic> query, {
    required int source,
    required _Category category,
    required Iterable<_Category> categories,
  }) async {
    final ids = [category.id];
    for (var i = 0; i < ids.length; i++) {
      for (final candidate in categories) {
        if (candidate.parentId == ids[i] && !ids.contains(candidate.id)) {
          ids.add(candidate.id);
        }
      }
    }

    Future<List<Map<String, dynamic>>> fetch(String id) =>
        _listItems({...query, 't': id}, source);

    final direct = await fetch(category.id);
    final children = ids.skip(1).toSet();
    // Some sources already include child categories in the parent's feed.
    if (children.isEmpty ||
        direct.any((item) => children.contains(item['type_id']?.toString()))) {
      return direct;
    }

    // Retry the whole page on failure to avoid skipping any child category.
    const batchSize = 5;
    final byId = <String, Map<String, dynamic>>{
      for (final item in direct) item['vod_id'].toString(): item,
    };
    for (var start = 1; start < ids.length; start += batchSize) {
      final pages = await Future.wait(
        ids.skip(start).take(batchSize).map(fetch),
      );
      for (final page in pages) {
        for (final item in page) {
          byId.putIfAbsent(item['vod_id'].toString(), () => item);
        }
      }
    }
    return _orderedItems(byId.values);
  }

  List<Map<String, dynamic>> _orderedItems(
    Iterable<Map<String, dynamic>> items,
  ) {
    final ordered =
        items.indexed.map((entry) {
            final (index, item) = entry;
            final updated = DateTime.tryParse(
              item['vod_time']?.toString() ?? '',
            );
            return (
              index: index,
              item: item,
              time: updated?.millisecondsSinceEpoch,
            );
          }).toList()
          ..sort((a, b) {
            final byTime = (b.time ?? 0).compareTo(a.time ?? 0);
            return byTime == 0 ? a.index.compareTo(b.index) : byTime;
          });
    return ordered.map((entry) => entry.item).toList();
  }

  Future<List<Map<String, dynamic>>> _animeItems(
    int source,
    Map<String, dynamic> query,
    String? category, {
    required bool requirePlayable,
  }) async {
    final catalog = await _sourceCategories(source);
    final types = {
      for (final entry in catalog.entries)
        if (_AnimeRegion.fromCategory(entry.key) case final region?
            when category == null ||
                category == _allCategories ||
                region.label == category)
          entry.value.id: entry.key,
    };
    final requestedPage = query['pg'] as int;
    final keyword = query['wd'] as String?;
    final feedKey = (source, category, requirePlayable);
    final previous = _animeFeeds[feedKey];
    final feed =
        requestedPage > 1 && previous != null && previous.keyword == keyword
            ? previous
            : (_animeFeeds[feedKey] = _AnimeFeed(keyword));
    var page = requestedPage;
    while (page > 1 && !feed.positions.containsKey(page)) {
      page--;
    }
    var positions =
        feed.positions[page] ?? {for (final id in types.keys) id: 1};
    for (; ; page++) {
      final next = <String, int>{};
      final items = <String, Map<String, dynamic>>{};
      for (final entry in positions.entries) {
        final id = entry.key;
        final result = await _nextAnimePage(
          source,
          query,
          id: id,
          name: types[id]!,
          firstPage: entry.value,
          requirePlayable: requirePlayable,
        );
        if (result.next != null) next[id] = result.next!;
        for (final item in result.items) {
          items.putIfAbsent(item['vod_id'].toString(), () => item);
        }
      }
      feed.positions[page + 1] = next;
      if (page == requestedPage) return _orderedItems(items.values);
      positions = next;
    }
  }

  Future<({List<Map<String, dynamic>> items, int? next})> _nextAnimePage(
    int source,
    Map<String, dynamic> query, {
    required String id,
    required String name,
    required int firstPage,
    required bool requirePlayable,
  }) async {
    const empty = (items: <Map<String, dynamic>>[], next: null);
    final seen = <String>{};
    for (var page = firstPage; ; page++) {
      final data = await _fetchData({
        ...query,
        't': id,
        'pg': page,
      }, source: source);
      final items = (data['list'] as List).cast<Map<String, dynamic>>();
      if (items.isEmpty) return empty;
      final matches =
          items
              .where(
                (item) =>
                    _matchesAnime(item, id, name) &&
                    (!requirePlayable ||
                        _parseEpisodes(item).any(_episodeHasHttpUrl)),
              )
              .toList();
      final last = int.tryParse(data['pagecount'].toString());
      if (matches.isNotEmpty || (last != null && page >= last)) {
        return (
          items: matches,
          next: last != null && page >= last ? null : page + 1,
        );
      }
      // Avoid looping if a source without pagination metadata ignores pg.
      if (!seen.add(items.map((item) => item['vod_id']).join(','))) {
        return empty;
      }
    }
  }

  bool _matchesAnime(Map<String, dynamic> item, String id, String name) {
    final itemId = item['type_id']?.toString();
    final itemName = item['type_name']?.toString();
    if (itemId == null ? itemName?.trim() != name.trim() : itemId != id) {
      return false;
    }
    if (_AnimeRegion.fromCategory(name) == _AnimeRegion.domestic) return true;
    final area = item['vod_area']?.toString().trim().toLowerCase() ?? '';
    if (area.isEmpty) return !name.contains('日韩');
    return area
        .split(RegExp(r'[\s/／,，、|｜;；·+]+'))
        .any(
          (part) => const {'日本', '日本国', 'japan', 'jp', 'jpn'}.contains(part),
        );
  }

  /// 空列表是有效结果；只有请求或协议异常才回退到下一个源。
  Future<List<VideoModel>> _listWithFallback(
    Map<String, dynamic> params, {
    String? category,
    bool requirePlayable = false,
  }) async {
    if (animeCatalogOnly &&
        category != null &&
        category != _allCategories &&
        !_AnimeRegion.values.any((region) => region.label == category)) {
      return [];
    }
    for (var source = 0; source < _listSourceCount; source++) {
      try {
        final query = Map<String, dynamic>.of(params);
        final List<Map<String, dynamic>> items;
        if (animeCatalogOnly) {
          items = await _animeItems(
            source,
            query,
            category,
            requirePlayable: requirePlayable,
          );
        } else if (category != null && category != _allCategories) {
          final categories = await _sourceCategories(source);
          final selected = categories[category];
          if (selected == null) {
            throw StateError('数据源 ${_sources[source].name} 不支持该分类');
          }
          items = await _categoryItems(
            query,
            source: source,
            category: selected,
            categories: categories.values,
          );
        } else {
          if (category == _allCategories &&
              _sources[source].id == lziApiSourceId) {
            query['t'] = _lziCategories[_defaultCategory];
          }
          items = await _listItems(query, source);
        }
        final videos = items.map((item) => _parseVideo(item, source: source));
        return requirePlayable && !animeCatalogOnly
            ? videos
                .where((video) => video.episodes!.any(_episodeHasHttpUrl))
                .toList()
            : videos.toList();
      } catch (e) {
        debugPrint('视频数据源 ${_sources[source].name} 请求失败: $e');
      }
    }
    throw Exception('视频数据源暂时不可用，请检查网络后重试');
  }

  @override
  Future<List<String>> getCategories() async {
    if (!primary.enabled) return [_allCategories];
    final categories = await _sourceCategories(0);
    if (animeCatalogOnly) {
      final supported = categories.keys.map(_AnimeRegion.fromCategory).toSet();
      return [
        _allCategories,
        for (final region in _AnimeRegion.values)
          if (supported.contains(region)) region.label,
      ];
    }
    return [_allCategories, ...categories.keys];
  }

  @override
  Future<List<VideoModel>> getHome({int page = 1}) async {
    final category =
        !animeCatalogOnly && primary.id == lziApiSourceId
            ? _defaultCategory
            : _allCategories;
    return getByCategory(category, page: page);
  }

  @override
  Future<List<VideoModel>> getByCategory(
    String category, {
    int page = 1,
  }) async {
    return _listWithFallback({'ac': 'detail', 'pg': page}, category: category);
  }

  @override
  Future<List<VideoModel>> search(String keyword, {int page = 1}) async {
    return _listWithFallback({'ac': 'detail', 'wd': keyword, 'pg': page});
  }

  Future<List<VideoModel>> searchPlayable(String keyword, {int page = 1}) =>
      _listWithFallback({
        'ac': 'detail',
        'wd': keyword,
        'pg': page,
      }, requirePlayable: true);

  static bool _episodeHasHttpUrl(EpisodeModel episode) {
    final uri = Uri.tryParse(episode.playUrl ?? episode.url);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.isScheme('http') || uri.isScheme('https'));
  }

  @override
  Future<VideoModel> getDetail(String url) async {
    final identity = decodeSourceVideoId(url);
    if (identity == null) {
      throw Exception('无效的视频标识，请重新搜索作品');
    }
    return _getDetail(
      identity.sourceConfigId,
      identity.vodId,
      allowPlaybackSubstitution: allowDetailPlaybackSubstitution,
    );
  }

  /// 用已确认的原始来源查询旧记录保存的数字作品 ID。
  Future<VideoModel> getDetailFromSource(
    String sourceConfigId,
    String vodId,
  ) async {
    if (!isNumericVodId(vodId)) {
      throw Exception('无效的视频标识，请重新搜索作品');
    }
    return _getDetail(sourceConfigId, vodId, allowPlaybackSubstitution: false);
  }

  Future<VideoModel> _getDetail(
    String sourceConfigId,
    String id, {
    required bool allowPlaybackSubstitution,
  }) async {
    final sourceIndex = _sources.indexWhere(
      (source) => source.enabled && source.id == sourceConfigId,
    );
    if (sourceIndex < 0) {
      throw Exception('作品的原始数据源已不可用，请重新搜索作品');
    }
    try {
      final data = await _fetchData({
        'ac': 'detail',
        'ids': id,
      }, source: sourceIndex);

      final list = data['list'] as List;
      if (list.isEmpty) {
        throw Exception('未找到视频详情');
      }

      final item = list[0] as Map<String, dynamic>;
      if (item['vod_id'].toString() != id) {
        throw const FormatException('数据源返回了不匹配的作品标识');
      }
      final video = _parseVideo(item, source: sourceIndex);

      // 如果当前源的 CDN 慢，尝试从其它源获取更快的播放地址
      final hasFastCdn =
          video.episodes?.any((ep) {
            final playUrl = ep.playUrl ?? '';
            return _fastCdnDomains.any((cdn) => playUrl.contains(cdn));
          }) ??
          false;

      // 只有主源详情才尝试用其它源替换播放地址（备用源本身已是备选，
      // 再回主源会引入额外请求并改变作品来源语义）。
      if (allowPlaybackSubstitution &&
          sourceIndex == 0 &&
          !hasFastCdn &&
          video.title.isNotEmpty &&
          _hasExplicitEpisodeTitles(item) &&
          video.year != null &&
          video.year!.trim().isNotEmpty) {
        for (var backup = 0; backup < _sources.length; backup++) {
          if (backup == sourceIndex) continue;
          try {
            final backupData = await _fetchData({
              'ac': 'detail',
              'wd': video.title,
            }, source: backup);

            final backupList = backupData['list'] as List;
            for (final backupItem in backupList) {
              if (backupItem is! Map<String, dynamic>) continue;
              final backupName = (backupItem['vod_name'] as String?) ?? '';
              if (backupName.trim() == video.title.trim() &&
                  _hasExplicitEpisodeTitles(backupItem) &&
                  backupItem['vod_year']?.toString().trim() ==
                      video.year!.trim()) {
                final backupVideo = _parseVideo(backupItem, source: backup);
                final episodes = video.episodes ?? <EpisodeModel>[];
                final replacements = backupVideo.episodes ?? <EpisodeModel>[];
                // 保留集数、顺序和剧集 ID，避免跨源缺集/特典造成续播错位。
                if (episodes.isEmpty ||
                    episodes.length != replacements.length ||
                    episodes.map((e) => e.title.trim()).toSet().length !=
                        episodes.length ||
                    replacements.map((e) => e.title.trim()).toSet().length !=
                        replacements.length) {
                  continue;
                }
                final byTitle = {
                  for (final ep in replacements) ep.title.trim(): ep,
                };
                if (!episodes.every(
                  (ep) => byTitle.containsKey(ep.title.trim()),
                )) {
                  continue;
                }
                return video.copyWith(
                  episodes:
                      episodes.map((ep) {
                        final replacement = byTitle[ep.title.trim()]!;
                        return EpisodeModel(
                          id: ep.id,
                          title: ep.title,
                          index: ep.index,
                          url: replacement.url,
                          playUrl: replacement.playUrl,
                          urlIsMediaPlayback: replacement.urlIsMediaPlayback,
                        );
                      }).toList(),
                );
              }
            }
          } catch (e) {
            debugPrint('备用源 ${_sources[backup].name} 失败: $e');
          }
        }
      }

      return video;
    } catch (e) {
      debugPrint('LziApiScraper getDetail error: $e');
      throw Exception('视频详情暂时不可用，请重试或返回搜索选择其他数据源');
    }
  }

  @override
  Future<List<String>> getPlayUrls(String episodeUrl) async {
    // 如果已经是 m3u8 直链，直接返回
    if (episodeUrl.endsWith('.m3u8') || episodeUrl.contains('.m3u8?')) {
      return [episodeUrl];
    }

    // 如果是 share 链接，尝试解析出 m3u8 地址
    try {
      final response = await _httpClient.get(episodeUrl);
      final content = response.data.toString();

      // 从 HTML 中提取 m3u8 地址
      final m3u8Regex = RegExp(r'var\s+main\s*=\s*"([^"]+\.m3u8[^"]*)"');
      final match = m3u8Regex.firstMatch(content);
      if (match != null) {
        var m3u8Url = match.group(1)!;
        // 如果是相对路径，补全为绝对路径
        if (m3u8Url.startsWith('/')) {
          final uri = Uri.parse(episodeUrl);
          m3u8Url = '${uri.scheme}://${uri.host}$m3u8Url';
        }
        return [m3u8Url];
      }

      // 尝试匹配其他格式的 m3u8
      final m3u8Regex2 = RegExp(r'https?://\S+\.m3u8\S*');
      final matches = m3u8Regex2.allMatches(content);
      if (matches.isNotEmpty) {
        return matches.map((m) => m.group(0)!).toList();
      }

      return [episodeUrl]; // 回退：返回原始 URL
    } catch (e) {
      debugPrint('LziApiScraper getPlayUrls error: $e');
      return [episodeUrl];
    }
  }

  /// 解析视频数据
  VideoModel _parseVideo(Map<String, dynamic> item, {required int source}) {
    if (item['vod_id'] == null || item['vod_name'] is! String) {
      throw const FormatException('数据源缺少作品标识或标题');
    }
    final vodId = item['vod_id'].toString();
    if (!isNumericVodId(vodId)) {
      throw const FormatException('数据源作品标识无效');
    }
    final config = _sources[source];
    final title = item['vod_name'] as String;
    final pic = item['vod_pic'] as String?;
    final blurb = item['vod_blurb'] as String?;
    final content = item['vod_content'] as String?;
    // CMS 的摘要可能损坏空格实体；优先从完整正文得到可读文本。
    final rawDescription =
        content != null && content.trim().isNotEmpty ? content : blurb ?? '';
    final description =
        (html
                    .parseFragment(
                      rawDescription.replaceAll(
                        RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false),
                        '\n',
                      ),
                    )
                    .text ??
                '')
            .replaceAll(RegExp(r'[ \t\u00a0\u3000]+'), ' ')
            .replaceAll(RegExp(r' *\n+ *'), '\n\n')
            .trim();
    final year = item['vod_year'] as String?;
    final area = item['vod_area'] as String?;
    final score = item['vod_score'] as String?;
    final doubanScore = item['vod_douban_score'] as String?;

    // 解析类型
    final className = item['vod_class'] as String?;

    // 解析评分
    double? rating;
    if (score != null && score != '0.0') {
      rating = double.tryParse(score);
    } else if (doubanScore != null && doubanScore != '0.0') {
      rating = double.tryParse(doubanScore);
    }

    // 解析选集
    final episodes = _parseEpisodes(item);

    return VideoModel(
      id: encodeSourceVideoId(config.id, vodId),
      title: title,
      cover: pic,
      description: description.isNotEmpty ? description : null,
      rating: rating,
      year: year,
      genre: className ?? area,
      source: config.name,
      sourceUrl: config.baseUrl,
      sourceConfigId: config.id,
      episodes: episodes,
    );
  }

  /// 选择最佳播放源
  String _selectBestSource(List<String> sources) {
    // 优先选择 m3u8 直链
    final m3u8Sources = sources.where((s) => s.contains('.m3u8')).toList();
    if (m3u8Sources.isEmpty) return sources[0];

    // 在 m3u8 源中选择 CDN 速度最快的
    for (final cdn in _fastCdnDomains) {
      for (final source in m3u8Sources) {
        if (source.contains(cdn)) {
          return source;
        }
      }
    }

    // 默认使用第一个 m3u8 源
    return m3u8Sources[0];
  }

  /// 显示用的自动集数不能作为跨源剧集对应关系的依据。
  bool _hasExplicitEpisodeTitles(Map<String, dynamic> item) {
    final raw = item['vod_play_url'] as String? ?? '';
    if (raw.isEmpty) return false;
    return _selectBestSource(raw.split(r'$$$')).split('#').every((part) {
      final separator = part.indexOf(r'$');
      return separator > 0 && part.substring(0, separator).trim().isNotEmpty;
    });
  }

  /// 解析选集列表：$$$ 分线路，# 分剧集，$ 分标题和 URL。
  List<EpisodeModel> _parseEpisodes(Map<String, dynamic> item) {
    final playUrl = item['vod_play_url'] as String? ?? '';

    if (playUrl.isEmpty) return [];

    // 分隔不同播放源
    final sources = playUrl.split(r'$$$');

    // 选择最佳播放源
    final selectedSource = _selectBestSource(sources);

    final episodes = <EpisodeModel>[];

    // 分隔不同集数
    final episodeParts = selectedSource.split('#');
    for (int i = 0; i < episodeParts.length; i++) {
      final part = episodeParts[i];
      final dollarIndex = part.indexOf(r'$');
      if (dollarIndex == -1) continue;

      final title = part.substring(0, dollarIndex).trim();
      final url = part.substring(dollarIndex + 1).trim();

      if (url.isNotEmpty) {
        episodes.add(
          EpisodeModel(
            id: 'ep_${i + 1}',
            title: title.isNotEmpty ? title : '第 ${i + 1} 集',
            url: url,
            index: i,
            playUrl: url, // 直接播放地址
            urlIsMediaPlayback: true,
          ),
        );
      }
    }

    return episodes;
  }
}
