import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/theme.dart';
import '../../core/utils/play_launcher.dart';
import '../../providers/download_provider.dart';
import '../../services/download_service.dart';
import '../../shared/widgets/desktop_page_header.dart';

class DownloadScreen extends ConsumerStatefulWidget {
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

typedef _DownloadGroupKey = ({bool hasVideoId, String id});

class _DownloadScreenState extends ConsumerState<DownloadScreen> {
  _DownloadGroupKey? _selectedGroup;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(downloadTasksProvider);
    final notifier = ref.read(downloadTasksProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final hasCompleted = tasks.any((t) => t.status == DownloadStatus.completed);

    return DesktopPage(
      title: '下载管理',
      actions: [
        if (hasCompleted)
          TextButton.icon(
            onPressed: () => _confirmClear(context, notifier),
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('清除已完成'),
          ),
      ],
      child:
          tasks.isEmpty
              ? _EmptyState(colors: colors)
              : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 760) {
                    return _taskList(tasks, notifier);
                  }
                  return _buildDesktop(tasks, notifier);
                },
              ),
    );
  }

  Widget _buildDesktop(
    List<DownloadTask> tasks,
    DownloadTasksNotifier notifier,
  ) {
    final groups = <_DownloadGroupKey, List<DownloadTask>>{};
    for (final task in tasks) {
      final videoId = task.videoId?.trim() ?? '';
      final key = (
        hasVideoId: videoId.isNotEmpty,
        id: videoId.isEmpty ? task.id : videoId,
      );
      (groups[key] ??= []).add(task);
    }

    final selectedKey =
        groups.containsKey(_selectedGroup)
            ? _selectedGroup!
            : groups.keys.first;
    final selected = groups[selectedKey]!;
    final selectedTitle = _groupTitle(selectedKey, selected);
    final completed =
        selected
            .where((task) => task.status == DownloadStatus.completed)
            .length;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 244,
            child: Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerLowest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Text('下载作品', style: theme.textTheme.titleMedium),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (final entry in groups.entries)
                          _DownloadGroupTile(
                            key: ValueKey(entry.key),
                            title: _groupTitle(entry.key, entry.value),
                            cover: entry.value.first.cover,
                            count: entry.value.length,
                            selected: entry.key == selectedKey,
                            onSelect:
                                () =>
                                    setState(() => _selectedGroup = entry.key),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '$completed / ${selected.length} 已完成',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _taskList(
                    selected,
                    notifier,
                    groupTitle: selectedKey.hasVideoId ? selectedTitle : null,
                    listKey: ValueKey(selectedKey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _groupTitle(_DownloadGroupKey key, List<DownloadTask> tasks) {
    final first = tasks.first.title;
    if (!key.hasVideoId) return first;

    // The saved title joins the series and episode with " - ".
    var prefix = first;
    while (prefix.contains(' - ')) {
      prefix = prefix.substring(0, prefix.lastIndexOf(' - '));
      if (prefix.isNotEmpty &&
          tasks.every((task) => task.title.startsWith('$prefix - '))) {
        return prefix;
      }
    }
    return first;
  }

  Widget _taskList(
    List<DownloadTask> tasks,
    DownloadTasksNotifier notifier, {
    String? groupTitle,
    Key? listKey,
  }) {
    final prefix = '$groupTitle - ';
    return ListView.separated(
      key: listKey,
      padding:
          groupTitle == null && listKey == null
              ? const EdgeInsets.fromLTRB(16, 12, 16, 24)
              : const EdgeInsets.only(bottom: 8),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final completed = task.status == DownloadStatus.completed;
        return _DownloadTaskTile(
          key: ValueKey(task.id),
          task: task,
          title:
              groupTitle != null && task.title.startsWith(prefix)
                  ? task.title.substring(prefix.length)
                  : task.title,
          onPause: () => notifier.pause(task.id),
          onResume: () => notifier.resume(task.id),
          onRemove: () => _confirmRemove(context, notifier, task),
          onShowInFolder: completed ? () => _showInFolder(task) : null,
          onPlay:
              completed
                  ? () => launchPlayer(
                    context,
                    videoUrl: task.savePath,
                    title: task.title,
                    videoId: task.videoId,
                    videoTitle: task.title,
                    isLocalFile: true,
                  )
                  : null,
        );
      },
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    DownloadTasksNotifier notifier,
    DownloadTask task,
  ) async {
    if (await _confirm(
          context,
          title: '删除下载',
          message: '将删除「${task.title}」的任务和本地文件。',
          action: '删除',
        ) &&
        mounted) {
      await notifier.remove(task.id);
    }
  }

  Future<void> _confirmClear(
    BuildContext context,
    DownloadTasksNotifier notifier,
  ) async {
    if (await _confirm(
          context,
          title: '清除已完成',
          message: '将删除所有已完成的下载任务及其本地文件。',
          action: '清除',
        ) &&
        mounted) {
      await notifier.clearCompleted();
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(action),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _showInFolder(DownloadTask task) async {
    if (!Platform.isWindows) return;
    try {
      final file = File(task.savePath);
      if (await file.exists()) {
        await Process.run('explorer.exe', ['/select,', file.path]);
        return;
      }
      final parent = file.parent;
      if (await parent.exists()) {
        await Process.run('explorer.exe', [parent.path]);
      }
    } catch (e) {
      debugPrint('打开下载文件夹失败: $e');
    }
  }
}

class _DownloadGroupTile extends StatelessWidget {
  const _DownloadGroupTile({
    super.key,
    required this.title,
    required this.cover,
    required this.count,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String? cover;
  final int count;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final coverUri = Uri.tryParse(cover?.trim() ?? '');
    final hasCover =
        coverUri != null &&
        (coverUri.isScheme('https') || coverUri.isScheme('http')) &&
        coverUri.host.isNotEmpty;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHigh,
      child: Icon(
        Icons.movie_outlined,
        size: 18,
        color: colors.onSurfaceVariant,
      ),
    );
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  height: 52,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child:
                        hasCover
                            ? Image.network(
                              coverUri.toString(),
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (_, _, _) => placeholder,
                            )
                            : placeholder,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: selected ? colors.onPrimaryContainer : null,
                        ),
                      ),
                      Text('$count 个任务', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: 32,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('还没有下载任务'),
            const SizedBox(height: 6),
            Text(
              '在作品详情页的选集卡片上点击下载按钮，即可离线保存。',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    super.key,
    required this.task,
    required this.title,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    this.onShowInFolder,
    this.onPlay,
  });

  final DownloadTask task;
  final String title;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final VoidCallback? onShowInFolder;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final failed = task.status == DownloadStatus.failed;
    final completed = task.status == DownloadStatus.completed;
    final progress = completed ? 1.0 : task.progress.clamp(0.0, 1.0);
    final percentage = '${(progress * 100).toStringAsFixed(0)}%';
    final statusColor =
        completed
            ? context.nova.success
            : failed
            ? colors.error
            : colors.onSurfaceVariant;
    final pathOrError = completed ? '已保存：${task.savePath}' : task.error;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          completed
                              ? task.status.label
                              : '${task.status.label} · $percentage',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (task.status.isActive)
                    IconButton(
                      tooltip: '暂停',
                      icon: const Icon(Icons.pause_circle_outline),
                      onPressed: onPause,
                    )
                  else if (task.status == DownloadStatus.paused || failed)
                    IconButton(
                      tooltip: failed ? '重试' : '继续',
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: onResume,
                    )
                  else if (onPlay != null)
                    IconButton(
                      tooltip: '播放本地文件',
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: onPlay,
                    ),
                  if (completed && onShowInFolder != null)
                    IconButton(
                      tooltip: '在文件夹中显示',
                      icon: const Icon(Icons.folder_open_outlined),
                      onPressed: onShowInFolder,
                    ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: progress, minHeight: 4),
              ),
              if (pathOrError != null) ...[
                const SizedBox(height: 6),
                Tooltip(
                  message: pathOrError,
                  child: Text(
                    pathOrError,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
