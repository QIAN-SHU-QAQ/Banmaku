import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_model.dart';
import '../services/database_service.dart';
import '../services/scraper/base_scraper.dart';
import '../services/scraper/lziapi_scraper.dart';
import '../services/scraper/source_config.dart';
import '../services/scraper/source_identity.dart';

/// 数据源配置版本号：设置页修改配置后自增，驱动下游 scraper 重建。
final sourceVersionProvider = StateProvider<int>((ref) => 0);

/// 当前保存的全部数据源配置（含已禁用项）。
final sourceConfigsProvider = Provider<List<SourceConfig>>((ref) {
  ref.watch(sourceVersionProvider);
  return DatabaseService().getSources();
});

final enabledSourcesProvider = Provider<List<SourceConfig>>(
  (ref) => ref.watch(sourceConfigsProvider).where((s) => s.enabled).toList(),
);

bool isFromOtherSource(VideoModel video, SourceConfig active) {
  final identity = decodeSourceVideoId(video.id);
  return identity != null
      ? identity.sourceConfigId != active.id
      : video.source != null && video.source != active.name;
}

final sourceAutoFallbackProvider = Provider<bool>((ref) {
  ref.watch(sourceVersionProvider);
  return DatabaseService().getSourceAutoFallback();
});

final selectSourceProvider = Provider<Future<void> Function(String)>((ref) {
  return (id) async {
    if (!ref.read(enabledSourcesProvider).any((source) => source.id == id)) {
      return;
    }
    final version = ref.read(sourceVersionProvider.notifier);
    await DatabaseService().setActiveSourceId(id);
    if (version.mounted) version.state++;
  };
});

/// 当前生效的数据源：优先用户选中的，否则取第一个启用的。
final activeSourceConfigProvider = Provider<SourceConfig>((ref) {
  ref.watch(sourceVersionProvider);
  final configs = ref.watch(sourceConfigsProvider);
  final enabled = ref.watch(enabledSourcesProvider);
  final activeId = DatabaseService().getActiveSourceId();

  if (enabled.isEmpty) {
    // 保留配置用于显示。请求会报告该源已禁用。
    return configs.isNotEmpty ? configs.first : SourceConfig.defaults().first;
  }
  return enabled.firstWhere(
    (c) => c.id == activeId,
    orElse: () => enabled.first,
  );
});

typedef OriginalSourceDetail =
    Future<VideoModel> Function(String id, String? sourceConfigId);

final originalSourceDetailProvider = Provider<OriginalSourceDetail>((ref) {
  final scraper = ref.watch(currentScraperProvider);
  return (id, sourceConfigId) async {
    if (scraper is! LziApiScraper) return scraper.getDetail(id);
    final identity = decodeSourceVideoId(id);
    if (sourceConfigId == null || identity == null) {
      throw StateError('无法确认原片源');
    }
    return scraper.getDetailFromSource(sourceConfigId, identity.vodId);
  };
});

/// 搜索和发现可以按设置回退。详情始终保留作品实际所属的源。
final currentScraperProvider = Provider<BaseScraper>((ref) {
  final active = ref.watch(activeSourceConfigProvider);
  return LziApiScraper(
    primary: active,
    fallbacks: ref.watch(enabledSourcesProvider),
    allowListFallback: ref.watch(sourceAutoFallbackProvider),
    allowDetailPlaybackSubstitution: false,
    animeCatalogOnly: true,
  );
});
