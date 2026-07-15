import '../storage/local_database.dart';
import 'package:sqflite/sqflite.dart';

// Canonical source-of-truth for the tombstone (pending-delete) key
// prefixes. `LocalDatabase._renameTombstonePrefixes` references them
// directly when building raw-SQL migrations, so the literal lives in
// one place. Application-layer code reads `LocalPolicyService.tombstoneKeyPrefix`
// as a re-aliased class-level constant for convenience.
import 'tombstone_prefixes.dart';

class LocalPolicyService {
  /// Optional override of [LocalDatabase.instance]. Production callers
  /// don't pass anything; tests pass an FFI-backed [LocalDatabase] to
  /// share a single source of truth with their `fromTestDatabase`
  /// instance instead of routing through the production singleton's
  /// lazy auto-opened temp file.
  final LocalDatabase? _dbOverride;

  LocalPolicyService({LocalDatabase? dbOverride})
      : _dbOverride = dbOverride;

  /// Returns the [LocalDatabase] backing all reads/writes. Defaults to
  /// [LocalDatabase.instance] for production callers.
  LocalDatabase get _db => _dbOverride ?? LocalDatabase.instance;

  Future<List<Map<String, dynamic>>> getPolicies() async {
    final db = await _db.database;
    return await db.query('policies');
  }

  Future<void> upsertPolicy({
    required String packageName,
    required String appName,
    required int timeLimitMinutes,
    bool isActive = true,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    
    await db.insert(
      'policies',
      {
        'packageName': packageName,
        'appName': appName,
        'timeLimitMinutes': timeLimitMinutes,
        'isActive': isActive ? 1 : 0,
        'lastUpdated': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUsage(String packageName, int usedMs) async {
    final db = await _db.database;
    final policies = await db.query(
      'policies',
      where: 'packageName = ?',
      whereArgs: [packageName],
    );

    if (policies.isNotEmpty) {
      final policy = policies.first;
      final limitMinutes = policy['timeLimitMinutes'] as int;
      // Bug B root-cause fix (Nov 2025): full-block policies
      // (limitMinutes == 0) explicitly mean "always block", NOT
      // "you went over your limit". Without this guard, any
      // `usedMs > 0` would flip `isOverLimit = 1` (because
      // `usedMs >= 0L` is always true), which then made SetLimitScreen
      // render the misleading "Settings are locked until tomorrow to
      // prevent bypass" warning and disable the time-limit slider.
      final limitMs = limitMinutes * 60 * 1000;
      final isOverLimit =
          limitMinutes > 0 && usedMs >= limitMs ? 1 : 0;

      await db.update(
        'policies',
        {
          'todayUsageMs': usedMs,
          'isOverLimit': isOverLimit,
          'lastUpdated': DateTime.now().toIso8601String(),
        },
        where: 'packageName = ?',
        whereArgs: [packageName],
      );
    }
  }

  Future<void> deletePolicy(String packageName) async {
    final db = await _db.database;
    await db.delete(
      'policies',
      where: 'packageName = ?',
      whereArgs: [packageName],
    );
  }

  Future<void> togglePolicy(String packageName, bool isActive) async {
    final db = await _db.database;
    await db.update(
      'policies',
      {'isActive': isActive ? 1 : 0},
      where: 'packageName = ?',
      whereArgs: [packageName],
    );
  }

  // Settings methods
  Future<void> saveSetting(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await _db.database;
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }

  Future<void> deleteSetting(String key) async {
    final db = await _db.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  /// Read every setting key matching [prefix] as a `Map<key, value>`. Used
  /// for "list each pending tombstone, prefix `tombstone_`" — keeps each
  /// delete intent isolated so corruption of one doesn't wipe the others
  /// the way a single JSON-blob setting would.
  Future<Map<String, String>> getSettingsByPrefix(String prefix) async {
    final db = await _db.database;
    final rows = await db.query(
      'settings',
      where: 'key LIKE ?',
      whereArgs: ['$prefix%'],
    );
    return {
      for (final r in rows)
        (r['key'] as String): (r['value'] as String),
    };
  }

  // ── Tombstone (pending-delete) helpers ──────────────────────────
  /// Canonical NEW tombstone key prefix (re-aliased from
  /// `kTombstoneKeyPrefix` in `tombstone_prefixes.dart`). Application-layer
  /// code continues to read `LocalPolicyService.tombstoneKeyPrefix` exactly
  /// as before; the canonical literal lives in one place, shared with the
  /// `LocalDatabase._renameTombstonePrefixes` migration SQL.
  ///
  /// One settings row per pending delete intent, keyed
  /// `tombstone.<pkg>:<screen>`. The `.` separator is intentional:
  /// SQL `LIKE` treats `_` as a single-character wildcard, so a package
  /// name starting with `tombstone_x` would have matched the OLD underscore
  /// prefix and produced phantom tombstones for unrelated policy IDs. `.`
  /// is a literal in LIKE, eliminating that wildcard ambiguity.
  static const String tombstoneKeyPrefix = kTombstoneKeyPrefix;

  Future<void> recordPendingTombstone(String packageName, String screenKey) async {
    try {
      await saveSetting(
        '$tombstoneKeyPrefix$packageName:$screenKey',
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // sqflite unavailable on web — accept the loss; the best-effort
      // DELETE in `AppsNotifier.deleteScreenPolicy` already tried.
    }
  }

  Future<void> clearPendingTombstone(String packageName, String screenKey) async {
    try {
      await deleteSetting('$tombstoneKeyPrefix$packageName:$screenKey');
    } catch (_) {}
  }

  /// Returns a map of `<pkg>:<screen> → ISO timestamp` for every queued
  /// delete intent. The `tombstone.` prefix is stripped from keys.
  Future<Map<String, String>> getPendingTombstones() async {
    try {
      final rows = await getSettingsByPrefix(tombstoneKeyPrefix);
      return {
        for (final entry in rows.entries)
          if (entry.key.startsWith(tombstoneKeyPrefix))
            entry.key.substring(tombstoneKeyPrefix.length): entry.value,
      };
    } catch (_) {
      return const {};
    }
  }
}
