import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import '../../core/network/http_client.dart';
import '../../models/video_model.dart';
import 'base_scraper.dart';
import 'source_config.dart';
import 'source_identity.dart';

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
  }) : primary = primary ?? SourceConfig.defaults().first,
       _fallbacks = fallbacks ?? SourceConfig.defaults().skip(1).toList();

  /// 主源
  final SourceConfig primary;

  /// 其余数据源（仅启用的会参与详情和列表请求）
  final List<SourceConfig> _fallbacks;

  final bool allowDetailPlaybackSubstitution;
  final bool allowListFallback;

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
  final _categoryCache = <int, Future<Map<String, String>>>{};

  Future<Map<String, String>> _sourceCategories(int source) async {
    if (_sources[source].id == lziApiSourceId) return _lziCategories;

    final pending = _categoryCache.putIfAbsent(source, () async {
      final data = await _fetchData({'ac': 'list'}, source: source);
      return {
        for (final entry in (data['class'] as List? ?? const []))
          if (entry case {
            'type_name': final String name,
            'type_id': final id,
          } when name.isNotEmpty && name != _allCategories && id != null)
            name: id.toString(),
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

  /// 空列表是有效结果；只有请求或协议异常才回退到下一个源。
  Future<List<VideoModel>> _listWithFallback(
    Map<String, dynamic> params, {
    String? category,
  }) async {
    for (var source = 0; source < _listSourceCount; source++) {
      try {
        final query = Map<String, dynamic>.of(params);
        if (category == _allCategories &&
            _sources[source].id == lziApiSourceId) {
          query['t'] = _lziCategories[_defaultCategory];
        } else if (category != null && category != _allCategories) {
          final categories = await _sourceCategories(source);
          final categoryId = categories[category];
          if (categoryId == null) {
            throw StateError('数据源 ${_sources[source].name} 不支持该分类');
          }
          query['t'] = categoryId;
        }
        final data = await _fetchData(query, source: source);
        return (data['list'] as List)
            .map(
              (item) =>
                  _parseVideo(item as Map<String, dynamic>, source: source),
            )
            .toList();
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
    return [_allCategories, ...categories.keys];
  }

  @override
  Future<List<VideoModel>> getHome({int page = 1}) async {
    final category =
        primary.id == lziApiSourceId ? _defaultCategory : _allCategories;
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
