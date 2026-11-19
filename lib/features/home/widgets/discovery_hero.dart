import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/video_model.dart';
import '../cover_url.dart';

/// Promotes the first catalog work whose cover can actually be displayed.
class DiscoveryHero extends StatefulWidget {
  const DiscoveryHero({super.key, required this.videos, required this.padding});

  final List<VideoModel> videos;
  final EdgeInsets padding;

  @override
  State<DiscoveryHero> createState() => _DiscoveryHeroState();
}

class _DiscoveryHeroState extends State<DiscoveryHero> {
  final _failedCovers = <String>{};

  @override
  Widget build(BuildContext context) {
    for (final video in widget.videos) {
      final cover = discoveryCoverUrl(video.cover);
      if (cover == null || _failedCovers.contains(cover)) continue;
      return CachedNetworkImage(
        key: ValueKey(cover),
        imageUrl: cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _failedCovers.add(cover)) setState(() {});
          });
          return const SizedBox.shrink();
        },
        imageBuilder:
            (context, image) => Padding(
              padding: widget.padding,
              child: _HeroBanner(video: video, cover: image),
            ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.video, required this.cover});

  final VideoModel video;
  final ImageProvider cover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink =
        Color.lerp(const Color(0xFF20172F), theme.colorScheme.primary, 0.09)!;
    const highlight = Color(0xFFEAD9FF);
    final metadata = [video.year, video.genre]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final height = wide ? 310.0 : 262.0;
        final inset = wide ? 36.0 : 20.0;
        final contentWidth = constraints.maxWidth * (wide ? 0.55 : 0.68);
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: ink,
            child: Stack(
              children: [
                Positioned.fill(
                  left: constraints.maxWidth * 0.23,
                  child: Image(
                    image: cover,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.35),
                    excludeFromSemantics: true,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ink,
                          ink.withValues(alpha: 0.96),
                          ink.withValues(alpha: 0.68),
                          ink.withValues(alpha: 0.15),
                        ],
                        stops: const [0.21, 0.40, 0.72, 1],
                      ),
                    ),
                  ),
                ),
                if (wide)
                  Positioned(
                    top: 25,
                    bottom: 25,
                    right: inset + constraints.maxWidth * 0.075,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: Container(
                        foregroundDecoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          image: DecorationImage(
                            image: cover,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height),
                  child: Padding(
                    padding: EdgeInsets.all(inset),
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '片库推荐',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: highlight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontSize: wide ? 42 : 32,
                              fontWeight: FontWeight.w700,
                              height: 1.12,
                            ),
                          ),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              metadata,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: highlight,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed:
                                () => context.push(
                                  '/detail/${Uri.encodeComponent(video.id)}',
                                ),
                            icon: const Icon(
                              Icons.arrow_outward_rounded,
                              size: 17,
                            ),
                            label: const Text('查看详情'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFAF1FF),
                              foregroundColor: ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
