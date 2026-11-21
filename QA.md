# QA round 3: 2026-11-21

This is an independent, read-only review of the branches as amended after round 2
(`origin/qa/issues-round2:QA.md`). Each branch is still one commit on top of
`upstream/main` and is diffed as `upstream/main...origin/<branch>`.

Environment: Linux, Flutter 3.47.2 / Dart 3.13.2, Node 22.23.5, running as **root**.
Two failures come from this environment and also happen on `upstream/main`:
- `OtzariaTargetPlatform.detect` throws on Linux.
- Running as root bypasses the read-only mirror.

They are marked **pre-existing**.

| Branch | Commit | Checks | Blocking findings |
| --- | --- | --- | --- |
| fix/289-drive-preferences | 25ae3a1 | green (1 pre-existing fail) | **no** |
| feat/288-cancel-custom-app-download | f8409da | **RED: 1 new test fails** (+1 pre-existing fail in custom_apps_manager) | **yes** |
| feat/290-report-drafts | dd56dac | green | **no** |
| store fix/302-hotfix-version | 04da220 (unchanged) | green (214/214) | **no** |
| store fix/303-plugin-registry | 7d4f303 | green (215/215) | **no** |

Severity: **bug** = wrong behaviour now · **risk** = can go wrong under realistic
conditions · **test-gap** · **nit**.

---

## 1. feat/288-cancel-custom-app-download (f8409da): BLOCKING

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` / `dart format --output=none --set-exit-if-changed .` / `flutter analyze --no-fatal-infos` | pass / pass (0 changed) / pass |
| launcher_app | `flutter test test/custom_apps_test.dart` | **+125 ~4 -1: a NEW test fails** |
| custom_apps_manager | `dart pub get` / format / `dart analyze` | pass / pass / pass |
| custom_apps_manager | `dart test test/custom_apps_manager_test.dart` | 94 pass, 1 fail (**pre-existing**, root bypasses read-only mirror) |
| otzaria_l10n | `dart pub get` / format / `dart analyze` / `dart test` | pass / pass / pass / pass (+55) |

```
00:10 +91 ~3 -1: הורדה לכל התוכנות — רק למה שיש בו חדש ביטול אחרי תוכנה שנכשלה: הכשל נספר [E]
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═══
The following StateError was thrown while running async test code:
Bad state: AppLogger.init() לא נקרא עדיין
#0  AppLogger.instance (package:launcher_app/src/services/app_logger.dart:86:7)
#1  CustomAppsController._guard (.../custom_apps_controller.dart:1085:17)
#2  CustomAppsController.download (.../custom_apps_controller.dart:711:20)
#3  CustomAppsController.downloadAllOutdated (.../custom_apps_controller.dart:675:13)
#4  main.<fn> (file:///.../launcher_app/test/custom_apps_test.dart:1900:18)
```

The test fails on its own (`--plain-name`) and in the full file. It does not depend on test order.

```
custom_apps_manager (pre-existing):
למידה אחרי התקנה כונן נעול: ההתקנה מצליחה גם כשאי אפשר לכתוב למראה [E]
  Expected: false
    Actual: <true>
```

### Round-2 findings

| # | Status |
| --- | --- |
| 1 bug: stale `lastDownloadCancelled` in download-all | **fixed.** It is reset right after the busy check in `downloadAllOutdated` (`custom_apps_controller.dart:633`), and also at the start of `download`. The new test "ביטול קודם אינו נשאר להורדת הכול שאין בה מה להוריד" passes. **Mutation:** deleting the reset makes that test fail ✓. The `download()` busy early return still skips the reset. That is fine: a busy return means another download is running, and that download already cleared the flag when it started. |
| 2 test-gap | **partly.** The controller test "failure before cancel is counted" was added, but it does not run (see new finding 1). There is still no widget test for the button (appears, disabled after one press) or for the cancelled snack. "Cancel during the last item" is not tested either. |
| 3 nit: punctuation of the joined snack | **fixed / accepted.** A trailing `.` is stripped from each part, the parts are joined with `'. '`, and the result ends with `.`. This works for both he and en today. A single l10n string would still be cleaner, but this does not block. |
| 4 nit: merge order with 290 | still applies. Both branches add line 1 of `יומן שינויים.md` (and edit `otzaria_l10n`), so the second one to merge needs a trivial rebase. |

### New findings

1. **bug (test, blocking): `launcher_app/test/custom_apps_test.dart` ~1884-1907, "ביטול אחרי תוכנה שנכשלה: הכשל נספר", fails with `StateError: AppLogger.init() לא נקרא עדיין`.**
   *Scenario:* the fake throws `SocketException` for item `a`. `_guard` (`custom_apps_controller.dart:1085`) logs it with `AppLogger.instance.warn`, and that throws because this group never initializes the logger. The test is red, so CI is red. The assertion `failed == 1` is never really checked.
   *Fix:* initialize the logger in the test, as "כללים שנלמדו ולא נשמרו נרשמים כאזהרה בלוג" already does (line ~538):
   ```dart
   await tester.runAsync(() async {
     AppLogger.resetForTest();
     await AppLogger.init(tempDir.path);
   });
   addTearDown(AppLogger.resetForTest);
   ```
   *Verified:* with exactly this addition the test passes (`+1: All tests passed!`). Then run the whole file before amending. Making `_guard` use `AppLogger.maybeInstance?` (like lines 139/341) would also work and be more robust, but it changes production code.

---

## 2. fix/289-drive-preferences (25ae3a1)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` | pass |
| launcher_app | `dart format --output=none --set-exit-if-changed .` | pass (306 files, 0 changed) |
| launcher_app | `flutter analyze --no-fatal-infos` | pass |
| launcher_app | `flutter test test/app_paths_test.dart` | +41 ~2, **1 fail, pre-existing** |

```
תת-הנתיבים שמתחת לתיקיית הנתונים mirror/library, mirror/app ו-mirror/plugins יושבים תחת dataDir [E]
  Unsupported operation: ... (זוהה: linux).  OtzariaTargetPlatform.detect
```

All seven seeding tests pass, including the new FAT32/DST test and the "legacy copy without a record" test.

### Round-2 findings

| # | Status |
| --- | --- |
| 1 risk: FAT32/DST mtime shift | **fixed.** `seeded_preferences.json` stores the sha256 of the drive content (`app_paths.dart` `seedPreferences`). An mtime-only change keeps the local edit, as the test "זמן שינוי שזז בכונן (FAT32 בשעון קיץ)…" shows. mtime is not used at all any more. |
| 2 nit: non-atomic copy | **fixed.** `writeBytesAtomically` (temp + `renameRetryingTransient`, and the temp is removed on failure). `crypto` and `otzaria_downloads` are already dependencies of launcher_app. |
| 3 nit: README run-on | **fixed.** Split into three sentences. |

### New findings (none blocking)

1. **nit / accepted design: first run after an upgrade from `upstream/main`.** With no record yet, if the local `faq_customization.json` differs from the drive copy, the drive copy wins once (the test "עותק ישן בלי רישום…" pins this). The code cannot tell "the drive was updated" from "the user edited it on this machine". It chooses the drive, which is the point of #289, but a local edit made under an older launcher is lost one time. This is acceptable. It could get one line in the commit message.
2. **test-gap (minor):** the branch "no record and the local content equals the drive" (it only writes the record) is not tested directly. A test that seeds identical content with no record, then edits locally, then reseeds and expects the local edit to stay would cover it.
3. **nit: `AGENTS.md:176`.** The new line "(#289). The state files deliberately are not seeded." is about 90 columns, while the rest of the paragraph wraps at about 80.
4. **nit:** no entry in `launcher_app/assets/יומן שינויים.md`. The fix is user-visible ("the help message on a locked drive now updates"). Add an entry before the release (CLAUDE.md, AGENTS.md §3) if it should be announced.

---

## 3. feat/290-report-drafts (dd56dac)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | pub get / format / `flutter analyze --no-fatal-infos` | pass / pass / pass |
| launcher_app | `flutter test test/app_reports_test.dart` | **pass** (+58) |
| otzaria_l10n | `dart pub get` / format / `dart analyze` / `dart test` | pass / pass / pass / pass (+55) |

### Round-2 findings

| # | Status |
| --- | --- |
| 1 nit: AGENTS.md §5.10 | **fixed.** It adds the bold landmine "The report draft lives on the machine, never on the drive", naming `forState(machineDir:)` / `AppPaths.machineStateDir` and saying "no machine dir means no drafts — not `stateDir`". |
| 2 nit: `restoreDraft` overrides a preselected type | **accepted as nit.** It is unchanged and harmless today, because the manual dialog preselects nothing. |

### New findings

**Clean.** The code is unchanged since round 2 except for the AGENTS.md entry. The merge-order nit with 288 (changelog line 1, `otzaria_l10n`) still applies.

---

## 4. otzaria-plugin-store fix/302-hotfix-version (04da220, unchanged)

| Command | Result |
| --- | --- |
| `cd native && node --test` | pass: 214 tests, 0 fail |
| `cd native && node --test 'test/**/*.test.js'` | pass: 214 tests, 0 fail |

**Status: clean.** On Node 22 `node --test` (no args) also passes here. The pre-existing nit about `package.json` `"test": "node --test test/"` is outside this branch.

---

## 5. otzaria-plugin-store fix/303-plugin-registry (7d4f303)

### Commands

| Command | Result |
| --- | --- |
| `cd native && node --test` | **pass**: 215 tests, 0 fail (upstream/main: 209) |
| `cd native && node --test 'test/**/*.test.js'` | **pass**: 215 tests, 0 fail |
| C++ build | not possible on Linux; reviewed by reading |

### Round-2 findings

| # | Status |
| --- | --- |
| 1 bug: test file did not compile | **fixed.** All Windows paths are written with `\\`, and the `\u00xx` escapes in the Hive fixtures are intact. The file loads, and all 6 tests run and pass. **Mutations (re-verified):** disabling `#mayUseCustomDatabasesFolder` → 1 fail ✓. Disabling `if (registered !== null) return registered;` → 4 fail ✓. Removing `readRegistry: this.sys?.pluginRegistry` → 1 fail (the wiring test) ✓. |
| 2 nit: whole `.hive` base64-encoded across the bridge | still open (not a correctness issue). |
| 3 nit: no log line when the registry is skipped | still open. |

### New findings

**Clean.** The JS and C++ are the same as reviewed in round 2. One observation, not a finding: when `customPluginsDir` is set, `dataRoot` is taken as the grandparent of `installed`. `PluginsManager.scanInstalled` never passes `customPluginsDir`, so today it cannot point at an unrelated `databases\plugins_host.db`.

---

## What should block merge

- **feat/288:** new finding 1. The new controller test "ביטול אחרי תוכנה שנכשלה: הכשל נספר" fails, because `AppLogger` is never initialized in that test. The fix is a 5-line test change, already verified to pass. Then run all of `test/custom_apps_test.dart` again.
- Everything else is green. The rest are nits or test-gaps.
