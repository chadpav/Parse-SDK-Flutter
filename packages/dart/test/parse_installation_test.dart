import 'dart:convert';

import 'package:parse_server_sdk/parse_server_sdk.dart';
import 'package:test/test.dart';

Future<void> _initParse() => Parse().initialize(
      'appId',
      'https://example.com',
      debug: true,
      fileDirectory: 'someDirectory',
      appName: 'appName',
      appPackageName: 'somePackageName',
      appVersion: 'someAppVersion',
    );

void main() {
  setUpAll(() async {
    await _initParse();
  });

  // Each test starts from a clean local store and a cleared install-id cache
  // so a test that pre-seeds the store isn't contaminated by a previous one.
  setUp(() async {
    await ParseCoreData().getStore().remove(keyParseStoreInstallation);
    ParseInstallation.debugResetInstallationIdCache();
  });

  test('should return true for exist TimeZone.', () async {
    final ParseInstallation installation =
        await ParseInstallation.currentInstallation();
    expect(installation.containsKey(keyTimeZone), isTrue);
  });

  // Regression: when an installation is loaded from the local store on a
  // subsequent launch (process died before the first server save), `fromJson`
  // populates `_objectData` but not `_unsavedChanges`. `_create()` POSTs
  // `toJson(forApiRQ: true)`, which reads from `_unsavedChanges` — without
  // the gate in `_updateInstallation()`, the POST body would carry no
  // `installationId` and the server would create a row whose
  // `installationId` column is empty.
  test('_updateInstallation re-stages installationId so create() POSTs it',
      () async {
    const String storedId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    final Map<String, dynamic> storedJson = <String, dynamic>{
      keyVarClassName: keyClassInstallation,
      keyInstallationId: storedId,
      keyDeviceType: 'android',
      keyAppName: 'appName',
    };
    await ParseCoreData()
        .getStore()
        .setString(keyParseStoreInstallation, jsonEncode(storedJson));

    final installation = await ParseInstallation.currentInstallation();
    expect(installation.installationId, equals(storedId));
    expect(installation.objectId, isNull);

    // Pre-condition: load-from-store uses `fromJson(addInUnSave: false)`, so
    // the install ID lives in `_objectData` only. `toJson(forApiRQ: true)`
    // reads `_unsavedChanges` — proving the regression exists if the gate
    // were removed.
    final Map<String, dynamic> bodyBeforeUpdate =
        installation.toJson(forApiRQ: true);
    expect(
      bodyBeforeUpdate.containsKey(keyInstallationId),
      isFalse,
      reason: 'Sanity check: installationId is in _objectData only after '
          'a fresh load from the local store.',
    );

    // Drive the same path the SDK takes before POST /installations. The
    // network call will fail (pointed at https://example.com), but by then
    // `_updateInstallation()` has run and re-staged installationId.
    final ParseResponse response = await installation.create();
    expect(response.success, isFalse);
    final Map<String, dynamic> apiBody =
        installation.toJson(forApiRQ: true);
    expect(
      apiBody[keyInstallationId],
      equals(storedId),
      reason:
          'installationId must be in _unsavedChanges so the create() POST '
          'body carries it. Otherwise the server creates a row whose '
          '`installationId` column is empty.',
    );
  });

  // Regression: a corrupted local store with `installationId: ""` should not
  // be reused. `_getFromLocalStore` must return null so `_createInstallation`
  // generates a fresh UUID instead.
  test('empty installationId in local store is rejected', () async {
    final Map<String, dynamic> poisonedJson = <String, dynamic>{
      keyVarClassName: keyClassInstallation,
      keyInstallationId: '',
      keyDeviceType: 'android',
    };
    await ParseCoreData()
        .getStore()
        .setString(keyParseStoreInstallation, jsonEncode(poisonedJson));

    final installation = await ParseInstallation.currentInstallation();
    expect(installation.installationId, isNotNull);
    expect(installation.installationId, isNotEmpty);
    expect(installation.installationId!.trim(), isNotEmpty);
  });

  // Whitespace-only IDs would survive an `isNotEmpty` check; make sure the
  // shared validator catches them too.
  test('whitespace-only installationId in local store is rejected', () async {
    final Map<String, dynamic> poisonedJson = <String, dynamic>{
      keyVarClassName: keyClassInstallation,
      keyInstallationId: '   ',
      keyDeviceType: 'android',
    };
    await ParseCoreData()
        .getStore()
        .setString(keyParseStoreInstallation, jsonEncode(poisonedJson));

    final installation = await ParseInstallation.currentInstallation();
    expect(installation.installationId, isNotNull);
    expect(installation.installationId!.trim(), isNotEmpty);
    expect(installation.installationId, isNot(equals('   ')));
  });

  // Non-string installationId (e.g. corrupted migration that wrote a Map)
  // should be discarded rather than crash the type cast.
  test('non-string installationId in local store is rejected', () async {
    final Map<String, dynamic> poisonedJson = <String, dynamic>{
      keyVarClassName: keyClassInstallation,
      keyInstallationId: <String, dynamic>{'unexpected': 'shape'},
      keyDeviceType: 'android',
    };
    await ParseCoreData()
        .getStore()
        .setString(keyParseStoreInstallation, jsonEncode(poisonedJson));

    final installation = await ParseInstallation.currentInstallation();
    expect(installation.installationId, isNotNull);
    expect(installation.installationId, isNotEmpty);
  });
}
