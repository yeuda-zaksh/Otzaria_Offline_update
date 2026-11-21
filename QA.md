# QA round 2 — 2026-11-21

This is an independent, read-only review of the branches as amended after round 1
(`origin/qa/issues-round1:QA.md`). Each branch is still one commit on top of
`upstream/main`, and is diffed as `upstream/main...origin/<branch>`.

Environment: Linux, Flutter 3.47.2 / Dart 3.13.2, Node 22.23.5, running as **root**.
As in round 1, two failures come from the environment and also happen on
`upstream/main`:
- `OtzariaTargetPlatform.detect` throws on Linux.
- Running as root bypasses the read-only mirror.

They are marked **pre-existing**. Every other check was green, except the one
failure in store branch 303 (section 5).

Severity: **bug** = wrong behaviour now · **risk** = can go wrong under realistic
conditions · **test-gap** · **nit**.

| Branch | Commit | Checks | New findings |
| --- | --- | --- | --- |
| fix/289-drive-preferences | d5ef35e | green (1 pre-existing fail) | 1 risk, 2 nit |
| feat/288-cancel-custom-app-download | 5093647 | green (1 pre-existing fail) | 1 bug (minor), 1 test-gap, 1 nit |
| feat/290-report-drafts | c32cb0b | green | 2 nit |
| store fix/302-hotfix-version | 04da220 (unchanged) | green | clean |
| store fix/303-plugin-registry | 9efd0e9 | **RED: the new test file does not compile** | **1 bug**, 2 nit |

---

## 1. fix/289-drive-preferences (d5ef35e)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` | pass |
| launcher_app | `dart format --output=none --set-exit-if-changed .` | pass |
| launcher_app | `flutter analyze --no-fatal-infos` | pass |
| launcher_app | `flutter test test/app_paths_test.dart` | 40 pass, 2 skipped, **1 fail, pre-existing** |

```
תת-הנתיבים שמתחת לתיקיית הנתונים mirror/library, mirror/app ו-mirror/plugins יושבים תחת dataDir [E]
  Unsupported operation: הכלי תומך בהתקנת אוצריא ב-Windows וב-macOS בלבד (זוהה: linux).
  package:otzaria_manager/src/models/otzaria_release.dart 17:12  OtzariaTargetPlatform.detect
```

All five seeding tests pass (the renamed one and the four new ones).

### Round-1 findings

| # | Status |
| --- | --- |
| 1 risk: `launcher_settings.json` overwritten | **fixed.** Only names in `driveOwnedPreferenceFileNames` (`faq_customization.json`) are refreshed. The test "הגדרות המחשב אינן נדרסות, גם כשהעותק בכונן חדש יותר" proves it with a newer drive copy. |
| 2 risk: comparing two clocks | **fixed.** The drive mtime is compared only with the drive mtime saved in `logs/seeded_preferences.json`. The test "שעון מחשב שמפגר…" would fail with the round-1 code (local 2026-10-01 < drive 2026-11-10 → overwritten). But see new finding 1 (FAT32/DST). |
| 3 risk: `setLastModified` failure | **fixed.** The mtime is no longer stamped on the copy. The record is written after the copy, and a missing or stale record only leads to a recopy. |
| 4 nit: test name | **fixed.** Renamed, with explicit mtimes. |

Seeding runs in `main` after `InstanceLock` and before `SettingsController` /
`FaqController` read anything, so no other process races the record. The record is
written with `writeStringAtomically`, which retries on transient Windows errors.

### New findings

1. **risk (minor) — `launcher_app/lib/src/services/app_paths.dart:346-350`: on a FAT32 stick, the drive mtime moves by an hour at every DST change, and the local edit is overwritten.**
   FAT32 stores local time without a time-zone offset. Windows converts it with the *current* bias, so after Israel switches between summer and winter time, the same unchanged file reports a different `lastModified`. Then `last != sourceTime`, and the drive copy overwrites the machine's `faq_customization.json`. (exFAT and NTFS store UTC and are not affected.)
   *Scenario:* the offline user customised the help message locally. Twice a year their edit goes back to the drive version, although the drive did not change.
   *Fix:* in the record, store a hash of the content that was seeded (sha256 of the drive file, or mtime **and** hash). When the mtime differs but the drive content hashes to the recorded value, only update the record.
2. **nit — `app_paths.dart:359` / pre-existing:** `source.copy` is not atomic. A first seed of `launcher_settings.json` cut off half-way (power loss, stick pulled out) leaves a truncated file that is never seeded again. The settings then fall back to defaults. This was the same before the branch. `copy` to `<name>.tmp` + `renameRetryingTransient` would close it.
3. **nit — `launcher_app/README.md:538`:** the new clause turns the sentence into a run-on ("…חוץ מהודעת העזרה שמתעדכנת בכל פעם שהעותק בכונן משתנה, קובצי המצב לא — הם…"). Split it into two sentences.

---

## 2. feat/288-cancel-custom-app-download (5093647)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | pub get / format / `flutter analyze --no-fatal-infos` | pass / pass / pass |
| launcher_app | `flutter test test/custom_apps_test.dart` | **pass** (+124, ~4 Windows-only) |
| custom_apps_manager | `dart pub get` / format / `dart analyze` | pass / pass / pass |
| custom_apps_manager | `dart test test/custom_apps_manager_test.dart` | 94 pass, **1 fail, pre-existing** |
| otzaria_l10n | `dart pub get` / format / `dart analyze` / `dart test` | pass / pass / pass / **pass** (+55) |

```
למידה אחרי התקנה כונן נעול: ההתקנה מצליחה גם כשאי אפשר לכתוב למראה [E]
  Expected: false
    Actual: <true>
```

**Mutation check of the new mid-stream test:** with `if (!keepPartialOnCancel)` in
`otzaria_downloads.dart:339` turned off, the test fails:

```
Actual: [.../App-3.0.exe.part.resume, .../App-3.0.exe.part.part]
```

So it really proves that the partial file and the resume state are removed.

### Round-1 findings

| # | Status |
| --- | --- |
| 1 risk: summary dropped after cancel | **fixed.** The snack is "בוטלה" plus downloaded and failed counts, shown as an error when failed > 0. A cancel pressed after the last item is no longer reported (`stopped`). |
| 2 nit: button missing between items | **fixed** for the download phase (`isDownloadingAll` keeps the button). It is still absent during the initial `_checkEach` peek phase, which is acceptable because nothing is downloading yet. |
| 3 test-gap | **partly.** The mid-stream test was added and verified (above). There is still no widget test that the button appears, is disabled after one press, and shows `downloadCancelledSnack`. The controller tests do not cover "cancel after the last item" or "failed count after a cancel". |
| 4 nit: merge order with 290 | still applies (both edit line 1 of `יומן שינויים.md` and `otzaria_l10n`). |

### New findings

1. **bug (minor) — `launcher_app/lib/src/controllers/custom_apps_controller.dart:652` (early return) + `custom_apps_screen.dart:418`: `lastDownloadCancelled` stays set from an earlier single download, and "download all" then says "ההורדה בוטלה" for a run that cancelled nothing.**
   `downloadAllOutdated` resets the flag only in its `finally`. That is reached only when there are targets. The early returns (`targets.isEmpty`, `online.isEmpty`, already busy) leave it as it was.
   *Scenario (reproduced with a throw-away test on the fake controller):* cancel the download of A, remove A, then click "download all" while B is up to date. Result: `(checked: 1, downloaded: 0, failed: 0)` with `lastDownloadCancelled == true`, so the snack is "ההורדה בוטלה" instead of "nothing new, 1 checked". It is the same without network, where "no connection" is shown as "cancelled".
   *Fix:* set `lastDownloadCancelled = false;` at the top of `downloadAllOutdated` (and in `download` before the `downloadingId != null` early return), and add this scenario as a test.
2. **test-gap:** see round-1 item 3. Add a widget test: the button appears, is disabled after one press, and shows the cancelled snack. Add controller tests for "cancel during the last item's `load()`" (expect not cancelled) and for "B failed, C cancelled" (expect `failed == 1`).
3. **nit — `custom_apps_screen.dart:420-425`:** the snack is built by joining three translated sentences with `'. '`. The pieces end inconsistently (`downloadAllSomeFailed` ends with "." and the others do not), so the text ends with or without a full stop depending on the case. A single `downloadCancelledSummary(downloaded, failed)` string in `otzaria_l10n` would keep the wording and punctuation in the translator's hands.

---

## 3. feat/290-report-drafts (c32cb0b)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | pub get / format / `flutter analyze --no-fatal-infos` | pass / pass / pass |
| launcher_app | `flutter test test/app_reports_test.dart` | **pass** (+58) |
| otzaria_l10n | `dart pub get` / format / `dart analyze` / `dart test` | pass / pass / pass / **pass** (+55) |

**Mutation checks of the new dialog tests:**
- Skip `restoreDraft()` in `_load()` → both `#290` dialog tests fail ✓.
- Remove the three `_x.text = _form.x` lines → the first dialog test fails ✓.
- Remove only `_title.text = …` → still green. This is not a gap: `_title` is a `late final` controller created with `_form.title` at its first build, which happens after the restore, so that line is redundant.

### Round-1 findings

| # | Status |
| --- | --- |
| 1 risk (privacy): draft on the drive | **fixed.** `AppReportsController.forState(machineDir: AppPaths.machineStateDir(...))` puts the draft in `%LOCALAPPDATA%\OtzariaOfflineUpdate\reports\launcher-draft.json` (per Windows user). With no machine dir, `drafts == null` and the buttons are hidden. In read-only mode this is the same folder as `stateDir`, still outside `reports/launcher` and `reports/outbox`. |
| 2 risk: hand-rolled atomic write | **fixed.** `writeStringAtomically`. |
| 3 nit: "cancel" replaced | **fixed.** "ביטול" stays next to "מחיקת הטיוטה" (asserted in the test). |
| 4 test-gap: dialog | **fixed.** Two dialog tests with `_MemoryDrafts`, verified by mutation. |

### New findings

1. **nit — `AGENTS.md` §5.10 is not updated.** The landmine "the draft is unredacted and has screenshots, so it lives in `machineStateDir` and never on the drive" exists only in a code comment. Someone who later "simplifies" `forState` to `stateDir` would bring back round-1 finding 1. Add one bold sentence to §5.10 (AGENTS.md §"Editing this file").
2. **nit — `app_report_form.dart` `restoreDraft`:** `type = draft.type ?? type` lets a saved draft override a type the caller preselected. That is harmless today, because the manual dialog does not preselect one, but it is worth knowing if a "suggest a feature" entry point is added.

---

## 4. otzaria-plugin-store fix/302-hotfix-version (04da220, unchanged)

| Command | Result |
| --- | --- |
| `cd native && node --test 'test/**/*.test.js'` | **pass**: 214 tests, 0 fail |

**Status: clean.** The round-1 nit (`package.json` `"test": "node --test test/"` fails on Node ≥ 22) is pre-existing and still open.

---

## 5. otzaria-plugin-store fix/303-plugin-registry (9efd0e9)

### Commands

| Command | Result |
| --- | --- |
| `cd native && node --test 'test/**/*.test.js'` | **FAIL**: 210 tests, 209 pass, **1 fail** (upstream/main: 209/209) |
| C++ build | not possible on Linux; reviewed by reading |

```
not ok 5 - test/installed_scanner.test.js
# file:///.../native/test/installed_scanner.test.js:7
# const APP_DATA = 'C:\Users\u\AppData\Roaming';
#                           ^^^^^^
# SyntaxError: Invalid Unicode escape sequence
```

### New findings

1. **bug — `native/test/installed_scanner.test.js` (whole file): every backslash in the amended test is single, so the file is a SyntaxError and none of its 6 tests run.**
   `'C:\Users\u\AppData\Roaming'` contains `\u\`, which is an invalid escape, so the module does not load. Lines 7-10, 16-23, 34, 52, 74, 81 and 91-92 all have Windows paths with one `\` where `\\` was meant. The source file is fine (`installed_scanner.js:158` has `\\databases\\`). It looks like an escaping loss during the amend. Round-1 had 212 passing tests, and this branch now shows 210 with one failing **file**. So the #303 regression test, the new custom-databases test and the `PluginsManager.scanInstalled` wiring test (round-1 test-gap 4) are not running at all, and `npm test` / CI is red.
   *Verified:* doubling every backslash except the `\u00xx` escapes makes the file pass (6/6). With that repair, both new tests are real:
   - Disabling the `#mayUseCustomDatabasesFolder` line fails "תיקיית מסדים מותאמת…".
   - Deleting `readRegistry: this.sys?.pluginRegistry` fails "מעביר את sys.pluginRegistry לסורק".

   *Fix:* restore the doubled backslashes (or use `String.raw` / `path.win32.join`), and run `node --test 'test/**/*.test.js'` before amending.

### Round-1 findings

| # | Status |
| --- | --- |
| 1 risk: stale default DB vs custom databases folder | **fixed, conservatively** (see the comparison below). |
| 2 nit: `disabled` / `source_type` | **fixed** for `disabled`: C++ returns only `{versions}`. `source_type` is still not read (not a regression). |
| 3 nit: non-TEXT `version` | **fixed.** `sqlite3_column_type(...) != SQLITE_TEXT` skips the row, for both id and version. |
| 4 test-gap: wiring | the test was written, but **does not run** (finding 1). After the repair it passes and catches the mutation. |

**Comparison with Otzaria's resolution order** (`Otzaria/otzaria` `dev:lib/core/app_paths.dart`).
`resolvePluginsDbPath` → `resolveNotesDbPath('plugins_host.db')` →
`_writableDatabasesDirectory()`:

1. `getDatabasesPath()`: the saved `key-databases-path` if it is non-empty. Otherwise `<dataRoot>/databases` if that folder exists. Otherwise `dirname(libraryPath)/databases`.
2. If that folder is not writable, Otzaria falls back to `<dataRoot>/databases` and copies `plugins_host.db` there. This is sticky, because from then on rule 1b picks it.

How the store maps each case:

| Otzaria state | Otzaria reads | Store reads | Outcome |
| --- | --- | --- | --- |
| key absent, `<dataRoot>\databases` exists | `<dataRoot>\databases` | same | ✓ registry |
| key absent, folder absent → next to library | `dirname(lib)\databases` | `<dataRoot>\databases\plugins_host.db` missing → `null` | folder scan (safe; #303 not fixed for this layout) |
| key set (non-empty) | custom folder, or `<dataRoot>\databases` if unwritable | skips the registry | folder scan (safe) |
| key set to `''`, or deleted but not yet compacted out of the append-only Hive log | `<dataRoot>\databases` | sees the key bytes → skips | folder scan (safe, conservative) |
| Hive failed and Otzaria used `SharePreferenceCache` (`main.dart:702`) | per its settings | no hive key → reads default | could read a stale default only in this rare fallback |

No case reads a stale database except the last, rare one. The "next to the library"
layout silently keeps the old folder-scan behaviour. If that layout matters, a later
step could port rule 1c (the store would need Otzaria's library path).

C++ (`sysapi.cpp:443-557`): the `column_type` check is loaded and validated with the
other symbols. Both statements are finalized before `close`. A partial read
(`code != SQLITE_DONE`) returns `null`. No new issues.

2. **nit — `installed_scanner.js:177-180`:** the whole `app_preferences.hive` (up to 16 MB) is base64-encoded across the WebView bridge on every scan, just to find a 19-byte key. Reading it in chunks, or adding a native `fileContains`, would avoid it. This is not a correctness problem.
3. **nit:** the rows of the table above ("next to library", "key set") silently keep the old behaviour. A single `log` line when the registry is skipped would make support easier ("registry skipped: custom databases folder").

---

## What should block merge

- **store fix/303:** finding 1. The amended test file does not compile, so CI is red and none of the new tests run. This is a one-line-per-path fix.
- **feat/288:** finding 1 (stale `lastDownloadCancelled`) is small but user-visible. It is a one-line fix plus a test.
- Everything else is a nit, a test-gap, or the FAT32/DST risk in 289, which is worth a follow-up but does not block.
