import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/video_model.dart';
import '../../../providers/video_provider.dart';
import '../../../services/scraper/base_scraper.dart';
import '../../detail/widgets/subject_summary.dart';

class SearchResultPreview extends ConsumerWidget {
  const SearchResultPreview({
    super.key,
    required this.result,
    this.scraper,
    required this.onOpenDetails,
    required this.onClose,
  });

  final VideoModel result;
  final BaseScraper? scraper;
  final VoidCallback onOpenDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final playbackSource = scraper;
    final provider =
        playbackSource == null
            ? null
            : sourceVideoDetailProvider((
              scraper: playbackSource,
              id: result.id,
            ));
    final detail = provider == null ? AsyncData(result) : ref.watch(provider);

    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('作品预览', style: theme.textTheme.titleSmall),
                  ),
                ),
                IconButton(
                  tooltip: '关闭预览',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: detail.when(
                skipLoadingOnRefresh: false,
                loading:
                    () => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SubjectSummary(video: result),
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(
                          semanticsLabel: '正在读取作品详情',
                        ),
                      ],
                    ),
                error:
                    (_, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SubjectSummary(video: result),
                        const SizedBox(height: 20),
                        const Text('详情读取失败'),
                        TextButton(
                          onPressed:
                              provider == null
                                  ? null
                                  : () => ref.invalidate(provider),
                          child: const Text('重试详情'),
                        ),
                      ],
                    ),
                data: (video) {
                  final description = video.description?.trim();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SubjectSummary(
                        video: video,
                        actions: FilledButton.icon(
                          onPressed: onOpenDetails,
                          icon: Icon(
                            provider == null
                                ? Icons.search_rounded
                                : Icons.arrow_outward_rounded,
                          ),
                          label: Text(provider == null ? '查找片源' : '查看详情'),
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          '简介',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.55,
                          ),
                        ),
                      ],
                      if (provider == null) ...[
                        const SizedBox(height: 16),
                        Text(
                          '作品资料来自 Bangumi',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
