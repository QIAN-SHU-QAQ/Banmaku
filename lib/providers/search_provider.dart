import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_model.dart';
import '../services/scraper/base_scraper.dart';
import '../services/scraper/lziapi_scraper.dart';
import '../services/scraper/source_config.dart';
import 'bangumi_provider.dart';
import 'scraper_provider.dart';

enum SearchMode { catalog, source, strictSource, allSources }

class SearchPage {
  const SearchPage(this.results, {this.failedSources = const []});

  final List<VideoModel> results;
  final List<String> failedSources;
}

typedef SearchPageLoader =
    Future<SearchPage> Function(String keyword, {int page});

final playbackSearchPageLoaderProvider = Provider<SearchPageLoader>((ref) {
  final sources = ref.watch(enabledSourcesProvider);
  final scrapers = [
    for (final source in sources)
      LziApiScraper(
        primary: source,
        fallbacks: const [],
        allowListFallback: false,
        allowDetailPlaybackSubstitution: false,
        animeCatalogOnly: true,
      ),
  ];
  return (keyword, {page = 1}) async {
    if (scrapers.isEmpty) {
      throw ScraperException('请在设置中启用至少一个片源。');
    }
    final responses = await Future.wait(
      scrapers.map((scraper) async {
        try {
          final results = await scraper
              .searchPlayable(keyword, page: page)
              .timeout(const Duration(seconds: 10));
          return (results: results, failure: null);
        } catch (_) {
          return (results: <VideoModel>[], failure: scraper.name);
        }
      }),
    );
    final failures =
        responses
            .map((response) => response.failure)
            .whereType<String>()
            .toList();
    if (failures.length == scrapers.length) {
      throw ScraperException('所有启用的片源查询失败，请稍后重试。');
    }
    final matching = <VideoModel>[];
    final related = <VideoModel>[];
    final query = keyword.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    for (final response in responses) {
      for (final video in response.results) {
        final title = video.title.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        (title.contains(query) ? matching : related).add(video);
      }
    }
    return SearchPage([...matching, ...related], failedSources: failures);
  };
});

/// 搜索状态（支持无限滚动分页）
class SearchState {
  final List<VideoModel> results;
  final bool isLoading;
  final String keyword;
  final int page;
  final bool hasMore;
  final String? error;
  final List<String> failedSources;

  SearchState({
    this.results = const [],
    this.isLoading = false,
    this.keyword = '',
    this.page = 1,
    this.hasMore = true,
    this.error,
    this.failedSources = const [],
  });

  SearchState copyWith({
    List<VideoModel>? results,
    bool? isLoading,
    String? keyword,
    int? page,
    bool? hasMore,
    String? error,
    bool clearError = false,
    List<String>? failedSources,
  }) {
    return SearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      keyword: keyword ?? this.keyword,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      failedSources: failedSources ?? this.failedSources,
    );
  }
}

/// 搜索 Notifier
class SearchNotifier extends StateNotifier<SearchState> {
  final SearchPageLoader _loadPage;
  int _requestId = 0;

  SearchNotifier(BaseScraper scraper) : this.withLoader(scraper.search);

  SearchNotifier.withLoader(
    Future<List<VideoModel>> Function(String keyword, {int page}) load,
  ) : this.withPages(
        (keyword, {page = 1}) async =>
            SearchPage(await load(keyword, page: page)),
      );

  SearchNotifier.withPages(this._loadPage) : super(SearchState());

  Future<void> search(String keyword) async {
    final query = keyword.trim();
    if (!mounted || query.isEmpty) return;

    final requestId = ++_requestId;
    state = SearchState(isLoading: true, keyword: query);

    try {
      final page = await _loadPage(query, page: 1);
      // Older requests can still complete after a new search, clear or disposal.
      if (!mounted || requestId != _requestId) return;
      state = SearchState(
        results: page.results,
        isLoading: false,
        keyword: query,
        page: 2,
        hasMore: page.results.isNotEmpty,
        failedSources: page.failedSources,
      );
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 加载下一页结果并追加（供列表滚到底部时调用）。
  Future<void> loadMore() async {
    if (!mounted || state.isLoading || !state.hasMore) return;
    final keyword = state.keyword;
    if (keyword.isEmpty) return;

    final requestId = _requestId;
    final requestedPage = state.page;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final page = await _loadPage(keyword, page: requestedPage);
      if (!mounted || requestId != _requestId) return;
      final seen = state.results.map((result) => result.id).toSet();
      state = state.copyWith(
        results: [
          ...state.results,
          ...page.results.where((result) => seen.add(result.id)),
        ],
        isLoading: false,
        hasMore: page.results.isNotEmpty,
        failedSources: {...state.failedSources, ...page.failedSources}.toList(),
        page: requestedPage + 1,
      );
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() {
    if (!mounted) return;
    _requestId++;
    state = SearchState();
  }
}

/// 每次打开搜索都创建独立的查询和分页状态。
final searchProvider = StateNotifierProvider.autoDispose
    .family<SearchNotifier, SearchState, ({Object session, SearchMode mode})>((
      ref,
      args,
    ) {
      if (args.mode == SearchMode.catalog) {
        return SearchNotifier.withLoader(
          ref.watch(bangumiApiProvider).searchCatalog,
        );
      }
      if (args.mode == SearchMode.allSources) {
        return SearchNotifier.withPages(
          ref.watch(playbackSearchPageLoaderProvider),
        );
      }
      final scraper = ref.watch(currentScraperProvider);
      return SearchNotifier(
        args.mode == SearchMode.strictSource &&
                scraper is LziApiScraper &&
                scraper.allowListFallback
            ? LziApiScraper(
              primary: scraper.primary,
              fallbacks: const [],
              allowListFallback: false,
              allowDetailPlaybackSubstitution: false,
              animeCatalogOnly: scraper.animeCatalogOnly,
            )
            : scraper,
      );
    });
