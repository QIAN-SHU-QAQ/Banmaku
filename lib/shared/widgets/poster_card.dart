import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/video_model.dart';

/// Sizes rows from the available width after horizontal grid padding.
SliverGridDelegateWithFixedCrossAxisCount posterGridDelegate(
  BuildContext context,
  double width, {
  required double maxTileWidth,
  required double spacing,
}) {
  final count = math.max(
    1,
    ((width + spacing) / (maxTileWidth + spacing)).ceil(),
  );
  final tileWidth = (width - (count - 1) * spacing) / count;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
    mainAxisExtent: tileWidth * 1.5 + PosterCard.captionHeight(context),
  );
}

/// A portrait cover with two title lines and one metadata line.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.video,
    this.onTap,
    this.onPlay,
    this.showSource = false,
    this.previewsOnEnter = false,
    this.selected = false,
  });

  final VideoModel video;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final bool showSource;
  final bool previewsOnEnter;
  final bool selected;

  static const _titleSize = 13.0;
  static const _metadataSize = 11.0;
  static const _lineHeight = 1.35;
  static const _titleTop = 7.0;
  static const _metadataTop = 3.0;
  static const _captionBottom = 4.0;

  /// Use this with the actual tile width to size a discovery grid row.
  static double captionHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return _titleTop +
        _titleHeight(scaler) +
        _metadataTop +
        _metadataHeight(scaler) +
        _captionBottom;
  }

  static double _titleHeight(TextScaler scaler) =>
      (scaler.scale(_titleSize) * _lineHeight * 2).ceilToDouble();

  static double _metadataHeight(TextScaler scaler) =>
      (scaler.scale(_metadataSize) * _lineHeight).ceilToDouble();

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  static final _radius = BorderRadius.circular(8);
  bool _hovered = false;
  bool _focused = false;
  bool _playFocused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final video = widget.video;
    final metadata = [
          if (widget.showSource) video.source,
          video.year,
          video.genre,
        ]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');
    final overlayAction = widget.onPlay ?? widget.onTap;
    final isPreview = widget.previewsOnEnter;

    return CallbackShortcuts(
      bindings: {
        if (!isPreview && overlayAction != null) ...{
          const SingleActivator(LogicalKeyboardKey.enter): overlayAction,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): overlayAction,
        },
      },
      child: Semantics(
        selected: isPreview ? widget.selected : null,
        child: Material(
          color: widget.selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: _radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap ?? widget.onPlay,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            borderRadius: _radius,
            hoverColor: colors.onSurface.withValues(alpha: 0.05),
            focusColor: colors.primary.withValues(alpha: 0.09),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: _radius,
                        child: Container(
                          foregroundDecoration: BoxDecoration(
                            borderRadius: _radius,
                            border: Border.all(
                              color:
                                  _focused || _playFocused || widget.selected
                                      ? colors.primary
                                      : colors.outlineVariant,
                              width:
                                  _focused || _playFocused || widget.selected
                                      ? 2
                                      : 1,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _cover(colors, video.cover),
                              if ((_hovered || _focused || _playFocused) &&
                                  overlayAction != null)
                                Center(
                                  child: Focus(
                                    canRequestFocus: false,
                                    descendantsAreFocusable:
                                        isPreview && widget.onPlay != null,
                                    onFocusChange: (value) {
                                      if (_playFocused != value) {
                                        setState(() => _playFocused = value);
                                      }
                                    },
                                    child: ExcludeSemantics(
                                      excluding: widget.onPlay == null,
                                      child: IconButton.filled(
                                        onPressed: overlayAction,
                                        tooltip:
                                            widget.onPlay != null
                                                ? '播放'
                                                : isPreview
                                                ? '预览作品'
                                                : '打开详情',
                                        icon: Icon(
                                          widget.onPlay == null
                                              ? Icons.arrow_outward_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    2,
                    PosterCard._titleTop,
                    2,
                    0,
                  ),
                  child: SizedBox(
                    height: PosterCard._titleHeight(scaler),
                    child: Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: PosterCard._titleSize,
                        height: PosterCard._lineHeight,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    2,
                    PosterCard._metadataTop,
                    2,
                    PosterCard._captionBottom,
                  ),
                  child: SizedBox(
                    height: PosterCard._metadataHeight(scaler),
                    child: Text(
                      metadata.isEmpty ? (video.description ?? '') : metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: PosterCard._metadataSize,
                        height: PosterCard._lineHeight,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(ColorScheme colors, String? cover) {
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 30,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    if (cover == null || cover.isEmpty) return placeholder;

    return CachedNetworkImage(
      imageUrl: cover.startsWith('http') ? cover : 'https://yhdm.me$cover',
      fit: BoxFit.cover,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}
