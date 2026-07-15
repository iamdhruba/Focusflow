/// Canonical DDL for the v1 baseline schema. Single source of truth so
/// production's `LocalDatabase._createDB` (used for fresh installs at
/// the current schema version) and `database_migration_test.openAtV1`
/// (used to bootstrap a v1 file for migration tests) cannot drift.
///
/// Multi-statement string — SQLite parses `;`-separated statements in a
/// single `await db.execute(...)` call. Order is preserved for future
/// foreign-key safety: `policies` is declared before `settings` because
/// of the convention even though currently no FKs reference these
/// tables.
///
/// Hoisted as a top-level [String] (not a class member) so both the
/// production file (`lib/core/storage/local_database.dart`) and the
/// test file (`test/database_migration_test.dart`) import the same
/// literal without indirection through a class.
const String kV1CreateSql = '''
  -- v1 baseline (policies + settings). Do not modify without a version
  -- bump; visit `LocalDatabase.runMigrations` for the upgrade path.
  -- SQLite ignores `--` comments so this is purely provenance.
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
  );
  CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
''';
