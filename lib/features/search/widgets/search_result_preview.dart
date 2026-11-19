import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/video_model.dart';
import '../../../providers/video_provider.dart';
import '../../../services/scraper/base_scraper.dart';
import '../../detail/widgets/subject_summary.dart';

class SearchResultPreview extends ConsumerWidget {
  const SearchResultPreview({
    super.key,
    this.result,
    this.scraper,
    this.onOpenDetails,
  });

  final VideoModel? result;
  final BaseScraper? scraper;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final selected = result;
    final selectedScraper = scraper;
    if (selected == null || selectedScraper == null) {
      return ColoredBox(
        color: colors.surfaceContainerLow,
        child: Center(
          child: Text(
            '选择作品以预览',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    final provider = sourceVideoDetailProvider((
      scraper: selectedScraper,
      id: selected.id,
    ));
    final detail = ref.watch(provider);

    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Semantics(
              container: true,
              label: '作品预览',
              child: detail.when(
                skipLoadingOnRefresh: false,
                loading:
                    () => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SubjectSummary(video: selected),
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
                        SubjectSummary(video: selected),
                        const SizedBox(height: 20),
                        const Text('详情读取失败'),
                        TextButton(
                          onPressed: () => ref.invalidate(provider),
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
                          icon: const Icon(Icons.arrow_outward_rounded),
                          label: const Text('查看详情'),
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
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
