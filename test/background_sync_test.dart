import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homework_radar/app_state.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/background_sync.dart';
import 'package:homework_radar/services/storage.dart';
import 'package:homework_radar/services/sync_policy.dart';

class RecordingState extends AppState {
  final requests = <Set<PlatformKind>>[];
  @override
  Future<String> syncPlatforms({Set<PlatformKind>? platforms}) async {
    requests.add({...?platforms});
    final statuses = Storage.syncStatuses();
    for (final p in platforms ?? Storage.syncAccounts()) {
      statuses[p] = (statuses[p] ?? const PlatformSyncStatus()).finish(
        SyncOutcome.success,
        DateTime.now(),
      );
    }
    await Storage.saveSyncStatuses(statuses);
    return '';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  late RecordingState state;
  late BackgroundSync controller;
  final native = <Map>[];
  final secrets = <String, String>{};
  setUp(() async {
    native.clear();
    secrets.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('homework_radar/platform'),
      (call) async {
        final a = call.arguments as Map?;
        if (call.method == 'secureRead') return secrets[a?['key']];
        if (call.method == 'secureWrite') secrets[a?['key']] = a?['value'];
        if (call.method == 'secureDelete') secrets.remove(a?['key']);
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(BackgroundSync.channel, (call) async {
      if (call.method == 'ready') return false;
      native.add(Map.from(call.arguments as Map));
      return true;
    });
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await Storage.saveChaoxing(cookie: 'synthetic');
    await Storage.saveMooc(cookie: 'synthetic', csrf: 'synthetic');
    state = RecordingState();
    controller = BackgroundSync(state, onForeground: () async {});
    await controller.init();
  });
  tearDown(() {
    controller.dispose();
    state.dispose();
  });

  test(
    'one failed publication cannot poison future automatic retries',
    () async {
      await Storage.clearChaoxing();
      await Storage.clearMooc();
      final actual = AppState();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (_) async => throw PlatformException(code: 'temporary-output-error'),
      );
      await expectLater(actual.syncAll(), throwsA(isA<PlatformException>()));
      expect(actual.syncing, false);
      await expectLater(actual.waitForSync(), completes);
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (_) async => true,
      );
      await expectLater(actual.syncAll(), completes);
      actual.dispose();
    },
  );

  test('resume only refreshes stale platforms; retry only fetches failed platforms', () async {
    final now = DateTime.now();
    await Storage.saveSyncStatuses({
      PlatformKind.chaoxing: const PlatformSyncStatus().finish(
        SyncOutcome.success,
        now,
      ),
      PlatformKind.mooc: const PlatformSyncStatus().finish(
        SyncOutcome.success,
        now.subtract(const Duration(minutes: 6)),
      ),
    });
    await controller.run('resume');
    expect(state.requests, [
      {PlatformKind.mooc},
    ]);
    await Storage.saveSyncStatuses({
      PlatformKind.chaoxing: const PlatformSyncStatus().finish(
        SyncOutcome.retry,
        now.subtract(const Duration(minutes: 6)),
      ),
      PlatformKind.mooc: const PlatformSyncStatus().finish(
        SyncOutcome.success,
        now.subtract(const Duration(hours: 3)),
      ),
    });
    await controller.run('retry');
    expect(state.requests.last, {PlatformKind.chaoxing});
  });
  test('settings survive reload and disabling cancels native scheduling without changing data', () async {
    await state.setSyncConfig(const SyncConfig(enabled: false, minutes: 120));
    expect(native.last['enabled'], false);
    expect(native.last['minutes'], 120);
    await Storage.init();
    expect(Storage.syncConfig().minutes, 120);
    await controller.run('periodic');
    expect(state.requests, isEmpty);
    // Foreground still checks data even with background scheduling disabled.
    await controller.run('resume');
    expect(state.requests.single, {PlatformKind.chaoxing, PlatformKind.mooc});
  });
  test('confirmed expiry is paused; fresh login clears status for only that account', () async {
    final expired = const PlatformSyncStatus().finish(
      SyncOutcome.loginExpired,
      DateTime.now(),
    );
    await Storage.saveSyncStatuses({
      PlatformKind.chaoxing: expired,
      PlatformKind.mooc: expired,
    });
    await controller.run('periodic');
    expect(state.requests, isEmpty);
    await state.loadLocal();
    expect(state.chaoxingState, AccountState.needRelogin);
    expect(state.moocState, AccountState.needRelogin);
    await state.onChaoxingLogin('renewed-synthetic', 'new-user', sync: false);
    expect(Storage.syncStatuses().containsKey(PlatformKind.chaoxing), false);
    expect(Storage.syncStatuses()[PlatformKind.mooc]!.paused, true);
    await controller.run('resume');
    expect(state.requests.single, {PlatformKind.chaoxing});
    await state.logoutChaoxing();
    expect(Storage.syncStatuses().containsKey(PlatformKind.chaoxing), false);
  });
}
