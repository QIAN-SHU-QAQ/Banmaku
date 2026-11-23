import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_model.dart';
import '../services/bangumi_api.dart';
import 'bangumi_provider.dart';

final discoveryCategories = List<String>.unmodifiable([
  '全部',
  ...BangumiApi.browseTags.keys,
]);

typedef DiscoveryPageLoader =
    Future<List<VideoModel>> Function(String category, {int page});

final discoveryPageLoaderProvider = Provider<DiscoveryPageLoader>(
  (ref) => ref.watch(bangumiApiProvider).browseCatalog,
);

/// 当前选中的分类；'全部' 表示首页默认推荐流
final selectedCategoryProvider = StateProvider<String>((ref) => '全部');

/// 分类筛选结果（支持无限滚动分页）
class CategoryFeedState {
  final String category;
  final List<VideoModel> videos;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? error;

  const CategoryFeedState({
    required this.category,
    this.videos = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.error,
  });

  CategoryFeedState copyWith({
    List<VideoModel>? videos,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? error,
    bool clearError = false,
  }) {
    return CategoryFeedState(
      category: category,
      videos: videos ?? this.videos,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CategoryFeedNotifier extends StateNotifier<CategoryFeedState> {
  CategoryFeedNotifier(this._loadPage, String category)
    : super(CategoryFeedState(category: category)) {
    loadMore();
  }

  final DiscoveryPageLoader _loadPage;
  int _requestId = 0;

  Future<void> loadMore() async {
    if (!mounted || state.isLoading || !state.hasMore) return;
    final requestId = _requestId;
    final requestedPage = state.page;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final videos = await _loadPage(state.category, page: requestedPage);
      if (!mounted || requestId != _requestId) return;
      final seen = state.videos.map((video) => video.id).toSet();
      state = state.copyWith(
        videos: [
          ...state.videos,
          ...videos.where((video) => seen.add(video.id)),
        ],
        isLoading: false,
        hasMore: videos.isNotEmpty,
        page: requestedPage + 1,
      );
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 刷新：丢弃已有结果，从第一页重新加载。
  Future<void> refresh() async {
    if (!mounted) return;
    _requestId++;
    state = CategoryFeedState(category: state.category);
    await loadMore();
  }
}

final categoryFeedProvider = StateNotifierProvider.family<
  CategoryFeedNotifier,
  CategoryFeedState,
  String
>((ref, category) {
  return CategoryFeedNotifier(ref.watch(discoveryPageLoaderProvider), category);
});
