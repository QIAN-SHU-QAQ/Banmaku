import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/video_model.dart';

class SubjectSummary extends StatelessWidget {
  const SubjectSummary({
    super.key,
    required this.video,
    this.score,
    this.actions,
  });

  final VideoModel video;
  final double? score;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final year = video.year?.trim();
    final genre = video.genre?.trim();
    final source = video.source?.trim();
    final episodeCount = video.episodes?.length;
    final rating = score ?? video.rating;
    final metadata = [
      if (year != null && year.isNotEmpty) Text(year),
      if (episodeCount != null && episodeCount > 0) Text('共 $episodeCount 集'),
      if (rating != null && rating.isFinite)
        Text(
          '评分 ${rating.toStringAsFixed(1)}',
          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubjectCover(cover: video.cover, width: compact ? 78 : 96),
                    SizedBox(width: compact ? 16 : 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: video.title,
                            excludeFromSemantics: true,
                            child: Text(
                              video.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  compact
                                      ? theme.textTheme.headlineSmall
                                      : theme.textTheme.headlineMedium,
                            ),
                          ),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            DefaultTextStyle(
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: metadata,
                              ),
                            ),
                          ],
                          if (source != null && source.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Tooltip(
                                message: '片源：$source',
                                excludeFromSemantics: true,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      '片源：$source',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: colors.onSecondaryContainer,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (genre != null && genre.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                genre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (actions != null) ...[const SizedBox(height: 12), actions!],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SubjectCover extends StatelessWidget {
  const _SubjectCover({required this.cover, required this.width});

  final String? cover;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = cover?.trim() ?? '';
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 28,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child:
            url.isEmpty
                ? placeholder
                : CachedNetworkImage(
                  imageUrl:
                      url.startsWith('http') ? url : 'https://yhdm.me$url',
                  fit: BoxFit.cover,
                  placeholder: (_, __) => placeholder,
                  errorWidget: (_, __, ___) => placeholder,
                ),
      ),
    );
  }
}
