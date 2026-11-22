# QA round 5 (2026-11-22)

| Topic | Checks | Blocking |
|---|---|---|
| A — store `fix/303-plugin-registry` (`350c160`, 1 commit on `upstream/main` `fe154e1`) | hive_ce 2.24.0 source (frame/key/value/crc/delete/compaction/box name); a real `app_preferences.hive` written by hive_ce 2.24.0 (plain, compacted, deleted key, mixed-case box name) and read with `readHiveStrings`; a corrupt-frame file read by hive_ce and by `readHiveStrings`; Otzaria `dev` @ `cee5952` (`AppPaths.getDatabasesPath`, `resolvePluginsDbPath`/`_writableDatabasesDirectory`, `HiveCache`, `SettingsRepository`, `PortablePaths`); `cd native && node --test` | **yes** (A1, A2) |
| B — launcher `fix/deterministic-test-plugin-zip` (`1049d89`, 1 commit on `upstream/main` `8f772e4`) | `dart pub get`, `dart format --set-exit-if-changed`, `dart analyze`, all 8 test files that use `pluginBytes`; reproduced the flake before the fix and checked it is gone after; grep for other encoders whose bytes are compared | no — clean |

Toolchain: Flutter 3.47.2 / Dart 3.13.2, Node v22.23.5.

## Command outputs

### A: `cd native && node --test`
```
# tests 220
# suites 53
# pass 220
# fail 0
```

### A: a real hive_ce file vs `readHiveStrings`
The generator opened box `'App_Preferences'` (hive lowercases it, so the file is `app_preferences.hive`). It then ran: put library, put databases=`D:\ספרייה\databases`, put int key 7, put bool, put a 300-char string, put databases=`E:\אוצריא\databases`, put library=null. Variants: `compact()`, and `delete('key-databases-path')`.
```
out-plain   [["key-library-path",null],["key-databases-path","E:\\אוצריא\\databases"],["key-dark-mode",null],["long","x…"]]
out-compact [["key-dark-mode",null],["long","x…"],["key-databases-path","E:\\אוצריא\\databases"],["key-library-path",null]]
out-delete  [["key-library-path",null],["key-databases-path",null],["key-dark-mode",null],["long","x…"]]
```
All three are correct. The CRC is standard CRC-32 over `[length .. end of value]`: zlib `crc32` matched 7/7 frames.

### B: plugins_manager
```
dart format --output=none --set-exit-if-changed .  -> Formatted 48 files (0 changed); exit 0
dart analyze                                       -> No issues found!
dart test <8 files using pluginBytes>              -> +270: All tests passed!
```
The 8 files: plugin_direct_installer, plugin_mirror_sync, plugin_build_integrity, plugin_mirror_store, plugin_store_client, plugin_manifest_reader, plugin_online_peek, plugins_manager. The known environment-only failures did not show up in these files.

Determinism probe: a throwaway script, since removed, called `pluginBytes('{"id":"x"}')`, waited 2.6 s, and called it again.
```
branch   (modified: DateTime(2024)): len 231/231 firstDiff=-1
upstream (no modified):              len 231/231 firstDiff=10
```
This reproduces the CI failure (byte 10 is the DOS time field) and shows that the fix removes it.

## Findings

### A1 — BLOCKING: the writability fallback of `resolvePluginsDbPath` is not ported, so the scanner can read a stale registry (#303 class)
- `native/web/js/store/installed_scanner.js:182-200`: `registryPath()` stops at "preferred" and returns `preferred\plugins_host.db` if that file exists.
- Otzaria does not open the db at `getDatabasesPath()`. It opens it at `resolvePluginsDbPath()` → `resolveNotesDbPath` → `_writableDatabasesDirectory()` (`lib/core/app_paths.dart:978-991`, Otzaria `dev` `cee5952`):
  ```dart
  final preferred = await getDatabasesPath();
  if (await isDirectoryWritable(preferred)) return preferred;
  final internal = p.join(await getDataRootPath(), 'databases');
  if (p.equals(internal, preferred)) return preferred;
  await _copyPersonalDatabases(preferred, internal);   // copies plugins_host.db
  return internal;
  ```
- When `key-databases-path` is set, `getDatabasesPath` always returns it, so the fallback is not sticky. If that folder is readable but not writable (issue #1031: admin ACL, Program Files, a read-only share), Otzaria copies `plugins_host.db` to `<dataRoot>\databases` once and from then on installs and uninstalls there. The original under `key-databases-path` is frozen. The store reads that frozen copy and reports uninstalled plugins as installed, which is exactly #303.
- The launcher twin that the JSDoc cites as the model does port this. `error_reports_manager/lib/src/services/user_state_report_queue.dart:35-38`:
  ```dart
  final writable = p.equals(preferred, internal) ||
      await (isWritable ?? _canWriteIn)(preferred);
  final file = File(p.join(writable ? preferred : internal, fileName));
  ```
  So the comment "פורט של `locateUserStateDb` במשגר" (`installed_scanner.js:175`) is not accurate.
- Fix: port the `writable ? preferred : internal` step. Use a probe that does not create folders, like `_canWriteIn`, through a `sys.*` helper. Add tests for a custom db folder that is not writable, with a stale db in it and a live db in `<dataRoot>\databases`.
- Note: without `key-databases-path` the fallback is sticky (`<dataRoot>\databases` now exists, so `getDatabasesPath` prefers it), and the scanner agrees in that case.

### A2 — BLOCKING (minor impact): `readHiveStrings` skips the CRC check, so after a corrupt frame it disagrees with Hive
- `native/web/js/util/hive_strings.js:16` says "frame פגום עוצר את הקריאה — כמו ש-Hive עוצר בו", but `:32-33` checks only the length.
- Hive's `readFrame` returns `null` on a CRC mismatch. `FrameHelper.framesFromBytes` stops there, and crash recovery truncates the file at that offset, so every later frame is discarded.
- Evidence: I flipped 1 byte inside the `key-dark-mode` frame, which sits between the two `key-databases-path` puts.
  ```
  readHiveStrings: key-databases-path = "E:\\אוצריא\\databases", key-library-path = null
  hive_ce 2.24.0:  databases=D:\ספרייה\databases library=C:\Users\u\AppData\Roaming\otzaria\books
  (hive then truncated the file 583 -> 154 bytes)
  ```
- The store can therefore resolve a different db folder than Otzaria does until Otzaria next opens the box.
- Fix: verify `crc32(bytes[offset .. offset+length-4]) === uint32LE(offset+length-4)` and `break` on a mismatch. The box is not encrypted (`HiveCache.init` passes no cipher), so the key CRC is 0 and plain CRC-32 matches. Add a test with a corrupt middle frame.

### A — verified OK (no finding)
- Frame format matches hive_ce 2.24.0 (`binary_reader_impl.dart` `readFrame`/`readKey`, `binary_writer_impl.dart` `writeKey`/`writeString`, `frame.dart`):
  - `uint32 LE frameLength` includes the length word and the CRC; `frameLength < 8` stops reading.
  - Key type 0 is a `uint32`. Key type 1 (`utf8StringT`) is a 1-byte UTF-8 length followed by the bytes; any other key type is corrupt.
  - Value type `stringT = 4` is a `uint32` UTF-8 byte length followed by the bytes.
  - An empty payload after the key means a delete frame. Putting `null` writes `nullT` (0), which the parser maps to `null`, and Otzaria also treats it as unset.
  - Keys are not lowercased (only box names are). The box has no header and is not encrypted.
  - `compact()` rewrites the latest frames in the same format (verified on a real file).
- Box and file: `HiveCache.keyName = 'app_preferences'`, opened with `path: AppPaths.getDataRootPath()`, so the file is `<dataRoot>\app_preferences.hive`. On Windows the data root is `%APPDATA%\otzaria`; in portable mode it is `<exeDir>\otzaria_data`. The keys are `'key-databases-path'` and `'key-library-path'` (`settings_repository.dart:140,142`).
- `getDatabasesPath` order is saved → `<dataRoot>\databases` if it exists → `dirname(getLibraryPath())\databases`, and the scanner matches it. The case with no `key-library-path` is not relevant on Windows, because `getLibraryPath` persists the default on first run and `_detectBundledLibraryPath` is Linux/macOS only.
- Non-blocking notes:
  - (a) Only `.hivec` present (crash mid-compaction): Hive renames it to `.hive` on open, but the scanner sees no settings and uses the defaults.
  - (b) Portable copy moved to another drive letter: stored absolute paths stay stale until Otzaria runs `PortablePaths.migrateIfMoved`.
  - (c) `windowsPath` trims values, Otzaria does not.
  - (d) A legacy relative `key-library-path` of `'.'` resolves against the store's own working directory.

### B — clean
- The fix is correct and deterministic (probe above). `archive` ^4.0.9 accepts `encode(archive, modified:)`, and the analyzer is clean.
- No test relies on the zip entry time being "now". The only `modified` and mtime reads in plugins_manager are filesystem `stat()` calls (`plugin_direct_installer.dart:142`, `installed_plugins_scanner.dart:190`), not zip entry times.
- Other archive encoders in the repo's tests:
  - `plugins_manager/test/plugin_manifest_reader_test.dart:107,145`: `ZipEncoder().encode(archive)` without `modified`. They only assert `PluginManifestReader.readId(...)` and compare no bytes, so they cannot flake.
  - `library_manager/test/companion_assets_installer_test.dart:462` and `library_manager/test/companion_streaming_test.dart:238,294`: `TarEncoder().encodeBytes` (tar mtime defaults to now). They are never compared against a second encoding; `expect(await source.readAsBytes(), compressedBefore)` compares the same file before and after. They cannot flake.
- The commit message follows AGENTS.md §4 and the change is a single 2-line comment.
