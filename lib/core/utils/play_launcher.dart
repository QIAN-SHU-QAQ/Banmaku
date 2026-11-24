import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/history_item.dart';
import '../../models/video_model.dart';
import '../../providers/scraper_provider.dart';
import '../../services/database_service.dart';
import '../../services/prefs_bridge.dart';
import '../../services/scraper/lziapi_scraper.dart';
import '../../shared/widgets/source_picker.dart';
import 'history_resume.dart';

/// 当前进程是否运行在 `flutter test` 里（测试环境不启动独立进程）。
bool get _isFlutterTest =>
    !kIsWeb &&
    (const bool.fromEnvironment('FLUTTER_TEST') ||
        Platform.environment['FLUTTER_TEST'] == 'true');

/// 打开播放器：启动一个独立的本程序进程来显示播放窗口。
///
/// 独立进程的好处：关闭播放窗口只结束该进程，主界面完全不受影响。
/// 如果启动失败（例如 flutter test 或非 Windows），回退到主窗口内路由播放。
Future<void> launchPlayer(
  BuildContext context, {
  required String videoUrl,
  required String title,
  List<Map<String, String>>? episodes,
  int currentIndex = 0,
  int startAt = 0,
  String? videoId,
  String? videoTitle,
  String? cover,
  String? sourceId,
  String? sourceName,
  bool isLocalFile = false,
}) async {
  final extra = <String, dynamic>{
    'videoUrl': videoUrl,
    'title': title,
    'episodes': episodes,
    'currentIndex': currentIndex,
    'startAt': startAt,
    'videoId': videoId,
    'videoTitle': videoTitle,
    'cover': cover,
    'sourceId': sourceId,
    'sourceName': sourceName,
    'isLocalFile': isLocalFile,
    // 主进程配置桥端口：播放器的进度/设置写入经由主进程持久化。
    'bridgePort': PrefsBridgeServer.instance?.port,
  };

  if (!kIsWeb && Platform.isWindows && !_isFlutterTest) {
    try {
      await Process.start(Platform.resolvedExecutable, [
        '--player',
        jsonEncode(extra),
      ], mode: ProcessStartMode.detached);
      return;
    } catch (e) {
      debugPrint('启动独立播放进程失败，回退到窗口内播放: $e');
    }
  }

  if (!context.mounted) return;
  context.push('/player', extra: extra);
}

/// 正在解析续播目标的作品，防止双击重复打开播放器。
final Set<String> _resuming = <String>{};

Future<void> resumeFromOriginalSource(
  BuildContext context,
  WidgetRef ref,
  HistoryItem item,
) {
  final isMacCms = ref.read(currentScraperProvider) is LziApiScraper;
  return launchHistoryResume(
    context,
    item,
    fetchDetail: () {
      final fetch = ref.read(originalSourceDetailProvider);
      return fetch(item.videoId, DatabaseService().sourceIdForHistory(item));
    },
    preserveSavedIdentity: isMacCms,
    onSwitchSource: () => pickSourceForSearch(context, ref, item.title),
  );
}

/// 从历史条目续播（R4）。
///
/// 不直接使用历史快照里的播放地址（可能已过期）：先通过 [fetchDetail]
/// 刷新作品详情，重新定位剧集与播放地址；无法定位时等待用户确认。
Future<void> launchHistoryResume(
  BuildContext context,
  HistoryItem item, {
  Future<VideoModel?> Function()? fetchDetail,
  bool preserveSavedIdentity = false,
  Future<void> Function()? onSwitchSource,
}) async {
  if (_resuming.contains(item.videoId)) return;
  _resuming.add(item.videoId);

  // 记录发起续播时的路由位置：StatefulShellRoute 会保留旧页面，页面仍
  // mounted 不代表还在前台。请求完成前用户切到别的分支时不能抢走导航。
  GoRouter? router;
  String? originUri;
  try {
    router = GoRouter.of(context);
    originUri = router.state.uri.toString();
  } catch (_) {
    // 非 GoRouter 环境（部分组件测试）不启用路由守卫。
  }
  var leftOrigin = false;
  void noteRouteChange() {
    if (router?.state.uri.toString() != originUri) leftOrigin = true;
  }

  router?.routerDelegate.addListener(noteRouteChange);
  bool stillActive() {
    if (!context.mounted || leftOrigin) return false;
    final currentRouter = router;
    if (currentRouter != null &&
        originUri != null &&
        currentRouter.state.uri.toString() != originUri) {
      return false;
    }
    return true;
  }

  try {
    HistoryResumeTarget? target;
    String? sourceName;
    if (fetchDetail != null) {
      do {
        target = await resolveHistoryResumeTarget(
          item,
          fetchDetail: () async {
            final original = await fetchDetail();
            sourceName = original?.source;
            // MacCMS already verified the source. Keep the saved lookup keys
            // for matching and history, and display the confirmed source name.
            return preserveSavedIdentity
                ? original?.copyWith(id: item.videoId, source: item.sourceId)
                : original;
          },
        );
        if (!stillActive()) return;
        if (target != null || onSwitchSource == null) break;
        if (!context.mounted) return;
        final action = await showDialog<_ResumeAction>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('无法从原片源续播'),
                content: Text('无法确认《${item.title}》的原剧集。重试，或换源后重新选择剧集。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed:
                        () => Navigator.pop(dialogContext, _ResumeAction.retry),
                    child: const Text('重试'),
                  ),
                  FilledButton(
                    onPressed:
                        () => Navigator.pop(
                          dialogContext,
                          _ResumeAction.switchSource,
                        ),
                    child: const Text('切换片源'),
                  ),
                ],
              ),
        );
        if (!stillActive()) return;
        if (action == _ResumeAction.switchSource) await onSwitchSource();
        if (action != _ResumeAction.retry) return;
      } while (true);
    } else if (item.episodes.isNotEmpty) {
      // 没有详情刷新入口时（测试/降级）仍使用快照，保持行为可用。
      final index = item.episodeIndex.clamp(0, item.episodes.length - 1);
      final episode = item.episodes[index];
      target = HistoryResumeTarget(
        videoUrl: episode.playUrl ?? episode.url,
        title: '${item.title} - ${episode.title}',
        episodes:
            item.episodes
                .map(
                  (e) => {
                    'id': e.id,
                    'title': e.title,
                    'url': e.playUrl ?? e.url,
                    'pageUrl': e.url,
                    'media': e.urlIsMediaPlayback ? 'true' : 'false',
                  },
                )
                .toList(),
        index: index,
        videoTitle: item.title,
        cover: item.cover,
        sourceId: item.sourceId,
      );
    }

    if (!stillActive()) return;

    if (target == null) {
      if (!context.mounted) return;
      context.push('/detail/${Uri.encodeComponent(item.videoId)}');
      return;
    }
    if (!context.mounted) return;
    await launchPlayer(
      context,
      videoUrl: target.videoUrl,
      title: target.title,
      episodes: target.episodes,
      currentIndex: target.index,
      startAt: item.position.inSeconds,
      videoId: item.videoId,
      videoTitle: item.title,
      cover: target.cover,
      sourceId: target.sourceId ?? item.sourceId,
      sourceName: sourceName,
    );
  } finally {
    router?.routerDelegate.removeListener(noteRouteChange);
    _resuming.remove(item.videoId);
  }
}

enum _ResumeAction { retry, switchSource }
