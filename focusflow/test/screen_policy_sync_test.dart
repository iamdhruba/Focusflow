import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:focusflow/core/services/local_policy_service.dart';
import 'package:focusflow/core/services/screen_policy_service.dart';
import 'package:focusflow/core/services/screen_policy_sync.dart';
import 'package:focusflow/core/services/tombstone_prefixes.dart';
import 'package:focusflow/core/storage/local_database.dart';

/// Hardcoded v1 schema bootstrap — lifted to top-level so it sits in the
/// local declaration hoisting order ahead of [setUp] below. (Dart hoists
/// local functions within their enclosing function, but pragmatically
/// declaring-before-use keeps the analyzer happy and makes the lifecycle
/// obvious to readers.)
Future<Database> openAtV1(String dbPath) async {
  final handle = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (handle, _) async {
      await handle.execute('''
        CREATE TABLE policies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          packageName TEXT UNIQUE NOT NULL,
          appName TEXT NOT NULL,
          timeLimitMinutes INTEGER NOT NULL DEFAULT 60,
          resetCycle TEXT NOT NULL DEFAULT 'daily',
          isActive INTEGER NOT NULL DEFAULT 1,
          todayUsageMs INTEGER NOT NULL DEFAULT 0,
          isOverLimit INTEGER NOT NULL DEFAULT 0,
          lastUpdated TEXT NOT NULL
        )
      ''');
      await handle.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    },
  );
  await handle.close();
  return handle;
}

/// End-to-end exercises for the Phase-3 delta-sync orchestrator
/// [performScreenPolicySync] — the same code path WorkManager runs every
/// ~15 min via `main.dart::callbackDispatcher`'s `localSyncTask`, and
/// `AppsNotifier.syncScreenPoliciesToServer()` runs on cold launch.
///
/// NOTE on schema bootstrap: the test bypasses `LocalDatabase._initDB`
/// (which lazily creates a v4 file at `getDatabasesPath()`) by passing
/// a fresh sqflite handle into `LocalDatabase.fromTestDatabase`. The
/// `onCreate` callback below inlines the SAME CREATE TABLE / CREATE
/// INDEX SQL that production's `_createDB` issues — if you change
/// `_createDB` in `local_database.dart`, update the corresponding
/// statement here to keep this test in lockstep.
///
/// Strategy:
///   1. Use sqflite_common_ffi to spin up an in-memory-equivalent DB on
///      a temp file (same pattern as [database_migration_test.dart]).
///   2. Wrap it as a `LocalDatabase` via the new test-only
///      [LocalDatabase.fromTestDatabase] constructor, so the orchestrator
///      sees a fully-functional `LocalDatabase` without polluting the
///      production singleton.
///   3. Pass that same instance to `LocalPolicyService({dbOverride: db})`
///      so the orchestrator's tombstone reads/clears and lastSyncAt
///      stamps hit the SAME database as the pending-row reads and
///      status updates. NOT the production singleton's lazily-opened
///      temp file.
///   4. Inject a fake [SyncPoster] lambda that captures what was POSTed
///      AND returns a canned `SyncScreenPolicyResult` so each test
///      exercises a different per-row outcome branch.
void main() {
  DatabaseFactory? previousFactory;

  setUpAll(() {
    sqfliteFfiInit();
    try {
      previousFactory = databaseFactory;
    } on StateError {
      previousFactory = null;
    }
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() {
    databaseFactory = previousFactory;
  });

  late Directory dir;
  late String path;
  late LocalDatabase db;
  late LocalPolicyService local;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ff_sync_test_');
    path = p.join(dir.path, 'focusflow.db');

    // Bootstrap v4 schema on a fresh temp file. Single OpenDatabase call
    // with version: 4 — the onCreate fires (file is new) AND onUpgrade
    // doesn't (target == current), so we don't need to pre-bootstrap v1.
    // The schema is created exactly as production would create it.
    final sqfliteHandle = await openDatabase(
      path,
      version: 4,
      onCreate: (handle, _) async {
        // Mirror the production `_createDB` shape exactly.
        await handle.execute('''
          CREATE TABLE policies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            packageName TEXT UNIQUE NOT NULL,
            appName TEXT NOT NULL,
            timeLimitMinutes INTEGER NOT NULL DEFAULT 60,
            resetCycle TEXT NOT NULL DEFAULT 'daily',
            isActive INTEGER NOT NULL DEFAULT 1,
            todayUsageMs INTEGER NOT NULL DEFAULT 0,
            isOverLimit INTEGER NOT NULL DEFAULT 0,
            lastUpdated TEXT NOT NULL
          )
        ''');
        await handle.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await handle.execute('''
          CREATE TABLE screen_policies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            packageName TEXT NOT NULL,
            screenKey TEXT NOT NULL,
            friendlyName TEXT NOT NULL,
            timeLimitMinutes INTEGER NOT NULL DEFAULT 0,
            isActive INTEGER NOT NULL DEFAULT 0,
            todayUsageMs INTEGER NOT NULL DEFAULT 0,
            serverId TEXT,
            lastUpdated TEXT NOT NULL,
            syncStatus TEXT NOT NULL DEFAULT 'pending',
            syncAttempts INTEGER NOT NULL DEFAULT 0,
            UNIQUE(packageName, screenKey)
          )
        ''');
        await handle.execute(
          'CREATE INDEX idx_screen_policies_pkg ON screen_policies(packageName)',
        );
        await handle.execute(
          'CREATE INDEX idx_screen_policies_sync_status '
          'ON screen_policies(syncStatus)',
        );
      },
    );
    db = LocalDatabase.fromTestDatabase(sqfliteHandle);
    // CRITICAL: pass `db` so LocalPolicyService's tombstone CRUD hits
    // the same DB the orchestrator's pending-row reads hit. Without
    // this, LocalPolicyService defaults to LocalDatabase.instance and
    // its writes land in a different FFI temp file.
    local = LocalPolicyService(dbOverride: db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  Future<void> seedPending(
    String packageName,
    String screenKey, {
    required String friendlyName,
    int timeLimitMinutes = 0,
    int isActive = 0,
    int syncAttempts = 0,
  }) async {
    await db.upsertScreenPolicy(<String, Object?>{
      'packageName': packageName,
      'screenKey': screenKey,
      'friendlyName': friendlyName,
      'timeLimitMinutes': timeLimitMinutes,
      'isActive': isActive,
      'todayUsageMs': 0,
      'lastUpdated': DateTime.now().toIso8601String(),
      'syncStatus': LocalDatabase.syncStatusPending,
      'syncAttempts': syncAttempts,
    });
  }

  Future<Map<String, String>> readTombstoneRows() async {
    final h = await db.database;
    final rows = await h.query('settings');
    return {
      for (final r in rows)
        if ((r['key'] as String).startsWith(kTombstoneKeyPrefix) ||
            (r['key'] as String).startsWith(kOldTombstoneKeyPrefix))
          r['key'] as String: r['value'] as String,
    };
  }

  test('cold-launch sweep — applied + deleted + applied: full pipeline',
      () async {
    // Seed two pending screen policies + one tombstone (for one of the
    // pending policies, simulating "user deleted this rule while offline").
    await seedPending('com.instagram.android', 'reels',
        friendlyName: 'Reels', timeLimitMinutes: 15, isActive: 1);
    await seedPending('com.example.app', 'home', friendlyName: 'Home');
    await local.recordPendingTombstone('com.example.app', 'home');

    final poster = FakeSyncPoster(const SyncScreenPolicyResult(
      success: true,
      applied: 2,
      deleted: 1,
      skipped: 0,
      results: <Map<String, dynamic>>[
        {
          'packageName': 'com.instagram.android',
          'screenKey': 'reels',
          'status': 'applied',
        },
        {'packageName': 'com.example.app', 'screenKey': 'home', 'status': 'deleted'},
      ],
    ));

    final res = await performScreenPolicySync(
      db: db,
      local: local,
      postSync: poster.post,
    );

    expect(res?.success, isTrue);
    expect(poster.calls.length, 1);
    final payload = poster.calls.single;
    expect(payload.length, 3,
        reason: 'two pending rows + one tombstone = 3 entries');
    // Tombstones come first so a server-side upsert applied earlier in
    // the batch gets removed regardless of order.
    expect(
      payload.firstWhere((p) => p['deleted'] == true)['packageName'],
      'com.example.app',
    );

    // Post-state: both pending rows → 'synced', tombstone cleared.
    final h = await db.database;
    final rows = await h.query('screen_policies');
    final byKey = <String, Map<String, Object?>>{
      for (final r in rows) '${r['packageName']}:${r['screenKey']}': r,
    };
    expect(byKey['com.instagram.android:reels']!['syncStatus'],
        LocalDatabase.syncStatusSynced);
    expect(byKey['com.example.app:home']!['syncStatus'],
        LocalDatabase.syncStatusSynced);
    expect(byKey['com.instagram.android:reels']!['syncAttempts'], 0);
    expect(byKey['com.example.app:home']!['syncAttempts'], 0);

    // Tombstone for the deleted rule is cleared.
    final tombstones = await readTombstoneRows();
    expect(tombstones.containsKey(
        '${kTombstoneKeyPrefix}com.example.app:home'), isFalse);

    // Marker timestamp set.
    final lastSyncAt = await local.getSetting('screenPoliciesLastSyncAt');
    expect(lastSyncAt, isNotNull);
  });

  test('skipped_newer outcome: tombstone cleared + row marked synced',
      () async {
    await seedPending('com.foo', 'home', friendlyName: 'Home');
    await local.recordPendingTombstone('com.foo', 'home');

    final poster = FakeSyncPoster(const SyncScreenPolicyResult(
      success: true,
      results: <Map<String, dynamic>>[
        {'packageName': 'com.foo', 'screenKey': 'home', 'status': 'skipped_newer'},
      ],
    ));

    await performScreenPolicySync(db: db, local: local, postSync: poster.post);

    final h = await db.database;
    final row = (await h.query('screen_policies')).single;
    expect(row['syncStatus'], LocalDatabase.syncStatusSynced);

    final tombstones = await readTombstoneRows();
    expect(tombstones.containsKey('${kTombstoneKeyPrefix}com.foo:home'),
        isFalse);
  });

  test('invalid outcome: row marked failed with syncAttempts=99', () async {
    await seedPending('com.foo', 'home', friendlyName: 'Home');
    await local.recordPendingTombstone('com.foo', 'home');

    final poster = FakeSyncPoster(const SyncScreenPolicyResult(
      success: true,
      results: <Map<String, dynamic>>[
        {'packageName': 'com.foo', 'screenKey': 'home', 'status': 'invalid'},
      ],
    ));

    await performScreenPolicySync(db: db, local: local, postSync: poster.post);

    final h = await db.database;
    final row = (await h.query('screen_policies')).single;
    expect(row['syncStatus'], LocalDatabase.syncStatusFailed);
    expect(row['syncAttempts'], 99);

    final tombstones = await readTombstoneRows();
    expect(tombstones.containsKey('${kTombstoneKeyPrefix}com.foo:home'),
        isTrue);
  });

  test('whole-batch failure (success=false): syncAttempts bumped, row stays pending',
      () async {
    await seedPending('com.foo', 'home', friendlyName: 'Home');

    final poster = FakeSyncPoster(const SyncScreenPolicyResult(
      success: false,
      message: 'server unreachable',
      results: <Map<String, dynamic>>[],
    ));

    final res = await performScreenPolicySync(
        db: db, local: local, postSync: poster.post);

    expect(res?.success, isFalse);

    final h = await db.database;
    var row = (await h.query('screen_policies')).single;
    expect(row['syncStatus'], LocalDatabase.syncStatusPending);
    expect(row['syncAttempts'], 1);

    // Five failed attempts graduate the row to 'failed'.
    await performScreenPolicySync(
        db: db, local: local, postSync: poster.post);
    await performScreenPolicySync(
        db: db, local: local, postSync: poster.post);
    await performScreenPolicySync(
        db: db, local: local, postSync: poster.post);
    await performScreenPolicySync(
        db: db, local: local, postSync: poster.post);
    row = (await h.query('screen_policies')).single;
    expect(row['syncAttempts'], 5);
    expect(row['syncStatus'], LocalDatabase.syncStatusFailed);
  });

  test('empty payload: lastSyncAt stamped without POST', () async {
    int postsCalled = 0;
    Future<SyncScreenPolicyResult> post(List<Map<String, dynamic>> p) async {
      postsCalled++;
      return const SyncScreenPolicyResult(success: true, results: []);
    }

    await performScreenPolicySync(db: db, local: local, postSync: post);

    expect(postsCalled, 0);
    final lastSyncAt = await local.getSetting('screenPoliciesLastSyncAt');
    expect(lastSyncAt, isNotNull);
  });

  test('postSync throws: returns null, rows left pending (next sync retries)',
      () async {
    await seedPending('com.foo', 'home', friendlyName: 'Home');

    Future<SyncScreenPolicyResult> exploding(List<Map<String, dynamic>> p) {
      throw StateError('mock network failure');
    }

    final res = await performScreenPolicySync(
        db: db, local: local, postSync: exploding);

    expect(res, isNull);
    final h = await db.database;
    final row = (await h.query('screen_policies')).single;
    expect(row['syncStatus'], LocalDatabase.syncStatusPending);
    expect(row['syncAttempts'], 0);
  });

  test('applied outcome on a tombstone-pending row: row synced, tombstone preserved',
      () async {
    // Tricky edge case: server returns 'applied' for a tombstone row.
    // Meaning: it accepted the payload but ignored our 'deleted:true'
    // flag. The orchestrator marks the row synced (server acknowledged
    // it) but PRESERVES the tombstone so the next sync retries the
    // delete intent. Otherwise a delete intent could be silently
    // swallowed by a misbehaving server.
    await seedPending('com.foo', 'home', friendlyName: 'Home');
    await local.recordPendingTombstone('com.foo', 'home');

    final poster = FakeSyncPoster(const SyncScreenPolicyResult(
      success: true,
      results: <Map<String, dynamic>>[
        {'packageName': 'com.foo', 'screenKey': 'home', 'status': 'applied'},
      ],
    ));

    await performScreenPolicySync(db: db, local: local, postSync: poster.post);

    final h = await db.database;
    final row = (await h.query('screen_policies')).single;
    expect(row['syncStatus'], LocalDatabase.syncStatusSynced);

    // Tombstone preserved: delete intent retries next sync.
    final tombstones = await readTombstoneRows();
    expect(tombstones.containsKey('${kTombstoneKeyPrefix}com.foo:home'),
        isTrue,
        reason: 'tombstone preserved on inconclusive "applied" outcome');
  });
}

/// Result-capturing fake [SyncPoster]. Records every payload it sees so
/// tests can assert what the orchestrator actually sent.
///
/// Cannot have a `const` constructor because the `calls` list is mutable
/// state used to introspect POSTs after the orchestrator runs. Each
/// instance is per-test (allocated fresh inside each `test()` body).
class FakeSyncPoster {
  FakeSyncPoster(this.response);

  final SyncScreenPolicyResult response;
  final List<List<Map<String, dynamic>>> calls = [];

  Future<SyncScreenPolicyResult> post(List<Map<String, dynamic>> payload) async {
    calls.add(payload);
    return response;
  }
}
