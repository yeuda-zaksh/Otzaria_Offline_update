# QA round 8 (2026-11-22)

Store `fix/303-plugin-registry` @ `f9b78af` (1 commit on `upstream/main` `fe154e1`). Base for comparison: round 7 @ `b934d43` (fetched by full SHA, since the branch was force-pushed). Node v22.23.5.

| Topic | Checks | Blocking |
|---|---|---|
| Scope of the change | `git diff --stat b934d43 f9b78af` | no — only `installed_scanner.js` (+16/-1) and `installed_scanner.test.js` (+31) |
| R7-1 fix: `volumeRootOf` + bound in `#anyAncestorExists` | round-7 13-shape scratch script re-run on the new code, plus 13 more edge shapes | no — fixed |
| Regex edge cases | lowercase drive, `\\server\share\` with trailing `\`, `\\?\UNC\…`, `//server/share` (after `windowsPath`), `\\.\E:`, `\db`, `E:db` | no — R8-1 is a note only |
| New tests | run against round-7 code to check they catch the bug | no — the "disconnected" test fails on the old code; the "reachable" test is a regression guard (passes on both, as expected) |
| R7-2 | not addressed (optional, by design) | no — accepted |
| Full test suite | `cd native && node --test` | no — 231/231 pass |

## Command outputs

### `git diff --stat b934d43 f9b78af`
```
 native/test/installed_scanner.test.js    | 31 +++++++++++++++++++++++++++++++
 native/web/js/store/installed_scanner.js | 16 +++++++++++++++-
 2 files changed, 46 insertions(+), 1 deletion(-)
```

### `cd native && node --test`
```
1..55
# tests 231
# suites 53
# pass 231
# fail 0
# cancelled 0
# skipped 0
# todo 0
```

### New tests against round-7 `installed_scanner.js`
```
not ok 13 - שיתוף רשת שנותק — הרישום הפנימי, בלי לטפס אל "\\"
# pass 21
# fail 1
```

### Scratch run: real `registryPath(ROOT)` on a fake fs
Internal `<ROOT>\databases\plugins_host.db` exists. The 3rd column lists the dirs the fake reports as existing. `dirExists` lists only the probes outside ROOT. The first 13 rows are the round-7 shapes.
```
drive gone                           "E:\\Gone\\db"                 []                                 -> INTERNAL   dirExists: E:\Gone\db, E:\Gone, E:\
drive present, folder missing        "E:\\Gone\\db"                 ["E:\\"]                           -> null (folder scan)   dirExists: E:\Gone\db, E:\Gone, E:\
drive root, drive gone               "E:\\"                         []                                 -> INTERNAL   dirExists: E:
drive root bare, drive gone          "E:"                           []                                 -> INTERNAL   dirExists: E:
UNC share unreachable                "\\\\server\\share\\db"        ["\\"]                             -> INTERNAL   dirExists: \\server\share\db, \\server\share
UNC share unreachable, no "\"        "\\\\server\\share\\db"        []                                 -> INTERNAL   dirExists: \\server\share\db, \\server\share
UNC share root unreachable           "\\\\server\\share"            ["\\"]                             -> INTERNAL   dirExists: \\server\share
UNC reachable, folder missing        "\\\\server\\share\\db"        ["\\\\server\\share","\\"]         -> null (folder scan)   dirExists: \\server\share\db, \\server\share
long-path prefix, drive gone         "\\\\?\\E:\\db"                ["\\"]                             -> INTERNAL   dirExists: \\?\E:\db, \\?\E:\
relative single                      "databases"                    ["\\"]                             -> INTERNAL   dirExists: databases
relative nested                      "foo\\bar"                     ["\\","foo"]                       -> INTERNAL   dirExists: foo\bar
trailing slashes                     "E:\\Gone\\db\\\\//"           []                                 -> INTERNAL   dirExists: E:\Gone\db, E:\Gone, E:\
double inner slash                   "E:\\\\db"                     []                                 -> INTERNAL   dirExists: E:\\db, E:\
--- extra edge cases
lowercase drive, present             "e:\\gone\\db"                 ["e:\\"]                           -> null (folder scan)   dirExists: e:\gone\db, e:\gone, e:\
lowercase long-path, present         "\\\\?\\e:\\db"                ["\\\\?\\e:\\","\\"]               -> null (folder scan)   dirExists: \\?\e:\db, \\?\e:\
long-path, drive present deep        "\\\\?\\E:\\a\\b"              ["\\\\?\\E:\\","\\"]               -> null (folder scan)   dirExists: \\?\E:\a\b, \\?\E:\a, \\?\E:\
UNC trailing \ unreachable           "\\\\server\\share\\"          ["\\"]                             -> INTERNAL   dirExists: \\server\share
UNC trailing, deep, reachable        "\\\\server\\share\\a\\b\\"    ["\\\\server\\share","\\"]         -> null (folder scan)   dirExists: \\server\share\a\b, \\server\share\a, \\server\share
UNC deep, mid exists                 "\\\\server\\share\\a\\b"      ["\\\\server\\share\\a","\\"]      -> null (folder scan)   dirExists: \\server\share\a\b, \\server\share\a
forward slashes UNC unreachable      "//server/share/db"            ["\\"]                             -> INTERNAL   dirExists: \\server\share\db, \\server\share
forward slashes UNC reachable        "//server/share/db"            ["\\\\server\\share","\\"]         -> null (folder scan)   dirExists: \\server\share\db, \\server\share
\\?\UNC\ reachable share             "\\\\?\\UNC\\server\\share\\x" ["\\\\?\\UNC\\server\\share","\\"] -> INTERNAL   dirExists: \\?\UNC\server\share\x
\\?\UNC\ unreachable                 "\\\\?\\UNC\\server\\share\\x" ["\\"]                             -> INTERNAL   dirExists: \\?\UNC\server\share\x
\\.\ device path                     "\\\\.\\E:\\db"                ["\\\\.\\E:\\","\\"]               -> null (folder scan)   dirExists: \\.\E:\db, \\.\E:\
rooted no drive "\db"                "\\db"                         ["\\"]                             -> INTERNAL   dirExists: \db
drive-relative "E:db"                "E:db"                         ["E:\\"]                           -> INTERNAL   dirExists: E:db
```
Compared with round 7: every UNC and `\\?\` row now stops at the volume root. `\`, `\\server` and `\\?` are never probed. The disconnected cases (`\\server\share\db`, `\\server\share`, `\\?\E:\db`) now go to INTERNAL, as Otzaria does. The drive-letter rows are unchanged. The UNC walk also makes one fewer SMB probe (no `\\server`), which helps the cost note from round 7.

## Findings

### R7-1 — fixed (`installed_scanner.js:59-62, 230-239`)
- Bound `parent.length >= root.length - 1`, checked against each root shape:
  - `X:\` (len 3): allows the parent `X:` (len 2), which is probed as `X:\`. The next `dirNameOf` returns `X:` itself, so the loop stops.
  - `\\server\share` (len L): allows only parents of length ≥ L-1, which in practice means the share itself. `\\server` is always shorter than `\\server\share` by at least 2, so it is never probed.
  - `\\?\X:\` (len 7): allows `\\?\X:` (len 6), which is probed as `\\?\X:\`. `\\?` (len 3) stops the loop.
  - The `-1` is there for the drive forms, where `dirNameOf` drops the trailing `\`. For UNC it is harmless: no ancestor can be exactly L-1 long.
- The regex is anchored with `^` across all three alternatives. It accepts lowercase drives. `[^\\?]+` keeps `\\?\…` out of the UNC alternative. With a trailing `\`, the root is still `\\server\share` (preferred has already been stripped at `:213`). `/` is already converted by `windowsPath` (`:65-67`). See the rows above.
- Relative paths, `\db` and `E:db` now give `root === null`, so the function returns false and the store uses the internal registry. Otzaria's folder picker only saves absolute paths, so this doesn't happen in practice. (Before the fix, a relative path with an existing parent gave null.)
- Loop termination still holds: the bound only adds an extra exit.

### R8-1 — non-blocking (note): `\\?\UNC\server\share\…` is not recognised (`installed_scanner.js:60`)
- `volumeRootOf` returns null for it, so a missing folder under a **reachable** share goes to INTERNAL (see the `\\?\UNC\ reachable share` row). Otzaria would create the folder and use an empty registry there, so the store would read the internal registry instead.
- In practice this doesn't happen. Otzaria's picker and settings never produce `\\?\UNC\` paths, and the disconnected case (the realistic one) is already correct. No action needed. Adding a `\\?\UNC\server\share` alternative to the regex (before the plain UNC one) would cover it if wanted.

### R7-2 — still open by choice (non-blocking)
Same as round 7: a missing folder under an existing ancestor that can't be written gives null (folder scan), while Otzaria falls back to internal.

### Rules
The added comments are 1-2 lines and explain a non-obvious why. No other files changed.

## Summary
The R7-1 fix is correct for every path shape tested (26 shapes). It never probes `\`, `\\server` or `\\?`. It is covered by a test that fails on the old code. There are no regressions (231/231). R8-1 (`\\?\UNC\` not recognised) is a theoretical note only. **Clean — nothing blocking.**
