import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../services/tombstone_prefixes.dart';
import 'local_database_schema.dart';

/// Local SQLite store for FocusFlow user rules.
///
/// Schema versions:
///   - v1: `policies`, `settings`
///   - v2: + `screen_policies` (Phase 2)
///   - v3: + `syncStatus` + `syncAttempts` on `screen_policies` for delta-sync
///   - v4: pure data rewrite — rename `settings.tombstone_<pkg>:<screen>`
///     keys to `tombstone.<pkg>:<screen>` so users upgrading keep their
///     pending deletes. NO schema shape changes.
class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();

  /// Per-instance DB handle. Moved off `static` so a test can construct
  /// multiple `LocalDatabase` instances backed by separate FFI / in-memory
  /// sqflite handles without polluting the production singleton's handle.
  Database? _database;

  static const int _schemaVersion = 4;

  /// Production constructor — lazily opens the platform sqflite file at
  /// `focusflow.db` on first [.database] access.
  LocalDatabase._init();

  /// Test-only constructor: pre-bind the underlying sqflite [Database]
  /// (typically an FFI-backed temp file opened by
  /// `sqflite_common_ffi`). The caller owns the handle — close it from
  /// `tearDown` to release the OS lock. NOT for production use.
  @pragma('vm:testing')
  LocalDatabase.fromTestDatabase(Database db) : _database = db;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final db = await _initDB('focusflow.db');
    _database = db;
    return db;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: _createDB,
      onUpgrade: runMigrations,
    );
  }

  Future _createDB(Database db, int version) async {
    // v1 baseline (policies + settings) sourced from the canonical
    // [kV1CreateSql] constant so production and `database_migration_test`
    // share one definition. The v4 additions below (screen_policies +
    // indexes) are still inline because they're conditional on the
    // current schema version — once a v5 Swiss-cheese-creep gets out of
    // hand, hoist them too as a sibling `kV4CreateSql` constant.
    await db.execute(kV1CreateSql);

    // Phase 2: per-screen rules. Composite unique key on (packageName, screenKey)
    // so the user can have at most one rule per in-app screen. Phase 3 added
    // syncStatus + syncAttempts columns so the delta-sync job can pick up
    // rows whose state diverges from what the server knows about.
    await db.execute('''
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

    await db.execute(
      'CREATE INDEX idx_screen_policies_pkg ON screen_policies(packageName)',
    );
    await db.execute(
      'CREATE INDEX idx_screen_policies_sync_status '
      'ON screen_policies(syncStatus)',
    );
  }

  /// v1 → v2: bring old installs forward by adding `screen_policies`.
  /// v2 → v3: add syncStatus + syncAttempts columns on screen_policies for
  /// the per-user delta-sync job.
  /// v3 → v4: rename `settings.tombstone_<pkg>:<screen>` rows to the new
  /// `tombstone.<pkg>:<screen>` prefix (no schema shape change).
  ///
  /// **Cascade semantics (by design):** the three `if (oldVersion < N)` branches
  /// are independent gates, NOT a sequential ladder. We can NOT widen them to
  /// `if (oldVersion >= N-1 && oldVersion < N)` because sqflite delivers the
  /// v1→v4 upgrade as a single `onUpgrade(1, 4)` call with no intermediate
  /// `onUpgrade(2, 3)` / `onUpgrade(3, 4)`. Each branch MUST fire on its own
  /// when jump-migrating.
  ///
  /// Side-effect of the cascade: opening a v1 file at **target** v2 still
  /// passes `oldVersion=1 < 3 < 4`, so every branch fires and the resulting
  /// schema carries v3+v4 state. This is fine because v3's ALTER TABLE is
  /// idempotency-guarded below and the v4 rename is also idempotent
  /// (WHERE-clause filters to old-format keys only).
  ///
  /// Static + idempotent at every step:
  ///   • `CREATE TABLE IF NOT EXISTS` — built into SQLite.
  ///   • `CREATE INDEX IF NOT EXISTS` — built into SQLite.
  ///   • `ALTER TABLE ADD COLUMN` — NOT idempotent in SQLite < 3.35.0 ⇒ we
  ///     probe via PRAGMA `table_info(table)` first and skip if the column
  ///     is already present. Without this guard, a multi-step upgrade
  ///     path (open at v2 first then at v3) would throw "duplicate
  ///     column name" because the `oldVersion < 3` branch re-applies its
  ///     ALTER TABLE — even though step 1 already added it.
  ///
  /// Static so migration tests can drive production migration SQL by hand
  /// (using a hardcoded v1 bootstrap) instead of duplicating SQL inside
  /// test files.
  static Future<void> runMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS screen_policies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          packageName TEXT NOT NULL,
          screenKey TEXT NOT NULL,
          friendlyName TEXT NOT NULL,
          timeLimitMinutes INTEGER NOT NULL DEFAULT 0,
          isActive INTEGER NOT NULL DEFAULT 0,
          todayUsageMs INTEGER NOT NULL DEFAULT 0,
          serverId TEXT,
          lastUpdated TEXT NOT NULL,
          UNIQUE(packageName, screenKey)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_screen_policies_pkg '
        'ON screen_policies(packageName)',
      );
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(
        db,
        table: 'screen_policies',
        column: 'syncStatus',
        declaration: "TEXT NOT NULL DEFAULT 'pending'",
      );
      await _addColumnIfMissing(
        db,
        table: 'screen_policies',
        column: 'syncAttempts',
        declaration: 'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_screen_policies_sync_status '
        'ON screen_policies(syncStatus)',
      );
    }
    if (oldVersion < 4) {
      await _renameTombstonePrefixes(db);
    }
  }

  /// v3 → v4: rename any `settings.key` rows that match the OLD tombstone
  /// prefix to the NEW one. Keeps queued deletes alive across the upgrade
  /// instead of silently dropping them.
  ///
  /// The prefix pair is sourced from [kOldTombstoneKeyPrefix] and
  /// [kTombstoneKeyPrefix] in `tombstone_prefixes.dart` as the canonical
  /// source-of-truth — every callsite in the app imports from there, so
  /// the migration SQL cannot drift from the live prefix if either ever
  /// changes. Compile-time `const` strings mean the interpolated SQL is
  /// effectively a static literal — no injection surface.
  ///
  /// **Idempotent:** the WHERE-filter only matches old-format keys
  /// (distinguished by the byte at `oldPrefix.length`), so running this on
  /// a v4 DB is a safe no-op.
  ///
  /// **Pure data rewrite; does not touch schema.**
  static Future<void> _renameTombstonePrefixes(Database db) async {
    const oldPrefix = kOldTombstoneKeyPrefix;
    const newPrefix = kTombstoneKeyPrefix;
    const oldTail = kOldTombstoneTail;
    const newTail = kNewTombstoneTail;

    // Drift guards fire early if either constant ever drifts in shape -
    // these would silently turn the rename into a no-op, so we want
    // failures at migration time, not in production after a deluge of
    // orphaned isActive=false rows on the server.
    assert(
      oldPrefix.length == newPrefix.length,
      'tombstone prefix length drift: old="$oldPrefix" (${oldPrefix.length}) '
      'vs new="$newPrefix" (${newPrefix.length}). The migration SQL relies '
      'on identical lengths so position-based SELECT is well-defined.',
    );
    const oldLen = oldPrefix.length;
    assert(
      oldTail != newTail,
      'tombstone prefix boundary drift: old="$oldPrefix" and new="$newPrefix" '
      'share the same tail byte "$oldTail". The WHERE-filter cannot '
      'discriminate old vs new keys, so the rename would be a silent no-op.',
    );

    // Raw-SQL injection guard: both constants are interpolated directly
    // into the UPDATE statement, so any character that would terminate a
    // SQL token (apostrophe, semicolon, paren, etc.) would either break
    // parsing silently or execute injected SQL. Whitelist alphanumerics,
    // `_`, and `.` - the only characters we actually need.
    assert(
      kSqlSafePattern.hasMatch(oldPrefix) &&
          kSqlSafePattern.hasMatch(newPrefix) &&
          kSqlSafePattern.hasMatch(oldTail) &&
          kSqlSafePattern.hasMatch(newTail),
      'tombstone prefix contains characters unsafe for raw SQL interpolation '
      '(must match $kSqlSafePattern): old="$oldPrefix", new="$newPrefix".',
    );

    await db.execute(
      "UPDATE settings "
      "SET key = '$newPrefix' || substr(key, ${oldLen + 1}) "
      "WHERE substr(key, $oldLen, 1) = '$oldTail'",
    );
  }

  /// Idempotent ALTER TABLE: probes PRAGMA table_info and only adds the
  /// column if it doesn't already exist. Centralized so the v2→v3 branch
  /// can be called multiple times (e.g. by a multi-step upgrade path) without
  /// throwing "duplicate column name".
  static Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String declaration,
  }) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }

  // ── Phase 2: screen_policies CRUD ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getScreenPolicies() async {
    final db = await database;
    return db.query('screen_policies');
  }

  /// Upsert by `(packageName, screenKey)` — replacing the row if one already
  /// exists for that screen. `serverId` is the Mongo `_id` returned from
  /// `/api/v1/screen-policies`; kept so we can DELETE by id when needed.
  Future<void> upsertScreenPolicy(Map<String, dynamic> row) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final merged = Map<String, dynamic>.from(row)..putIfAbsent('lastUpdated', () => now);
    merged['lastUpdated'] = now;
    // Any explicit upsert from the UI assumes the row diverges from what
    // the server knows (or learns soon). Default to pending unless caller
    // passed an explicit syncStatus (e.g. remote hydration passing 'synced').
    merged.putIfAbsent('syncStatus', () => 'pending');
    merged.putIfAbsent('syncAttempts', () => 0);
    await db.insert(
      'screen_policies',
      merged,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteScreenPolicy(String packageName, String screenKey) async {
    final db = await database;
    await db.delete(
      'screen_policies',
      where: 'packageName = ? AND screenKey = ?',
      whereArgs: [packageName, screenKey],
    );
  }

  Future<void> deleteScreenPolicyByServerId(String serverId) async {
    final db = await database;
    await db.delete(
      'screen_policies',
      where: 'serverId = ?',
      whereArgs: [serverId],
    );
  }

  Future<void> updateScreenUsage(String packageName, String screenKey, int usedMs) async {
    final db = await database;
    await db.update(
      'screen_policies',
      {
        'todayUsageMs': usedMs,
        'lastUpdated': DateTime.now().toIso8601String(),
      },
      where: 'packageName = ? AND screenKey = ?',
      whereArgs: [packageName, screenKey],
    );
  }

  // ── Phase 3: delta-sync bookkeeping ──────────────────────────────────────

  /// All rows whose `syncStatus` is 'pending' or 'failed' — these are the
  /// candidates for the next push to /api/v1/screen-policies/sync. The
  /// delta-sync job iterates this list, posts it, and (per-row outcomes)
  /// updates the status via [markScreenPolicySyncStatus].
  Future<List<Map<String, dynamic>>> getPendingScreenPoliciesForSync({
    int limit = 200,
  }) async {
    final db = await database;
    return db.query(
      'screen_policies',
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'lastUpdated ASC',
      limit: limit,
    );
  }

  /// Bulk-apply sync outcomes per row. Hard-deletes are encoded as
  /// [deleted] = true in the [syncScreenPolicies] payload and result in
  /// the local row being removed (we don't keep tombstones locally — the
  /// `lastUpdated: now` + syncStatus='synced' on a missing row IS the
  /// tombstone signal for the next push).
  Future<void> markScreenPoliciesSyncStatus(
    List<({String packageName, String screenKey, String status, int? attempts})> updates,
  ) async {
    if (updates.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final u in updates) {
      batch.update(
        'screen_policies',
        {
          'syncStatus': u.status,
          'syncAttempts': u.attempts ?? 0,
        },
        where: 'packageName = ? AND screenKey = ?',
        whereArgs: [u.packageName, u.screenKey],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Mark a single row as pending (e.g. after a UI edit crosses into
  /// dirty state).
  Future<void> markScreenPolicyPending(String packageName, String screenKey) async {
    final db = await database;
    await db.update(
      'screen_policies',
      {'syncStatus': 'pending', 'syncAttempts': 0},
      where: 'packageName = ? AND screenKey = ?',
      whereArgs: [packageName, screenKey],
    );
  }

  /// Constants for syncStatus values.
  static const String syncStatusPending = 'pending';
  static const String syncStatusSyncing = 'syncing';
  static const String syncStatusSynced = 'synced';
  static const String syncStatusFailed = 'failed';
}
