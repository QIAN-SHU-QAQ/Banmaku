import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Use the configured Windows HTTP proxy for supported built-in services.
void installWindowsProxy() {
  if (!Platform.isWindows) return;
  final proxy = WindowsProxy.read();
  if (proxy != null) HttpOverrides.global = _WindowsHttpOverrides(proxy);
}

class WindowsProxy {
  const WindowsProxy(this.server, this.bypass);

  final String server;
  final String bypass;

  static WindowsProxy? read() {
    final getConfig = DynamicLibrary.open('winhttp.dll').lookupFunction<
      Int32 Function(Pointer<_WinHttpProxyConfig>),
      int Function(Pointer<_WinHttpProxyConfig>)
    >('WinHttpGetIEProxyConfigForCurrentUser');
    final free = DynamicLibrary.open('kernel32.dll').lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('GlobalFree');
    final config = calloc<_WinHttpProxyConfig>();
    try {
      if (getConfig(config) == 0 || config.ref.proxy == nullptr) return null;
      final bypass = config.ref.bypass;
      return WindowsProxy(
        config.ref.proxy.toDartString(),
        bypass == nullptr ? '' : bypass.toDartString(),
      );
    } finally {
      for (final text in [
        config.ref.autoConfigUrl,
        config.ref.proxy,
        config.ref.bypass,
      ]) {
        if (text != nullptr) free(text.cast());
      }
      calloc.free(config);
    }
  }

  String findProxy(Uri uri, {Map<String, String> environment = const {}}) {
    final key = '${uri.scheme}_proxy';
    final env = environment.map(
      (key, value) => MapEntry(key.toLowerCase(), value),
    );
    if (const {
          'api.bgm.tv',
          'lain.bgm.tv',
          'cj.lziapi.com',
        }.contains(uri.host) &&
        !env.containsKey(key) &&
        !_isBypassed(uri.host)) {
      final proxy = _serverForScheme(uri.scheme);
      if (proxy != null) env[key] = proxy;
    }
    return HttpClient.findProxyFromEnvironment(uri, environment: env);
  }

  String? _serverForScheme(String scheme) {
    String? generic;
    for (final part in server.split(';')) {
      final separator = part.indexOf('=');
      if (separator == -1) {
        if (part.trim().isNotEmpty) generic ??= part.trim();
      } else if (part.substring(0, separator).trim().toLowerCase() == scheme) {
        final address = part.substring(separator + 1).trim();
        return address.isEmpty ? null : address;
      }
    }
    return generic;
  }

  bool _isBypassed(String host) {
    for (final part in bypass.split(';')) {
      final pattern = part.trim().toLowerCase();
      if (pattern == '<local>' && !host.contains('.')) return true;
      final wildcard = RegExp.escape(pattern).replaceAll(r'\*', '.*');
      if (RegExp('^$wildcard\$').hasMatch(host)) return true;
    }
    return false;
  }
}

final class _WinHttpProxyConfig extends Struct {
  @Int32()
  external int autoDetect;

  external Pointer<Utf16> autoConfigUrl;
  external Pointer<Utf16> proxy;
  external Pointer<Utf16> bypass;
}

class _WindowsHttpOverrides extends HttpOverrides {
  _WindowsHttpOverrides(this.proxy);

  final WindowsProxy proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy =
            (uri) => proxy.findProxy(uri, environment: Platform.environment);
}
