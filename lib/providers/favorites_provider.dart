import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_model.dart';
import '../services/database_service.dart';

class FavoritesNotifier extends StateNotifier<List<VideoModel>> {
  FavoritesNotifier() : super(DatabaseService().getFavorites());

  /// 已收藏则取消，否则置顶添加
  Future<void> toggle(VideoModel video) async {
    final db = DatabaseService();
    final saved = db.favoriteForVideo(video);
    if (saved != null) {
      await db.removeFavorite(saved.id);
    } else {
      await db.addFavorite(video);
    }
    if (mounted) state = db.getFavorites();
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<VideoModel>>((ref) {
      return FavoritesNotifier();
    });
