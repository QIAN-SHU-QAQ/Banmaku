import 'package:flutter/material.dart';

import '../../core/window/main_window_chrome.dart';

/// In-content title bar for the main window. Only the open title area drags.
class DesktopPageHeader extends StatelessWidget {
  const DesktopPageHeader({
    super.key,
    required this.title,
    this.leading,
    this.toolbar,
    this.actions = const [],
  });

  final String title;
  final Widget? leading;
  final Widget? toolbar;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = constraints.maxWidth < 720 ? 16.0 : 24.0;
          final onSecondLine =
              actions.length > 2 && constraints.maxWidth < 820 ||
              toolbar != null && constraints.maxWidth < 880;
          final actionsBar = Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Row(
                  children: [
                    if (leading != null) ...[
                      const SizedBox(width: 6),
                      leading!,
                    ] else
                      SizedBox(width: inset),
                    Expanded(
                      child: DesktopDragRegion(
                        child: SizedBox(
                          height: 58,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!onSecondLine && toolbar != null)
                      Flexible(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: toolbar!,
                        ),
                      ),
                    if (!onSecondLine && actions.isNotEmpty) ...[
                      actionsBar,
                      const SizedBox(width: 8),
                    ],
                    const DesktopWindowControls(),
                  ],
                ),
              ),
              if (onSecondLine)
                Padding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (toolbar != null) toolbar!,
                      if (toolbar != null && actions.isNotEmpty)
                        const SizedBox(height: 8),
                      if (actions.isNotEmpty) actionsBar,
                    ],
                  ),
                ),
              Divider(height: 1, color: colors.outlineVariant),
            ],
          );
        },
      ),
    );
  }
}

class DesktopPage extends StatelessWidget {
  const DesktopPage({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageHeader(title: title, leading: leading, actions: actions),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
