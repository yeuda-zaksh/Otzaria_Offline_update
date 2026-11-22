# QA round 10 — `fix/310-asset-pattern-architecture`

Commit `86599cc` (one commit on `upstream/main` `8f772e4`). Diff vs upstream: `custom_apps_manager/README.md`,
`lib/src/models/github_source.dart`, `lib/src/services/github_app_client.dart`, `test/custom_apps_manager_test.dart`,
`test/github_app_client_test.dart` (+194/−4). Read-only QA, Flutter 3.47.2 / Dart 3.13.2, root on Linux.

## Summary

| Topic | Checks | Blocking |
|---|---|---|
| F1 fix (npp, sibling tagged) | `[npp.Installer.exe, npp.Installer.arm64.exe]` + x64 pattern → `null`; full npp release → `.x64.exe` | no (fixed) |
| Upload-window race, x86 uploaded **first and alone** | `[npp.8.7.0.Installer.exe]` only → picks the 32-bit build, stored as the new tag | no (R1, residual, narrow window) |
| Klei Kodesh v10 + portable zip | x64 **and** x86 patterns → `KleiKodeshSetup-v10.7.0.exe`; zip is not tagged, does not block | no (works) |
| Mixed releases | `-x86-portable.zip`, `_i386`, `(x86)`, `win32`, `.x86.msi`, `-arm64` sibling → fallback off | no |
| F2 fix (hand-edited patterns) | `_x64$`, `-x64\.exe$`, `^-x64\.exe$`, `^-x64$`, `^.*-x64…`, `^\d+-…` → `null` | no (fixed); top-level `\|` nit (R3) |
| `namesArchitecture` false positives | `Win32DiskImager`, `Win64Tools`, `Win64OpenSSL`, `x64dbg`, `Box64` → plain. `x86-asm-tool`, `Tools.for.Win32`, `Win32-OpenSSL` → ARCH | no — a false positive only turns the fallback off (= pre-#310 behaviour) |
| `namesArchitecture` false negatives | `ia32`, `arm64ec`, `armhf`/`armv7`, `[x64]`, `+x64`, `x32`, bare `-64-` → plain | no (R2) |
| F3 / F4 | unchanged, left as is by design (pre-existing / safe no-op) | no |
| F5 (comments, README) | test history comment gone; README no longer states a false invariant; all new comments ≤2 lines, no history | clean |
| F6 (`downloadFromGithub` test) | new test passes; checks `fileName` and `version` | clean |
| Stored version after fallback download | `10.7.0` from the tag (test + code `custom_apps_manager.dart:470`) | no |
| Pattern not relearned after a fallback download | future tagged sibling silently freezes on the last neutral release | no (R4) |
| format / analyze / tests | clean except the 2 known env-only failures | no |

## Command outputs

### custom_apps_manager
```
$ dart pub get              → OK (12 packages have newer versions incompatible with dependency constraints.)
$ dart format --output=none --set-exit-if-changed .
Formatted 49 files (0 changed) in 0.11 seconds.
$ dart analyze
Analyzing custom_apps_manager...
No issues found!
$ dart test
00:03 +406 -2: Some tests failed.
Failing tests:
  test/custom_apps_manager_test.dart: למידה אחרי התקנה כונן נעול: ההתקנה מצליחה גם כשאי אפשר לכתוב למראה
  test/known_locations_test.dart: שמירה וטעינה תיקייה שאינה ניתנת לכתיבה אינה שגיאה
$ dart test test/github_app_client_test.dart
00:00 +29: All tests passed!
$ dart test test/custom_apps_manager_test.dart -N 'downloading from GitHub'
00:00 +5: All tests passed!
```
Both failures are the known env-only ones (read-only mirror bypassed as root), same as round 9.

### launcher_app
```
$ flutter pub get           → Got dependencies!
$ flutter analyze --no-fatal-infos
Analyzing launcher_app...
No issues found! (ran in 19.9s)
$ flutter test test/custom_apps_test.dart
00:20 +122 ~4: All tests passed!
```

### Regex probe (round-9 script re-run against `86599cc`, plus new cases)
```
[npp.8.6.9.Installer.x64.exe] neutral=^npp\.\d+\.\d+\.\d+\.Installer\.exe$
   [npp.8.7.0.Installer.exe, npp.8.7.0.Installer.arm64.exe]            -> null              (was: 32-bit build)
   [npp.8.7.0.Installer.exe]                                           -> npp.8.7.0.Installer.exe   ← R1
   [npp.8.7.0.Installer.exe, ….x64.exe, ….arm64.exe]                   -> npp.8.7.0.Installer.x64.exe
[7z2407-x64.exe]  pattern=^\d+z2407-x64\.exe$  neutral=null              -> null (pre-existing, see N1)
[App-Setup-1.0-x86.exe] [App-Setup-1.1.exe, App-Setup-1.1-arm64.exe]    -> null
[App-1.0-x86_64.exe]  neutral=^App-\d+\.\d+_\d+\.exe$  [App-1.1.exe]    -> null (F3, unchanged)
[App-1.0-win-x64.zip] [App-1.1-win.zip]                                -> App-1.1-win.zip
[App-1.0-64bit.exe]   neutral=null [App-1.1-32bit.exe, App-1.1.exe]     -> App-1.1-32bit.exe (F3, exact match, pre-existing)
[App_1.0_amd64.exe]   [App_1.1.exe, App_1.1_i386.exe] -> null ; [App_1.1.exe] -> App_1.1.exe
[App-1.0-X64.exe]     [App-1.1.exe]                                    -> App-1.1.exe
[x64-App-1.0.exe]     neutral=null                                     -> null (F4)
[App Setup 1.2 (x64).exe] [App Setup 1.3.exe, App Setup 1.3 (x86).exe] -> null ; alone -> App Setup 1.3.exe
[App-1.2(x64).exe]    neutral=null                                     -> null (F4)
[App-1.0-x64.exe] from [.exe.sha256, .exe.sig, -portable.zip, -debug.exe, Other-1.1.exe, App-1.1.exe] -> App-1.1.exe
[App-1.0-x64-portable.zip] [App-1.1-portable.zip, App-1.1-x86-portable.zip] -> null ; alone -> App-1.1-portable.zip
[App-win64-1.0.exe]   [App-win32-1.1.exe, App-1.1.exe] -> null ; [App-1.1.exe] -> App-1.1.exe
[-x64.exe]            neutral=null                                     -> null
[App.x64.msi]         [App.msi, App.x86.msi] -> null ; [App.msi] -> App.msi
--- Klei ---
x64 pattern [KitveiHakodeshPortable-v10.7.0.zip, KleiKodeshSetup-v10.7.0.exe]        -> KleiKodeshSetup-v10.7.0.exe
x86 pattern  same                                                                     -> KleiKodeshSetup-v10.7.0.exe
x64 pattern  + KleiKodeshSetup-v10.7.0-arm64.exe                                      -> null (R4)
--- hand-edited (withoutArchitecture) ---
^App\-x64\.exe$  -> ^App\\.exe$   (valid, matches nothing — F4)
-x64\.exe$ / _x64$ / ^-x64$ / ^-x64\.exe$ / ^.*-x64\.exe$ / ^App-x64 / ^\d+-App-x64\.exe$ / ^כלי-x64\.exe$ -> null
^A-x64\..*$      -> ^A\..*$       Other.exe=false
^App-x64\.exe|^Other-x64\.exe$ -> ^App\.exe|^Other\.exe$   (R3)
^A|B-x64\.exe$   -> ^A|B\.exe$    App.exe.sha256=true      (R3; the original already matched every A…)
--- namesArchitecture ---
plain  Win32DiskImager-1.0.0-binary.zip, win32diskimager-1.0.0-install.exe, Win64Tools-1.0.exe,
       Win64OpenSSL-3_3_0.exe, x64dbg_2024-12-11.zip, snapshot_2024-x64dbg.zip, Box64-1.0.exe,
       App-universal.exe, App-64bits.exe, App1.0x64.exe, App_x64v3.exe, App,x64.exe, App~x64.exe,
       KitveiHakodeshPortable-v10.7.0.zip, KleiKodeshSetup-v10.7.0.exe
plain  App-1.0-ia32.exe, App-1.0-arm64ec.exe, App-1.0-armhf.exe, App-1.0-armv7.exe, App-1.0-arm.exe,
       App [x64].exe, App-1.0+x64.exe, App-x32.exe, App-1.0-w64.exe, SumatraPDF-3.5.2-64-install.exe   ← R2
ARCH   App.x86.exe, App-1.0.x86.zip, App-1.0-win-x64.zip, App-1.0-x86-64.exe, App-1.0-x86_64.AppImage,
       App(x64).exe, App 64-bit.exe, App-1.0-i686.exe, App-1.0-aarch64.zip, App-WIN32.EXE, App-1.0-x64,
       App-1.0-x64.exe.sha256, pywin32-306.win-amd64-py3.12.exe, Win64 OpenSSL Light-3_3_0.exe
ARCH   x86-asm-tool-1.0.exe, Tools.for.Win32.exe, Win32-OpenSSL.exe     ← product-name false positives (safe)
```

## Findings

F1, F2, F5, F6 from round 9 are fixed. No blocking findings.

### R1 — non-blocking: the upload-window race survives when the x86 file is uploaded first and alone
`custom_apps_manager/lib/src/services/github_app_client.dart:106-120`.
The guard needs a tagged sibling to see that the plain name means x86. In the first seconds or minutes of a release
built by a CI that uploads one asset at a time (e.g. `softprops/action-gh-release` creates the release, then uploads),
an npp-style release can hold only `npp.8.7.0.Installer.exe`. Then `namesArchitecture` is false for every asset, the
x64 pattern falls back, `downloadFromGithub` stores the 32-bit installer with `version` = the new tag, and the card stays
"up to date" when the x64 file arrives (`customAppOnlineIsNewer(tag, tag)` is false). It needs a user to check inside
that window *and* an x86-first upload order, so it is not blocking. A single release cannot tell "moved to one installer"
from "x86 uploaded first". Cheap options if wanted: allow the fallback only for a release whose `publishedAt` is older
than ~1 hour, or only when the last exact-match release in the window has no asset matching the neutral pattern (npp
v8.6.9 has one; whether Klei v9.1.4 also shipped an unsuffixed exe could not be verified, since the real release list
is blocked in this session, and the test fixture assumes it did, so check before choosing this one). No test covers this case.

### R2 — non-blocking: `namesArchitecture` misses some real tokens (false negatives)
`custom_apps_manager/lib/src/models/github_source.dart:155-162`. Not recognized: `ia32` (the electron-builder 32-bit
suffix), `arm64ec`, `armhf`/`armv7`/`arm`, `[x64]`, `+x64`, `x32`, `w64`. A false negative turns the guard off for that
release. Example: x64 pattern from `App-1.0-x64.exe`, a release that has `[App-1.1.exe, App-1.1-ia32.exe]`. The fallback
picks `App-1.1.exe`. For electron-builder that file is normally the combined multi-arch NSIS installer, so the pick is
usually right, but it is not guaranteed. Adding `ia32` and `arm64ec` (and `[`/`]`/`+` as separators) is cheap.
False positives (`x86-asm-tool`, `Tools.for.Win32`, `Win32-OpenSSL`) only turn the fallback **off**, which is the
pre-#310 behaviour (it stays on the last exact release), so they are safe and **cannot** select a wrong file.

### R3 — nit: a hand-edited pattern with top-level alternation passes the F2 guard
`github_source.dart:145-150`. The guard checks only the first branch: `^A|B-x64\.exe$` → `^A|B\.exe$` (the second branch
is unanchored and matches any `…B.exe`), and `^App-x64\.exe|^Other-x64\.exe$` falls back for both products. The original
patterns were already loose (`^A` matches every `A…`), and the form never produces `|`, so this is cosmetic. Optional:
return `null` when the pattern contains an unescaped `|`.

### R4 — nit: the fallback is never persisted, so a later tagged sibling freezes the app again silently
`custom_apps_manager.dart:449-455` / `:470`: after a fallback download `assetPattern` stays the x64 pattern. If Klei
(or any repo) later adds e.g. `KleiKodeshSetup-v11.0.0-arm64.exe` next to the plain installer, the guard turns the
fallback off for v11 and `fetchLatest` silently stays on the last v10 release. That is the original #310 symptom, and
it is an acceptable trade-off of the guard. Relearning the pattern from the downloaded asset name would avoid it, but
it is outside this fix.

### N1 — pre-existing, outside the diff: names whose version follows a letter freeze the version
`github_source.dart:113-114` (`_versionDigits`): `7z2407-x64.exe` → `^\d+z2407-x64\.exe$`. The `2407` follows `z`, so it is
kept literally, and the 7-Zip asset never matches the next version (`7z2408-x64.exe`). This is the same class as the
earlier `v9` bug. It is not caused by this branch.

### Comments and commit
New code comments are ≤2 lines and record no history (`github_app_client.dart:104-105, 111`;
`github_source.dart:134-135, 143-144, 154`). The test comments are short and descriptive. The commit message explains
the why, names the issue, and no longer claims the false invariant. It still has no `Claude-Session:` trailer (nit,
same as round 9; AGENTS.md does not require it).

## Verdict
**Clean for merge** with respect to blocking issues. F1 and F2 are fixed and covered by tests, F6 is covered, and all
checks pass except the known env-only failures. Residuals R1–R4 are non-blocking. R1 (x86 uploaded first and alone)
is the only one that can still store a wrong-architecture installer, and only inside a short upload window.
