import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_model.dart';
import '../services/database_service.dart';
import '../services/scraper/base_scraper.dart';
import '../services/scraper/source_identity.dart';
import 'scraper_provider.dart';

/// 首页视频列表状态
class VideoListState {
  final List<VideoModel> videos;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  VideoListState({
    this.videos = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  VideoListState copyWith({
    List<VideoModel>? videos,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
    bool clearError = false,
  }) {
    return VideoListState(
      videos: videos ?? this.videos,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 首页视频列表 Notifier
class VideoListNotifier extends StateNotifier<VideoListState> {
  final BaseScraper _scraper;
  int _requestId = 0;

  VideoListNotifier(this._scraper) : super(VideoListState()) {
    loadVideos();
  }

  Future<void> loadVideos() async {
    if (state.isLoading) return;
    await refresh();
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    final requestId = _requestId;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final nextPage = state.currentPage + 1;
      final videos = await _scraper.getHome(page: nextPage);
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(
        videos: [...state.videos, ...videos],
        isLoading: false,
        hasMore: videos.isNotEmpty,
        currentPage: nextPage,
      );
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    final requestId = ++_requestId;
    state = VideoListState(isLoading: true);
    try {
      final videos = await _scraper.getHome(page: 1);
      if (!mounted || requestId != _requestId) return;
      state = VideoListState(
        videos: videos,
        isLoading: false,
        hasMore: videos.isNotEmpty,
        currentPage: 1,
      );
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      state = VideoListState(isLoading: false, error: e.toString());
    }
  }
}

/// 首页视频列表 Provider
final videoListProvider =
    StateNotifierProvider<VideoListNotifier, VideoListState>((ref) {
      final scraper = ref.watch(currentScraperProvider);
      return VideoListNotifier(scraper);
    });

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
