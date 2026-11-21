# QA round 1 — 2026-11-21

Independent read-only review. Each branch is diffed as `upstream/main...origin/<branch>`
(each is one commit on top of `upstream/main`). Environment: Linux, Flutter 3.47.2 /
Dart 3.13.2, Node 22.23.5, running as **root**. Root ignores read-only file
permissions, and the launcher does not support Linux, so tests that rely on either
fail on `upstream/main` too. Those failures are marked **pre-existing** below.

Severity: **bug** = wrong behaviour now · **risk** = can go wrong under realistic
conditions · **test-gap** · **nit**.

---

## 1. fix/289-drive-preferences (e024438)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` | pass |
| launcher_app | `dart format --output=none --set-exit-if-changed .` | pass (306 files, 0 changed) |
| launcher_app | `flutter analyze --no-fatal-infos` | pass (No issues found) |
| launcher_app | `flutter test test/app_paths_test.dart` | 38 pass, 2 skipped (Windows-only), **1 fail, pre-existing** |

The failure is the same on `upstream/main`. The launcher does not support Linux:

```
תת-הנתיבים שמתחת לתיקיית הנתונים mirror/library, mirror/app ו-mirror/plugins יושבים תחת dataDir [E]
  Unsupported operation: הכלי תומך בהתקנת אוצריא ב-Windows וב-macOS בלבד (זוהה: linux).
  package:otzaria_manager/src/models/otzaria_release.dart 17:12  OtzariaTargetPlatform.detect
```

Checked by reverting each part of the fix:
- Revert `app_paths.dart` → the `#289` test fails (`Expected: 'new message' Actual: 'old message'`). The test proves the fix.
- Keep the fix but drop `setLastModified` → the `#289` test also fails, so the mtime stamping is covered too. The test's fixed dates are in the past, so this holds at any wall-clock time from now on.

### Findings

1. **risk — `launcher_app/lib/src/services/app_paths.dart:324-341`: the whole of `launcher_settings.json` overwrites the machine's copy whenever the drive copy is newer, not just the help text.**
   #289 is about the FAQ/help message. The same rule now also covers `launcher_settings.json`, which holds per-machine choices: `ui.language`, `ui.textScale`, `protection.enabled/password` (safer mode), `reports.senderEmails` and `sync.personal*`.
   *Scenario:* in read-only mode, the user of an offline machine switches to English and turns on safer mode with a password. Weeks later the owner unlocks the drive at home and changes any setting (each change rewrites the file via `SettingsController._save`), then locks it again. The next launch on the offline machine copies the drive file over the local one. The language reverts, the local safer-mode password is replaced or turned off, and the saved sender email is gone, with no prompt. Before this change a machine kept its own copy once it had one.
   *Fix:* limit "newer drive wins" to `faq_customization.json` (the content this issue is about) and keep `launcher_settings.json` seeded once. If settings must follow the drive too, merge key by key and never take `protection.*` or `reports.senderEmails` from the drive. Add a test where a local `launcher_settings.json` survives a newer drive copy.

2. **risk — same lines: whichever file has the newer timestamp wins, across two computers' clocks.**
   The drive file's mtime comes from the online machine's clock; the local edit's mtime comes from the offline machine's clock. Offline machines often have a wrong clock (no NTP).
   *Scenario:* the offline PC's clock runs a month behind. Any local edit gets an mtime older than the drive copy, so the drive copy overwrites it on every launch, and local edits never stick.
   *Fix:* compare against the drive mtime recorded at the last copy, not against wall-clock times. For example, store the last-seeded source mtime or hash in `stateFilesDir`, and copy only when the drive file differs from what was last seeded.

3. **risk (minor) — `app_paths.dart:337-338`: if `setLastModified` throws after `copy` succeeds, the copy keeps "now" as its mtime.** The `on FileSystemException { continue; }` swallows the error. Later drive updates older than that launch are then ignored: the original #289 symptom, on that machine only. *Fix:* on failure, delete the target (or write to a temp file, stamp it, then rename), so the next launch tries again.

4. **nit — `launcher_app/test/app_paths_test.dart:588` "העתקה אינה דורסת העדפות שכבר נשמרו במחשב"** now passes only because the machine file is written after the drive file. With the new rule its name says more than it checks. Rename it, or set explicit mtimes as the two new tests do.

Repo rules: comment ≤2 lines ✓, AGENTS.md entry updated in place ✓. No l10n changes.

---

## 2. feat/288-cancel-custom-app-download (c7d24e2)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` / format / `flutter analyze --no-fatal-infos` | pass / pass (307, 0 changed) / pass |
| launcher_app | `flutter test test/custom_apps_test.dart` | **pass** (+124, 4 skipped Windows-only) |
| custom_apps_manager | `dart pub get` / format / `dart analyze` | pass / pass (49, 0 changed) / pass |
| custom_apps_manager | `dart test test/custom_apps_manager_test.dart` | 93 pass, **1 fail, pre-existing** |
| otzaria_l10n | `dart pub get` / format / `dart analyze` / `dart test` | pass / pass / pass / **pass** (+55) |

The failure is identical on `upstream/main`. Running as root bypasses the read-only mirror the test depends on:

```
למידה אחרי התקנה כונן נעול: ההתקנה מצליחה גם כשאי אפשר לכתוב למראה [E]
  Expected: false
    Actual: <true>
```

Cancellation path checked: `GithubAppClient.download` turns `isCancelled` into `checkCancelled`, which throws `CustomAppDownloadCancelled`. `otzaria_downloads.downloadFile` polls it every 100 ms through `_DownloadCancellation`, so a stalled connection is also aborted. `.part` and `.resume` are removed (`keepPartialOnCancel: false` plus `_deleteQuietly(temp)` in the manager). `_guard` never sees the exception, so `errorMessage` stays null. Label "ביטול ההורדה" is an action noun ✓, and the strings exist in both he and en ✓.

### Findings

1. **risk — `launcher_app/lib/src/screens/custom_apps/custom_apps_screen.dart:418-421`: after a cancelled "download all", the summary is dropped and only "ההורדה בוטלה" is shown.**
   *Scenario:* "download all" with 3 programs. A downloads, B fails (404 or rate limit), and the user cancels C. The snack says only "the download was cancelled". The user never learns that B failed, and `result.downloaded`/`failed` are computed and then ignored. The same happens when cancel lands after the last item has already been committed: the snack says "cancelled" although everything downloaded.
   *Fix:* on cancel, still report `downloaded`/`failed` (for example "בוטל — X הורדו, Y נכשלו"), or at least show the failure snack when `failed > 0`.

2. **nit — `custom_apps_screen.dart:257` and `custom_apps_controller.dart:697-735`: there is no cancel button for part of "download all".** `downloadingId` is null during the initial `_checkEach` peek phase and during `await load()` between items, so the button disappears there. A slow USB `load()` makes it flicker away right when users reach for it. Consider showing it while `isDownloadingAll`, with `cancelDownload` accepting `isDownloadingAll || downloadingId != null`.

3. **test-gap — `custom_apps_manager/test/custom_apps_manager_test.dart:589`** cancels with `isCancelled: () => true`, so it aborts before the first byte. No test cancels mid-stream (after some `onProgress`) to prove the partial `.part.part` and `.resume` files are removed. The controller tests use `_FakeManager`, which throws by itself, so the real `GithubAppClient` → `downloadFile` wiring is covered only by the first-byte case. There is also no widget test that the button appears, is disabled after one press (`cancelRequested`), or shows `downloadCancelledSnack`.

4. **nit — merge order:** 288 and 290 both insert line 1 of `launcher_app/assets/יומן שינויים.md` and touch `otzaria_l10n` files. The conflict is trivial, but whoever merges second must keep both bullets above `* **0.30**`.

Repo rules: comments ≤2 lines ✓, l10n he+en ✓, changelog bullet unheaded at top ✓.

---

## 3. feat/290-report-drafts (b3e5c4c)

### Commands

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` / format / `flutter analyze --no-fatal-infos` | pass / pass (307, 0 changed) / pass |
| launcher_app | `flutter test test/app_reports_test.dart` | **pass** (+56) |
| otzaria_l10n | `dart pub get` / format / `dart analyze` / `dart test` | pass / pass / pass / **pass** (+55) |

"Restore vs typing" race: no problem found. `AppReportForm.collecting` starts `true` and the fields are hidden until `loadAttachments()` finishes, which `_load()` runs only after `restoreDraft()`. The user cannot type before the draft lands. The crash dialog (`trigger != manual`) gets `supportsDraft == false`, so sending a crash report does not delete the manual draft ✓. The draft file sits at `reports/launcher-draft.json`, outside both `reports/outbox` and `reports/launcher`, so neither queue scanner picks it up ✓.

### Findings

1. **risk (privacy) — `launcher_app/lib/src/app_report/app_report_draft_store.dart:72-78` and `lib/main.dart:195-196`: the unredacted draft, screenshots included, is written to the USB drive in normal (writable) mode.**
   `AppReportsController.forState(stateDir: paths.stateDir)`, and in writable mode `stateDir == dataDir`, which is the drive. The class doc ("במחשב, לא בכונן נעול") holds only in read-only mode. `AppReportDraft` deliberately stores the text before redaction ("ההסתרה נעשית רק בשליחה"), plus `images` as base64.
   *Scenario:* user A on machine 1 pastes a screenshot of their desktop with personal data, then clicks "שמירת טיוטה". The drive goes to machine 2, where user B opens "report a problem" and the dialog opens pre-filled with A's text and screenshot. The data also stays on a removable drive that can be lost.
   *Fix:* store the draft on the machine (for example under `%LOCALAPPDATA%\OtzariaOfflineUpdate`, as read-only mode already does), or tie it to the machine and user (store the host name and user, and ignore a draft from elsewhere). At minimum, correct the class doc.

2. **risk — `app_report_draft_store.dart:95-102`: hand-rolled atomic write instead of the repo's `writeStringAtomically` (`otzaria_downloads/lib/src/atomic_file.dart`).**
   It always uses the same `launcher-draft.json.tmp` name and does not retry. On Windows, `rename` over a file that Defender or the indexer briefly holds fails with error 5, 32 or 33. The shared helper retries exactly those codes (`renameRetryingTransient`), and its write queue prevents two saves from interleaving on the same `.tmp`. A failed save also leaves the `.tmp` behind.
   *Scenario:* the user clicks "שמירת טיוטה" while AV is scanning the previous draft. The result is "שמירת הטיוטה נכשלה" plus an orphan `.tmp` on the drive.
   *Fix:* `await writeStringAtomically(path, jsonEncode(draft.toJson()));` (`launcher_app` already depends on `otzaria_downloads`). Every store in `custom_apps_manager` and `otzaria_manager` uses it.

3. **nit — `launcher_app/lib/src/screens/app_report/app_report_dialog.dart:358-374`: when a draft was restored, "ביטול" is replaced by "מחיקת הטיוטה".** The only way to leave without deleting is "שמירת טיוטה" or Esc / the barrier, and the latter silently drops edits made since the restore. Consider keeping "ביטול" (leave the draft as is) next to "מחיקת הטיוטה", as Otzaria's dialog does.

4. **test-gap — `launcher_app/test/app_reports_test.dart:910-990`** covers only `AppReportForm`. Nothing tests the dialog: that restored values reach the `TextEditingController`s (`_title.text = …`), that "שמירת טיוטה" pops the dialog, that "מחיקת הטיוטה" removes the file, or that `draftRestoredNote` appears. A regression in `_load()` (for example, setting the controllers before `restoreDraft` finishes) would pass every current test.

Repo rules: comment ≤2 lines ✓, l10n he+en ✓, labels are action nouns ("שמירת טיוטה", "מחיקת הטיוטה") ✓, Hebrew uses masculine singular ("שתפתח") ✓, changelog bullet unheaded at top ✓.

---

## 4. otzaria-plugin-store fix/302-hotfix-version (04da220)

### Commands

| Command | Result |
| --- | --- |
| `cd native && node --test test/` | **fails on Node 22 for the command itself**: `Error: Cannot find module '.../native/test'`. Node 22 treats a directory argument as a module. Same on `upstream/main`, so it is not caused by the branch. |
| `cd native && node --test 'test/**/*.test.js'` | **pass**: 214 tests, 0 fail (upstream/main: 209) |

`releaseVersionFromExe` was compared with Otzaria's `appReleaseVersion` (`Otzaria/otzaria` `dev:lib/update/app_release_version.dart`) and with `OtzariaUpdateCheckResult.versionFromDisk` here. The results match for real version strings. The extra guards (`build >= 10000`, components ≤ 99) match `versionFromDisk`. `-beta+…` keeps only the core, like Dart's `int.tryParse('98-beta') == null`. The state file still stores the raw exe version (`#save` → `installedTagName`), and the conversion happens on read, so old state files are also fixed (covered by the second probe test).

### Findings

clean. One **nit**: `native/package.json` → `"test": "node --test test/"` has the same Node-22 problem. If CI uses Node ≥ 22, change it to `node --test` (default discovery) or `node --test 'test/**/*.test.js'`. This is pre-existing and outside this branch.

---

## 5. otzaria-plugin-store fix/303-plugin-registry (a376d65)

### Commands

| Command | Result |
| --- | --- |
| `cd native && node --test 'test/**/*.test.js'` | **pass**: 212 tests, 0 fail (see 302 for why not `test/`) |
| C++ build | not possible on Linux; reviewed by reading |

C++ review of `native/src/sysapi.cpp:443-563`:
- **Calling convention:** `WINAPI` on every pointer type matches winsqlite3's `__stdcall` exports on x86, and is ignored on x64/ARM64 ✓.
- **Loading:** `LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_SYSTEM32)` closes the DLL-planting hole ✓. All eight symbols are checked ✓. Function-local statics give thread-safe one-time init under concurrent `RunAsync` ✓.
- **Cleanup:** a failed `open` still closes the returned handle ✓. `finalize(nullptr)` after a failed `prepare` is a documented no-op ✓. Both statements are finalized before `sqlite3_close` (not `_v2`), so close cannot return BUSY ✓. No early return between `open` and `close` ✓.
- **Encoding and JSON:** `Utf8(db_path)` goes to `sqlite3_open_v2` (UTF-8 API) ✓. `JsonString(std::string_view)` escapes bytes, and `JsonObject` / `JsonArray` take pre-encoded values, so there is no double escaping ✓.
- **Read-only + WAL:** `SQLITE_OPEN_READONLY` still maps `-shm` read/write when the directory allows it. This matches the launcher's `sqlite3.open(mode: OpenMode.readOnly)`. `busy_timeout(2000)` matches `PRAGMA busy_timeout=2000` ✓.
- **Partial reads:** a missing table (no `table_info` rows) or a step error (`complete == false`) returns `null`, which falls back to the folder scan, like the Dart `catch → null` ✓.

### Findings

1. **risk — `native/web/js/store/installed_scanner.js:142-160`: a stale `<dataRoot>\databases\plugins_host.db` wins over the real registry when Otzaria uses a custom databases folder.**
   The launcher resolves the file through `locateUserStateDb` (`databasesPath` setting, then `<dataRoot>\databases` if present, then next to `libraryPath`; see `PluginsModuleController.locateOtzariaPluginsDb`). The store always reads `<dataRoot>\databases\plugins_host.db`. The comment says a custom folder "falls back to the folder scan", but that holds only when the default file is absent.
   *Scenario:* a user once ran Otzaria with the default folder, then pointed "databases folder" in Otzaria settings to `D:\OtzariaDB`. The old `%APPDATA%\otzaria\databases\plugins_host.db` stays behind. The store reads it and shows plugins installed or uninstalled since the move with their old state: the #303 symptom again, now from a stale DB instead of a stale folder, and the launcher and store disagree.
   *Fix:* port the `databasesPath` lookup. The store already reads Otzaria's settings elsewhere; if it cannot, return `null` whenever a non-default `databasesPath` is set. Add a test with both files present.

2. **nit (parity) — `sysapi.cpp` / `installed_scanner.js`: `source_type` (development / localhost_dev) is not read, and `disabled` is returned but ignored by JS.** The launcher's `InstalledPluginsState` carries both. A development install will be offered an "update" from the store that replaces the developer's build. The folder scan had the same gap, so this is not a regression. Either drop `disabled` from the C++ payload or use it.

3. **nit — `sysapi.cpp` row loop: a `version` stored with a non-TEXT type** is converted to text by `sqlite3_column_text` and accepted, while the Dart reader skips rows where `version is! String`. This is harmless, but it is a parity difference.

4. **test-gap — `native/test/installed_scanner.test.js`** tests the scanner with an injected `readRegistry`. Nothing covers the `plugins_manager.js:64` wiring (`readRegistry: this.sys?.pluginRegistry`), so a typo there would silently fall back to the folder scan with every test still green. Add a `PluginsManager.scanInstalled()` test with a fake `sys.pluginRegistry`.

---

## Summary

| Branch | Checks | Findings |
| --- | --- | --- |
| fix/289-drive-preferences | green (1 pre-existing Linux-only fail) | 3 risk, 1 nit — **#1 (settings and safer-mode password overwritten) should be fixed before merge** |
| feat/288-cancel-custom-app-download | green (1 pre-existing root-only fail) | 1 risk, 2 nit, 1 test-gap |
| feat/290-report-drafts | green | 2 risk (**privacy: unredacted draft on the drive**), 1 nit, 1 test-gap |
| store fix/302-hotfix-version | green | clean |
| store fix/303-plugin-registry | green (C++ read only) | 1 risk (stale default DB vs custom databases folder), 2 nit, 1 test-gap |
