import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// `DatabaseException` is re-exported from `sqflite_common_ffi` via the
// shared `sqflite_common` interface layer, so we don't need to import
// the higher-level `sqflite` package just for the typed catch below.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:focusflow/core/services/tombstone_prefixes.dart';
import 'package:focusflow/core/storage/local_database.dart';
// Schema constants (single source of truth for v1 DDL shared with
// `LocalDatabase._createDB` — see `local_database_schema.dart`).
import 'package:focusflow/core/storage/local_database_schema.dart';

/// Migration tests for [LocalDatabase].
///
/// Strategy:
///   1. Bootstrap a temp DB at v1 by *hardcoding* the v1 CREATE TABLE
///      statements inline. Production's `_createDB` (`LocalDatabase`) is
///      not usable here because it ignores the `version` argument and
///      always emits the latest schema — using it here would bottom-out
///      the cascade at v4 row-state on first open and the migration
///      routine would never run, silently passing the assertions.
///
///   2. Close the v1 handle and reopen at the target version with
///      `onUpgrade: LocalDatabase.runMigrations` so production migration
///      SQL is exercised verbatim.
///
///   3. Inspect the resulting schema via SQLite PRAGMA — structured,
///      whitespace-immune, and introspectable from Dart without parsing
///      CREATE TABLE text.
void main() {
  DatabaseFactory? previousFactory;

  setUpAll(() {
    // FFI plugin activation. `databaseFactoryFfi` reroutes sqflite calls
    // over Dart FFI instead of Flutter MethodChannel, so this suite runs
    // entirely without `WidgetsFlutterBinding`.
    sqfliteFfiInit();
    // Reading `databaseFactory` BEFORE we set our own throws when no
    // factory has been registered yet on the latest sqflite>=2.3.3.
    // Recover gracefully — there is nothing meaningful to restore from.
    try {
      previousFactory = databaseFactory;
    } on StateError {
      previousFactory = null;
    }
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() {
    // Restore (or clear) the global factory state so downstream test files
    // in the same `flutter test` VM don't inherit the FFI factory by
    // accident. If a downstream file needs a real platform channel, it
    // must register its own factory in its own setUpAll — fail-loudly is
    // safer than silently inheriting ours.
    databaseFactory = previousFactory;
  });

  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ff_db_migration_test_');
    path = p.join(dir.path, 'focusflow.db');
  });

  tearDown(() async {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  /// v1 baseline — policies + settings, no screen_policies.
  ///
  /// Uses the same [kV1CreateSql] constant as production's
  /// `LocalDatabase._createDB`, which closes the historical drift
  /// hazard where the test could pass against a phantom schema while
  /// prod's real CREATE clauses differed silently.
  Future<Database> openAtV1(String dbPath) async {
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(kV1CreateSql);
      },
    );
    await db.close();
    return db;
  }

  Future<Map<String, Map<String, Object?>>> readColumns(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(screen_policies)');
    return {
      for (final r in rows) (r['name'] as String): r,
    };
  }

  Future<List<String>> readIndexes(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA index_list($table)');
    return rows.map((r) => r['name'] as String).toList();
  }

  /// SQLite creates implicit indexes for `UNIQUE` constraints named
  /// `sqlite_autoindex_<table>_<seq>`. The `INTEGER PRIMARY KEY` rowid is
  /// special — it does NOT generate an auto-index. Filter those out so the
  /// migration tests can assert "user-declared indexes" cleanly.
  Future<List<String>> readExplicitIndexes(Database db, String table) async {
    final all = await readIndexes(db, table);
    return all
        .where((name) => !name.startsWith('sqlite_autoindex_'))
        .toList();
  }

  Future<Map<String, String>> readSettings(Database db) async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  test(
      'v1 → v4 full migration creates screen_policies + adds syncStatus defaults',
      () async {
    await openAtV1(path);

    var db = await openDatabase(
      path,
      version: 4,
      onCreate: (_, __) =>
          throw StateError('v4 must run onUpgrade path (file already v1)'),
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );
    try {
      final cols = await readColumns(db);
      final colNames = cols.keys.toSet();
      expect(colNames, containsAll(const <String>{
            'id',
            'packageName',
            'screenKey',
            'friendlyName',
            'timeLimitMinutes',
            'isActive',
            'todayUsageMs',
            'serverId',
            'lastUpdated',
            'syncStatus',
            'syncAttempts',
          }));

      // Composite unique — verify the literal SQL emitted by sqflite
      // contains the UNIQUE(packageName, screenKey) clause.
      final masterRows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' "
        "AND name='screen_policies'",
      );
      final sql = masterRows.first['sql'] as String;
      expect(sql, contains('UNIQUE(packageName, screenKey)'));

      // Both indexes present.
      final idxs = await readIndexes(db, 'screen_policies');
      expect(idxs, containsAll(<String>[
        'idx_screen_policies_pkg',
        'idx_screen_policies_sync_status',
      ]));

      // Default values: PRAGMA returns the literal default clause — string
      // types are wrapped in single quotes.
      expect(cols['syncStatus']!['dflt_value'], "'pending'");
      expect(cols['syncStatus']!['notnull'], 1);
      expect(cols['syncAttempts']!['dflt_value'], '0');
      expect(cols['syncAttempts']!['notnull'], 1);
    } finally {
      await db.close();
    }
  });

  test(
      'v1 → v4 + insert: defaults fire and composite-UNIQUE rejects duplicates',
      () async {
    await openAtV1(path);
    final db = await openDatabase(
      path,
      version: 4,
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );

    try {
      // Insert without specifying syncStatus/syncAttempts: defaults fire.
      await db.insert('screen_policies', <String, Object?>{
        'packageName': 'com.instagram.android',
        'screenKey': 'reels',
        'friendlyName': 'Reels',
        'timeLimitMinutes': 15,
        'isActive': 1,
        'todayUsageMs': 0,
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      final row = (await db.query(
        'screen_policies',
        where: 'screenKey = ?',
        whereArgs: <Object?>['reels'],
        limit: 1,
      ))
          .first;
      expect(row['syncStatus'], 'pending');
      expect(row['syncAttempts'], 0);

      // And the per-screen composite-UNIQUE still prevents duplicates.
      try {
        await db.insert('screen_policies', <String, Object?>{
          'packageName': 'com.instagram.android',
          'screenKey': 'reels',
          'friendlyName': 'Reels',
          'timeLimitMinutes': 15,
          'isActive': 0,
          'todayUsageMs': 0,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        fail('Duplicate composite-UNIQUE insert should have thrown');
      } on DatabaseException catch (e) {
        // sqflite_common_ffi surfaces constraint violations as
        // `DatabaseException` whose `toString()` contains
        // `UNIQUE constraint failed: …`. Tightening the matcher to
        // this specific exception class makes the assertion honest: if
        // the throw site stops being a UNIQUE violation (e.g. a NOT NULL
        // misconfiguration), the test will surface that explicitly
        // instead of swallowing the wrong failure mode.
        expect(
          e.toString().toLowerCase(),
          contains('unique constraint'),
          reason: 'expected a UNIQUE constraint violation, got: $e',
        );
      }
    } finally {
      await db.close();
    }
  });

  test(
      'runMigrations is idempotent on a v4 DB (no duplicate-column throw, no double-rename)',
      () async {
    // Boot at v4 from a v1-bridge file, then call runMigrations multiple
    // times directly. Without the PRAGMA-based idempotency guard in
    // `_addColumnIfMissing`, the second call would throw `duplicate column
    // name: syncStatus`. Without the WHERE-clause filter in the v3->v4
    // tombstone rename, the second call would either be a no-op (lucky)
    // or attempt to re-rename already-renamed keys into something else
    // (buggy).
    await openAtV1(path);
    var db = await openDatabase(
      path,
      version: 4,
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );
    await db.close();

    db = await openDatabase(
      path,
      version: 4,
      onCreate: (_, __) =>
          throw StateError('v4 should be reached via the v1→v4 open above'),
    );
    try {
      // Insert a tombstone row under the OLD prefix so the v3->v4 rename
      // has something to chew on during each direct invocation.
      await db.insert('settings', <String, Object?>{
        'key': '${kOldTombstoneKeyPrefix}com.example.id:reels',
        'value': '2025-01-01T00:00:00.000Z',
      });

      // Direct re-invocation simulates any path that re-enters
      // runMigrations (e.g. a multi-step open or an offline-online ping).
      await LocalDatabase.runMigrations(db, 3, 4);
      await LocalDatabase.runMigrations(db, 3, 4);
      await LocalDatabase.runMigrations(db, 3, 4);

      // Schema unchanged after the redundant calls.
      final cols = await readColumns(db);
      expect(cols.containsKey('syncStatus'), isTrue);
      expect(cols.containsKey('syncAttempts'), isTrue);

      final explicitIdxs = await readExplicitIndexes(db, 'screen_policies');
      expect(explicitIdxs.length, 2,
          reason: 'CREATE INDEX IF NOT EXISTS should not duplicate indexes');
      expect(explicitIdxs,
          containsAll(<String>[
            'idx_screen_policies_pkg',
            'idx_screen_policies_sync_status',
          ]));

      // Idempotency on the rename: only ONE tombstone row exists, and its
      // key is in the NEW format. If the rename fired twice, the key
      // would have become `tombstone..com.example.id:reels`
      // (tombstone. tombstone. <rest>) — bug.
      final settings = await readSettings(db);
      expect(
        settings.keys,
        equals(<String>['${kTombstoneKeyPrefix}com.example.id:reels']),
      );
      expect(settings['${kTombstoneKeyPrefix}com.example.id:reels'],
          '2025-01-01T00:00:00.000Z');
    } finally {
      await db.close();
    }
  });

  test(
      'v1 → v2 → v4 multi-step walk: cascade + idempotency + rename all hold',
      () async {
    // Real-world multi-step upgrade path: a user might keep the app open
    // across two app versions (or be force-upgraded by a sync service) and
    // have their DB file written to once at v2, then later at v4. Without
    // the cascade gates AND the PRAGMA guard on ALTER TABLE, the second
    // (or third) open would either skip the v3 columns (if the oldVersion
    // ladder were narrowed to `>= N-1`) or throw `duplicate column name`
    // (without the guard). With cascade correct: v1->v2 opens trigger
    // every cascade branch up to v4-effective state; subsequent v2->v4
    // closes-and-reopens exercise the strict sibling branches (v3 only on
    // first step, v4 only on second).
    await openAtV1(path);

    // Step 1: open at v2. Cascade semantics mean oldVersion=1 < 2/3/4
    // fires ALL branches — schema is at v4-effective state on file with
    // user_version=2 after this single call.
    var db = await openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );
    try {
      final colsAfterV2 = await readColumns(db);
      expect(colsAfterV2.keys,
          containsAll(<String>['syncStatus', 'syncAttempts']),
          reason: 'v2-open cascade should already include v3 columns');

      final idxsAfterV2 = await readIndexes(db, 'screen_policies');
      expect(
        idxsAfterV2,
        containsAll(<String>[
          'idx_screen_policies_pkg',
          'idx_screen_policies_sync_status',
        ]),
      );
    } finally {
      await db.close();
    }

    // Step 2: reopen at v4. onUpgrade(2, 4) fires. v3 branch fires the
    // PRAGMA-guarded ADD COLUMNs (both columns already exist -> no-op)
    // and IF NOT EXISTS indexes; v4 branch fires the tombstone rename
    // (WHERE filter excludes new-format keys -> no-op when no fixtures).
    db = await openDatabase(
      path,
      version: 4,
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );
    try {
      // Tables + indexes unchanged. No duplicate column names thrown.
      final cols = await readColumns(db);
      expect(cols.keys.toSet(), containsAll(<String>{
        'id',
        'packageName',
        'screenKey',
        'friendlyName',
        'timeLimitMinutes',
        'isActive',
        'todayUsageMs',
        'serverId',
        'lastUpdated',
        'syncStatus',
        'syncAttempts',
      }));

      final explicitIdxs = await readExplicitIndexes(db, 'screen_policies');
      expect(
        explicitIdxs.length,
        2,
        reason: 'multi-step open must NOT duplicate indexes',
      );
      expect(explicitIdxs,
          containsAll(<String>[
            'idx_screen_policies_pkg',
            'idx_screen_policies_sync_status',
          ]));

      // Defaults preserved across the multi-step upgrade.
      expect(cols['syncStatus']!['dflt_value'], "'pending'");
      expect(cols['syncAttempts']!['dflt_value'], '0');
    } finally {
      await db.close();
    }
  });

  test('reopen at the same version is a no-op (no migration re-run)',
      () async {
    // Run a full v1→v4 migration, then reopen at v4 — onCreate + onUpgrade
    // should NOT fire (the existing v4 file is presented as v4).
    await openAtV1(path);
    var db = await openDatabase(
      path,
      version: 4,
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );
    await db.close();

    var onCreateFired = false;
    var onUpgradeFired = false;
    db = await openDatabase(
      path,
      version: 4,
      onCreate: (_, __) {
        onCreateFired = true;
      },
      onUpgrade: (_, __, ___) {
        onUpgradeFired = true;
      },
    );
    await db.close();

    expect(onCreateFired, isFalse);
    expect(onUpgradeFired, isFalse);
  });

  test(
      'v3 → v4 migration renames old-format tombstone keys; '
      'leaves new-format keys and unrelated settings untouched; '
      'is idempotent on re-run', () async {
    // Bootstrap v3 state by opening at v3 with v1 data underneath — the
    // cascade fires all v2+v3 branches; tombstone rename doesn't fire
    // because we're at target v3.
    await openAtV1(path);
    var db = await openDatabase(
      path,
      version: 3,
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );

    // Preload the mixed fixture: old-format tombstone rows (must rename),
    // new-format tombstone row (must stay), and an unrelated settings row
    // (must stay).
    await db.insert('settings', <String, Object?>{
      'key': '${kOldTombstoneKeyPrefix}com.example.app:reels',
      'value': '2025-01-01T00:00:00.000Z',
    });
    await db.insert('settings', <String, Object?>{
      'key': '${kOldTombstoneKeyPrefix}com.example.app:posts',
      'value': '2025-01-02T00:00:00.000Z',
    });
    await db.insert('settings', <String, Object?>{
      'key': '${kTombstoneKeyPrefix}com.other.app:explore',
      'value': '2025-01-03T00:00:00.000Z',
    });
    await db.insert('settings', <String, Object?>{
      'key': 'screenPoliciesLastSyncAt',
      'value': '2025-02-15T12:00:00.000Z',
    });
    await db.close();

    // Sanity check pre-migration state — the helpers are going to read
    // this in a moment, so we want explicit confirmation that the
    // bootstrap left mixed keys.
    db = await openDatabase(
      path,
      version: 3,
      onCreate: (_, __) => throw StateError('reopen should not create'),
    );
    final preSettings = await readSettings(db);
    expect(
      preSettings.keys,
      containsAll(<String>{
        '${kOldTombstoneKeyPrefix}com.example.app:reels',
        '${kOldTombstoneKeyPrefix}com.example.app:posts',
        '${kTombstoneKeyPrefix}com.other.app:explore',
        'screenPoliciesLastSyncAt',
      }),
    );
    await db.close();

    // Trigger v3 → v4.
    db = await openDatabase(
      path,
      version: 4,
      onUpgrade: (db, oldV, newV) => LocalDatabase.runMigrations(db, oldV, newV),
    );
    try {
      final afterRename = await readSettings(db);
      // Old keys folded into new format with VALUES preserved.
      expect(
          afterRename['${kTombstoneKeyPrefix}com.example.app:reels'],
          '2025-01-01T00:00:00.000Z');
      expect(
          afterRename['${kTombstoneKeyPrefix}com.example.app:posts'],
          '2025-01-02T00:00:00.000Z');
      // Old keys gone.
      expect(
          afterRename.containsKey(
              '${kOldTombstoneKeyPrefix}com.example.app:reels'),
          isFalse,
          reason: 'old-format key should have been renamed away');
      expect(
          afterRename.containsKey(
              '${kOldTombstoneKeyPrefix}com.example.app:posts'),
          isFalse,
          reason: 'old-format key should have been renamed away');
      // New-format key untouched.
      expect(afterRename['${kTombstoneKeyPrefix}com.other.app:explore'],
          '2025-01-03T00:00:00.000Z');
      // Unrelated settings row untouched.
      expect(afterRename['screenPoliciesLastSyncAt'],
          '2025-02-15T12:00:00.000Z');
      // Total count: 4 entries (was 4, still 4 after rename — two
      // collisions would have created duplicates and bumped the count).
      expect(afterRename.length, 4);
    } finally {
      await db.close();
    }

    // Idempotency: reopen at v4 again. The WHERE-filter on the rename
    // SQL means already-renamed keys are not touched; no schema changes;
    // no exceptions thrown.
    db = await openDatabase(
      path,
      version: 4,
      onCreate: (_, __) => throw StateError('reopen should not create'),
      onUpgrade: (_, __, ___) =>
          throw StateError('reopen at v4 from v4 must not re-fire migrations'),
    );
    try {
      final afterSecondRun = await readSettings(db);
      expect(afterSecondRun, equals(<String, String>{
        '${kTombstoneKeyPrefix}com.example.app:reels': '2025-01-01T00:00:00.000Z',
        '${kTombstoneKeyPrefix}com.example.app:posts': '2025-01-02T00:00:00.000Z',
        '${kTombstoneKeyPrefix}com.other.app:explore': '2025-01-03T00:00:00.000Z',
        'screenPoliciesLastSyncAt': '2025-02-15T12:00:00.000Z',
      }));
    } finally {
      await db.close();
    }
  });
}
