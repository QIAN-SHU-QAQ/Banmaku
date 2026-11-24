import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/branding.dart';
import '../../core/window/main_window_chrome.dart';

/// Branch indices follow routes.dart. Search is a full-window route.
class MainScaffold extends StatelessWidget {
  const MainScaffold({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final current = navigationShell.currentIndex;
    void go(int index) =>
        navigationShell.goBranch(index, initialLocation: index == current);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border: Border(
                    right: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const DesktopDragRegion(child: _Brand()),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          _NavigationItem(
                            icon: Icons.search_rounded,
                            label: '搜索',
                            onTap: () => context.push('/search'),
                          ),
                          const SizedBox(height: 12),
                          _NavigationItem(
                            icon: Icons.explore_outlined,
                            label: '发现',
                            selected: current == 0,
                            onTap: () => go(0),
                          ),
                          _NavigationItem(
                            icon: Icons.bookmarks_outlined,
                            label: '收藏',
                            selected: current == 1,
                            onTap: () => go(1),
                          ),
                          _NavigationItem(
                            icon: Icons.history_rounded,
                            label: '历史',
                            selected: current == 3,
                            onTap: () => go(3),
                          ),
                          _NavigationItem(
                            icon: Icons.download_outlined,
                            label: '下载',
                            selected: current == 2,
                            onTap: () => go(2),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                      child: _NavigationItem(
                        icon: Icons.settings_outlined,
                        label: '设置',
                        selected: current == 4,
                        onTap: () => go(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: appDisplayName,
      child: SizedBox(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              appIconAsset,
              width: 34,
              height: 34,
              cacheWidth: 128,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 3),
            Text(
              appDisplayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color =
        selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    final borderRadius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: colors.primary.withValues(alpha: 0.07),
            focusColor: colors.primary.withValues(alpha: 0.18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              child: Column(
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
