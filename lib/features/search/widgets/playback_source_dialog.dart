import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../models/video_model.dart';
import '../../../services/playback_source_probe.dart';

Future<VideoModel?> choosePlaybackSource(
  BuildContext context,
  List<VideoModel> versions,
) => showDialog<VideoModel>(
  context: context,
  builder: (_) => _PlaybackSourceDialog(versions: versions),
);

class _PlaybackSourceDialog extends StatefulWidget {
  const _PlaybackSourceDialog({required this.versions});

  final List<VideoModel> versions;

  @override
  State<_PlaybackSourceDialog> createState() => _PlaybackSourceDialogState();
}

class _PlaybackSourceDialogState extends State<_PlaybackSourceDialog> {
  final _pending = <String, CancelToken>{};
  final _results = <String, PlaybackSourceStatus>{};

  @override
  void dispose() {
    for (final token in _pending.values) {
      token.cancel();
    }
    super.dispose();
  }

  void _testAll() {
    setState(() {
      _results.clear();
      for (final version in widget.versions) {
        _pending[version.id] = CancelToken();
      }
    });
    for (final version in widget.versions) {
      unawaited(_testSource(version, _pending[version.id]!));
    }
  }

  Future<void> _testSource(VideoModel version, CancelToken token) async {
    final result = await probePlaybackSource(version, token);
    if (!mounted) return;
    setState(() {
      _pending.remove(version.id);
      _results[version.id] = result;
    });
  }

  Widget _status(String id) {
    final colors = Theme.of(context).colorScheme;
    final result = _results[id];
    final label = switch (result) {
      PlaybackSourceStatus.available => '首集可用',
      PlaybackSourceStatus.unavailable => '首集不可用',
      PlaybackSourceStatus.noAddress => '无剧集地址',
      PlaybackSourceStatus.timedOut => '检测超时',
      null => _pending.containsKey(id) ? '检测中…' : '',
    };
    return Semantics(
      liveRegion: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: switch (result) {
            PlaybackSourceStatus.available => colors.primary,
            PlaybackSourceStatus.unavailable => colors.error,
            _ => colors.onSurfaceVariant,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.versions.first;
    return AlertDialog(
      title: const Text('选择片源'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text([work.title, work.year].whereType<String>().join(' · ')),
            const SizedBox(height: 12),
            for (final version in widget.versions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(version.source ?? version.sourceConfigId ?? '片源'),
                subtitle:
                    version.title == work.title ? null : Text(version.title),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _status(version.id),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () => Navigator.of(context).pop(version),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _pending.isEmpty ? _testAll : null,
          icon: const Icon(Icons.network_check_rounded),
          label: Text(
            _pending.isNotEmpty
                ? '测试中…'
                : _results.isEmpty
                ? '测试全部'
                : '重新测试',
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
