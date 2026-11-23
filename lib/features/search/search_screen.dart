import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/video_model.dart';
import '../../providers/scraper_provider.dart';
import '../../providers/search_provider.dart';
import '../../services/database_service.dart';
import '../../services/scraper/base_scraper.dart';
import '../../shared/widgets/desktop_page_header.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/source_picker.dart';
import 'playback_search_groups.dart';
import 'widgets/catalog_work_dialog.dart';
import 'widgets/playback_source_dialog.dart';
import 'widgets/search_result_preview.dart';

/// 全屏搜索页（覆盖整个窗口，不走 Rail shell）：
/// 搜索框 + 筛选 chips + 结果计数 + 海报/列表视图切换。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.initialKeyword,
    this.recoverySearch = true,
    this.catalogSearch = false,
    this.allSources = false,
  });

  final String? initialKeyword;
  final bool recoverySearch;
  final bool catalogSearch;
  final bool allSources;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final List<String> _searchHistory = [];
  final List<String> _hotSearches = ['鬼灭之刃', '进击的巨人', '咒术回战', '间谍过家家', '电锯人'];

  bool _showAsGrid = true;
  String? _resultFilter;
  ({String id, BaseScraper? scraper})? _selection;
  String _submittedKeyword = '';
  int _queryRevision = 0;

  bool get _isSourceRecovery =>
      !widget.catalogSearch &&
      widget.initialKeyword != null &&
      widget.recoverySearch;
  bool get _canQuickPlay =>
      !widget.catalogSearch && !widget.allSources && !_isSourceRecovery;
  String? get _selectedId => _selection?.id;

  late final _search = searchProvider((
    session: this,
    mode:
        widget.catalogSearch
            ? SearchMode.catalog
            : widget.allSources
            ? SearchMode.allSources
            : _isSourceRecovery
            ? SearchMode.strictSource
            : SearchMode.source,
  ));
  ProviderListenable<SearchNotifier> get _searchNotifier => _search.notifier;

  @override
  void initState() {
    super.initState();
    _submittedKeyword = widget.initialKeyword?.trim() ?? '';
    _searchController.text = _submittedKeyword;
    _searchHistory.addAll(DatabaseService().getSearchHistory());
    if (widget.initialKeyword != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _performSearch(_submittedKeyword);
      });
    }
    if (widget.catalogSearch) return;
    ref.listenManual(_searchNotifier, (_, notifier) {
      final query = _submittedKeyword;
      if (query.isEmpty) return;
      Future.microtask(() {
        if (!mounted ||
            _submittedKeyword != query ||
            !identical(ref.read(_searchNotifier), notifier)) {
          return;
        }
        setState(_resetResultsView);
        notifier.search(query);
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _clearSearch();
      return;
    }

    _searchFocus.unfocus();

    // 添加到搜索历史（本地展示 + 持久化）
    setState(() {
      _submittedKeyword = trimmed;
      _resetResultsView();
      _searchHistory.remove(trimmed);
      _searchHistory.insert(0, trimmed);
      if (_searchHistory.length > 10) {
        _searchHistory.removeLast();
      }
    });
    DatabaseService().addSearchHistory(trimmed);

    ref.read(_searchNotifier).search(trimmed);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _submittedKeyword = '';
      _resetResultsView();
    });
    ref.read(_searchNotifier).clear();
  }

  void _resetResultsView() {
    _resultFilter = null;
    _selection = null;
    _queryRevision++;
  }

  void _setResultFilter(String? filter) {
    final selectedId = _selectedId;
    setState(() {
      _resultFilter = filter;
      if (selectedId != null &&
          !ref
              .read(_search)
              .results
              .any(
                (video) =>
                    video.id == selectedId && _matchesFilter(video, filter),
              )) {
        _selection = null;
      }
    });
  }

  bool _matchesFilter(VideoModel video, String? filter) {
    if (filter == null) return true;
    return (video.genre ?? '')
        .split(RegExp(r'[,，/、|]'))
        .any((part) => part.trim() == filter);
  }

  /// 从结果的 genre 字段提取筛选项（去重，保序，最多 10 个）
  List<String> _extractGenres(List<VideoModel> results) {
    final genres = <String>{};
    for (final video in results) {
      final genre = video.genre;
      if (genre == null || genre.isEmpty) continue;
      for (final part in genre.split(RegExp(r'[,，/、|]'))) {
        final g = part.trim();
        if (g.isNotEmpty) genres.add(g);
        if (genres.length >= 10) return genres.toList();
      }
    }
    return genres.toList();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(_search);
    final colorScheme = Theme.of(context).colorScheme;

    final groups =
        widget.allSources
            ? groupPlaybackSearchResults(searchState.results)
            : const <String, List<VideoModel>>{};
    final results =
        widget.allSources
            ? groups.values.map((versions) => versions.first).toList()
            : searchState.results;
    final filters =
        widget.allSources ? const <String>[] : _extractGenres(results);
    if (_resultFilter != null && !filters.contains(_resultFilter)) {
      _resultFilter = null;
    }
    final filtered =
        _resultFilter == null
            ? results
            : results
                .where((video) => _matchesFilter(video, _resultFilter))
                .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DesktopPageHeader(
              title: widget.catalogSearch ? '作品搜索' : '片源搜索',
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回',
                onPressed:
                    () => context.canPop() ? context.pop() : context.go('/'),
              ),
              toolbar: Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: _searchController,
                      builder:
                          (context, value, _) => TextField(
                            controller: _searchController,
                            autofocus: widget.initialKeyword == null,
                            focusNode: _searchFocus,
                            textInputAction: TextInputAction.search,
                            onSubmitted: _performSearch,
                            onChanged: (text) {
                              if (text.trim().isEmpty &&
                                  _submittedKeyword.isNotEmpty) {
                                _clearSearch();
                              }
                            },
                            decoration: InputDecoration(
                              hintText: '输入片名',
                              prefixIcon: const Icon(Icons.search),
                              isDense: true,
                              suffixIconConstraints:
                                  const BoxConstraints.tightFor(
                                    width: 40,
                                    height: 36,
                                  ),
                              suffixIcon:
                                  value.text.isEmpty
                                      ? null
                                      : IconButton(
                                        tooltip: '清空搜索',
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          _clearSearch();
                                          _searchFocus.requestFocus();
                                        },
                                      ),
                            ),
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _performSearch(_searchController.text),
                    child: const Text('搜索'),
                  ),
                  if (widget.catalogSearch)
                    OutlinedButton(
                      onPressed:
                          () =>
                              openSourceSearch(context, _searchController.text),
                      child: const Text('按片源搜索'),
                    )
                  else if (widget.allSources)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('全部已启用片源'),
                    )
                  else
                    const SourcePicker(),
                ],
              ),
            ),

            // 结果工具条：筛选 chips + 计数 + 视图切换
            if (searchState.results.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child:
                            filters.isEmpty
                                ? const SizedBox.shrink()
                                : ListView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FilterChip(
                                        showCheckmark: false,
                                        visualDensity: VisualDensity.compact,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        label: const Text('全部'),
                                        selected: _resultFilter == null,
                                        onSelected:
                                            (_) => _setResultFilter(null),
                                      ),
                                    ),
                                    for (final filter in filters)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: FilterChip(
                                          showCheckmark: false,
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          label: Text(filter),
                                          selected: _resultFilter == filter,
                                          onSelected:
                                              (selected) => _setResultFilter(
                                                selected ? filter : null,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                      ),
                    ),
                    Text(
                      '共 ${filtered.length} ${widget.allSources ? '部作品' : '条'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      tooltip: _showAsGrid ? '列表视图' : '海报视图',
                      icon: Icon(
                        _showAsGrid
                            ? Icons.view_list_outlined
                            : Icons.grid_view_outlined,
                      ),
                      onPressed:
                          () => setState(() => _showAsGrid = !_showAsGrid),
                    ),
                  ],
                ),
              ),
            ],

            if (searchState.failedSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '查询失败：${searchState.failedSources.join('、')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _performSearch(_submittedKeyword),
                      child: const Text('重新查询'),
                    ),
                  ],
                ),
              ),

            Expanded(
              child:
                  searchState.isLoading && searchState.results.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : searchState.results.isNotEmpty
                      ? _buildResults(filtered, searchState, groups)
                      : searchState.error != null
                      ? _buildError(context, searchState.error!)
                      : searchState.keyword.isNotEmpty
                      ? _buildNoResults(context, searchState.keyword)
                      : _buildSearchSuggestions(context),
            ),
            if (searchState.isLoading && searchState.results.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2)
            else if (searchState.error != null &&
                searchState.results.isNotEmpty)
              TextButton(
                onPressed: ref.read(_searchNotifier).loadMore,
                child: const Text('加载更多失败，重试'),
              )
            else if (widget.allSources &&
                searchState.hasMore &&
                searchState.results.isNotEmpty)
              TextButton(
                onPressed: ref.read(_searchNotifier).loadMore,
                child: const Text('加载更多作品'),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- 结果视图 ----------

  Widget _buildResults(
    List<VideoModel> results,
    SearchState state,
    Map<String, List<VideoModel>> groups,
  ) {
    final selection = _selection;
    final selected =
        results.where((video) => video.id == selection?.id).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canPreview = !widget.allSources && constraints.maxWidth >= 1120;
        void open(VideoModel video) {
          final versions = groups[video.id];
          if (versions != null) {
            _choosePlaybackSource(versions);
          } else {
            _openResult(video, canPreview: canPreview);
          }
        }

        final list = NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.axis == Axis.vertical &&
                notification.metrics.extentAfter < 400 &&
                !state.isLoading &&
                state.error == null &&
                state.hasMore &&
                state.keyword.isNotEmpty) {
              ref.read(_searchNotifier).loadMore();
            }
            return false;
          },
          child:
              results.isEmpty
                  ? Center(
                    child: Text(
                      '该筛选下暂无结果',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                  : _showAsGrid
                  ? _buildPosterGrid(
                    context,
                    results,
                    canPreview: canPreview,
                    onOpen: open,
                  )
                  : _buildResultList(
                    context,
                    results,
                    canPreview: canPreview,
                    onOpen: open,
                  ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            if (canPreview && selection != null && selected != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: (constraints.maxWidth / 3).clamp(360.0, 500.0),
                child: SearchResultPreview(
                  key: ValueKey(selected.id),
                  result: selected,
                  scraper: selection.scraper,
                  onOpenDetails: () => _openPreviewTarget(selected),
                  onClose: () => setState(() => _selection = null),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _choosePlaybackSource(List<VideoModel> versions) async {
    final selected = await choosePlaybackSource(context, versions);
    if (mounted && selected != null) _openDetails(selected);
  }

  void _openResult(VideoModel video, {required bool canPreview}) {
    if (canPreview) {
      setState(() {
        _selection = (
          id: video.id,
          scraper:
              widget.catalogSearch ? null : ref.read(currentScraperProvider),
        );
      });
    } else if (widget.catalogSearch) {
      showCatalogWork(context, video);
    } else {
      _openDetails(video);
    }
  }

  void _openPreviewTarget(VideoModel video) {
    if (widget.catalogSearch) {
      openSourceSearch(context, video.title, fromCatalog: true);
    } else {
      _openDetails(video);
    }
  }

  void _openDetails(VideoModel video, {bool play = false}) {
    final path = '/detail/${Uri.encodeComponent(video.id)}';
    final query =
        _isSourceRecovery ? '?chooseEpisode=1' : (play ? '?play=1' : '');
    context.push('$path$query');
  }

  Widget _buildNoResults(BuildContext context, String keyword) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 28,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text('未找到相关动漫'),
            const SizedBox(height: 8),
            Text(
              widget.catalogSearch
                  ? '作品库没有找到“$keyword”。可以试试别名、原名，或按片源搜索。'
                  : widget.allSources
                  ? '已响应的片源未找到“$keyword”的剧集地址。可以试试其他名称。'
                  : '当前片源未找到“$keyword”。可以切换片源，或试试其他名称。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterGrid(
    BuildContext context,
    List<VideoModel> results, {
    required bool canPreview,
    required ValueChanged<VideoModel> onOpen,
  }) {
    final active = ref.watch(activeSourceConfigProvider);
    return LayoutBuilder(
      builder:
          (context, constraints) => GridView.builder(
            key: PageStorageKey(('search-grid', _queryRevision)),
            primary: false,
            padding: const EdgeInsets.all(16),
            gridDelegate: posterGridDelegate(
              context,
              constraints.maxWidth - 32,
              maxTileWidth: 180,
              spacing: 16,
            ),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final video = results[index];
              return PosterCard(
                key: ValueKey((video.id, index)),
                video: video,
                showSource:
                    !widget.allSources && isFromOtherSource(video, active),
                previewsOnEnter: canPreview,
                selected: canPreview && _selectedId == video.id,
                onTap: () => onOpen(video),
                onPlay:
                    _canQuickPlay
                        ? () => _openDetails(video, play: true)
                        : null,
              );
            },
          ),
    );
  }

  Widget _buildResultList(
    BuildContext context,
    List<VideoModel> results, {
    required bool canPreview,
    required ValueChanged<VideoModel> onOpen,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = ref.watch(activeSourceConfigProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView.separated(
          key: PageStorageKey(('search-list', _queryRevision)),
          primary: false,
          padding: const EdgeInsets.all(16),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final video = results[index];
            final cover = video.cover;
            final selected = canPreview && _selectedId == video.id;
            final showSource =
                !widget.allSources && isFromOtherSource(video, active);
            return Card(
              color: selected ? colorScheme.primaryContainer : null,
              child: Semantics(
                selected: canPreview ? selected : null,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onOpen(video),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Container(
                          width: 72,
                          height: 100,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child:
                              cover != null && cover.isNotEmpty
                                  ? CachedNetworkImage(
                                    imageUrl:
                                        cover.startsWith('http')
                                            ? cover
                                            : 'https://yhdm.me$cover',
                                    fit: BoxFit.cover,
                                    errorWidget:
                                        (context, url, error) => Icon(
                                          Icons.movie_outlined,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  )
                                  : Icon(
                                    Icons.movie_outlined,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (video.year != null ||
                                  video.genre != null ||
                                  (video.source != null && showSource))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    [
                                      if (showSource) video.source,
                                      video.year,
                                      video.genre,
                                    ].whereType<String>().join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              if (video.description != null &&
                                  video.description!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    video.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (canPreview && _canQuickPlay)
                          IconButton(
                            tooltip: '播放 ${video.title}',
                            onPressed: () => _openDetails(video, play: true),
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------- 建议页 ----------

  Widget _buildSearchSuggestions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_searchHistory.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '搜索历史',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _searchHistory.clear());
                      DatabaseService().clearSearchHistory();
                    },
                    child: Text(
                      '清除',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _searchHistory.map((query) {
                      return InputChip(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        label: Text(query),
                        onPressed: () {
                          _searchController.text = query;
                          _performSearch(query);
                        },
                        onDeleted: () {
                          setState(() => _searchHistory.remove(query));
                          _persistHistory();
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 28),
            ],
            Text(
              '热门搜索',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _hotSearches.asMap().entries.map((entry) {
                    final query = entry.value;
                    return ActionChip(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      label: Text(query),
                      onPressed: () {
                        _searchController.text = query;
                        _performSearch(query);
                      },
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// 单条删除后把剩余历史整体重写回 DB
  void _persistHistory() {
    DatabaseService().clearSearchHistory();
    for (final q in _searchHistory) {
      DatabaseService().addSearchHistory(q);
    }
  }

  // ---------- 错误 ----------

  Widget _buildError(BuildContext context, String error) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 28,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '搜索失败',
            style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            widget.catalogSearch ? '作品库暂时无法访问。' : error,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed:
                    () => ref.read(_searchNotifier).search(_submittedKeyword),
                child: const Text('重试'),
              ),
              if (!widget.catalogSearch && !widget.allSources)
                const SourcePicker(label: '切换片源'),
            ],
          ),
        ],
      ),
    );
  }
}
