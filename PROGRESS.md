# Parity — Build Progress Log

Laptop 1 (foundation machine). Session 1 started 2026-08-29.

Environment at session start:
- Flutter 3.41.7 stable, Dart 3.11.5, Windows x64
- Connected devices: Windows desktop, Chrome, Edge. NO Android device or emulator.
- Remote: https://github.com/RizzuSkh/IQOO.git (branch main)

## For Laptop 2 and Laptop 3 — how to pick this up safely

`main` currently has everything through Stage 7 (see the stage log below), fully
committed and pushed. Read this before you touch anything.

**Pull first, every time, before starting new work:**
```
git checkout main
git pull origin main
```

**Ownership boundaries (CLAUDE.md section 17) — do not cross these:**
- Laptop 1 owns `lib/models/`, `lib/logic/`, `test/`, and `lib/main.dart`. Those
  files are done for P0 and are load-bearing for both of you — `compare()` and
  `phraseWithRules()` are the contract everything else calls into. If one of
  them looks wrong for what you need, ask, don't edit it.
- Laptop 2 owns `lib/screens/capture_spec.dart`, `capture_assembly.dart`,
  `review_extraction.dart`.
- Laptop 3 owns `lib/screens/results.dart`, `lib/io/report.dart`.
- `lib/screens/` currently has nothing in it but a `.gitkeep` — Laptop 1's
  `lib/main.dart` is a throwaway debug harness, not the real UI, and does not
  touch `lib/screens/` at all. You are not merging against anyone else's screen
  code because none exists yet.

**Work on your own branch, not directly on `main`:**
```
git checkout -b feat/capture   # or feat/results
```
Commit small, working states as you go. Open a PR back to `main` when a feature
is usable — don't sit on one giant uncommitted branch.

**What you can build against right now, already tested:**
- `SpecItem` (`lib/models/spec_item.dart`) — has `copyWith()` ready for F9
  manual correction.
- `DiffResult` / `Discrepancy` (`lib/models/diff_result.dart`) — four lists:
  `missing`, `unexpected`, `mismatched`, `unread`. Use `result.isMatch` for the
  zero-discrepancy success state (PRD section 23).
- `compare(spec, assembly)` (`lib/logic/compare.dart`) — pure, deterministic,
  13 passing tests. Feed it `List<SpecItem>`, get a `DiffResult` back.
- `phraseWithRules(diffResult)` (`lib/logic/phrase.dart`) — one sentence, 26
  passing tests, handles the empty case explicitly.
- `parseBlocks(blocks)` (`lib/logic/parser.dart`) — returns
  `ParseResult { items, unparsedRows }`. `unparsedRows` is exactly what
  `review_extraction.dart` (Laptop 2) needs to show the user rows OCR couldn't
  read as a position.
- `OcrReader` (`lib/logic/ocr.dart`) — wraps ML Kit, returns `List<OcrBlock>`.
  **Compiles but has never read a real photograph.** Treat it as unverified
  until someone runs it against a printed label on a device.

**Before you push:**
- `flutter analyze` clean, `flutter test` all passing — non-negotiable per
  CLAUDE.md section 18.
- Run `flutter format` on anything you touched.
- Do not `git push --force` to `main`. Do not run `git reset --hard` on a branch
  someone else may have pulled. If you hit a merge conflict, resolve it — don't
  discard either side's changes without checking what's in them first.
- Pull `main` again right before you open your PR in case Laptop 1 or the other
  laptop landed something while you were working.

## Stage 0 — Scaffold
Status: DONE
Files touched: pubspec.yaml, android/app/build.gradle.kts,
android/app/src/main/AndroidManifest.xml, lib/{screens,logic,io,models}/,
test/fixtures/, .gitignore, analysis_options.yaml
Check run: `flutter analyze` and `flutter build apk --debug`
Check result: analyze — "No issues found! (ran in 22.4s)".
Build — "√ Built build\app\outputs\flutter-apk\app-debug.apk" (exit 0, 1266.7s,
180 MB debug APK). This is stronger than "boots to default screen": it proves the
whole Android toolchain links, including the ML Kit native dependency.
Commit: de2554f
Notes:
- Created with `--platforms=android` only. iOS/web/desktop folders would be dead
  weight and more to keep building. Add a platform later if anyone needs one.
- `--org com.rtiparadox.parity` + project name `parity` yields applicationId
  `com.rtiparadox.parity.parity`. That is what the flag does; flagged, not changed.
- minSdk 26, targetSdk 36, compileSdk 36.
- Main manifest declares CAMERA only, no INTERNET. Flutter's stock debug/ and
  profile/ manifests still declare INTERNET — that is how hot reload talks to the
  app and it is NOT merged into a release build. Release satisfies NFR5.
- Secret scan over dart/yaml/gradle/xml/properties: no matches for OpenRouter or
  api key patterns.

## Stage 1 — Data contracts
Status: DONE
Files touched: lib/models/spec_item.dart, lib/models/diff_result.dart
Check run: `flutter analyze`
Check result: "No issues found! (ran in 4.9s)"
Commit: 43b2a5c — PUSHED TO ORIGIN/MAIN (68ecfd6..43b2a5c)
Notes:
- DiffResult uses the corrected FOUR-state shape: missing, unexpected,
  mismatched, unread. PRD section 17 lists only three DiffType values and
  contradicts its own section 18 table. Four is correct. PRD.md itself has NOT
  been edited — someone should fix section 17 so it stops misleading people.
- SpecItem gained `isUnread` and `copyWith`. copyWith is there for F9 manual
  correction (Laptop 2). Neither changes the field contract.
- Pushed immediately so Laptop 2 and Laptop 3 are unblocked.

## Stage 2 — Test fixtures
Status: DONE
Files touched: test/fixtures/case_01_missing.json, case_02_mismatched.json,
case_03_unexpected.json, case_04_unread.json
Check run: JSON parse of all four files
Check result: all four report "valid"
Commit: d7b80bc
Notes:
- Written exactly as specified, not invented.
- case_03 pins down a rule worth knowing: its spec has P4 with component "" and
  expects `unexpected`, so an EMPTY COMPONENT ON THE SPEC SIDE means "the
  specification calls for nothing here". An empty component on the ASSEMBLY side
  means unread. The same empty string means different things on each side.
  compare() implements exactly that.

## Stage 3 — compare.dart
Status: DONE
Files touched: lib/logic/compare.dart, test/compare_test.dart
Check run: `flutter test test/compare_test.dart`
Check result: "00:01 +13: All tests passed!" — 4 fixtures + 9 invariants
Commit: d5ee071
Notes:
- Pure Dart. No imports beyond the two model files: no model, no network, no I/O.
- Output order is deterministic: specification order first, then assembly-only
  positions in observed order. Locked by a repeat-run test.
- One case no fixture covers: both sides unread at the same position. Decided it
  reports `unread` with expected == null, rather than nothing. Nothing is known
  there, and silence would read as a match. If the team disagrees, this is the
  line to revisit — it is the only judgement call in the file.
- Duplicate positions in one list: first occurrence wins, documented.

## Stage 4 — phrase.dart
Status: DONE
Files touched: lib/logic/phrase.dart, test/phrase_test.dart
Check run: `flutter test`
Check result: "00:00 +26: All tests passed!"
Commit: 1b8dbda
Notes:
- Rules only. No model, per the standing rules for this session.
- Actual output, captured by running it:
  case_01 -> "1 discrepancy: P2 should hold 7805 but nothing was found there."
  case_02 -> "1 discrepancy: P2 holds LM358 where the specification calls for 7805."
  case_03 -> "1 discrepancy: P4 holds NE555, which the specification does not call for."
  case_04 -> "1 discrepancy: P3 could not be read — the specification calls for
              LM358, so it needs a retake or manual entry."
  empty   -> "No discrepancies found — the assembly matches the specification."
- Singular/plural handled. A test asserts the string "null" never reaches the user.

## Stage 5 — OCR wrapper
Status: DONE (code) — **COMPILES — NOT YET VERIFIED ON DEVICE**
Files touched: lib/logic/ocr.dart
Check run: `flutter analyze`
Check result: "No issues found! (ran in 13.5s)"
Commit: 8f409d7
Notes:
- THIS HAS NEVER BEEN RUN AGAINST A REAL PHOTOGRAPH. It compiles and links. That
  is all that is known. Do not treat OCR as working until someone photographs a
  real label with it.
- Returns a plain `OcrBlock` (text, boundingBox, confidence) instead of ML Kit's
  `TextBlock`, so parser.dart and its tests need neither the plugin nor a device.
- ML Kit's TextBlock carries NO confidence field; only TextLine and TextElement
  do, and those are nullable. OcrBlock.confidence is the mean of whatever the
  lines reported and defaults to 1.0 when nothing is reported. It means
  "unknown", not "certain" — do not build a confidence indicator on it without
  checking what the device actually returns.
- No acceleration claim is made anywhere in the file.

## Stage 6 — parser.dart
Status: DONE
Files touched: lib/logic/parser.dart, test/parser_test.dart
Check run: `flutter test`
Check result: "00:04 +43: All tests passed!"
Commit: 6248c2f
Notes:
- PRD section 19 as written: rows by Y-centre, tolerance = half the median block
  height, sort by X within a row, leftmost is position.
- Returns `ParseResult { items, unparsedRows }`. Rows whose leftmost block is not
  a position label go to unparsedRows instead of being dropped, which is what
  section 19 asks for and what Laptop 2's correction UI needs to display.
- Position pattern is `^P\d+$` after uppercasing and stripping trailing
  punctuation. Deliberately no OCR-confusion repair: "Pl" for "P1" is NOT
  auto-corrected, it goes to unparsedRows. Guessing is the thing we do not do.
- Extra blocks beyond the second are appended to the component rather than
  discarded, so stray text shows up as a visible mismatch, not a silent loss.
- One test failed first time. The failure was my test's expectation, not the
  parser: for two blocks separated by more than the tolerance, the second row has
  no position label of its own, so it belongs in unparsedRows. Corrected the test
  to assert that. Fixture data was not touched.

## Stage 7 — Debug harness in main.dart
Status: DONE
Files touched: lib/main.dart
Check run: `flutter analyze`, then built, installed and launched on the device:
`flutter build apk --debug`, `adb install -r`, `adb shell am start`
Check result:
- analyze — "No issues found! (ran in 6.9s)"
- build — "√ Built build\app\outputs\flutter-apk\app-debug.apk" (exit 0, 25.5s)
- install — "Success"
- launch — process alive (pid 16256), Impeller/Vulkan backend up, Dart VM service
  listening. `grep -c "FATAL EXCEPTION"` over logcat returned 0.
- screenshot pulled from the device confirms the UI actually rendered: title,
  Capture Spec / Capture Assembly / Reset, "Capture the specification, then the
  assembly.", both sections showing "not captured", "Waiting for both captures."
- tapped Capture Spec: topResumedActivity became
  `com.android.camera/.CameraActivity`, so image_picker and the CAMERA
  permission are wired correctly. Backed out; app resumed without crashing.
Commit: 9ee0dfa
Notes:
- Device is I2501 / Android 16 (API 36) — the iQOO. It was not connected earlier
  in the session and appeared partway through; Stages 0-6 were verified without it.
- lib/screens/ untouched. This harness is meant to be deleted when Laptop 2 and 3
  land the real screens.
- **I did NOT photograph anything.** Backing out of the camera rather than firing
  the shutter means the OCR -> parser path has still never seen a real image.
  Someone must point this at a printed label and confirm blocks come back.
  That is the single most important unverified thing in the project.

## Stage 7b — Release permission audit (unplanned, found during Stage 7)
Status: see result below
Files touched: android/app/src/release/AndroidManifest.xml (new)
Why this exists:
Stage 0 asked for a manifest requesting CAMERA only. After installing on the
device, `dumpsys package` showed the app requesting INTERNET,
ACCESS_NETWORK_STATE and CAMERA. Tracing it through the manifest-merger blame
file: `com.google.android.datatransport:transport-backend-cct:2.3.3` — a
telemetry backend pulled in transitively by ML Kit — declares BOTH INTERNET and
ACCESS_NETWORK_STATE in its own manifest. So Stage 0's trim was incomplete:
editing our manifest does not stop a library from adding permissions during the
merge, and the release build would have shipped requesting network access.

This matters beyond box-ticking. NFR5 is tested by "manifest review", and the
whole pitch is that the app cannot phone home. A judge running `aapt dump
permissions` on the release APK would have seen INTERNET.

Fix: a release-only source set that strips both with `tools:node="remove"`.
Release-only on purpose — the debug and profile manifests need INTERNET for
`flutter run` hot reload, and stripping it in the main manifest would break
everyone's development loop.

Check run: `flutter build apk --release`
Check result: **NOT VERIFIED.** The release build was started but stalled with
no output for several minutes on this machine (it had already hit one native
`malloc` OOM earlier in the session while running a plain manifest-generation
task, likely from running heavy Gradle work back-to-back without enough free
RAM). The fix below is applied to source and reasoned through the manifest
merger blame file, but nobody has actually run `aapt dump permissions` on a
built release APK to confirm INTERNET is gone. Treat this the same as OCR:
compiles/reasoned-through, not proven.
Commit: (pending, this session)
Notes:
- **NEXT ACTION FOR ANY LAPTOP:** run `flutter build apk --release` (ideally on
  a machine with more free memory, or after closing other heavy apps), then
  `aapt dump permissions build/app/outputs/flutter-apk/app-release.apk` and
  confirm only CAMERA is listed. This is a two-minute check that just could not
  be completed here — do not skip it before the demo.

## Session 1 end-of-session summary
Ended: 2026-08-29, Laptop 1.

**DONE and verified (tests or device):**
- Stage 0 Scaffold — analyze clean, debug APK builds and links (incl. ML Kit native code)
- Stage 1 Data contracts — pushed to origin/main early to unblock Laptop 2 & 3
- Stage 2 Test fixtures — 4 JSON files, shared ground truth
- Stage 3 compare.dart — pure, deterministic, 13 tests pass (4 fixtures + 9 invariants)
- Stage 4 phrase.dart — rules-based, 26 tests pass, no model
- Stage 6 parser.dart — 16 tests pass against hand-built block fixtures
- Stage 7 debug harness — installed and run on the actual iQOO 15 (I2501,
  Android 16/API 36): renders, Capture Spec opens the real camera, no crash

**COMPILED BUT NOT DEVICE-VERIFIED — do not claim these work:**
- Stage 5 OCR wrapper (lib/logic/ocr.dart) — has NEVER read a real photograph.
  This is the single biggest open risk in the project (PRD section 20's own
  "Known risks" table flags it HIGH). Someone must point the harness at a
  printed label before claiming F2/F4 work.
- Release-build permission strip (android/app/src/release/AndroidManifest.xml)
  — reasoned correct via the manifest-merger blame file, but the actual release
  APK has not been built and inspected on this machine due to a resource
  constraint (Gradle stalled after an earlier native OOM). Run
  `flutter build apk --release` + `aapt dump permissions` before the demo.

**NOT STARTED (Stage 8+, P1/P2 stretch, and everything owned by screens/):**
- F9 Manual correction UI — Laptop 2, lib/screens/review_extraction.dart
- F8 Report export (file + clipboard) — Laptop 3, lib/io/report.dart
- F7 Colour-coded results screen — Laptop 3, lib/screens/results.dart
- F1/F3 Capture screens (the real UI, not the debug harness) — Laptop 2,
  lib/screens/capture_spec.dart, capture_assembly.dart
- F10 Reset — only proven in the debug harness in miniature; needs the real
  screens wired to it
- P2 stretch (on-device LLM phrasing, confidence indicators) — explicitly out
  of scope this session per standing rules; do not start until P0 is fully done
  and device-verified
- NFR1 timing measurement (<15s pipeline, 5 runs) — needs a real device run
  with real photographs, blocked on Stage 5 verification
- NFR3 negative-case testing (blurry photo, no text, zero discrepancies) —
  needs real device runs
- No unit tests exist yet for screens/ or io/ — expected, those aren't written

Current commit: 267c063 (this entry's own commit will be the true HEAD)

**What Laptop 1 should do next, in order:**
1. Photograph a real printed label with the debug harness and confirm OCR
   actually returns text (Stage 5 verification — the #1 blocker)
2. Get a release build through successfully and run the permission check above
3. Only after both of those: help Laptop 2/3 integrate logic/ into the real
   screens, since lib/screens/ is off-limits to edit directly this session

## Session 2 — Audit (no code changes)
Ran: 2026-08-29, Laptop 1. Read-only audit. Nothing committed by this entry.

**Repository state:** working tree clean, `main` level with `origin/main`
(0 ahead / 0 behind), HEAD 18d766a. Tracked source is exactly what Session 1
described: `lib/screens/` and `lib/io/` still contain only `.gitkeep`.

**Re-verified this session (actually run, not inherited from the log above):**
- `flutter analyze` — "No issues found! (ran in 16.3s)"
- `flutter test` — "00:00 +43: All tests passed!", exit 0
  (13 compare + 17 parser + 10 phrase `test()` blocks, 43 cases total)
- `dart format --output=none --set-exit-if-changed .` — 10 files, 0 changed
- Secret scan over dart/yaml/kts/xml/properties for api-key/OpenRouter/bearer
  patterns — no matches (NFR4 holds)
- `compare.dart` imports only the two model files; `phrase.dart` imports only
  `diff_result.dart`. Purity claim (FR7, CLAUDE.md 11) confirmed by inspection.
- minSdk 26 / targetSdk 36 / compileSdk 36 in `android/app/build.gradle.kts`
  (NFR7 as written; build not re-run, see blocker below)

**Correction to the Stage 7b entry above:** it records its commit as
"(pending, this session)". It was in fact committed as e0925e9
("fix: strip network permissions from release manifest"). The stage's
*verification* is still outstanding — only the commit line was stale.

### BLOCKER FOUND — C: drive is full
`C:` has **2 MB free of 291 GB (100% used)**. `D:` has 103 GB free.

This is not cosmetic. The first `flutter test` of this session hung for over
ten minutes and then died with:

```
FileSystemException: writeFrom failed,
path = 'C:\Users\...\Temp\flutter_tools.*\flutter_test_compiler.*\output.dill'
(OS Error: There is not enough space on the disk, errno = 112)
```

This almost certainly also explains Session 1's Stage 7b symptoms — the stalled
`flutter build apk --release` and the earlier native `malloc` OOM were blamed on
RAM, but a full disk produces exactly that behaviour under Gradle.

**Workaround proven to work:** with `TEMP`/`TMP`/`TMPDIR` pointed at
`D:\tmp_flutter`, `flutter test` completed normally (43 passed). That is how the
test result above was obtained. It is a workaround, not a fix — Gradle also
writes to `C:\Users\<user>\.gradle`, so an APK build needs either real free
space on C: or `GRADLE_USER_HOME` redirected to D: as well.

Largest reclaimable items on C: `AppData\Local\Android` 4.03 GB,
`AppData\Local\Pub\Cache` 0.73 GB, `AppData\Local\Temp` 0.28 GB,
`.gradle` 0.14 GB. Freeing those alone will not fix a 291 GB drive with 2 MB
free — something else on C: is consuming it and needs a human look.

**Until C: has headroom, this laptop cannot build an APK — debug or release.**
That blocks the Stage 7b permission check, the demo APK, and the backup APK
required by CLAUDE.md section 21.

### Second blocker — no device attached
`flutter devices` lists only Windows, Chrome and Edge. `adb devices` is empty.
The iQOO (I2501) that appeared during Session 1 is not connected now, so no
device verification could be attempted this session. Stage 5 (OCR against a
real photograph) remains the single most important unverified thing in the
project, exactly as Session 1 left it.

### Status against PRD section 27 acceptance criteria
| Criterion | Status |
|---|---|
| Two photographs produce two structured lists on-device | NOT PROVEN — camera opens, no photograph ever taken |
| All 3 unit tests pass | PASS — 43 tests, re-run this session |
| All three discrepancy types display correctly | NOT STARTED — no results screen exists |
| Summary sentence appears with no model present | PASS at logic level; no UI to show it |
| Full aeroplane-mode run succeeds | NOT TESTED |
| No crash on all 3 negative cases | NOT TESTED |
| Pipeline under 15 seconds, measured | NOT MEASURED |
| Reset gives a clean run | Harness only, never after a real capture |
| Report file written and clipboard populated | NOT STARTED — `lib/io/` is empty |
| Clean clone builds on another laptop | NOT TESTED |
| No secrets in repository | PASS — scanned again this session |

### Build-order position (CLAUDE.md section 22)
P0 chain F1 → F2 → F3 → F4 → F5 → F6 → F7 → F10.
F5 and F6 are done and tested. F2/F4 are half done: the parser half is tested,
the OCR half has never seen a real image. F1/F3 exist only inside the debug
harness. F7 does not exist. F10 exists only in the harness. **No P1 work has
been started, which is correct** — F8 and F9 must stay untouched until every P0
criterion passes.

### Documentation inconsistency still open
PRD section 17 still lists three `DiffType` values while section 18 and the
shipped code use four (`unread` is first-class). Session 1 flagged this and
deliberately did not edit the PRD. It should be fixed so it stops misleading
Laptop 2 and Laptop 3, by team agreement rather than unilaterally.

### Also noted, not acted on
- `android/app/build.gradle.kts` release build still signs with the debug
  keystore (stock Flutter TODO). Acceptable for a hackathon APK; worth knowing.
- `applicationId` remains `com.rtiparadox.parity.parity` — Session 1 decision,
  unchanged.

## Session 2 — Actions taken after the audit
Laptop 1, 2026-08-29. Everything below is code/tooling work that needed no free
space on `C:`; everything that did need a machine with disk or a human hand is
written up in `HANDOFF.md` instead.

**Toolchain moved onto D:** `GRADLE_USER_HOME=D:\gradle_home`,
`TEMP`/`TMP`/`TMPDIR`/`GRADLE_OPTS -Djava.io.tmpdir` all pointed at
`D:\tmp_flutter`. `D:\gradle_home` was seeded from `C:\Users\<user>\.gradle`
(145 MB — wrapper and native only; the dependency cache was already gone, so a
build re-downloads ~1.5 GB). Under this environment `flutter analyze` and
`flutter test` both run normally. Exact recipe is in HANDOFF.md.

**Device is reachable again.** `adb devices` was empty despite the cable being
plugged in — a stale daemon, not a cable or a permission. `adb kill-server &&
adb start-server` brought back `10BFCH1K9Y00237` = I2501, Android 16 / API 36,
with Session 1's debug APK still installed.

**Git Bash mangles Android paths.** `adb push x /data/local/tmp/` was silently
rewritten to `C:/Program Files/Git/data/local/tmp/` and failed with
`secure_mkdirs() failed`. Every adb command needs `MSYS_NO_PATHCONV=1`. This also
explains the bogus `adb shell df` output earlier in the session.

**Reference images added** — `test/fixtures/parity_spec.png` and
`parity_assembly.png`, plus `generate_reference_images.ps1` that regenerates
them. Rendered spec sheets, 1200x1600, black on white, position column at the
left margin and component column at 58% width so the two arrive as separate OCR
blocks. Their content is chosen so the correct answer is fixed:

    spec:     P1 NE555   P2 7805    P3 LM358
    assembly: P1 NE555   P2 LM358   P4 NE555

Expected DiffResult: P3 missing, P4 unexpected, P2 mismatched — 3 discrepancies.
This gives the project a deterministic on-device check with a known answer,
which the camera path can never provide.

**Harness gained a reference-image path** (`lib/main.dart`, Laptop 1's file):
a `Read Reference Images` button runs OCR -> parser -> compare -> phrase over the
two PNGs read from the app's **own documents directory**. Deliberately the
documents directory and not `/sdcard/Download`, because shared storage would
require READ_MEDIA_IMAGES and break NFR5 — this way CAMERA remains the only
permission. Files get there with `adb push` to `/data/local/tmp` followed by
`run-as ... cp ... app_flutter/`; confirmed both PNGs are sitting in
`app_flutter/` on the device now.

Check run: `flutter analyze` — "No issues found! (ran in 22.2s)".
`dart format` — 0 changed. `flutter test` — re-run at this tree, see commit.

**NOT YET VERIFIED at time of this commit:** the reference-image path has been
analyzed and formatted but **not yet run on the device** — the debug APK
containing it was still building when this was committed (cold Gradle cache,
~1.5 GB of downloads). Nobody has seen it produce the expected sentence yet.
Treat it exactly like Stage 5: written, not proven. The APK currently installed
on the phone is the older Session 1 build and does **not** have the button.

**Still handed off, not done** (full prompts in HANDOFF.md):
1. Photograph a real printed physical label — the one thing reference images
   cannot substitute for, and still the #1 risk (T+6h stop rule applies)
2. Release APK + `aapt dump permissions` — Stage 7b, needs a completed build
3. NFR1 timing over 5 runs; NFR3 negative cases; NFR2 aeroplane-mode run
4. NFR6 clean clone on Laptop 2 or 3
5. Backup APK on a second device (CLAUDE.md section 21)
6. The screens themselves — F7 (P0) before F8/F9 (P1)

**A parser risk worth knowing before anyone photographs anything:** the parser
expects position and component as two separate OCR blocks. ML Kit merges nearby
text, so a tight printed row may return one block reading `"P1 NE555"`, which
fails `^P\d+$` and lands in `unparsedRows` — nothing is lost, but nothing pairs
either. Widen the column gap first. If it still merges on real photographs, that
is a `lib/logic/parser.dart` change and therefore Laptop 1's to make; report it
rather than patching locally.

## Session 3 — Laptop 1, root-caused and fixed "OCR picks up unwanted things"

Audited GitHub first per user request (see chat log for full write-up); nothing
was lost — Laptop 2/3's teammate (`Talha-Khan-47`) had pushed a complete P0 UI
(`capture_screen.dart`, `review_extraction_screen.dart`, `results_screen.dart`,
`report.dart`, and a rewritten `main.dart`) in commits `6792bf5`/`f4929b1`.
Local `main` was 2 commits behind and fast-forwarded cleanly — no conflicts.

**Root cause found for "random values" / "picks up unwanted things":** not an
OCR model problem (ML Kit's on-device model is fixed and cannot be trained or
fine-tuned — there is no dataset or training step available). Two real code
bugs plus a controllable input problem:

1. `lib/logic/parser.dart` appended every block sharing a row's height onto
   the component string. A real breadboard has plenty of incidental text at
   label height — column numbers, resistor colour codes, date codes — and all
   of it was getting glued onto the real component name. **Fixed:** only the
   second block in a row becomes the component; anything past that goes into
   a new `ParseResult.ignoredNoise` list instead of corrupting the text.
2. `capture_screen.dart` ran OCR over the entire photo with no way to exclude
   anything outside the label region. **Fixed:** added a crop step between
   capture and OCR — symmetric horizontal/vertical trim sliders with a live
   masked preview, a "Scan Selected Area" button, and a "Use Full Photo"
   fallback so the old behaviour is still reachable if cropping misbehaves.
   Implemented in `lib/logic/image_crop.dart` using only `dart:ui` (image
   decode + `Canvas.drawImageRect` + PNG re-encode) — no new dependency.
3. `review_extraction_screen.dart` had no way to delete a bad row or add a
   missed one — F9 was edit-only. **Fixed:** added delete per row, an add-row
   dialog per section, and an expandable diagnostics panel showing
   `unparsedRows` and `ignoredNoise` (previously computed but discarded after
   capture, never shown to the operator) with a one-tap "Add" to promote a
   stray row into a real item.

Files touched: `lib/logic/parser.dart`, `lib/logic/image_crop.dart` (new),
`lib/screens/capture_screen.dart`, `lib/screens/review_extraction_screen.dart`,
`lib/screens/results_screen.dart` (deprecation fix only), `test/parser_test.dart`,
`test/image_crop_test.dart` (new).

**This crosses the file-ownership lines in CLAUDE.md/HANDOFF.md** — capture
and review screens are Laptop 2's files. Done at the repo owner's explicit
request this session ("do whatever changes are good"); flag it to Laptop 2 so
they know why their files changed under them and can review.

Check run: `flutter analyze` — "No issues found!" (0 issues, including the two
pre-existing `withOpacity` deprecation warnings, fixed in passing).
`flutter test` — **43/43 passed** (38 existing + 5 new in `image_crop_test.dart`
covering the actual pixel-crop math).
**NOT run on-device this session** — analyze/test only, no `flutter build` or
`flutter run`, per instruction to avoid long tasks. The crop UI's math
(fractional insets avoid needing screen-to-image pixel mapping) is sound but
**unverified on a real camera photo**. Next session must run it on the iQOO.

**Demo images added** — `demo_assets/`: three 1920×1080 landscape PNGs
(`demo_spec_A`, `demo_assembly_A_match`, `demo_assembly_B_tampered`) generated
locally with a known exact answer, meant to be displayed full-screen on the
laptop and photographed with the phone — not loaded into the app directly, and
explicitly recommended over any web-sourced image (arbitrary fonts, watermarks,
compression noise all hurt OCR consistency, and a strange image can't be
rehearsed against twice). `demo_assets/README.md` has the full run-through and
expected results for both scenarios. `demo_assets/generate_demo_screens.ps1`
regenerates them.

**C: drive is no longer full** — confirmed ~70GB free (was 2MB in Session 2).
The D:-redirect workaround in HANDOFF.md is no longer required, though still
harmless to use.

**Still true from HANDOFF.md, unchanged by this session:**
- Nobody has run OCR against a real camera photograph yet — still the #1 risk.
- Release APK permission strip still unverified (`aapt dump permissions`).
- NFR1/NFR2/NFR3/NFR6 all still outstanding, all need a device.

## Session 4 — fixed "no valid labels found" on the user's own demo image

User reported the crop fix from Session 3 didn't help — same error even
cropped tight. They'd generated a realistic AI breadboard photo
(`Downloads\based\ChatGPT Image Aug 29, 2026, 11_54_02 PM.png`, 1536x1024,
three chips: NE555P, LM358P, LM393N) and expected to use it directly.

**Root cause, confirmed not guessed:** the photo has ZERO text matching
`^P\d+$` anywhere in it — only each chip's own tiny etched part code, three
lines per chip (e.g. "NE555P" / "93M" / "DN1810"). No crop setting could ever
fix this; there was nothing for the parser to find. Verified by replaying the
photo's actual text through `parseBlocks()` in
`test/demo_realistic_scenario_test.dart` — it parses to zero items, every
line landing in `unparsedRows`, exactly reproducing the reported error.

**Fix:** `demo_assets/overlay_labels_on_breadboard.ps1` appends a clean white
label panel below the photo (not overlaid on top — a first attempt did that
and put labels in one touching horizontal strip, which risked ML Kit merging
all three into an unparseable block; caught before it shipped and fixed to
stack rows vertically like the already-working `demo_spec_A.png` layout).
Produces `demo_assembly_realistic_match.png` / `_tampered.png`, paired with
a new `demo_spec_realistic.png`.

**Verified two ways**, not just visually:
1. `test/demo_realistic_scenario_test.dart` (4 new tests, all passing) replays
   both the original unlabeled photo (confirms it parses to nothing — the bug)
   and the new labeled layout at its actual generated coordinates (confirms
   `parseBlocks()` + `compare()` produce exactly the documented match/tamper
   results).
2. Visual read-back of each generated PNG after every script run — caught the
   horizontal-strip merge risk and a `$photo.Height` accessed after
   `$photo.Dispose()` bug (silently returned a stale value, drawing the panel
   at y=0 on top of the photo instead of below it) before committing either.

Check run: `flutter analyze` — 0 issues. `flutter test` — **47/47 passing**
(43 previous + 4 new).

Files added: `demo_assets/overlay_labels_on_breadboard.ps1`,
`demo_assets/demo_spec_realistic.png`,
`demo_assets/demo_assembly_realistic_match.png`,
`demo_assets/demo_assembly_realistic_tampered.png`,
`test/demo_realistic_scenario_test.dart`. `demo_assets/README.md` updated
with the realistic-set instructions and expected results.

**Still not run on a real device** — this fix is verified against the actual
parser logic with the actual generated coordinates, which is strong evidence,
but nobody has photographed either the label-panel demo image or a real
object with the app on the iQOO yet. That remains the top open item.

## Session 5 — the real bug: position format mismatch with the actual BOM

User reported OCR still failing "even on the written text for the blueprint"
after Session 4's crop/label fixes. Found `Breadboard_Bill_of_Materials.pdf`
in the user's Downloads — the team's actual verified spec document (BB-01,
Assembly A). Its POSITION column reads bare digits: `1`, `2`, `3`, `4` — NOT
`P1` style. `lib/logic/parser.dart`'s `_positionPattern` was `^P\d+$`,
rejecting every single row of the real document regardless of photo quality,
lighting, or crop. This is the actual root cause "even written text fails."

**Fix:** `_positionPattern` changed to `^P?\d+$` — the `P` is now optional.
Purely additive: every existing "P1"-style test still passes. Verified with
new tests replaying the BOM's exact table structure (position, component,
description columns) through `parseBlocks()`, confirming the description
column is correctly treated as ignored noise (Session 3's fix) rather than
merged into the component.

**Also found and fixed:** the AI-generated "realistic" breadboard photo from
Session 4 shows chips etched NE555P/LM358P/LM393N, but the real BOM's
position 2 calls for a 7805 voltage regulator (a 3-pin TO-220 part, nothing
like these 8-pin DIP chips). Relabelling the photo "7805" would visually
contradict itself to anyone who looks closely. Fixed by keeping that demo set
honest (uses the chips' own real part numbers, documented as "illustrative,
not the official BOM") and regenerating the primary `demo_spec_A` /
`demo_assembly_A_match` / `demo_assembly_B_tampered` set to exactly match
`Breadboard_Bill_of_Materials.pdf`'s real positions (bare digits) and real
components (NE555, 7805, LM358), with the tamper scenario now putting an
unauthorised part in the BOM's actual spare slot (position 4) rather than an
invented position 5.

Also fixed the on-device hint text in `capture_screen.dart` that only showed
a "P1: NE555" example, which didn't reflect the team's real format.

Check run: `flutter analyze` — 0 issues. `flutter test` — **51/51 passing**
(47 previous + 4 new in the "bare-digit positions" group).

Files touched: `lib/logic/parser.dart`, `lib/screens/capture_screen.dart`,
`test/parser_test.dart`, `demo_assets/generate_demo_screens.ps1`,
`demo_assets/overlay_labels_on_breadboard.ps1`, all demo PNGs regenerated,
`demo_assets/README.md`.

**Verified on-device this session:** built fresh debug APK, installed on a
second phone (Realme RMX3031, Android 13/API 33 — not the iQOO), launched
twice cleanly with zero fatal exceptions, screenshotted the real Home/Capture
UI running. adb dropped the USB connection partway through re-verification
(known flaky-cable/daemon issue, not an app issue) — a full real-camera
end-to-end run against the corrected demo images is still the next concrete
step once reconnected.
