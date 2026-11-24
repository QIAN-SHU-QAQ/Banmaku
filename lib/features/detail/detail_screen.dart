import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/utils/play_launcher.dart';
import '../../models/bangumi_info.dart';
import '../../models/video_model.dart';
import '../../providers/bangumi_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/scraper_provider.dart';
import '../../providers/video_provider.dart';
import '../../services/bangumi_api.dart';
import '../../services/database_service.dart';
import '../../shared/widgets/desktop_page_header.dart';
import '../../shared/widgets/source_picker.dart';
import 'widgets/bangumi_match_dialog.dart';
import 'widgets/subject_summary.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final String id;
  final bool autoplay;
  final bool chooseEpisode;
  final VideoModel? savedVideo;

  const DetailScreen({
    super.key,
    required this.id,
    this.autoplay = false,
    this.chooseEpisode = false,
    this.savedVideo,
  });

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  bool _autoplayTriggered = false;

  @override
  Widget build(BuildContext context) {
    final saved = widget.savedVideo;
    final provider =
        saved == null
            ? videoDetailProvider(widget.id)
            : savedVideoDetailProvider(saved);
    final videoDetail = ref.watch(provider);

    return DesktopPage(
      title: '作品详情',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: '返回',
        onPressed: () => context.canPop() ? context.pop() : context.go('/'),
      ),
      child: videoDetail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stack) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 28,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '加载失败',
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () {
                          if (saved == null) {
                            final scraper = ref.read(currentScraperProvider);
                            ref.invalidate(
                              sourceVideoDetailProvider((
                                scraper: scraper,
                                id: widget.id,
                              )),
                            );
                          }
                          ref.invalidate(provider);
                        },
                        child: const Text('重试'),
                      ),
                      if (saved != null)
                        OutlinedButton(
                          onPressed:
                              () => pickSourceForSearch(
                                context,
                                ref,
                                saved.title,
                              ),
                          child: const Text('切换片源'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        data: (video) {
          if (widget.autoplay &&
              !widget.chooseEpisode &&
              !_autoplayTriggered &&
              video.episodes?.isNotEmpty == true) {
            _autoplayTriggered = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  !widget.chooseEpisode &&
                  ModalRoute.of(context)?.isCurrent != false) {
                _playEpisode(video, 0);
              }
            });
          }
          return _buildDetail(video);
        },
      ),
    );
  }

  Widget _buildDetail(VideoModel video) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final query = BangumiQuery(videoId: video.id, title: video.title);
    final bangumiLookup = ref.watch(bangumiInfoProvider(query));
    final bangumi = bangumiLookup.valueOrNull?.info;
    ref.watch(historyProvider);
    ref.watch(favoritesProvider);
    final db = DatabaseService();
    final history = widget.chooseEpisode ? null : db.historyForVideo(video);
    final isFavorite = db.favoriteForVideo(video) != null;
    final episodes = video.episodes ?? const <EpisodeModel>[];
    final watchedIndex = history?.episodeIndex;
    final hasWatchedEpisode =
        watchedIndex != null &&
        watchedIndex >= 0 &&
        watchedIndex < episodes.length;
    final description = video.description?.trim() ?? '';
    final wide = MediaQuery.sizeOf(context).width >= 1200;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 4, wide ? 32 : 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            key: ValueKey(video.id),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubjectSummary(
                video: video,
                score: bangumi?.score,
                actions: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (history != null)
                      FilledButton.icon(
                        onPressed:
                            () =>
                                resumeFromOriginalSource(context, ref, history),
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('继续观看'),
                      ),
                    if (!widget.chooseEpisode)
                      FilledButton.icon(
                        style:
                            history == null
                                ? null
                                : FilledButton.styleFrom(
                                  backgroundColor: colors.secondaryContainer,
                                  foregroundColor: colors.onSecondaryContainer,
                                ),
                        onPressed:
                            episodes.isEmpty
                                ? null
                                : () => _playEpisode(video, 0),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('立即播放'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _toggleFavorite(video),
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? colors.error : null,
                      ),
                      label: Text(isFavorite ? '已收藏' : '收藏'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            episodes.isEmpty ? '选集' : '选集 (${episodes.length})',
                            style: theme.textTheme.titleLarge,
                          ),
                          if (widget.chooseEpisode)
                            Text(
                              '请重新选集',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.primary,
                              ),
                            )
                          else if (hasWatchedEpisode)
                            Text(
                              '看到第 ${watchedIndex + 1} 集',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (episodes.isEmpty)
                        Text('当前片源暂无剧集', style: theme.textTheme.bodySmall)
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < episodes.length; i++)
                              _EpisodeThumbCard(
                                title: episodes[i].title,
                                index: i,
                                isCurrent: i == watchedIndex,
                                onTap: () => _playEpisode(video, i),
                                onDownload: () => _downloadEpisode(video, i),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SubjectIntroduction(description: description),
              ],
              const SizedBox(height: 20),
              _buildBangumiStatus(video, query, bangumiLookup),
              if (bangumi != null) _buildBangumiDetails(video, bangumi, wide),
            ],
          ),
        ),
      ),
    );
  }

  /// Bangumi 资料状态与手动匹配入口。
  ///
  /// 无论自动匹配为空、资料服务不可用还是角色接口部分降级，这里都能显示
  /// 可操作的提示；宽/窄布局共用，避免窄屏只能在数据栏里找到手选入口。
  Widget _buildBangumiStatus(
    VideoModel video,
    BangumiQuery query,
    AsyncValue<BangumiLookupResult> async,
  ) {
    final lookup = async.valueOrNull;
    final colors = Theme.of(context).colorScheme;

    if (async.isLoading && lookup == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              '正在加载 Bangumi 资料…',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final unavailable =
        async.hasError ||
        lookup == null ||
        lookup.status == BangumiLookupStatus.unavailable;
    final noMatch = lookup?.status == BangumiLookupStatus.noMatch;
    final partial = lookup?.partial == true;
    final info = lookup?.info;
    // 只有角色资料（没有评分/制作人员）时，宽屏数据栏与窄屏展开区都不会
    // 出现手选入口；这里单独提供，避免用户无法纠正或解除已有映射。
    final incomplete =
        lookup?.status == BangumiLookupStatus.success &&
        !partial &&
        info != null &&
        info.score == null &&
        info.staff.isEmpty;
    if (!unavailable && !noMatch && !partial && !incomplete) {
      return const SizedBox.shrink();
    }

    final title =
        unavailable
            ? 'Bangumi 资料暂不可用'
            : noMatch
            ? '暂无可靠的 Bangumi 匹配'
            : partial
            ? '部分 Bangumi 资料不可用'
            : 'Bangumi 资料不完整';
    final subtitle =
        unavailable
            ? '可重试，或手动选择对应条目'
            : noMatch
            ? '可手动选择对应条目'
            : partial
            ? '评分与制作人员可用，角色资料缺失'
            : '仅有角色资料，可手动选择条目';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unavailable)
                TextButton(
                  onPressed: () => ref.invalidate(bangumiInfoProvider(query)),
                  child: const Text('重试'),
                ),
              TextButton.icon(
                onPressed: () => _showBangumiMatchDialog(video.id, video.title),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('手动匹配'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBangumiDetails(
    VideoModel video,
    BangumiInfo bangumi,
    bool wide,
  ) {
    final theme = Theme.of(context);
    final hasProductionInfo = bangumi.score != null || bangumi.staff.isNotEmpty;
    final staff = [
      for (final entry in bangumi.staff)
        ListTile(
          dense: true,
          title: Text(entry.name),
          subtitle: Text(entry.role),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasProductionInfo)
          if (wide)
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('制作资料'),
                    subtitle:
                        bangumi.scoreCount == null
                            ? null
                            : Text('${bangumi.scoreCount} 人评分'),
                    trailing: TextButton.icon(
                      onPressed:
                          () => _showBangumiMatchDialog(video.id, video.title),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('资料不准确？手动匹配'),
                    ),
                  ),
                  ...staff,
                ],
              ),
            )
          else
            ExpansionTile(
              title: const Text('制作资料'),
              subtitle:
                  bangumi.scoreCount == null
                      ? null
                      : Text('${bangumi.scoreCount} 人评分'),
              children: [
                ...staff,
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.tune, size: 18),
                  title: const Text('资料不准确？手动匹配'),
                  onTap: () => _showBangumiMatchDialog(video.id, video.title),
                ),
              ],
            ),
        if (bangumi.characters.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('角色', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 132 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 3,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: bangumi.characters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder:
                  (context, index) =>
                      _CharacterCard(character: bangumi.characters[index]),
            ),
          ),
        ],
      ],
    );
  }

  /// R7：手动选择 Bangumi 条目并按完整视频 ID 持久化，避免自动匹配到
  /// 错误作品/季数，也避免同名不同作品共用一份关联。
  Future<void> _showBangumiMatchDialog(String videoId, String title) async {
    final api = ref.read(bangumiApiProvider);
    final existing = DatabaseService().getBangumiMapping(videoId);
    final selected = await showDialog<Object?>(
      context: context,
      builder:
          (_) => BangumiMatchDialog(
            search: (query) => api.searchSubjects(query),
            initialQuery: title,
            title: title,
            hasExistingMapping: existing != null,
            existingLabel: existing?['name']?.toString(),
          ),
    );
    if (selected == null || !mounted) return;
    if (selected is String && selected == BangumiMatchDialog.clearValue) {
      await DatabaseService().removeBangumiMapping(videoId);
    } else if (selected is BangumiSubjectCandidate) {
      await DatabaseService().setBangumiMapping(videoId, {
        'subjectId': selected.subjectId,
        'name': selected.displayTitle,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
    ref.invalidate(
      bangumiInfoProvider(BangumiQuery(videoId: videoId, title: title)),
    );
  }

  void _playEpisode(VideoModel video, int index) async {
    final episode = video.episodes![index];

    // 如果有直接播放地址，直接播放
    if (episode.playUrl != null && episode.playUrl!.isNotEmpty) {
      _navigateToPlayer(video, index, episode.playUrl!);
      return;
    }

    // 否则显示加载中，获取播放地址
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final scraper = ref.read(currentScraperProvider);
      final playUrls = await scraper.getPlayUrls(episode.url);

      if (mounted) Navigator.pop(context);

      if (playUrls.isNotEmpty) {
        _navigateToPlayer(video, index, playUrls.first);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂无可用播放源')));
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取播放地址失败: $e')));
      }
    }
  }

  Future<void> _downloadEpisode(VideoModel video, int index) async {
    final episode = video.episodes![index];
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在解析下载地址...')));

    try {
      var url = episode.playUrl;
      if (url == null || url.isEmpty) {
        final scraper = ref.read(currentScraperProvider);
        final playUrls = await scraper.getPlayUrls(episode.url);
        if (playUrls.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂无可用播放源，无法下载')));
          return;
        }
        url = playUrls.first;
      }

      await ref
          .read(downloadTasksProvider.notifier)
          .addTask(
            title: '${video.title} - ${episode.title}',
            url: url,
            videoId: video.id,
            cover: video.cover,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已加入下载队列，可在「下载」页查看')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加下载失败: $e')));
    }
  }

  void _toggleFavorite(VideoModel video) {
    ref.read(favoritesProvider.notifier).toggle(video).then((_) {
      if (!mounted) return;
      final isFav = DatabaseService().favoriteForVideo(video) != null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(isFav ? '已加入收藏' : '已取消收藏')));
    });
  }

  void _navigateToPlayer(VideoModel video, int index, String videoUrl) {
    launchPlayer(
      context,
      videoUrl: videoUrl,
      title: '${video.title} - ${video.episodes![index].title}',
      episodes:
          video.episodes!
              .map(
                (e) => {
                  'id': e.id,
                  'title': e.title,
                  'url': e.playUrl ?? e.url,
                  'pageUrl': e.url,
                  'media': e.urlIsMediaPlayback ? 'true' : 'false',
                },
              )
              .toList(),
      currentIndex: index,
      videoId: DatabaseService().historyIdForVideo(video),
      videoTitle: video.title,
      cover: video.cover,
      sourceId: video.source,
    );
  }
}

class _SubjectIntroduction extends StatefulWidget {
  const _SubjectIntroduction({required this.description});

  final String description;

  @override
  State<_SubjectIntroduction> createState() => _SubjectIntroductionState();
}

class _SubjectIntroductionState extends State<_SubjectIntroduction> {
  static const _previewLines = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.6,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final preview = TextPainter(
          text: TextSpan(text: widget.description, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: _previewLines,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = preview.didExceedMaxLines;
        preview.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('简介', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              widget.description,
              style: style,
              maxLines: _expanded ? null : _previewLines,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (canExpand)
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(_expanded ? '收起简介' : '展开简介'),
              ),
          ],
        );
      },
    );
  }
}

class _EpisodeThumbCard extends StatelessWidget {
  final String title;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _EpisodeThumbCard({
    required this.title,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = title.isEmpty ? '第 ${index + 1} 集' : title;
    return SizedBox(
      width: 158,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isCurrent ? colors.primaryContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isCurrent ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: label,
                excludeFromSemantics: true,
                child: TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    alignment: AlignmentDirectional.centerStart,
                    padding: const EdgeInsetsDirectional.only(
                      start: 10,
                      end: 4,
                    ),
                    foregroundColor:
                        isCurrent
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '下载本集',
              iconSize: 16,
              icon: const Icon(Icons.download_outlined),
              onPressed: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}

/// 角色卡：头像 + 角色名 + CV
class _CharacterCard extends StatelessWidget {
  final BangumiCharacter character;

  const _CharacterCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child:
                character.imageUrl != null
                    ? CachedNetworkImage(
                      imageUrl: character.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget:
                          (context, url, error) => Icon(
                            Icons.person_outline,
                            color: colorScheme.onSurfaceVariant,
                          ),
                    )
                    : Icon(
                      Icons.person_outline,
                      color: colorScheme.onSurfaceVariant,
                    ),
          ),
          const SizedBox(height: 6),
          Text(
            character.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (character.cv != null)
            Text(
              character.cv!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
