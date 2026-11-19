import 'package:flutter/material.dart';
import '../../../models/video_model.dart';
import '../../../shared/widgets/poster_card.dart';

class VideoCard extends StatelessWidget {
  final VideoModel video;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final bool showSource;

  const VideoCard({
    super.key,
    required this.video,
    this.onTap,
    this.onPlay,
    this.showSource = false,
  });

  @override
  Widget build(BuildContext context) => PosterCard(
    video: video,
    onTap: onTap,
    onPlay: onPlay,
    showSource: showSource,
  );
}
