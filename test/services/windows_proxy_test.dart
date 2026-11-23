import 'package:flutter_test/flutter_test.dart';
import 'package:nova_play/core/network/windows_proxy.dart';

void main() {
  test(
    'Windows HTTPS proxy applies to Bangumi metadata, covers and LziApi',
    () {
      const proxy = WindowsProxy(
        'http=web.test:8080;https=secure.test:8081',
        '',
      );
      expect(
        proxy.findProxy(Uri.https('api.bgm.tv')),
        'PROXY secure.test:8081',
      );
      expect(
        proxy.findProxy(Uri.https('lain.bgm.tv')),
        'PROXY secure.test:8081',
      );
      expect(
        proxy.findProxy(Uri.https('cj.lziapi.com')),
        'PROXY secure.test:8081',
      );
      expect(proxy.findProxy(Uri.https('example.test')), 'DIRECT');
    },
  );

  test('Windows and environment proxy exceptions remain effective', () {
    const proxy = WindowsProxy('proxy.test:8080', '*.bgm.tv');
    expect(proxy.findProxy(Uri.https('api.bgm.tv')), 'DIRECT');
    expect(
      proxy.findProxy(
        Uri.https('api.bgm.tv'),
        environment: {'https_proxy': 'env.test:8081'},
      ),
      'PROXY env.test:8081',
    );
    expect(
      const WindowsProxy('proxy.test:8080', '').findProxy(
        Uri.https('lain.bgm.tv'),
        environment: {'no_proxy': 'lain.bgm.tv'},
      ),
      'DIRECT',
    );
  });
}
