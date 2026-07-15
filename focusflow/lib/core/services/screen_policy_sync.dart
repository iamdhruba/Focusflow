import 'package:focusflow/core/services/local_policy_service.dart';
import 'package:focusflow/core/services/screen_policy_service.dart';
import 'package:focusflow/core/storage/local_database.dart';

/// Caller-supplied POST lambda. Production code wraps a real
/// `ScreenPolicyService`; tests supply a canned-response fake.
typedef SyncPoster = Future<SyncScreenPolicyResult> Function(
  List<Map<String, dynamic>> payload,
);

/// Drives the Phase-3 per-user delta-sync pipeline (the same body
/// WorkManager runs every ~15 min via `localSyncTask`, and
/// `AppsNotifier.syncScreenPoliciesToServer()` runs on cold launch):
///
///   1. Read pending local screen-policy rows (`syncStatus = pending|failed`)
///      AND settings-table tombstones (pending delete intent).
///   2. Shape them into the `{policies: [...]}` payload (tombstones first
///      so a server-side upsert applied earlier in the batch gets removed
///      regardless of order).
///   3. POST via [postSync]. In production that's a real HTTP round-trip;
///      in tests that's a canned-response lambda.
///   4. Apply per-row outcomes (`applied` / `noop` / `deleted` /
///      `skipped_newer` -> `synced`, `invalid` / unknown -> `failed`).
///      `deleted` / `noop` / `skipped_newer` ALSO clear the matching local
///      tombstone (intent fulfilled by server). `applied` is treated as
///      "synced" but the tombstone is preserved (server may have
///      misinterpreted the `deleted:true` flag and the intent is still
///      unresolved — let the next sync retry).
///   5. Stamp `screenPoliciesLastSyncAt` so we can audit when we last
///      talked to the server.
///
/// **Returns** the server's `SyncScreenPolicyResult` on a non-empty
/// payload that the server processed, `null` for the no-op success
/// (empty payload) AND for any exception thrown during the flow.
///
/// **Whole-batch failure** (POST returned `success: false`) keeps the
/// rows pending and bumps their `syncAttempts` counter. After 5 failed
/// attempts the row graduates to `failed` status so the UI can surface
/// "your rules aren't syncing" rather than looping forever.
Future<SyncScreenPolicyResult?> performScreenPolicySync({
  required LocalDatabase db,
  required LocalPolicyService local,
  required SyncPoster postSync,
}) async {
  try {
    final pendingRows = await db.getPendingScreenPoliciesForSync();
    final tombstones = await local.getPendingTombstones();
    final payload = <Map<String, dynamic>>[];

    for (final entry in tombstones.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 2) continue;
      payload.add({
        'packageName': parts[0],
        'screenKey': parts[1],
        'deleted': true,
        'localLastUpdated': entry.value,
      });
    }
    for (final row in pendingRows) {
      payload.add({
        'packageName': row['packageName'],
        'screenKey': row['screenKey'],
        if (row['friendlyName'] != null) 'friendlyName': row['friendlyName'],
        'timeLimitMinutes': row['timeLimitMinutes'] as int? ?? 0,
        'isActive': (row['isActive'] as int? ?? 0) == 1,
        'localLastUpdated': row['lastUpdated'] as String?,
      });
    }

    if (payload.isEmpty) {
      // No rows to push — but still record when we last looked so the UI
      // can show "last synced 30s ago" instead of "never".
      await local.saveSetting(
        'screenPoliciesLastSyncAt',
        DateTime.now().toIso8601String(),
      );
      return null;
    }

    final res = await postSync(payload);
    if (!res.success) {
      await _bumpFailedAttempts(db, pendingRows);
      return res;
    }

    final updates = <({
      String packageName,
      String screenKey,
      String status,
      int? attempts,
    })>[];
    for (final r in res.results) {
      final pkg = r['packageName']?.toString() ?? '';
      final key = r['screenKey']?.toString() ?? '';
      final statusStr = r['status']?.toString() ?? 'unknown';
      if (pkg.isEmpty || key.isEmpty) continue;

      // Per-row terminal status. `applied`/`noop`/`deleted`/`skipped_newer`
      // all count as "synced" because the server acknowledged the row;
      // anything else (`invalid`, null, future enum variants) goes to
      // `failed` so the UI can surface it.
      final isOk = statusStr == 'applied' ||
          statusStr == 'noop' ||
          statusStr == 'deleted' ||
          statusStr == 'skipped_newer';
      updates.add((
        packageName: pkg,
        screenKey: key,
        status:
            isOk ? LocalDatabase.syncStatusSynced : LocalDatabase.syncStatusFailed,
        attempts: isOk ? 0 : 99,
      ));

      // Tombstone clearing: server has resolved the delete intent only when
      // it returned `deleted` (delete succeeded), `noop` (nothing to do,
      // probably already gone), or `skipped_newer` (server has fresher
      // state than our delete intent). `applied` is intentionally NOT
      // included — that would mean the server ignored our `deleted:true`
      // flag, and we want the next sync to retry rather than believe
      // the intent is fulfilled.
      final isTombstoneCleared = statusStr == 'deleted' ||
          statusStr == 'noop' ||
          statusStr == 'skipped_newer';
      if (isTombstoneCleared && tombstones.containsKey('$pkg:$key')) {
        await local.clearPendingTombstone(pkg, key);
      }
    }

    if (updates.isNotEmpty) {
      await db.markScreenPoliciesSyncStatus(updates);
    }
    await local.saveSetting(
      'screenPoliciesLastSyncAt',
      DateTime.now().toIso8601String(),
    );
    return res;
  } catch (_) {
    // Network or DB exception: leave rows pending, next sync retries.
    return null;
  }
}

/// Bookkeeping for the whole-batch failure path. Each pending row's
/// `syncAttempts` counter is incremented; the row graduates from
/// `pending` to `failed` after 5 attempts so the UI can show the user
/// "your offline edits aren't reaching the server." Pulled out of the
/// main orchestrator so the call site stays focused on per-row
/// outcomes.
Future<void> _bumpFailedAttempts(
  LocalDatabase db,
  List<Map<String, dynamic>> pendingRows,
) async {
  final updates = <({
    String packageName,
    String screenKey,
    String status,
    int? attempts,
  })>[];
  for (final row in pendingRows) {
    final pkg = row['packageName']?.toString();
    final key = row['screenKey']?.toString();
    if (pkg == null || key == null) continue;
    final attempts = (row['syncAttempts'] as int? ?? 0) + 1;
    updates.add((
      packageName: pkg,
      screenKey: key,
      status: attempts >= 5
          ? LocalDatabase.syncStatusFailed
          : LocalDatabase.syncStatusPending,
      attempts: attempts,
    ));
  }
  if (updates.isNotEmpty) {
    await db.markScreenPoliciesSyncStatus(updates);
  }
}
