# QA round 9 — `fix/310-asset-pattern-architecture`

Commit `6b3d3b4` (one commit on `upstream/main` `8f772e4`). Diff: `custom_apps_manager/README.md`,
`lib/src/models/github_source.dart`, `lib/src/services/github_app_client.dart`,
`test/github_app_client_test.dart` (+109/−3). Read-only QA, Flutter 3.47.2 / Dart 3.13.2, running as root on Linux.

## Summary

| Topic | Checks | Blocking |
|---|---|---|
| Klei Kodesh (#310) end to end | fetchLatest + selectAsset on the v10 asset names → `v10.7.0` / `KleiKodeshSetup-v10.7.0.exe` | no (works) |
| **Fallback to the wrong architecture** | x64 pattern + no x64 asset in a release → falls back to the *unsuffixed* file, which in common naming (e.g. Notepad++) **is the 32-bit build** | **yes** (F1) |
| Fallback becomes too broad | hand-edited / foreign patterns: `_x64$` → `$` (matches everything), `-x64\.exe$` → `\.exe$` | no (F2) |
| Regex edge cases | `x86_64`, `-64bit`, `(x64)` without a space, token at the start, escaped `\-` | no (F3, F4) |
| Strict-first order | inside a release: yes. fetchLatest usable filter and `_usableAsset` both go through `selectAsset` | no |
| Other callers | form (`fetchLatest` with `assetPattern: ''`), launcher online check (`peekLatestOnline` → `fetchLatest`), download (`_usableAsset`) — all covered by the one change | no |
| Versions after downloading v10.7.0 | stored `10.7.0` from the tag; `compareVersions('10.7.0.0','10.7.0') == 0` → card shows no pending update | no |
| Install of v10 installer | kind is sniffed at install time; the v10 Rust setup → `interactive` (no wrong Inno flags) | no (note N1) |
| format / analyze / tests | all clean except known env-only failures | no |
| Comments (≤2 lines, no history) | code comments OK; the test-fixture comment and README text are history-ish | no (nit F5) |
| Commit message §4 | explains the why, issue reference, Co-Authored-By. Claim "an x64 pattern never falls to the x86 installer" is wrong (F1). No `Claude-Session:` trailer | no (nit) |
| Test gaps | no test for the unsuffixed = x86 convention; no `downloadFromGithub` test through the fallback | no (F6) |

## Command outputs

### custom_apps_manager
```
$ dart pub get              → OK (12 packages have newer versions incompatible…)
$ dart format --output=none --set-exit-if-changed .
Formatted 49 files (0 changed) in 0.15 seconds.
$ dart analyze
Analyzing custom_apps_manager...
No issues found!
$ dart test
00:05 +402 -2: Some tests failed.
Failing tests:
  test/custom_apps_manager_test.dart: למידה אחרי התקנה כונן נעול: ההתקנה מצליחה גם כשאי אפשר לכתוב למראה
  test/known_locations_test.dart: שמירה וטעינה תיקייה שאינה ניתנת לכתיבה אינה שגיאה
```
Both failures are env-only (read-only mirror bypassed as root, `id -u` = 0). Re-run in isolation:
```
  Expected: empty
    Actual: {'PC-1': 'C:\\Apps\\X'}
  Expected: false
    Actual: <true>
```
All 18 tests in `github_app_client_test.dart`, including the 5 new ones, pass.

### launcher_app
```
$ flutter pub get           → Got dependencies!
$ flutter analyze --no-fatal-infos
Analyzing launcher_app...
No issues found! (ran in 25.9s)
$ flutter test test/custom_apps_test.dart
00:23 +122 ~4: All tests passed!
```

### Checking against the real GitHub data
`curl https://api.github.com/repos/KleiKodesh/KleiKodeshProject/releases?per_page=20` is **blocked in this
session** (`403 … GitHub access to this repository is not enabled for this session`; `add_repo` with push access was
refused, and `releases.atom`/`expanded_assets` are blocked too). Instead:
- `git ls-remote --tags` gives the real tag list: `v9.1.5`, `v10.0.0` … `v10.7.0` (14 v10 tags).
- The asset names come from the repo's own build (`Build/build.ps1:48` `KleiKodeshSetup-v$Version.exe`;
  `.github/workflows/release.yml:220` uploads `KleiKodeshSetup-$tag.exe` and `KitveiHakodeshPortable-$tag.zip` in a
  single `gh release create`; README: "one installer (AnyCPU)").
- A throwaway script (deleted afterwards) fed those 14 v10 releases plus a v9.1.4 with `-x64`/`-x86` through
  `GithubAppClient.fetchLatest` (MockClient):
```
pattern=^KleiKodeshSetup-v\d+\.\d+\.\d+-x64\.exe$
latest=v10.7.0 version=10.7.0 asset=KleiKodeshSetup-v10.7.0.exe
```
- `OtzariaUpdateCheckResult.compareVersions`: `10.7.0.0 vs 10.7.0 -> 0`, `10.7.0.0 vs v10.7.0 -> 0`,
  `9.1.4.0 vs 10.7.0 -> -1`. Klei sets `AssemblyFileVersion` to four parts (`build.ps1:104`), so after the download
  `CustomAppView.pending` is `none` and `customAppOnlineIsNewer('10.7.0','10.7.0')` is false.

### Regex probe (outputs from the same script)
```
[npp.8.6.9.Installer.x64.exe]  neutral=^npp\.\d+\.\d+\.\d+\.Installer\.exe$
   pick from [npp.8.7.0.Installer.exe, npp.8.7.0.Installer.arm64.exe] -> npp.8.7.0.Installer.exe   ← 32-bit build
[App-Setup-1.0-x86.exe]        neutral=^App-Setup-\d+\.\d+\.exe$
   pick from [App-Setup-1.1.exe, App-Setup-1.1-arm64.exe] -> App-Setup-1.1.exe
[App-1.0-x86_64.exe]  pattern=^App-\d+\.\d+-x86_\d+\.exe$  neutral=^App-\d+\.\d+_\d+\.exe$  -> null
[App-1.0-win-x64.zip] neutral=^App-\d+\.\d+-win\.zip$ -> App-1.1-win.zip
[App-1.0-64bit.exe]   pattern=^App-\d+\.\d+-\d+bit\.exe$  neutral=null
   pick from [App-1.1-32bit.exe, App-1.1.exe] -> App-1.1-32bit.exe                                  ← pre-existing
[App_1.0_amd64.exe]   neutral=^App_\d+\.\d+\.exe$ -> App_1.1.exe (i386 not picked)
[App-1.0-X64.exe]     neutral=^App-\d+\.\d+\.exe$ -> App-1.1.exe
[x64-App-1.0.exe]     neutral=null
[App Setup 1.2 (x64).exe] neutral=^App Setup \d+\.\d+\.exe$ -> App Setup 1.3.exe ((x86) not picked)
[App-1.2(x64).exe]    neutral=null
[App-1.0-x64.exe] from [.exe.sha256, .exe.sig, -portable.zip, -debug.exe, Other-1.1.exe, App-1.1.exe] -> App-1.1.exe
[App-1.0-x64-debug.exe]    neutral=^App-\d+\.\d+-debug\.exe$ -> App-1.1-debug.exe
[App-1.0-x64-portable.zip] neutral=^App-\d+\.\d+-portable\.zip$ -> App-1.1-portable.zip (x86-portable not picked)
[App-win64-1.0.exe] from [App-win32-1.1.exe, App-1.1.exe] -> App-1.1.exe
[-x64.exe]  neutral=^\.exe$
[App.x64.msi] neutral=^App\.msi$ -> App.msi (App.x86.msi not picked)
hand ^App\-x64\.exe$ -> ^App\\.exe$ valid=true matchesOther.exe=false
hand -x64\.exe$ -> \.exe$ valid=true matchesOther.exe=true
hand _x64$ -> $ valid=true matchesOther.exe=true
hand ^-x64$ -> ^$ valid=true matchesOther.exe=false
hand x64 / ^App-(x64|arm64)\.exe$ / ^App-x64.exe$ / ^App[-_]x64\.exe$ -> null
```
Not affected: checksum and signature files, portable zips, debug builds and other products (everything stays
anchored with `^…$` and keeps the extension). The neutral pattern was never invalid regex in any case tried, and
`matches()` swallows a `FormatException` anyway.

## Findings

### F1 — BLOCKING: an x64 pattern falls back to the 32-bit installer when the plain name means x86
`custom_apps_manager/lib/src/services/github_app_client.dart:106-113`,
`custom_apps_manager/lib/src/models/github_source.dart:134-148`.

The fix assumes an unsuffixed file is "a general installer". In a common naming scheme the unsuffixed file is the
**32-bit** build and only x64/arm64 carry a suffix: Notepad++ ships `npp.X.Installer.exe` (x86),
`npp.X.Installer.x64.exe` and `npp.X.Installer.arm64.exe`. The probe above shows the x64 pattern selecting
`npp.8.7.0.Installer.exe`. The commit message ("an x64 pattern never falls back to the x86 installer") and the README
("a file for another architecture matches neither pattern") are true only when x86 is suffixed explicitly.

Picking the exact match first protects only the steady state. Failure case: a project that uploads assets one by one
after publishing the release (common with CI, or when one matrix job fails). During that window the new release has
`App.exe` (x86) and no `App.x64.exe` yet:
1. Before: `fetchLatest` skipped that release (no match) and stayed on the previous one.
2. Now: `selectAsset` succeeds through the neutral pattern, so the release counts as "usable" (`github_app_client.dart:36-39`).
   `downloadFromGithub` (`custom_apps_manager.dart:450-455` → `_usableAsset`) downloads the 32-bit installer and
   stores `version` = the new tag.
3. When the x64 asset shows up later, `customAppOnlineIsNewer(tag, tag)` is false, so the card stays "up to date"
   with the wrong-architecture installer on the drive until the next release. The reverse case (an x86 pattern in a
   repo where the plain file is x64) gives an installer that will not run on 32-bit Windows.

Suggested minimal guard: fall back only when **no asset in the release carries an architecture token**, meaning the
release really moved to one installer, as Klei v10 did (`[KitveiHakodeshPortable-v10.7.0.zip, KleiKodeshSetup-v10.7.0.exe]`).
That still fixes #310, and npp-style releases (which have `.x64`/`.arm64` siblings) never fall back. Add a test for
`[App.exe, App.arm64.exe]` with an x64 pattern → `null`.

### F2 — non-blocking: the neutral pattern can become match-everything for patterns not made by `fromAssetName`
`github_source.dart:136-148`. Patterns from the form are always `^…$` (`custom_app_form_dialog.dart:399`), but
`descriptor.json` travels on the drive and can be hand-edited. `_x64$` → `$` matches **every** asset (including
`.sha256`), and `-x64\.exe$` → `\.exe$` matches any exe of any product in the repo. Cheap guard: apply the fallback
only to patterns that start with `^`, or reject a neutral pattern with no literal text before the extension. The
learned `-x64.exe` → `^\.exe$` is harmless (it matches only a file literally named `.exe`).

### F3 — non-blocking, pre-existing: `-64bit` patterns already match `-32bit`, and the `64bit|32bit` alternatives are dead
`github_source.dart:107-108` (`_versionDigits`) turns the `64` in `-64bit` into `\d+` (it follows a separator), so
`App-1.0-64bit.exe` → `^App-\d+\.\d+-\d+bit\.exe$` already picks `App-1.1-32bit.exe` with the **exact** pattern
(probe above). For the same reason `withoutArchitecture` never sees the literal `64bit`/`32bit`, so those alternatives
in `_architectureToken` (`:137`) never fire for learned patterns. `x86_64` similarly becomes `x86_\d+`, and its
neutral form `_\d+` never matches a plain file (harmless, but the fallback has no effect for it). Not caused by this
diff, but it sits right next to it.

### F4 — non-blocking: unsupported forms, where the fallback does nothing (safe)
Token at the start (`x64-App-1.0.exe`), `(x64)` without a leading space (`App-1.2(x64).exe`), and an escaped hyphen
`\-x64` (gives `^App\\.exe$`, still valid regex and matches nothing). These only miss the fallback; they never pick a
wrong file.

### F5 — nit: history in a test comment and in the README
`custom_apps_manager/test/github_app_client_test.dart` (new block): `// #310: KleiKodesh dropped the -x64/-x86 builds
for one installer in v10.` is a history note (AGENTS.md §4: "never record history in a comment"). The README paragraph
(`custom_apps_manager/README.md:78-85`) tells the story ("got stuck silently on v9.1.4…"). That is acceptable for
docs, but its last sentence repeats the false invariant from F1. The commit message has no `Claude-Session:` trailer
(the session's attribution asks for one; AGENTS.md itself does not require it).

### F6 — test gaps
- No test for the unsuffixed = x86 convention (F1).
- No test of `CustomAppsManager.downloadFromGithub` downloading through the fallback (`_usableAsset`), so stored
  `fileName`/`version` for the neutral asset are unverified.
- No test that a newer release with a neutral file beats an older release that matches exactly, within one window
  (covered only indirectly by the `fetchLatest` Klei test).

### N1 — note (not this diff): v10 changes installer technology
Klei v10's `KleiKodeshSetup` is a custom Rust installer (`Build/installer-rs`, silent flag `--silent`), not the
earlier framework. `CustomAppInstaller.install` sniffs the kind at install time (`custom_app_installer.dart:74-77`),
so it falls to `interactive` (the user clicks through). No wrong flags are passed. Whether the learned
`registryDisplayName`/`exeName` from v9 still detect the v10 install was **not verified** (no Windows here).
`כתבי הקודש.exe` at 10.7.0.0 is the commit's claim and could not be checked independently.

## Verdict
The Klei Kodesh case is fixed and all checks pass. **One blocking issue (F1):** the fallback can install the
wrong-architecture build in common naming schemes, which contradicts the invariant the commit and README state.
Restrict the fallback to releases with no architecture-tagged asset, add the npp-style test, and then re-run QA.
