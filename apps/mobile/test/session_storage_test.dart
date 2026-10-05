import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Remembering survives restart; disabling removes saved and refreshed sessions',
    () async {
      final values = <String, String>{};
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final key = call.arguments['key'] as String;
            switch (call.method) {
              case 'write':
                values[key] = call.arguments['value'] as String;
                return null;
              case 'read':
                return values[key];
              case 'containsKey':
                return values.containsKey(key);
              case 'delete':
                values.remove(key);
                return null;
            }
            throw StateError('Unexpected storage operation');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final first = SecureSessionStorage();
      await first.initialize();
      await first.setRemember(true);
      await first.persistSession('test-session');
      final restarted = SecureSessionStorage();
      await restarted.initialize();
      expect(await restarted.accessToken(), 'test-session');
      await restarted.setRemember(false);
      expect(await restarted.hasAccessToken(), false);
      await restarted.persistSession('refreshed-session');
      expect(await restarted.hasAccessToken(), false);
      final secondRestart = SecureSessionStorage();
      await secondRestart.initialize();
      await secondRestart.persistSession('another-refresh');
      expect(await secondRestart.accessToken(), isNull);
      await secondRestart.setRemember(true);
      await secondRestart.persistSession('new-login');
      await secondRestart.removePersistedSession();
      expect(await secondRestart.hasAccessToken(), false);
    },
  );
}
