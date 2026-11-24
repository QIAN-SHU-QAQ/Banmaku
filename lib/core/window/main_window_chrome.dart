import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowChrome extends StatefulWidget {
  const DesktopWindowChrome({
    super.key,
    required this.manager,
    required this.child,
  });

  final WindowManager manager;
  final Widget child;

  @override
  State<DesktopWindowChrome> createState() => _DesktopWindowChromeState();
}

class _DesktopWindowChromeState extends State<DesktopWindowChrome>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _listenToWindow();
  }

  @override
  void didUpdateWidget(DesktopWindowChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      oldWidget.manager.removeListener(this);
      _listenToWindow();
    }
  }

  void _listenToWindow() {
    final manager = widget.manager;
    manager.addListener(this);
    unawaited(_readWindowState(manager));
  }

  Future<void> _readWindowState(WindowManager manager) async {
    final maximized = await manager.isMaximized();
    if (mounted && manager == widget.manager) _setMaximized(maximized);
  }

  void _setMaximized(bool maximized) {
    if (_maximized != maximized) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  @override
  void onWindowRestore() => unawaited(_readWindowState(widget.manager));

  @override
  void onWindowLeaveFullScreen() => unawaited(_readWindowState(widget.manager));

  @override
  void dispose() {
    widget.manager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _WindowChromeScope(
      manager: widget.manager,
      maximized: _maximized,
      child: widget.child,
    );
  }
}

class _WindowChromeScope extends InheritedWidget {
  const _WindowChromeScope({
    required this.manager,
    required this.maximized,
    required super.child,
  });

  final WindowManager manager;
  final bool maximized;

  static _WindowChromeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_WindowChromeScope>();
  }

  @override
  bool updateShouldNotify(_WindowChromeScope oldWidget) {
    return manager != oldWidget.manager || maximized != oldWidget.maximized;
  }
}

/// Wrap a title or open space in a header to make it a window drag target.
class DesktopDragRegion extends StatelessWidget {
  const DesktopDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = _WindowChromeScope.maybeOf(context);
    if (chrome == null) return child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onPanStart: (_) => unawaited(chrome.manager.startDragging()),
      onDoubleTap: () async {
        if (await chrome.manager.isMaximized()) {
          await chrome.manager.unmaximize();
        } else {
          await chrome.manager.maximize();
        }
      },
      child: child,
    );
  }
}

class DesktopWindowControls extends StatelessWidget {
  const DesktopWindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = _WindowChromeScope.maybeOf(context);
    if (chrome == null) return const SizedBox.shrink();

    final manager = chrome.manager;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          label: '最小化',
          icon: Icons.remove,
          onPressed: manager.minimize,
        ),
        _CaptionButton(
          label: chrome.maximized ? '还原' : '最大化',
          icon: chrome.maximized ? Icons.filter_none : Icons.crop_square,
          onPressed: chrome.maximized ? manager.unmaximize : manager.maximize,
        ),
        _CaptionButton(
          label: '关闭',
          icon: Icons.close,
          onPressed: manager.close,
          close: true,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.close = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        icon: Icon(icon, size: 16),
        tooltip: label,
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (close && states.contains(WidgetState.hovered)) {
              return Colors.white;
            }
            return colors.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (close && states.contains(WidgetState.hovered)) {
              return const Color(0xffc42b1c);
            }
            return null;
          }),
        ),
      ),
    );
  }
}
