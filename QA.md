# QA round 6 (2026-11-22)

| Topic | Checks | Blocking |
|---|---|---|
| A1 — writability fallback in `registryPath()` (store `fix/303-plugin-registry` @ `4b4630b`, 1 commit on `upstream/main` `fe154e1`) | diff vs Otzaria `dev` @ `cee5952` (`_writableDatabasesDirectory`, `_copyPersonalDatabases`, `isDirectoryWritable`); `fsapi::WriteTextAtomic` and `DeleteFileAt` semantics; bridge `fs.writeText`/`fs.delete` path restrictions; exe arch/manifest (UAC VirtualStore); callers of `scanInstalled` (concurrency); scratch tests (equal-path spellings, overlapping scans) | **yes (minor)**: A1-R1 |
| A2 — CRC check in `readHiveStrings` | real `app_preferences.hive` written by hive_ce 2.24.0: plain, compacted, deleted key, plus 6 corrupt variants, each read by `readHiveStrings` and by hive_ce | no — clean |
| Tests (`native/test/installed_scanner.test.js`) | `cd native && node --test`; review of new tests | no — gaps listed |
| Rest of the diff (bridge.cpp, sysapi.cpp/h, bridge.js, plugins_manager.js) | re-read for regressions | no — clean |

Toolchain: Node v22.23.5, Dart SDK 3.10.4 with `hive_ce: 2.24.0` (pinned) to generate files.

## Command outputs

### `cd native && node --test` (at `4b4630b`)
```
# tests 225
# suites 53
# pass 225
# fail 0
```

### A2: real hive_ce files
Generator: box `'App_Preferences'`; put library, put databases=`D:\ספרייה\databases`, put int key 7, put bool, put 300×`x`, put databases=`E:\אוצריא\databases`, put library=null.
Frames: `0:71 library | 71:58 databases | 129:22 <int 7> | 151:25 dark-mode | 176:319 long | 495:58 databases | 553:27 library`; zlib `crc32` matches 7/7.
```
out-plain   [["key-library-path",null],["key-databases-path","E:\\אוצריא\\databases"],["key-dark-mode",null],["long","xxx…"]]
out-compact [["key-dark-mode",null],["long","xxx…"],["key-databases-path","E:\\אוצריא\\databases"],["key-library-path",null]]
out-delete  [["key-library-path",null],["key-databases-path",null],["key-dark-mode",null],["long","xxx…"]]
```
Corrupt variants (`readHiveStrings` first line, then hive_ce `openBox` and the file size after hive's recovery):
```
c-mid      (byte 161 ^0xff, inside dark-mode frame)
  readHiveStrings: library=C:\Users\u\AppData\Roaming\otzaria\books  databases=D:\ספרייה\databases
  hive_ce:         databases=D:\ספרייה\databases library=C:\Users\u\AppData\Roaming\otzaria\books   size 151
c-crcfield (byte 175 ^1, the crc word of dark-mode frame)
  readHiveStrings: library=C:\...\books  databases=D:\ספרייה\databases
  hive_ce:         databases=D:\ספרייה\databases library=C:\...\books                            size 151
c-dbval    (byte 525 ^1, inside the 2nd databases value)
  readHiveStrings: library=C:\...\books  databases=D:\ספרייה\databases  dark-mode=null long=xxx…
  hive_ce:         databases=D:\ספרייה\databases library=C:\...\books                            size 495
c-last     (byte 560 ^1, last frame)
  readHiveStrings: library=C:\...\books  databases=E:\אוצריא\databases
  hive_ce:         databases=E:\אוצריא\databases library=C:\...\books                            size 553
c-trunc    (file cut to 570 bytes)
  readHiveStrings: library=C:\...\books  databases=E:\אוצריא\databases
  hive_ce:         databases=E:\אוצריא\databases library=C:\...\books                            size 553
c-first    (byte 20 ^1, first frame)
  readHiveStrings: {} (defaults)
  hive_ce:         HiveError: Could not read the box. The encryption cipher may be wrong or the box may be corrupted.
```
All match hive_ce, including the corrupt-middle case that failed in round 5. `c-first`: `HiveCache.init` (`lib/data/data_providers/hive_data_provider.dart:66-73`) does not catch this, so Otzaria cannot start at all; the store falling back to defaults doesn't matter here.

### A1: scratch test (in the scratchpad, not committed), real scanner with a fake fs whose `writeText` holds an exclusive handle on the path for 50 ms, like `WriteTextAtomic` (`CreateFileW(temp, GENERIC_WRITE, 0 /*no sharing*/ …)`)
```
custom = C:\USERS\U\APPDATA\ROAMING\OTZARIA\DATABASES\   -> writes 0, reads <that>\plugins_host.db   (no probe: OK)
custom = C:/Users/u/AppData/Roaming/otzaria/databases     -> writes 0                                 (OK)
custom = ...\otzaria\databases\\                          -> writes 0                                 (OK)
two overlapping scan() calls, custom = D:\DB (writable, has plugins_host.db), internal db also present:
  A asked ["D:\\DB\\plugins_host.db"]
  B asked ["C:\\Users\\u\\AppData\\Roaming\\otzaria\\databases\\plugins_host.db"]
```

## Findings

### A1-R1 — BLOCKING (minor): concurrent probes give a false "not writable", so the scanner reads the internal db
- `native/web/js/store/installed_scanner.js:213-227` `#isWritable` writes the fixed name `<dir>\.otzaria_store_write_probe`. `fs.writeText` → `fsapi::WriteTextAtomic` (`native/src/fsapi.cpp:109-113`) opens `<path>.tmp` with `CREATE_ALWAYS` and share mode `0`. A second probe on the same folder at the same moment fails with a sharing violation. A `MoveFileExW` while the other scan holds the `.tmp` also fails (`:137`). Either way `#isWritable` returns false, and `:206-207` switches to `<dataRoot>\databases`.
- Otzaria guards against exactly this. `lib/core/directory_writability.dart:7,13-18` puts one in-flight `_probe` per path into `_activeProbes`. The port drops that guard.
- Overlapping scans really happen. `controller.js:273` ticks `refreshInstalled()` every `INSTALL_WATCH_INTERVAL_MS = 1000` (`:39`) while an install is pending, with no re-entrancy guard (`:223-224` only awaits `#loading`). `main.js:180` also calls it after detection. One scan can take over 1 s, because `sysapi.cpp:517` sets `busy_timeout(db, 2000)` and Otzaria is writing `plugins_host.db` during the install the watch is waiting on.
- Effect, reproduced above: when a stale `<dataRoot>\databases\plugins_host.db` exists (left by an earlier fallback episode whose ACL was later fixed), scan B returns that frozen registry. That is the #303 symptom. `#settleInstallWatch(scanned)` (`controller.js:247`) can also treat the stale version as "changed" and close the watch, so the wrong map stays until the next manual refresh. With no internal db, B quietly falls back to the folder scan instead.
- Fix (either one): give each probe its own name (for example `.otzaria_store_write_probe-<random>`), or keep a `Map<dir, Promise<bool>>` of in-flight probes like `_activeProbes`. Add a test with two concurrent `scan()` calls and an exclusive-handle fake `writeText`.

### A1 — verified OK
- The logic matches `_writableDatabasesDirectory`: preferred is used if writable; if preferred equals internal it is kept; otherwise internal is used. The store reads internal only when the db exists there; Otzaria creates it there or copies it in. Equal-path detection works for case, `/` and trailing `\` (scratch test). It is not `p.equals`, which also normalizes `.`/`..`, but a miss there only means probing the same folder, so the result is the same.
- Probe accuracy: `WriteTextAtomic` needs `FILE_ADD_FILE` and write on `.tmp`, then `DELETE` on it for the rename. Otzaria needs `FILE_ADD_FILE` and write, then `DELETE` for `probe.delete()`. Both sides need the same rights, so they give the same answer, including for a create-but-no-delete ACL (both say false). `MoveFileExW(REPLACE_EXISTING)` within one folder is a plain rename on SMB too.
- No UAC VirtualStore false positive: the build is x64 (`native/build.ps1:54,96`), and virtualization only applies to 32-bit processes. Otzaria's launcher manifest is `asInvoker`; the store has no `requestedExecutionLevel`, which also means asInvoker. Both run with the same token.
- The bridge `fs.writeText`/`fs.delete` (`bridge.cpp:204-213,234-238`) have no path allowlist, so the probe is not failed by policy.
- No side effects that confuse Otzaria. The name differs from `.otzaria_write_probe`, so neither deletes the other's file. Otzaria never lists the databases folder: `_copyPersonalDatabases` only copies named files, and change-location moves the whole folder.

### A1 — non-blocking notes
- (a) Leftover `.tmp`: `fsapi.cpp:132-134` returns on a `FlushFileBuffers` failure without `DeleteFileW(temp)`. Under a create-without-delete ACL, `:139`'s `DeleteFileW` also fails. Either way `<dir>\.otzaria_store_write_probe.tmp` stays behind (empty). Otzaria leaves its own probe behind under the same ACL, so this is cosmetic. Consider deleting the temp on the flush-failure path.
- (b) `installed_scanner.js:220-224`: if the write succeeds but `remove` fails, the probe returns true, while Otzaria returns false. After a successful rename this practically only happens with a transient lock (AV), so the impact is nil. It is still a documented divergence.
- (c) `WriteTextAtomic` calls `CreateDirectories(parent)` (`fsapi.cpp:105`). If the folder disappears between `dirExists` (`installed_scanner.js:205`) and the probe (for example Otzaria's change-location moving it), the store recreates an empty folder, contrary to "store never creates folders". This is a very narrow window.
- (d) A custom folder on a drive that is gone (unplugged USB, disconnected share): Otzaria's `Directory.create` fails, so it uses internal and works from `<dataRoot>\databases`. The store returns null and does a folder scan. This is no worse than before the change. It could be refined: if no ancestor of preferred exists, treat the folder as not writable.

### Tests — gaps (non-blocking except the A1-R1 test)
- No concurrency test (A1-R1).
- No test that a custom path equal to internal (different case, `/`, trailing `\`) skips the probe and reads internal. I verified this by hand above; worth pinning.
- The `remove`-fails path of `#isWritable` is untested.
- The fake `writeText` does not model the `.tmp` + rename, so "probe leaves no file" proves only the JS side. That test is fine for what it is.
- The crc test flips a key byte only. Flips of the crc word and the value bytes were verified on real files above.

### Rest of the diff — clean
`ReadPluginRegistry` and the `sys.pluginRegistry` wiring are unchanged since round 5 apart from what is listed. `readRegistry: this.sys?.pluginRegistry` passes an arrow function, so there is no `this` binding issue.
