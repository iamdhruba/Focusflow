// Canonical constants for tombstone (pending-delete) key prefixes.
//
// Lives outside both `local_database.dart` and `local_policy_service.dart`
// to break the import cycle between them - `LocalDatabase` needs the OLD
// prefix for the schema-version-4 migration; `LocalPolicyService` exposes
// the NEW prefix as a class-level alias for application code.
//
// `k`-prefixed top-level constants are a Dart convention for compile-time
// values that have no namespace semantics - just `const` references.

// NEW tombstone key prefix used by current builds.
//
// One `settings` row per pending delete intent, keyed
// `tombstone.<pkg>:<screen>`. The `.` separator is intentional: SQL
// `LIKE` treats `_` as a single-character wildcard, so a package name
// starting with `tombstone_x` would match a `tombstone_` prefix and
// produce phantom tombstones for unrelated policy IDs. `.` is a literal
// in LIKE, eliminating the wildcard ambiguity.
//
// MUST be comprised only of [A-Za-z0-9.] -
// `LocalDatabase._renameTombstonePrefixes` compiles this directly into
// raw SQL, so any character that would change SQL tokenization (apostrophe,
// semicolon, paren, etc.) would break the migration silently. A runtime
// assertion in the migration helper enforces this contract.
const String kTombstoneKeyPrefix = 'tombstone.';

// OLD tombstone key prefix used before the dot-format rename. Retained
// at the constant level FOR MIGRATION-TIME USE ONLY -
// `LocalDatabase._renameTombstonePrefixes` rewrites keys with this
// prefix in place during the schema-version-4 upgrade.
//
// New application code MUST NOT use this - always use
// [kTombstoneKeyPrefix] (`tombstone.`) instead.
//
// MUST also be composed only of [A-Za-z0-9_] for the same raw-SQL reason
// as [kTombstoneKeyPrefix]; bounds check lives in the migration helper.
const String kOldTombstoneKeyPrefix = 'tombstone_';

// Shared tail bytes for distinguishing OLD vs NEW format keys by
// position. Hoisted as top-level constants because Dart's `const`
// evaluator cannot invoke `String[int]` indexing on a `const String`
// to produce another `const String` (methods vs constructors), so
// the migration helper reads these directly instead of computing them
// inline.
const String kOldTombstoneTail = '_';
const String kNewTombstoneTail = '.';

// Whitelist pattern for SQL safety: only byte sequences composed of
// alphanumerics, underscore, and period. Compiled once at startup
// (top-level `const`) and reused across every migration-invocation
// so the regex engine never re-parses the pattern.
final RegExp kSqlSafePattern = RegExp(r'^[A-Za-z0-9._]+$');
