import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/history_item.dart';
import '../cover_url.dart';

class ContinueWatchingCard extends StatelessWidget {
  const ContinueWatchingCard({
    super.key,
    required this.item,
    required this.sourceName,
    required this.onTap,
  });

  final HistoryItem item;
  final String? sourceName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final episode = item.episodeTitle?.trim();
    final source = sourceName?.trim();
    final hasEpisode = episode != null && episode.isNotEmpty;
    final hasSource = source != null && source.isNotEmpty;
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        focusColor: colors.primary.withValues(alpha: 0.18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 100, child: _ResumeArtwork(cover: item.cover)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasEpisode || hasSource) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (hasEpisode)
                            Flexible(
                              child: Text(
                                episode,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metadataStyle,
                              ),
                            ),
                          if (hasEpisode && hasSource)
                            Text(' · ', style: metadataStyle),
                          if (hasSource)
                            Flexible(
                              child: Tooltip(
                                message: source,
                                excludeFromSemantics: true,
                                child: Text(
                                  source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: metadataStyle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '已看 ${_formatDuration(item.position)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (item.progress > 0) ...[
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: colors.surfaceContainerHighest,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    if (minutes >= 60) {
      return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _ResumeArtwork extends StatelessWidget {
  const _ResumeArtwork({required this.cover});

  final String? cover;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imageUrl = discoveryCoverUrl(cover);
    final placeholder = ColoredBox(
      color: colors.primaryContainer,
      child: Center(
        child: Icon(Icons.movie_outlined, color: colors.onPrimaryContainer),
      ),
    );
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.4),
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            )
          else
            placeholder,
          Positioned(
            right: 7,
            bottom: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xD923192E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
