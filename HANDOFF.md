# Parity — Laptop 1 handoff

Written 2026-08-29 during Laptop 1's session 2. `PROGRESS.md` has the full stage
history and the audit; this file is only **the work Laptop 1 could not finish and
exactly how to finish it**, with a copy-pasteable prompt per task.

Nothing here changes the architecture, adds a dependency, or touches a file owned
by Laptop 2 or Laptop 3.

---

## Why work is being handed over

Laptop 1's `C:` drive is **100% full — 2 MB free of 291 GB** (`D:` has 103 GB).
That is what killed `flutter test` with `errno = 112` and what actually stalled
Session 1's release build; the "not enough RAM" diagnosis in the Stage 7b note
was wrong.

The toolchain has since been redirected onto `D:` (recipe below), which is enough
to build and run. What a redirect **cannot** fix is anything needing a human hand
or a second machine: aiming a camera at a physical object, toggling aeroplane mode
part-way through a run, or cloning onto a clean laptop. Those are the handoff
tasks.

**If your `C:` has space, ignore the next section — just `git pull` and work
normally.**

---

## Working on a full C: drive (Laptop 1 only)

Every Flutter and Gradle invocation needs these first, or it will fail on a
temp-file write:

```bash
export GRADLE_USER_HOME="D:\\gradle_home"
export TEMP="D:\\tmp_flutter"
export TMP="D:\\tmp_flutter"
export TMPDIR="D:\\tmp_flutter"
export GRADLE_OPTS="-Djava.io.tmpdir=D:\\tmp_flutter"
```

`D:\gradle_home` was seeded by copying `C:\Users\<you>\.gradle` (which held only
the Gradle 8.14 wrapper — the dependency cache was already gone, so the first
build re-downloads roughly 1.5 GB of Android/ML Kit artifacts).

Two more gotchas found the hard way:

- **Git Bash rewrites Android absolute paths.** `adb push x /data/local/tmp/`
  silently becomes `C:/Program Files/Git/data/local/tmp/`. Prefix every adb
  command with `MSYS_NO_PATHCONV=1` (and `MSYS2_ARG_CONV_EXCL='*'`).
- **`adb devices` came back empty even with the cable plugged in.** The daemon
  was stale; `adb kill-server && adb start-server` brought the iQOO
  (`10BFCH1K9Y00237`, I2501, Android 16 / API 36) straight back.

---

## Reference images — how to exercise OCR without a camera

`test/fixtures/parity_spec.png` and `parity_assembly.png` are rendered spec
sheets committed to the repo (`generate_reference_images.ps1` regenerates them).
The debug harness has a **Read Reference Images** button that runs
OCR → parser → compare → phrase over them from the app's own documents
directory, so no storage permission is involved and CAMERA stays the only
permission the app asks for.

Push them to the device with:

```bash
MSYS_NO_PATHCONV=1 adb push test/fixtures/parity_spec.png /data/local/tmp/
MSYS_NO_PATHCONV=1 adb push test/fixtures/parity_assembly.png /data/local/tmp/
MSYS_NO_PATHCONV=1 adb shell "run-as com.rtiparadox.parity.parity sh -c \
  'cp /data/local/tmp/parity_*.png app_flutter/'"
```

The images are built so the correct answer is fixed and known:

| | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| spec | NE555 | 7805 | LM358 | — |
| assembly | NE555 | LM358 | — | NE555 |

Expected `DiffResult`: **P3 missing, P4 unexpected, P2 mismatched** — 3
discrepancies, and the phrase should read:

> 3 discrepancies: P3 should hold LM358 but nothing was found there; P4 holds
> NE555, which the specification does not call for; P2 holds LM358 where the
> specification calls for 7805.

If the app prints that, the whole on-device chain is proven against a known
answer. **It does not prove camera capture** — that is Task 1.

---

## Task 1 — Photograph a real printed physical label (HIGHEST PRIORITY)

**Needs:** the iQOO, a printer, and a human hand. Cannot be automated.
**Gates:** F2 and F4, and therefore every P0 acceptance criterion downstream.
**Stop rule:** CLAUDE.md T+6h — if OCR will not read a real printed label,
manual entry becomes the primary input and OCR drops to an enhancement. Find
this out early, not at T+12h.

Reference images prove ML Kit works on a clean render. They say nothing about a
phone camera, a curved sticker, glare, or venue lighting — which is the actual
risk PRD section 19 and the Known Risks table both flag as HIGH.

Steps:
1. Print a label sheet: position labels down the left, components to the right,
   black on white, text at least 1 cm tall, a wide horizontal gap between the
   two columns. Use the layout in `test/fixtures/parity_spec.png`.
2. `flutter run` the harness on the iQOO, tap **Capture Spec**, photograph the
   printed sheet, and read the status line: it reports how many blocks OCR
   returned and how many rows parsed.
3. Repeat with **Capture Assembly** against the breadboard's own labels.
4. Write down the real numbers — blocks read, rows parsed, anything landing in
   `unparsed:` — in `PROGRESS.md`. Numbers, not "it worked".

**Watch for this specific failure.** The parser expects the position and the
component to arrive as **two separate OCR blocks** (PRD section 19). ML Kit
merges text that sits close together, so a tight row may come back as one block
reading `"P1 NE555"`. The parser will then fail `^P\d+$` on the whole string and
send the row to `unparsedRows` — nothing lost, but nothing paired either. If
that happens on real photographs:
- widen the column gap on the printed sheet first, and re-shoot; and
- report it, because the fix is a parser change (splitting a single block's text
  into leading position + remainder) and `lib/logic/parser.dart` is Laptop 1's
  file. **Do not edit it yourself** — CLAUDE.md section 17.

Prompt to paste:

```
Parity, on the iQOO with a real printed label sheet.

Run the debug harness, tap Capture Spec, photograph the printed sheet, then tap
Capture Assembly and photograph the breadboard. Report the exact status line
each time: how many OCR blocks came back, how many rows parsed, and every row
that landed in unparsedRows.

Do not change lib/logic/parser.dart or lib/logic/ocr.dart — Laptop 1 owns those.
If position and component come back merged into one block, say so and stop;
that is a finding for Laptop 1, not something to patch locally.

Then append the numbers to PROGRESS.md as a Stage 5 verification entry and
commit. Do not force-push.
```

---

## Task 2 — NFR1: measure the pipeline (needs Task 1 first)

Five consecutive real-photograph runs, wall-clock from shutter to summary,
recorded individually. PRD requires under 15 seconds. Log all five numbers and
the slowest, not an average.

Prompt to paste:

```
Parity NFR1. On the iQOO, run the full harness pipeline five consecutive times
with real photographs. Time each run from shutter to summary appearing. Report
all five times and the worst case, and append them to PROGRESS.md. Fail the
criterion honestly if any run exceeds 15 seconds.
```

---

## Task 3 — NFR3: the three negative cases (needs Task 1 first)

From PRD section 23, on the device, and the app must not crash:
1. A deliberately blurry / out-of-focus photograph.
2. A photograph with no text in it at all — expect "no labels found", not a
   crash and not a blank screen.
3. Two identical photographs — expect the explicit success state, never an
   empty results view.

Prompt to paste:

```
Parity NFR3 negative cases on the iQOO. Run three cases through the harness:
a blurry photo, a photo containing no text, and two identical photos. For each,
report exactly what the app displayed and whether it crashed (check logcat for
FATAL EXCEPTION). Append results to PROGRESS.md. Do not change any logic file.
```

---

## Task 4 — NFR2: full aeroplane-mode run (needs Task 1 first)

Radios off — WiFi, mobile data, Bluetooth — then a complete run with real
photographs. This is a demo requirement, not just a capability. Confirm ML Kit's
model is already on the device and no first-run download is waiting; the whole
pitch dies on stage if it is.

Prompt to paste:

```
Parity NFR2. Put the iQOO in aeroplane mode (verify WiFi, mobile data and
Bluetooth are all off), then run the full harness pipeline with real
photographs. Report whether OCR still returned text and the summary still
appeared. Append the result to PROGRESS.md.
```

---

## Task 5 — NFR6: clean clone on another laptop (Laptop 2 or 3)

```bash
git clone https://github.com/RizzuSkh/IQOO.git parity-clean
cd parity-clean
flutter pub get
flutter analyze          # must be clean
flutter test             # must be 43/43
flutter build apk --debug
```

Prompt to paste:

```
Parity NFR6 clean-clone check. Clone https://github.com/RizzuSkh/IQOO.git into a
fresh directory, run flutter pub get, flutter analyze, flutter test and
flutter build apk --debug. Report the exact output of each. If anything fails on
a clean machine that passes on Laptop 1, that is a real bug — report it, don't
work around it locally.
```

---

## Task 6 — backup APK on a second device

CLAUDE.md section 21 requires a backup APK on a second device in case the iQOO
fails on stage. Nobody has built one. Whoever has disk space: build the release
APK, install it on a second Android phone, and confirm it launches and runs the
reference-image path.

---

## Task 7 — the screens (already owned, unchanged)

Still not started, and still gating the P0 chain:

- **Laptop 2** — `lib/screens/capture_spec.dart`, `capture_assembly.dart`,
  `review_extraction.dart` (F1, F3, and F9 correction).
- **Laptop 3** — `lib/screens/results.dart`, `lib/io/report.dart` (F7 colour-coded
  results, F8 export).

Build against these, all tested and stable:
`compare(spec, assembly) → DiffResult`, `phraseWithRules(result) → String`,
`parseBlocks(blocks) → ParseResult{items, unparsedRows}`,
`SpecItem.copyWith(...)` for correction, `result.isMatch` for the success state.
`DiffResult` has **four** lists — `missing`, `unexpected`, `mismatched`,
`unread` — not the three PRD section 17 still claims. Section 18 and the code
agree on four; section 17 is the stale one.

Note the ordering rule from CLAUDE.md section 22: **F7 is P0, F8 and F9 are P1.**
Results display comes before report export and before the correction UI.

---

## Do not do these

- Do not edit `lib/logic/*`, `lib/models/*`, `test/*` or `lib/main.dart` —
  Laptop 1's files, and `compare()`/`phraseWithRules()` are the contract
  everything else calls.
- Do not add a dependency without approval (CLAUDE.md section 10).
- Do not add a permission to the manifest. CAMERA only (NFR5).
- Do not `git push --force`, and do not `git reset --hard` a branch someone may
  have pulled.
- Do not mark anything done without running it on the device.
