import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/network/http_client.dart';
import '../models/video_model.dart';
import 'm3u8/m3u8_parser.dart';

enum PlaybackSourceStatus { available, unavailable, noAddress, timedOut }

const _sampleSize = 1024;
const _playlistLimit = 256 * 1024;
final _markupStart = RegExp(r'^<(?:!doctype|html|head|body|script|\?xml)');

/// 抽查片源首个剧集。HLS 继续读取一个媒体分片，直链只读取文件开头。
Future<PlaybackSourceStatus> probePlaybackSource(
  VideoModel video,
  CancelToken token,
) async {
  final first = video.episodes?.firstOrNull;
  final uri = Uri.tryParse(first?.playUrl ?? first?.url ?? '');
  if (uri == null || !_isHttp(uri)) return PlaybackSourceStatus.noAddress;

  try {
    final accessible = await _probe(uri, token).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        token.cancel();
        throw TimeoutException('播放地址检测超时');
      },
    );
    return accessible
        ? PlaybackSourceStatus.available
        : PlaybackSourceStatus.unavailable;
  } on TimeoutException {
    return PlaybackSourceStatus.timedOut;
  } on DioException catch (error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout => PlaybackSourceStatus.timedOut,
      _ => PlaybackSourceStatus.unavailable,
    };
  } on Exception {
    return PlaybackSourceStatus.unavailable;
  }
}

bool _isHttp(Uri uri) =>
    uri.host.isNotEmpty && (uri.isScheme('http') || uri.isScheme('https'));

Future<bool> _probe(Uri uri, CancelToken token) async {
  final response = await _fetch(uri, token);
  if (!uri.path.toLowerCase().endsWith('.m3u8') &&
      !response.realUri.path.toLowerCase().endsWith('.m3u8') &&
      !_contentType(response).contains('mpegurl')) {
    return _hasSample(response, segment: false);
  }

  var playlist = await _readPlaylist(response);
  if (playlist.isMaster) {
    final variant = await _fetch(Uri.parse(playlist.variants.first.url), token);
    playlist = await _readPlaylist(variant);
  }
  if (playlist.segments.isEmpty) return false;
  final segment = await _fetch(
    Uri.parse(playlist.segments.first.url),
    token,
    sample: true,
  );
  return _hasSample(segment, segment: true);
}

Future<Response<ResponseBody>> _fetch(
  Uri uri,
  CancelToken token, {
  bool sample = false,
}) {
  if (!_isHttp(uri)) throw const FormatException('无效的播放地址');
  return HttpClient().get<ResponseBody>(
    uri.toString(),
    cancelToken: token,
    options: Options(
      responseType: ResponseType.stream,
      receiveDataWhenStatusError: false,
      headers: sample ? {'range': 'bytes=0-1023'} : null,
    ),
  );
}

String _contentType(Response<ResponseBody> response) =>
    response.headers[Headers.contentTypeHeader]?.firstOrNull?.toLowerCase() ??
    '';

Future<M3u8Playlist> _readPlaylist(Response<ResponseBody> response) async {
  final bytes = await _readPrefix(response, _playlistLimit);
  final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
  if (!text.startsWith('#EXTM3U')) {
    throw M3u8FormatException('不是有效的 m3u8 播放列表');
  }
  return M3u8Parser.parse(text, baseUrl: response.realUri.toString());
}

Future<bool> _hasSample(
  Response<ResponseBody> response, {
  required bool segment,
}) async {
  final bytes = await _readPrefix(response, _sampleSize);
  if (bytes.isEmpty) return false;
  final type = _contentType(response);
  final prefix =
      ascii
          .decode(bytes.take(32).toList(), allowInvalid: true)
          .trimLeft()
          .toLowerCase();
  if (type.contains('html') ||
      type.contains('json') ||
      type.contains('xml') ||
      _markupStart.hasMatch(prefix)) {
    return false;
  }
  if (segment || type.startsWith('video/') || type.startsWith('audio/')) {
    // 错误页也可能返回 200。视频分片和音视频容器都有二进制字节。
    return bytes.any(
      (byte) => byte < 32 && byte != 9 && byte != 10 && byte != 13,
    );
  }
  // 部分直链 CDN 使用 application/octet-stream。
  return (bytes.length >= 8 &&
          ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') ||
      (bytes.length > 188 && bytes[0] == 0x47 && bytes[188] == 0x47);
}

Future<Uint8List> _readPrefix(
  Response<ResponseBody> response,
  int limit,
) async {
  final bytes = BytesBuilder(copy: false);
  final body = response.data;
  if (body != null) {
    await for (final chunk in body.stream) {
      final remaining = limit - bytes.length;
      if (chunk.length >= remaining) {
        bytes.add(Uint8List.sublistView(chunk, 0, remaining));
        break;
      }
      bytes.add(chunk);
    }
  }
  return bytes.takeBytes();
}
