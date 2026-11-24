import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/play_launcher.dart';
import '../../models/history_item.dart';
import '../../models/video_model.dart';
import '../../providers/home_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/scraper_provider.dart';
import '../../services/database_service.dart';
import '../../shared/widgets/desktop_page_header.dart';
import '../../shared/widgets/poster_card.dart';
import '../search/widgets/catalog_work_dialog.dart';
import 'widgets/category_tabs.dart';
import 'widgets/continue_watching_card.dart';
import 'widgets/discovery_hero.dart';
import 'widgets/video_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter >= 200) return;
    final category = ref.read(selectedCategoryProvider);
    ref.read(categoryFeedProvider(category).notifier).loadMore();
  }

  Future<void> _refresh() {
    final category = ref.read(selectedCategoryProvider);
    return ref.read(categoryFeedProvider(category).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final state = ref.watch(categoryFeedProvider(selectedCategory));
    final history = ref.watch(historyProvider);
    final colors = Theme.of(context).colorScheme;
    return DesktopPage(
      title: '发现',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.push('/search'),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('搜索作品'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/schedule'),
          icon: const Icon(Icons.calendar_today_outlined, size: 17),
          label: const Text('新番时间表'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
          ),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final inset = compact ? 16.0 : 24.0;
            final all = selectedCategory == '全部';
            return CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child:
                      all && state.videos.isNotEmpty
                          ? DiscoveryHero(
                            videos: state.videos,
                            padding: EdgeInsets.fromLTRB(inset, 14, inset, 4),
                            onOpen: (video) => showCatalogWork(context, video),
                          )
                          : const SizedBox.shrink(),
                ),
                if (history.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _continueWatching(
                      context,
                      history,
                      inset: inset,
                      cardWidth: compact ? 282 : 320,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, 17, inset, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(context, '片库'),
                        const SizedBox(height: 8),
                        CategoryTabs(
                          categories: discoveryCategories,
                          selectedCategory: selectedCategory,
                          onCategorySelected: (category) {
                            ref.read(selectedCategoryProvider.notifier).state =
                                category;
                            if (_scrollController.hasClients) {
                              _scrollController.jumpTo(0);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                _feed(state, inset),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Semantics(
    header: true,
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _continueWatching(
    BuildContext context,
    List<HistoryItem> history, {
    required double inset,
    required double cardWidth,
  }) {
    final extraLineHeight = (MediaQuery.textScalerOf(context).scale(18) - 18)
        .clamp(0.0, double.infinity);
    final scrollBehavior = ScrollConfiguration.of(context);
    final sources = ref.watch(sourceConfigsProvider);
    final database = DatabaseService();
    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 5),
            child: Row(
              children: [
                Expanded(child: _sectionTitle(context, '继续观看')),
                TextButton(
                  onPressed: () => context.go('/history'),
                  child: const Text('观看记录'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 115 + extraLineHeight * 4,
            child: ScrollConfiguration(
              behavior: scrollBehavior.copyWith(
                dragDevices: {
                  ...scrollBehavior.dragDevices,
                  PointerDeviceKind.mouse,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: inset),
                itemCount: history.take(12).length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = history[index];
                  final sourceId = database.sourceIdForHistory(item);
                  final configuredName =
                      sources
                          .where((source) => source.id == sourceId)
                          .firstOrNull
                          ?.name;
                  return SizedBox(
                    width: cardWidth,
                    child: ContinueWatchingCard(
                      item: item,
                      sourceName: configuredName ?? item.sourceId,
                      onTap: () => resumeFromOriginalSource(context, ref, item),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feed(CategoryFeedState state, double inset) {
    final notifier = ref.read(categoryFeedProvider(state.category).notifier);
    if (state.isLoading && state.videos.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null && state.videos.isEmpty) {
      return _message('作品库加载失败', onRetry: notifier.loadMore);
    }
    if (state.videos.isEmpty) {
      return _message('暂无内容', onRetry: notifier.refresh);
    }
    return SliverMainAxisGroup(
      slivers: [
        _grid(state.videos, inset),
        if (state.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (state.error != null)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                onPressed: notifier.loadMore,
                child: const Text('加载更多失败，重试'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid(List<VideoModel> videos, double inset) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      sliver: SliverLayoutBuilder(
        builder:
            (context, constraints) => SliverGrid(
              gridDelegate: posterGridDelegate(
                context,
                constraints.crossAxisExtent,
                maxTileWidth: 185,
                spacing: 16,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final video = videos[index];
                return VideoCard(
                  video: video,
                  onTap: () => showCatalogWork(context, video),
                );
              }, childCount: videos.length),
            ),
      ),
    );
  }

  Widget _message(String title, {required VoidCallback onRetry}) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
