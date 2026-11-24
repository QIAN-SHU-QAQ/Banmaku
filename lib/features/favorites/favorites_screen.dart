import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/play_launcher.dart';
import '../../models/video_model.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../services/database_service.dart';
import '../../shared/widgets/desktop_page_header.dart';
import '../../shared/widgets/wide_media_card.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    // 反查观看历史：收藏卡上展示进度并支持一键续播
    ref.watch(historyProvider);

    return DesktopPage(
      title: '收藏',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: Text(
              '${favorites.length} 部',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
      child:
          favorites.isEmpty
              ? _buildEmptyState(context)
              : LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 1320
                          ? 3
                          : constraints.maxWidth >= 860
                          ? 2
                          : 1;
                  final scale = MediaQuery.textScalerOf(context).scale(14);
                  Widget item(BuildContext context, int index) =>
                      _mediaCard(context, ref, favorites[index]);
                  final padding = EdgeInsets.all(
                    constraints.maxWidth >= 720 ? 24 : 16,
                  );
                  return columns == 1
                      ? ListView.separated(
                        padding: padding,
                        itemCount: favorites.length,
                        itemBuilder: item,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                      )
                      : GridView.builder(
                        padding: padding,
                        itemCount: favorites.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent:
                              122 +
                              (scale - 14).clamp(0.0, double.infinity) * 5,
                        ),
                        itemBuilder: item,
                      );
                },
              ),
    );
  }

  Widget _mediaCard(BuildContext context, WidgetRef ref, VideoModel video) {
    final history = DatabaseService().historyForVideo(video);
    void openDetails() {
      context.push('/detail/${Uri.encodeComponent(video.id)}', extra: video);
    }

    return WideMediaCard(
      title: video.title,
      coverUrl: video.cover,
      subtitle: video.genre,
      meta: video.episodes == null ? null : '共 ${video.episodes!.length} 集',
      progress: history?.progress,
      onTap: openDetails,
      onResume: () {
        if (history != null) {
          resumeFromOriginalSource(context, ref, history);
        } else {
          openDetails();
        }
      },
      onLongPress: () => _confirmRemove(context, ref, video),
      onRemove: () => _confirmRemove(context, ref, video),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref, VideoModel video) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('移除收藏'),
            content: Text('确定要移除「${video.title}」吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(favoritesProvider.notifier).toggle(video);
                  Navigator.pop(context);
                },
                child: const Text('移除'),
              ),
            ],
          ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border_rounded,
            size: 28,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无收藏',
            style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '点击视频详情页的心形按钮添加收藏',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
