import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/danmaku_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../shared/widgets/desktop_page_header.dart';
import 'source_management_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _sectionKeys = List.generate(4, (_) => GlobalKey());
  int _selectedSection = 0;

  static const _sections = [
    ('主题', Icons.palette_outlined),
    ('播放器', Icons.ondemand_video_outlined),
    ('下载与数据源', Icons.storage_outlined),
    ('关于', Icons.info_outline),
  ];

  void _showSection(int index) {
    final anchor = _sectionKeys[index].currentContext;
    if (anchor == null) return;
    setState(() => _selectedSection = index);
    Scrollable.ensureVisible(
      anchor,
      duration: const Duration(milliseconds: 210),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final playerSettings = ref.watch(playerSettingsProvider);
    final danmaku = ref.watch(danmakuSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    Widget heading(int index) => Padding(
      key: _sectionKeys[index],
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        _sections[index].$1,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: colors.primary),
      ),
    );
    Widget pending(IconData icon, String title) => ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text(title),
      subtitle: const Text('尚未开放'),
    );
    final options = [
      heading(0),
      for (final option in const [
        (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined),
        (ThemeMode.light, '浅色', Icons.light_mode_outlined),
        (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
      ])
        ListTile(
          leading: Icon(option.$3, size: 20),
          title: Text(option.$2),
          selected: mode == option.$1,
          trailing:
              mode == option.$1
                  ? Icon(Icons.check, size: 20, color: colors.primary)
                  : null,
          onTap: () => ref.read(themeModeProvider.notifier).setMode(option.$1),
        ),
      const Divider(),
      heading(1),
      SwitchListTile(
        secondary: const Icon(Icons.play_circle_outline, size: 20),
        title: const Text('自动播放下一集'),
        subtitle: const Text('一集播完后自动切到下一集'),
        value: playerSettings.autoPlayNext,
        onChanged: ref.read(playerSettingsProvider.notifier).setAutoPlayNext,
      ),
      ListTile(
        leading: const Icon(Icons.speed, size: 20),
        title: const Text('默认播放速度'),
        subtitle: const Text('新打开的视频使用该倍速'),
        trailing: Text(
          '${playerSettings.playbackSpeed}x',
          style: TextStyle(color: colors.primary),
        ),
        onTap: () => _showSpeedDialog(context, ref),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.subtitles_outlined, size: 20),
        title: const Text('弹幕'),
        subtitle: const Text('播放时显示弹幕（需要弹弹play账号）'),
        value: danmaku.enabled,
        onChanged: ref.read(danmakuSettingsProvider.notifier).setEnabled,
      ),
      ListTile(
        leading: const Icon(Icons.key_outlined, size: 20),
        title: const Text('弹弹play 账号'),
        subtitle: Text(
          danmaku.hasCredentials
              ? '已配置：${danmaku.appId}'
              : '未配置，点击填入 AppId / AppSecret（免费申请）',
        ),
        trailing: Text(
          danmaku.hasCredentials ? '修改' : '去配置',
          style: TextStyle(color: colors.primary),
        ),
        onTap: () => _showDanmakuCredentialsDialog(context, ref),
      ),
      ListTile(
        leading: const Icon(Icons.tune, size: 20),
        title: const Text('弹幕样式'),
        subtitle: Text(
          '透明度 ${(danmaku.opacity * 100).round()}% · '
          '字号 ${danmaku.fontSize.round()} · '
          '显示区域 ${(danmaku.area * 100).round()}%',
        ),
        onTap: () => _showDanmakuStyleDialog(context, ref),
      ),
      const Divider(),
      heading(2),
      pending(Icons.folder_outlined, '下载路径'),
      ListTile(
        leading: const Icon(Icons.source_outlined, size: 20),
        title: const Text('源管理'),
        subtitle: const Text('启停 / 切换 / 测速 / 添加自定义源'),
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SourceManagementScreen()),
            ),
      ),
      const Divider(),
      heading(3),
      ListTile(
        leading: const Icon(Icons.info_outline, size: 20),
        title: const Text('NovaPlay'),
        subtitle: const Text('视频聚合播放器'),
        onTap:
            () => showAboutDialog(
              context: context,
              applicationName: 'NovaPlay',
              children: [const Text('视频聚合播放器')],
            ),
      ),
      pending(Icons.update, '检查更新'),
    ];
    return DesktopPage(
      title: '设置',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return Padding(
            padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 18, wide ? 24 : 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide) ...[
                  SizedBox(
                    width: 184,
                    child: Column(
                      children: [
                        for (var i = 0; i < _sections.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: Icon(_sections[i].$2, size: 19),
                              title: Text(
                                _sections[i].$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: i == _selectedSection,
                              selectedTileColor: colors.primaryContainer,
                              onTap: () => _showSection(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: options,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSpeedDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(playerSettingsProvider).playbackSpeed;
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => SimpleDialog(
            title: const Text('默认播放速度'),
            children: [
              for (final speed in playbackSpeeds)
                SimpleDialogOption(
                  onPressed: () {
                    ref
                        .read(playerSettingsProvider.notifier)
                        .setPlaybackSpeed(speed);
                    Navigator.pop(dialogContext);
                  },
                  child: Row(
                    children: [
                      Text('${speed}x'),
                      const Spacer(),
                      if (speed == current)
                        Icon(
                          Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
            ],
          ),
    );
  }

  Future<void> _showDanmakuCredentialsDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(danmakuSettingsProvider);
    final appIdController = TextEditingController(text: current.appId);
    final secretController = TextEditingController(text: current.appSecret);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogColors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('弹弹play 账号'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('弹幕来自弹弹play 开放弹幕网络。请先在开发者中心免费申请 AppId / AppSecret：'),
                const SizedBox(height: 6),
                InkWell(
                  onTap:
                      () => launchUrl(
                        Uri.parse('https://dev.dandanplay.com'),
                        mode: LaunchMode.externalApplication,
                      ),
                  child: Text(
                    'https://dev.dandanplay.com',
                    style: TextStyle(color: dialogColors.primary),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: appIdController,
                  decoration: const InputDecoration(
                    labelText: 'AppId',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: secretController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'AppSecret',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '凭据只保存在本机；清空后保存即可停止加载弹幕。',
                  style: TextStyle(
                    fontSize: 12,
                    color: dialogColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (saved == true) {
      await ref
          .read(danmakuSettingsProvider.notifier)
          .saveCredentials(appIdController.text, secretController.text);
    }
    appIdController.dispose();
    secretController.dispose();
  }

  Future<void> _showDanmakuStyleDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(danmakuSettingsProvider);
    var opacity = current.opacity;
    var fontSize = current.fontSize;
    var area = current.area;

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Widget slider({
                required String label,
                required String valueText,
                required double value,
                required double min,
                required double max,
                required int divisions,
                required ValueChanged<double> onChanged,
              }) {
                final textTheme = Theme.of(dialogContext).textTheme;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: textTheme.bodyMedium),
                        const Spacer(),
                        Text(valueText, style: textTheme.bodySmall),
                      ],
                    ),
                    Slider(
                      value: value,
                      min: min,
                      max: max,
                      divisions: divisions,
                      onChanged: onChanged,
                    ),
                  ],
                );
              }

              return AlertDialog(
                title: const Text('弹幕样式'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      slider(
                        label: '透明度',
                        valueText: '${(opacity * 100).round()}%',
                        value: opacity,
                        min: 0.2,
                        max: 1.0,
                        divisions: 8,
                        onChanged: (v) => setDialogState(() => opacity = v),
                      ),
                      slider(
                        label: '字号',
                        valueText: fontSize.round().toString(),
                        value: fontSize,
                        min: 10,
                        max: 32,
                        divisions: 11,
                        onChanged: (v) => setDialogState(() => fontSize = v),
                      ),
                      slider(
                        label: '显示区域（屏幕高度占比）',
                        valueText: '${(area * 100).round()}%',
                        value: area,
                        min: 0.2,
                        max: 1.0,
                        divisions: 8,
                        onChanged: (v) => setDialogState(() => area = v),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final notifier = ref.read(
                        danmakuSettingsProvider.notifier,
                      );
                      await notifier.setOpacity(opacity);
                      await notifier.setFontSize(fontSize);
                      await notifier.setArea(area);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          ),
    );
  }
}
