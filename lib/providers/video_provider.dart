import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_model.dart';
import '../services/database_service.dart';
import '../services/scraper/base_scraper.dart';
import '../services/scraper/source_identity.dart';
import 'scraper_provider.dart';

/// 视频详情 Provider
final videoDetailProvider = FutureProvider.autoDispose
    .family<VideoModel, String>((ref, id) {
      final scraper = ref.watch(currentScraperProvider);
      return ref.watch(
        sourceVideoDetailProvider((scraper: scraper, id: id)).future,
      );
    });

/// 同一片源版本的预览和详情共用请求。切源后，旧预览不会主动发起新请求。
final sourceVideoDetailProvider = FutureProvider.autoDispose
    .family<VideoModel, ({BaseScraper scraper, String id})>(
      (ref, lookup) => lookup.scraper.getDetail(lookup.id),
    );

final savedVideoDetailProvider = FutureProvider.autoDispose
    .family<VideoModel, VideoModel>((ref, video) async {
      final fetch = ref.watch(originalSourceDetailProvider);
      final detail = await fetch(
        video.id,
        DatabaseService().sourceIdForFavorite(video),
      );
      if (decodeSourceVideoId(video.id) != null &&
          detail.title.trim().toLowerCase() !=
              video.title.trim().toLowerCase()) {
        throw StateError('原片源返回的作品与收藏不一致');
      }
      return detail;
    });

/// 视频播放地址 Provider
final playUrlsProvider = FutureProvider.family<List<String>, String>((
  ref,
  episodeUrl,
) async {
  final scraper = ref.watch(currentScraperProvider);
  return scraper.getPlayUrls(episodeUrl);
});
