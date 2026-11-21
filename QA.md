# QA round 4: 2026-11-21

This is an independent, read-only review of the two branches amended after round 3
(`origin/qa/issues-round3:QA.md`). Each branch is still one commit on top of
`upstream/main`, diffed as `upstream/main...origin/<branch>`. The round-3 commits
(f8409da, 25ae3a1) cannot be fetched any more, because the amend made them
unreachable. So the stated changes were reviewed directly in the current diff.

Environment: Linux, Flutter 3.47.2 / Dart 3.13.2, running as **root**. There are two
known environment failures, and both also happen on `upstream/main`:
`OtzariaTargetPlatform.detect` on Linux, and root bypassing the read-only mirror.

| Branch | Commit | Checks | Blocking |
| --- | --- | --- | --- |
| feat/288-cancel-custom-app-download | 904f5e5 | green: launcher_app +126 ~4; custom_apps_manager 94/95 (1 pre-existing) | **no** |
| fix/289-drive-preferences | 1e480a9 | green: +42 ~2, 1 pre-existing | **no** |

---

## 1. feat/288-cancel-custom-app-download (904f5e5): clean

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` | pass |
| launcher_app | `dart format --output=none --set-exit-if-changed .` | pass (307 files, 0 changed) |
| launcher_app | `flutter analyze --no-fatal-infos` | pass (No issues found) |
| launcher_app | `flutter test test/custom_apps_test.dart` | **pass: `+126 ~4: All tests passed!`** |
| launcher_app | same, `--test-randomize-ordering-seed 1` and `42` | pass / pass (+126 ~4) |
| custom_apps_manager | `dart pub get` / format / `dart analyze` | pass / pass (49, 0 changed) / No issues found |
| custom_apps_manager | `dart test test/custom_apps_manager_test.dart` | +94 -1 (**pre-existing**, root) |

```
00:01 +43 -1: למידה אחרי התקנה כונן נעול: ההתקנה מצליחה גם כשאי אפשר לכתוב למראה [E]
  Expected: false
    Actual: <true>
  test/custom_apps_manager_test.dart 1068:7  main.<fn>.<fn>
```

**Round-3 blocking finding 1 is fixed.** The test "ביטול אחרי תוכנה שנכשלה: הכשל נספר"
now calls `AppLogger.resetForTest()` and `await AppLogger.init(tempDir.path)` inside
`runAsync`, and registers `addTearDown(AppLogger.resetForTest)` before that. This is
the same pattern as the existing test "כללים שנלמדו…" (line ~538). The test passes,
so `failed == 1` is now really checked.

**No logger leak.** The tear-down resets the singleton, and the whole file passes in
declared order and under two random orderings. The log file sits in the
per-test `tempDir`, which the group `tearDown` deletes.

New findings: **clean.** The round-3 non-blocking items still apply as before. There is
no widget test for the cancel button or the cancelled snack, and there is the
changelog/l10n merge-order nit with 290.

---

## 2. fix/289-drive-preferences (1e480a9): clean

| Package | Command | Result |
| --- | --- | --- |
| launcher_app | `flutter pub get` | pass |
| launcher_app | `dart format --output=none --set-exit-if-changed .` | pass (306 files, 0 changed) |
| launcher_app | `flutter analyze --no-fatal-infos` | pass (No issues found) |
| launcher_app | `flutter test test/app_paths_test.dart` | +42 ~2 -1 (**pre-existing**) |

```
00:00 +42 ~2 -1: תת-הנתיבים שמתחת לתיקיית הנתונים mirror/library, mirror/app ו-mirror/plugins יושבים תחת dataDir [E]
  Unsupported operation: הכלי תומך בהתקנת אוצריא ב-Windows וב-macOS בלבד (זוהה: linux).
  package:otzaria_manager/src/models/otzaria_release.dart 17:12  OtzariaTargetPlatform.detect
```

All eight seeding tests pass, including the new one.

### Round-3 findings

| # | Status |
| --- | --- |
| 1 nit: legacy copy is overwritten once | **addressed.** The commit message now explains it. |
| 2 test-gap: no record, local copy identical to drive | **fixed.** The new test "עותק ישן בלי רישום וזהה לכונן — רק נרשם, ועריכה אחריו נשמרת" covers it. |
| 3 nit: AGENTS.md line length | **fixed.** It is rewrapped to about 80 columns. The text is accurate: the hash is in `seeded_preferences.json` and mtime is not used. |
| 4 nit: changelog entry | still open and not blocking. It is needed only if the fix should be announced in the release. |

### New findings (none blocking)

1. **nit (test strength).** Mutation check: with the branch `last == null && local == drive`
   disabled (`if (false && …)`), the new test **still passes**. Without the branch the code
   rewrites identical bytes and records the same digest, so the visible behaviour is the
   same. The branch only avoids a redundant write. The test does pin the behaviour that
   matters (a later local edit is kept), so this is fine. Just know that it does not prove
   the branch itself runs.
2. **nit (commit message).** Two body lines were not rewrapped after editing. One is
   about 95 characters ("עריכה מקומית ("במחשב הזה") נשמרת… מתעדכן פעם") and one is about
   120 ("שלא השתנה, גם כששעון… הגדרות המחשב"). The rest wraps at about 72.
   This is cosmetic, and could be fixed at the next amend.

---

**Verdict:** both branches are unblocked. Nothing failed except the two known
environment failures.
