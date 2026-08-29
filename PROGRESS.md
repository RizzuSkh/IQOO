# Parity — Build Progress Log

Laptop 1 (foundation machine). Session 1 started 2026-08-29.

Environment at session start:
- Flutter 3.41.7 stable, Dart 3.11.5, Windows x64
- Connected devices: Windows desktop, Chrome, Edge. NO Android device or emulator.
- Remote: https://github.com/RizzuSkh/IQOO.git (branch main)

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

