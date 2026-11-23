import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/core/network/http_client.dart';
import 'package:nova_play/services/scraper/lziapi_scraper.dart';
import 'package:nova_play/services/scraper/source_config.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Object Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(respond(options)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _video(
  int id, {
  String title = '番剧',
  String year = '2026',
  String host = 'slow.example',
}) => {
  'vod_id': id,
  'vod_name': title,
  'vod_year': year,
  'vod_play_url': '第1集\$https://$host/1.m3u8',
};
Map<String, dynamic> _list(List<Object> items) => {'code': 1, 'list': items};
Never _fail(RequestOptions options) =>
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );

void main() {
  late _Adapter adapter;
  late HttpClientAdapter previous;
  late LziApiScraper scraper;
  void respond(Object Function(RequestOptions) handler) {
    adapter = _Adapter(handler);
    HttpClient().dio.httpClientAdapter = adapter;
  }

  setUp(() {
    previous = HttpClient().dio.httpClientAdapter;
    scraper = LziApiScraper();
  });
  tearDown(() => HttpClient().dio.httpClientAdapter = previous);

  test('主源断连后使用备用搜索并保留来源身份', () async {
    respond(
      (o) => o.uri.host == 'cj.lziapi.com' ? _fail(o) : _list([_video(900)]),
    );
    final result = await scraper.search('番剧');
    expect(result.single.id, '360zy:900');
    expect(result.single.source, '360zy');
    expect(result.single.sourceUrl, contains('360zy.com'));
    expect(adapter.requests.length, 2);
  });
  for (final invalidId in [
    '',
    'oops',
    {'id': 1},
  ]) {
    test('主源作品 ID 无效时回退备用源: $invalidId', () async {
      respond(
        (o) => _list([
          o.uri.host == 'cj.lziapi.com'
              ? {..._video(1), 'vod_id': invalidId}
              : _video(900),
        ]),
      );
      expect((await scraper.search('番剧')).single.id, '360zy:900');
      expect(adapter.requests.length, 2);
    });
  }
  test('两源缺少真实剧集标题时不按自动生成的集数匹配', () async {
    respond(
      (o) => _list([
        {
          ..._video(o.uri.host == 'cj.lziapi.com' ? 1 : 900),
          'vod_play_url':
              o.uri.host == 'cj.lziapi.com'
                  ? r'$https://slow.example/one.m3u8#$https://slow.example/two.m3u8'
                  : r'$https://vod1.maowushi.com/two.m3u8#$https://vod1.maowushi.com/one.m3u8',
        },
      ]),
    );
    final result = await scraper.getDetail('1');
    expect(result.episodes!.first.playUrl, 'https://slow.example/one.m3u8');
  });
  test('备用源缺少真实标题时不与主源显式集数匹配', () async {
    respond(
      (o) => _list([
        {
          ..._video(o.uri.host == 'cj.lziapi.com' ? 1 : 900),
          'vod_play_url':
              o.uri.host == 'cj.lziapi.com'
                  ? r'第 1 集$https://slow.example/one.m3u8#第 2 集$https://slow.example/two.m3u8'
                  : r'$https://vod1.maowushi.com/two.m3u8#$https://vod1.maowushi.com/one.m3u8',
        },
      ]),
    );
    expect(
      (await scraper.getDetail('1')).episodes!.first.playUrl,
      'https://slow.example/one.m3u8',
    );
  });
  test('正常空搜索不触发换源', () async {
    respond((o) => _list([]));
    expect(await scraper.search('不存在'), isEmpty);
    expect(adapter.requests.length, 1);
  });
  test('简介优先解析完整正文，解码实体并保留段落', () async {
    respond(
      (_) => _list([
        {
          ..._video(1),
          'vod_blurb': '截断摘要 &amp;    ;',
          'vod_content': '<p>甲&nbsp;&amp; 乙</p><p>下一段</p>',
        },
      ]),
    );
    expect((await scraper.search('番剧')).single.description, '甲 & 乙\n\n下一段');
  });
  test('所有源失败抛出可见错误', () async {
    respond(_fail);
    await expectLater(
      scraper.search('番剧'),
      throwsA(predicate((e) => e.toString().contains('数据源'))),
    );
    expect(adapter.requests.length, 2);
  });
  for (final response in [
    {'code': 0, 'list': []},
    {'code': 1, 'list': 'broken'},
  ]) {
    test('主源协议异常也会回退: $response', () async {
      respond(
        (o) => o.uri.host == 'cj.lziapi.com' ? response : _list([_video(900)]),
      );
      expect((await scraper.search('番剧')).single.id, '360zy:900');
    });
  }
  test('首页回退按备用源分类名称查 ID', () async {
    respond((o) {
      if (o.uri.host == 'cj.lziapi.com') return _fail(o);
      if (o.queryParameters['ac'] == 'list') {
        return {
          'code': 1,
          'class': [
            {'type_id': 40, 'type_name': '日韩动漫'},
          ],
        };
      }
      expect(o.queryParameters['t'].toString(), '40');
      return _list([_video(900)]);
    });
    expect((await scraper.getHome()).single.id, '360zy:900');
    expect(adapter.requests.length, 3);
  });
  test('备用源不支持分类时不会误取其他分类', () async {
    respond(
      (o) =>
          o.uri.host == 'cj.lziapi.com'
              ? _fail(o)
              : {
                'code': 1,
                'class': [
                  {'type_id': 40, 'type_name': '日韩动漫'},
                ],
              },
    );
    await expectLater(scraper.getByCategory('港台动漫'), throwsException);
    expect(adapter.requests.length, 2);
  });
  test('自定义主源使用自己的分类编号，全部不限制分类', () async {
    final defaults = SourceConfig.defaults();
    final custom = LziApiScraper(primary: defaults.last, fallbacks: []);
    respond((o) {
      if (o.queryParameters['ac'] == 'list') {
        return {
          'code': 1,
          'class': [
            {'type_id': 40, 'type_name': '日韩动漫'},
            {'type_id': 50, 'type_name': '喜剧'},
          ],
        };
      }
      return _list([_video(1)]);
    });

    expect(await custom.getCategories(), ['全部', '日韩动漫', '喜剧']);
    expect((await custom.getByCategory('喜剧')).single.id, '360zy:1');
    expect(adapter.requests.last.queryParameters['t'], '50');
    expect((await custom.getByCategory('全部')).single.id, '360zy:1');
    expect(adapter.requests.last.queryParameters, isNot(contains('t')));
    expect(adapter.requests.length, 3);
  });
  test('父分类汇总有内容的子分类，分页使用相同来源和上游页码', () async {
    final custom = LziApiScraper(
      primary: SourceConfig.defaults().last,
      fallbacks: [],
    );
    respond((request) {
      if (request.queryParameters['ac'] == 'list') {
        return {
          'code': 1,
          'class': [
            {'type_id': 4, 'type_name': '动漫', 'type_pid': 0},
            {'type_id': 38, 'type_name': '国产动漫', 'type_pid': '4'},
            {'type_id': '39', 'type_name': '日韩动漫', 'type_pid': 4},
            {'type_id': 40, 'type_name': '剧场版', 'type_pid': 39},
            {'type_id': 3, 'type_name': '综艺', 'type_pid': 0},
            {'type_id': 37, 'type_name': '欧美综艺', 'type_pid': 3},
          ],
        };
      }
      final category = request.queryParameters['t'];
      final page = request.queryParameters['pg'];
      switch ((category, page)) {
        case ('38', 1):
          return _list([
            {..._video(380), 'type_id': 38, 'vod_time': '2026-11-23 13:00:00'},
          ]);
        case ('39', 1):
          return _list([
            {..._video(390), 'type_id': 39, 'vod_time': '2026-11-23 15:00:00'},
          ]);
        case ('40', 2):
          return _list([_video(402)]);
        case ('37', _):
          fail('请求了无关分类');
        default:
          return _list([]);
      }
    });

    expect((await custom.getByCategory('动漫')).map((video) => video.id), [
      '360zy:390',
      '360zy:380',
    ]);
    expect((await custom.getByCategory('动漫', page: 2)).single.id, '360zy:402');
    expect(await custom.getByCategory('动漫', page: 3), isEmpty);
    expect((await custom.getByCategory('国产动漫')).single.id, '360zy:380');
    expect(
      adapter.requests.every((req) => req.uri.host == '360zy.com'),
      isTrue,
    );
  });

  test('上游已经汇总子分类时沿用其分页', () async {
    final custom = LziApiScraper(
      primary: SourceConfig.defaults().last,
      fallbacks: [],
    );
    respond((request) {
      if (request.queryParameters['ac'] == 'list') {
        return {
          'code': 1,
          'class': [
            {'type_id': 4, 'type_name': '动漫', 'type_pid': 0},
            {'type_id': 38, 'type_name': '国产动漫', 'type_pid': 4},
          ],
        };
      }
      expect(request.queryParameters['t'], '4');
      return _list([
        {..._video(381), 'type_id': 38},
      ]);
    });
    expect((await custom.getByCategory('动漫')).single.id, '360zy:381');
    expect(adapter.requests, hasLength(2));
  });
  test('带来源 ID 的详情只请求对应源', () async {
    respond((o) {
      expect(o.uri.host, '360zy.com');
      expect(o.queryParameters['ids'], '900');
      return _list([_video(900)]);
    });
    expect((await scraper.getDetail('360zy:900')).id, '360zy:900');
    expect(adapter.requests.length, 1);
  });
  test('主源 ID 失败不能拿同一个数字请求备用源', () async {
    respond(_fail);
    await expectLater(scraper.getDetail('1'), throwsException);
    expect(adapter.requests.length, 1);
  });
  test('备用播放地址不改变作品与剧集身份', () async {
    respond(
      (o) => _list([
        o.uri.host == 'cj.lziapi.com'
            ? _video(1)
            : _video(900, host: 'vod1.maowushi.com'),
      ]),
    );
    final result = await scraper.getDetail('1');
    expect(result.id, '1');
    expect(result.source, 'LziApi');
    expect(result.episodes!.single.id, 'ep_1');
    expect(result.episodes!.single.playUrl, contains('vod1.maowushi.com'));
  });
  for (final candidate in [
    _video(900, title: '番剧 第二季', host: 'vod1.maowushi.com'),
    _video(900, year: '2025', host: 'vod1.maowushi.com'),
    _video(900, year: '', host: 'vod1.maowushi.com'),
  ]) {
    test(
      '拒绝不确定的同名作品匹配: ${candidate['vod_name']} ${candidate['vod_year']}',
      () async {
        respond(
          (o) => _list([o.uri.host == 'cj.lziapi.com' ? _video(1) : candidate]),
        );
        expect(
          (await scraper.getDetail('1')).episodes!.single.playUrl,
          contains('slow.example'),
        );
      },
    );
  }
  test('详情备用请求失败仍保留可用主源', () async {
    respond(
      (o) => o.uri.host == 'cj.lziapi.com' ? _list([_video(1)]) : _fail(o),
    );
    expect((await scraper.getDetail('1')).id, '1');
  });
  test('详情兼容字符串成功状态', () async {
    respond(
      (o) => {
        'code': '1',
        'list': [_video(1, host: 'vod1.maowushi.com')],
      },
    );
    expect((await scraper.getDetail('1')).id, '1');
  });
  test('详情不接受与请求 ID 不一致的作品', () async {
    respond((o) => _list([_video(2)]));
    await expectLater(scraper.getDetail('1'), throwsException);
    expect(adapter.requests.length, 1);
  });
  test('未知来源不发出请求', () async {
    respond((o) => _list([]));
    await expectLater(scraper.getDetail('unknown:1'), throwsException);
    expect(adapter.requests, isEmpty);
  });
  test('裸数字 ID 不会请求已禁用或缺失的 LziApi', () async {
    final defaults = SourceConfig.defaults();
    final custom = LziApiScraper(
      primary: defaults.last,
      fallbacks: [defaults.first.copyWith(enabled: false)],
    );
    respond((_) => _list([_video(1)]));

    await expectLater(custom.getDetail('1'), throwsException);
    await expectLater(custom.getDetail('lziapi:1'), throwsException);
    expect(adapter.requests, isEmpty);
  });
  test('已禁用的当前源不会收到分类请求', () async {
    final disabled = LziApiScraper(
      primary: SourceConfig.defaults().last.copyWith(enabled: false),
      fallbacks: [],
    );
    respond((_) => _list([]));

    expect(await disabled.getCategories(), ['全部']);
    expect(adapter.requests, isEmpty);
  });
  test('以原来源查询旧裸数字 ID 只请求对应来源', () async {
    respond((o) => _list([_video(1, host: o.uri.host)]));
    final detail = await scraper.getDetailFromSource('360zy', '1');
    expect(detail.id, '360zy:1');
    expect(detail.episodes!.single.playUrl, 'https://360zy.com/1.m3u8');
    expect(adapter.requests.single.uri.host, '360zy.com');
  });
  test('关闭备用详情替换后只请求作品所属源', () async {
    final scoped = LziApiScraper(allowDetailPlaybackSubstitution: false);
    respond((o) => _list([_video(1, host: o.uri.host)]));

    final detail = await scoped.getDetail('1');
    expect(detail.episodes!.single.playUrl, 'https://cj.lziapi.com/1.m3u8');
    expect(adapter.requests.single.uri.host, 'cj.lziapi.com');
  });
  test('关闭列表回退后仍能按作品 ID 查询备用源', () async {
    final scoped = LziApiScraper(allowListFallback: false);
    respond((o) {
      if (o.uri.host == 'cj.lziapi.com') return _fail(o);
      return _list([_video(1)]);
    });

    await expectLater(scoped.search('番剧'), throwsException);
    expect(adapter.requests.single.uri.host, 'cj.lziapi.com');
    expect((await scoped.getDetail('360zy:1')).id, '360zy:1');
    expect(adapter.requests.last.uri.host, '360zy.com');
  });
  test('切换剧集地址时保持主源剧集顺序', () async {
    respond((o) {
      final primary = o.uri.host == 'cj.lziapi.com';
      return _list([
        {
          ..._video(primary ? 1 : 900),
          'vod_play_url':
              primary
                  ? r'第1集$https://slow.example/1.m3u8#第2集$https://slow.example/2.m3u8'
                  : r'第2集$https://vod1.maowushi.com/2.m3u8#第1集$https://vod1.maowushi.com/1.m3u8',
        },
      ]);
    });
    final episodes = (await scraper.getDetail('1')).episodes!;
    expect(episodes.map((e) => e.id), ['ep_1', 'ep_2']);
    expect(episodes.map((e) => e.title), ['第1集', '第2集']);
    expect(episodes.map((e) => e.playUrl), [
      'https://vod1.maowushi.com/1.m3u8',
      'https://vod1.maowushi.com/2.m3u8',
    ]);
  });
  test('备用源剧集缺失时保持主源列表', () async {
    respond(
      (o) => _list([
        o.uri.host == 'cj.lziapi.com'
            ? {
              ..._video(1),
              'vod_play_url':
                  r'第1集$https://slow.example/1.m3u8#第2集$https://slow.example/2.m3u8',
            }
            : _video(900, host: 'vod1.maowushi.com'),
      ]),
    );
    final episodes = (await scraper.getDetail('1')).episodes!;
    expect(episodes.length, 2);
    expect(episodes.first.playUrl, contains('slow.example'));
  });
}
