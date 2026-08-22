import 'dart:convert';

import 'package:mockito/mockito.dart';
import 'package:parse_server_sdk/parse_server_sdk.dart';
import 'package:test/test.dart';

import '../../../parse_query_test.mocks.dart';
import '../../../test_utils.dart';

void main() {
  setUpAll(() async {
    await initializeParse();
  });

  group('ParseUser — persist only the current user to local storage', () {
    late MockParseClient client;

    const String currentUserObjectId = 'userAAA';
    const String detachedUserObjectId = 'userBBB';

    final String mePath = Uri.parse(
      '$serverUrl$keyEndPointUserName',
    ).toString();
    final String detachedPutPath = Uri.parse(
      '$serverUrl$keyEndPointClasses$keyClassUser/$detachedUserObjectId',
    ).toString();
    final String currentPutPath = Uri.parse(
      '$serverUrl$keyEndPointClasses$keyClassUser/$currentUserObjectId',
    ).toString();

    setUp(() async {
      client = MockParseClient();
      await ParseCoreData().getStore().remove(keyParseStoreUser);
    });

    /// Seeds local storage with user A as the stored current user,
    /// the way a successful login would have left it.
    Future<void> seedCurrentUserInStorage() async {
      final ParseUser current = ParseUser(null, null, null, client: client);
      current.fromJson(<String, dynamic>{
        keyVarObjectId: currentUserObjectId,
        keyVarSessionToken: 'r:currentSession',
        keyVarUsername: 'alice@example.com',
      });
      await ParseCoreData().getStore().setString(
        keyParseStoreUser,
        json.encode(current.toJson(full: true)),
      );
    }

    Future<String?> storedUserObjectId() async {
      final String? userJson = await ParseCoreData().getStore().getString(
        keyParseStoreUser,
      );
      if (userJson == null) {
        return null;
      }
      return json.decode(userJson)[keyVarObjectId];
    }

    ParseUser detachedUser() {
      final ParseUser user = ParseUser(null, null, null, client: client);
      user.fromJson(<String, dynamic>{
        keyVarObjectId: detachedUserObjectId,
        keyVarSessionToken: 'r:staleAnonSession',
        keyVarUsername: 'anonymous-uuid',
      });
      return user;
    }

    test('getUpdatedUser() on a detached instance must NOT replace the '
        'stored current user. a stale anonymous instance whose fetch '
        'resolves after a login would otherwise clobber the freshly '
        'logged-in user on disk — the daily forced re-login bug', () async {
      await seedCurrentUserInStorage();

      when(client.get(mePath, options: anyNamed('options'))).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarObjectId: detachedUserObjectId,
            keyVarUsername: 'anonymous-uuid',
            keyVarSessionToken: 'r:staleAnonSession',
          }),
        ),
      );

      final ParseResponse response = await detachedUser().getUpdatedUser(
        client: client,
      );

      expect(response.success, isTrue);
      expect(await storedUserObjectId(), equals(currentUserObjectId));
    });

    test('save() on a detached instance must NOT replace the stored current '
        'user. save responses previously persisted whichever instance '
        'handled them, with no current-user check', () async {
      await seedCurrentUserInStorage();

      when(
        client.put(
          detachedPutPath,
          options: anyNamed('options'),
          data: anyNamed('data'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarUpdatedAt: '2026-08-19T12:00:01.000Z',
          }),
        ),
      );

      final ParseUser user = detachedUser();
      user.set<String>('localeIdentifier', 'en-US');

      final ParseResponse response = await user.save();

      expect(response.success, isTrue);
      expect(await storedUserObjectId(), equals(currentUserObjectId));
    });

    test('update() on a detached instance must NOT replace the stored '
        'current user', () async {
      await seedCurrentUserInStorage();

      when(
        client.put(
          detachedPutPath,
          options: anyNamed('options'),
          data: anyNamed('data'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarUpdatedAt: '2026-08-19T12:00:01.000Z',
          }),
        ),
      );

      final ParseUser user = detachedUser();
      user.set<String>('localeIdentifier', 'en-US');

      final ParseResponse response = await user.update();

      expect(response.success, isTrue);
      expect(await storedUserObjectId(), equals(currentUserObjectId));
    });

    test('save() on the current user instance still persists to local '
        'storage. gating must not break the ordinary keep-disk-in-sync '
        'behavior for the user that is actually current', () async {
      await seedCurrentUserInStorage();

      when(
        client.put(
          currentPutPath,
          options: anyNamed('options'),
          data: anyNamed('data'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarUpdatedAt: '2026-08-19T12:00:01.000Z',
          }),
        ),
      );

      final ParseUser user = ParseUser(null, null, null, client: client);
      user.fromJson(<String, dynamic>{
        keyVarObjectId: currentUserObjectId,
        keyVarSessionToken: 'r:currentSession',
        keyVarUsername: 'alice@example.com',
      });
      user.set<String>('localeIdentifier', 'en-US');

      final ParseResponse response = await user.save();

      expect(response.success, isTrue);
      expect(await storedUserObjectId(), equals(currentUserObjectId));

      final String? userJson = await ParseCoreData().getStore().getString(
        keyParseStoreUser,
      );
      expect(json.decode(userJson!)['localeIdentifier'], equals('en-US'));
    });

    test('getUpdatedUser() on the current user instance still persists the '
        'refreshed data to local storage', () async {
      await seedCurrentUserInStorage();

      when(client.get(mePath, options: anyNamed('options'))).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarObjectId: currentUserObjectId,
            keyVarUsername: 'alice@example.com',
            keyVarEmail: 'alice+updated@example.com',
            keyVarSessionToken: 'r:currentSession',
          }),
        ),
      );

      final ParseUser user = ParseUser(null, null, null, client: client);
      user.fromJson(<String, dynamic>{
        keyVarObjectId: currentUserObjectId,
        keyVarSessionToken: 'r:currentSession',
      });

      final ParseResponse response = await user.getUpdatedUser(client: client);

      expect(response.success, isTrue);
      final String? userJson = await ParseCoreData().getStore().getString(
        keyParseStoreUser,
      );
      expect(
        json.decode(userJson!)[keyVarEmail],
        equals('alice+updated@example.com'),
      );
    });

    test('login() always persists — it establishes the new current user and '
        'must replace whoever was stored before', () async {
      await seedCurrentUserInStorage();

      final String loginPath = Uri.parse(
        '$serverUrl$keyEndPointLogin',
      ).toString();
      when(
        client.post(
          loginPath,
          options: anyNamed('options'),
          data: anyNamed('data'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarObjectId: 'userCCC',
            keyVarUsername: 'bob@example.com',
            keyVarSessionToken: 'r:bobSession',
          }),
        ),
      );

      final ParseUser user = ParseUser(
        'bob@example.com',
        'hunter2',
        null,
        client: client,
      );

      final ParseResponse response = await user.login();

      expect(response.success, isTrue);
      expect(await storedUserObjectId(), equals('userCCC'));
    });

    test('loginAnonymous() always persists — first-ever auth with nothing in '
        'storage must still write the new current user', () async {
      final String usersPath = Uri.parse(
        '$serverUrl$keyEndPointUsers',
      ).toString();
      when(
        client.post(
          usersPath,
          options: anyNamed('options'),
          data: anyNamed('data'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 201,
          data: jsonEncode(<String, dynamic>{
            keyVarObjectId: 'anonDDD',
            keyVarSessionToken: 'r:anonSession',
          }),
        ),
      );

      final ParseUser user = ParseUser(null, null, null, client: client);

      final ParseResponse response = await user.loginAnonymous();

      expect(response.success, isTrue);
      expect(await storedUserObjectId(), equals('anonDDD'));
    });

    test('signUp() always persists — it establishes the new current user '
        'even when a different user is stored', () async {
      await seedCurrentUserInStorage();

      final String usersPath = Uri.parse(
        '$serverUrl$keyEndPointClasses$keyClassUser',
      ).toString();
      when(
        client.post(
          usersPath,
          options: anyNamed('options'),
          data: anyNamed('data'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 201,
          data: jsonEncode(<String, dynamic>{
            keyVarObjectId: 'userEEE',
            keyVarSessionToken: 'r:newSession',
          }),
        ),
      );

      final ParseUser user = ParseUser(
        'carol@example.com',
        'hunter2',
        'carol@example.com',
        client: client,
      );

      final ParseResponse response = await user.signUp();

      expect(response.success, isTrue);
      expect(await storedUserObjectId(), equals('userEEE'));
    });

    test('getCurrentUserFromServer() always persists — it starts from an '
        'empty instance whose objectId is only known from the response, and '
        'its whole purpose is to refresh the current user', () async {
      await seedCurrentUserInStorage();

      when(client.get(mePath, options: anyNamed('options'))).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarObjectId: 'userFFF',
            keyVarUsername: 'dave@example.com',
            keyVarSessionToken: 'r:daveSession',
          }),
        ),
      );

      final ParseResponse? response = await ParseUser.getCurrentUserFromServer(
        'r:daveSession',
        client: client,
      );

      expect(response!.success, isTrue);
      expect(await storedUserObjectId(), equals('userFFF'));
    });

    test('save() on a detached instance still adopts a fresh sessionToken '
        'from the response (_adoptResponseSessionTokenIfChanged behavior is '
        'preserved) even though it no longer persists to storage', () async {
      await seedCurrentUserInStorage();
      ParseCoreData().setSessionId('r:staleAnonSession');

      when(
        client.put(
          detachedPutPath,
          options: anyNamed('options'),
          data: anyNamed('data'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarUpdatedAt: '2026-08-19T12:00:01.000Z',
            keyVarSessionToken: 'r:mintedSession',
          }),
        ),
      );

      final ParseUser user = detachedUser();
      user.password = 'newPassword';

      final ParseResponse response = await user.save();

      expect(response.success, isTrue);
      expect(ParseCoreData().sessionId, equals('r:mintedSession'));
      expect(await storedUserObjectId(), equals(currentUserObjectId));
    });

    test('a corrupt stored current-user blob is treated as no current user — '
        'the responding instance must not persist over it (FormatException '
        'branch of the current-user gate)', () async {
      const String corruptBlob = 'not-valid-json{{{';
      await ParseCoreData().getStore().setString(
        keyParseStoreUser,
        corruptBlob,
      );

      when(client.get(mePath, options: anyNamed('options'))).thenAnswer(
        (_) async => ParseNetworkResponse(
          statusCode: 200,
          data: jsonEncode(<String, dynamic>{
            keyVarObjectId: detachedUserObjectId,
            keyVarUsername: 'anonymous-uuid',
            keyVarSessionToken: 'r:staleAnonSession',
          }),
        ),
      );

      final ParseResponse response = await detachedUser().getUpdatedUser(
        client: client,
      );

      expect(response.success, isTrue);
      expect(
        await ParseCoreData().getStore().getString(keyParseStoreUser),
        equals(corruptBlob),
      );
    });
  });
}
