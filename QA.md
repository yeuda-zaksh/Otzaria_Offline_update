# QA round 7 (2026-11-22)

Store `fix/303-plugin-registry` @ `b934d43` (1 commit on `upstream/main` `fe154e1`). Compared with Otzaria `dev` @ `cee5952` (`lib/core/app_paths.dart:688-701, 978-1010`, `lib/core/directory_writability.dart`). Node v22.23.5.

| Topic | Checks | Blocking |
|---|---|---|
| A1-R1 fix: unique probe name | `#isWritable` code; Otzaria `_activeProbes`; new concurrency test (does it fail on the old code?) | no — fixed |
| Note (b): written but not removable = not writable | code against `_probe` (`probe.delete()` throws → false); new test | no — fixed, matches Otzaria |
| Note (d): missing preferred folder (`#anyAncestorExists`) | loop termination for every path shape using `dirNameOf`; scratch run of the real `registryPath` with a fake fs (13 shapes); Win32 `GetFileAttributesW` meaning of `\`, `\\server`, `E:` | **no (minor)** — R7-1 (UNC), R7-2 (ancestor that exists but can't be written) |
| preferred equal to internal → canonical spelling, no probe | code against `_writableDatabasesDirectory` (`p.equals` → preferred); test | no — clean |
| Note (a) `.tmp` left on flush failure | left unchanged on purpose | no — accepted |
| Tests | `cd native && node --test` | no — 229/229 pass |
| Rest of the diff (bridge.cpp, sysapi.cpp/h, bridge.js, plugins_manager.js, hive_strings.js) | re-read | no — clean |

## Command outputs

### `cd native && node --test`
```
1..55
# tests 229
# suites 53
# pass 229
# fail 0
# cancelled 0
# skipped 0
# todo 0
```

### Scratch run: real `registryPath(ROOT)` on a fake fs (internal `<ROOT>\databases\plugins_host.db` exists; "existing" = dirs the fake reports as existing)
```
drive gone                         custom="E:\\Gone\\db"           -> INTERNAL            dirExists: E:\Gone\db, E:\Gone, E:\
drive present, folder missing      custom="E:\\Gone\\db"  [E:\]    -> null (folder scan)  dirExists: E:\Gone\db, E:\Gone, E:\
drive root, drive gone             custom="E:\\"                   -> INTERNAL            dirExists: E:
drive root bare, drive gone        custom="E:"                     -> INTERNAL            dirExists: E:
UNC share unreachable              custom="\\\\server\\share\\db" [\]  -> null (folder scan)  dirExists: \\server\share\db, \\server\share, \\server, \
UNC share unreachable, no "\"      custom="\\\\server\\share\\db"      -> INTERNAL            (same probes)
UNC share root unreachable         custom="\\\\server\\share" [\]      -> null (folder scan)  dirExists: \\server\share, \\server, \
UNC reachable, folder missing      custom="\\\\server\\share\\db" [\\server\share, \] -> null  dirExists: \\server\share\db, \\server\share
long-path prefix, drive gone       custom="\\\\?\\E:\\db" [\]          -> null (folder scan)  dirExists: \\?\E:\db, \\?\E:\, \\?, \
relative single                    custom="databases"              -> INTERNAL            dirExists: databases
relative nested                    custom="foo\\bar"               -> INTERNAL            dirExists: foo\bar, foo
trailing slashes                   custom="E:\\Gone\\db\\\\//"     -> INTERNAL            dirExists: E:\Gone\db, E:\Gone, E:\
double inner slash                 custom="E:\\\\db"               -> INTERNAL            dirExists: E:\\db, E:\
```
(Script: `qa7/shapes.mjs` in the session scratchpad, not committed.) On real Windows `dirExists('\\')` is always true: `GetFileAttributesW(L"\\")` is the root of the process's current drive (`fsapi.cpp:145-151` → `bridge.js:205`). So the "[\]" rows are what happens on a real machine.

## Findings

### A1-R1 — fixed
- `installed_scanner.js:232-242`: the name is `.otzaria_store_write_probe-<Math.random base36, ≤8 chars>`. Collisions are negligible. A short suffix (when `Math.random()` has few base-36 digits) is harmless.
- The new test (`installed_scanner.test.js`, "שתי סריקות חופפות") would fail on the round-6 code. Both scans run the same awaits in step, so they reach `writeText` together. The fake holds the path for 20 ms and throws on a second open, so the second scan falls back to internal, which the `asked` assertion catches. The test is meaningful.

### Note (b) — fixed
- `:236-238`: if `remove` throws, the `catch` returns false. This matches `_probe` (`directory_writability.dart:20-29`). There is a test for it.

### preferred == internal — clean
- `:203-206`: trailing `\` is stripped, the comparison ignores case, and `/` was already converted by `windowsPath` (`:56-58`). Otzaria calls `isDirectoryWritable(preferred)` and then returns preferred when `p.equals(internal, preferred)`. Either way the active folder is internal, so the store skipping the probe gives the same result.

### `#anyAncestorExists` (`installed_scanner.js:219-226`) — loop termination: OK
`dirNameOf` (`:44-47`) returns either `path.slice(0, cut)` with `cut < trimmed.length ≤ path.length`, which is strictly shorter, or `path` itself when it has no `\`. So the sequence strictly shrinks until a fixed point, and the loop stops at `parent === dir`. Checked shapes: `D:\x` (probes `D:\`, stops at `D:`), `D:` / `D:\` (preferred becomes `D:` after `:203`, loop body never runs), UNC (`\\server\share` → `\\server` → `\` → fixed point), relative (`foo` → fixed point), trailing and doubled slashes. No infinite loop is possible.

### R7-1 — non-blocking (minor): a disconnected UNC share does not fall back to internal; the walk reaches `\`
- `:219-224` walks `\\server\share\db` → `\\server\share` → `\\server` → `\`. `\` is not a parent of a UNC path. On Windows it means the current drive's root (always present), so `#anyAncestorExists` returns true and `registryPath` returns **null** (folder scan), as in the "UNC share unreachable" row above. The same happens for `\\server\share` as the setting itself, and for `\\?\E:\…` with drive E gone.
- Otzaria: `Directory('\\\\server\\share\\db').create(recursive: true)` fails when the server or share is unreachable. `isDirectoryWritable` → false, so it uses `<dataRoot>\databases` (`app_paths.dart:978-988`). The store therefore scans folders while Otzaria uses the internal registry. That is the #303 symptom (a leftover folder shown as installed) in exactly the "disconnected share" case that round 6 note (d) called out. It is no worse than before the change, which is why this is non-blocking.
- Cost: on an unreachable host every `GetFileAttributesW` can block for the SMB/name-resolution timeout. The walk adds 2 calls (`\\server\share`, `\\server`) on top of `dirExists(preferred)`. They run on the `RunAsync` worker, so the UI is fine. But with the 1 s `refreshInstalled` watch, which has no re-entrancy guard (round 6, `controller.js:273`), slow scans pile up.
- Fix: stop the walk at the volume root. For `\\server\share\…` the highest ancestor to test is `\\server\share`. For `\\?\X:\…` it is `\\?\X:\`. Never test a bare `\`, `\\server` or `\\?`. For example, return false once `parent` is `\` or starts with `\\` and has fewer than 4 `\`-separated parts. Add tests for an unreachable `\\server\share\db` (expect internal) and a reachable share with a missing folder (expect null).

### R7-2 — non-blocking (note): missing folder under an existing ancestor that can't be written
- `:209-211` returns null whenever any ancestor exists. Otzaria's `Directory.create(recursive)` also fails when the nearest existing ancestor denies creating subfolders (an admin ACL, a read-only share, `C:\Program Files\…` in portable mode: the #1031 case). It then falls back to internal (`_copyPersonalDatabases` creates `<dataRoot>\databases`). The store scans folders in that case.
- It is no worse than before, and the store must not create folders. A close approximation would be to run `#isWritable` on the nearest existing ancestor (a file write needs `FILE_ADD_FILE`, `create` needs `FILE_ADD_SUBDIRECTORY`; they usually come together). Optional.

### Other path-shape notes (no action)
- Relative settings (`databases`, `foo\bar`) are resolved against the store's working directory, not Otzaria's. Otzaria's folder picker always saves absolute paths, so this doesn't happen in practice.
- `windowsPath` trims spaces and Otzaria does not (already the case before; a path ending in a space is invalid on Windows anyway).

### Note (a) — accepted as is
The temp file stays only on a `FlushFileBuffers` failure, and it is empty. This is cosmetic and the function is shared.

### Rest of the diff — clean
`ReadPluginRegistry` (`sysapi.cpp:+443-557`): read-only open, `busy_timeout`, table check, TEXT-only rows, a partial read gives `null`. The bridge wiring (`bridge.cpp:+322-326`, `bridge.js:+223`, `plugins_manager.js:+64`) and `hive_strings.js` are unchanged in substance since round 6. I found no regressions.

## Summary
The round 6 blocker (A1-R1) is fixed and covered by a test. Notes (b) and (d) and the canonical-internal change are correct for drive-letter paths. Remaining: R7-1 (UNC/`\\?\` walk reaches `\`, so a disconnected share doesn't fall back to internal) and R7-2 (ancestor can't be written). Both are minor and no worse than before the change. **Nothing blocking.**
