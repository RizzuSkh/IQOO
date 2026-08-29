# Parity — Product Requirements Document

**Version:** 1.0 (hackathon build) · **Track:** Productivity
**Principle:** READ → STRUCTURE → COMPARE → REPORT

---
                                                                                
## 1. Executive summary

Parity is an offline Android application that verifies a physical assembly against its
written specification. It photographs a spec sheet and the assembly, extracts both into
structured lists using on-device OCR, computes discrepancies deterministically, and
reports exactly what is missing, extra, or incorrect.

Every AI camera product answers "what is this?" Parity answers "is this correct?"

---

## 2. Problem

Verifying installed equipment against its specification is one of the most common and
least automated tasks in technical work. A technician holds a printed spec in one hand,
looks at the equipment, and compares line by line from memory. It is slow, error-prone,
and the only record is a signature on paper.

Existing field tools are forms-first: an office worker pre-builds a checklist, and the
technician taps through it. This fails when reality does not match the form.

## 3. Target user

Field technicians, commissioning engineers, and assembly-line supervisors who verify
physical equipment against documentation.

## 4. Current workflow

1. Print the spec sheet
2. Stand in front of the equipment
3. Read one line, look at the equipment, compare from memory
4. Repeat for every line
5. Sign the sheet

Failure modes: transcription errors, skipped lines, no audit trail, no evidence capture.

## 5. Proposed solution

Parity derives the checklist from the specification itself. Two photographs replace the
manual line-by-line comparison, and the output is only the differences.

## 6. Why phone-first

The subject is a physical object that must be stood in front of. A laptop cannot be held
up to equipment in a plant room. The phone is the only device that is simultaneously
camera, OCR engine, and compute while pointed at the work. Remove the phone and the
product does not degrade — it ceases to exist.

## 7. Why AI

On-device ML (Google ML Kit text recognition) performs the perception step: converting
photographs of physical objects and printed documents into structured text. This is not
solvable with conventional programming.

AI is deliberately NOT used for the judgement step. See section 18.

## 8. Why on-device

- **Confidentiality:** specifications and bills of materials are customer IP, frequently
  security-restricted. Client sites and datacentres do not permit uploads.
- **Connectivity:** the work happens in basements, substations, and plant rooms without
  usable signal.
- **Latency:** verification is interactive; a network round-trip per capture is unusable.

## 9. User journey

1. Open app
2. Photograph the specification sheet
3. Review the extracted expected list; correct any OCR errors by tapping
4. Photograph the physical assembly
5. Review the extracted observed list; correct any OCR errors by tapping
6. View discrepancies, colour-coded by type
7. Export report to device storage and clipboard
8. Reset for the next inspection

## 10. Demo journey

1. Team shows the assembled breadboard and its printed Bill of Materials
2. Team hands the board to a judge and turns away
3. Judge alters the board unobserved (removes, moves, or swaps an IC)
4. Team photographs the spec sheet, then the board
5. App reports exactly what changed
6. Team enables aeroplane mode and repeats — proving fully offline operation

## 11. Core features

| ID | Feature |
|----|---------|
| F1 | Capture specification photograph |
| F2 | On-device OCR extraction to structured expected list |
| F3 | Capture assembly photograph |
| F4 | On-device OCR extraction to structured observed list |
| F5 | Deterministic comparison producing typed discrepancies |
| F6 | Rules-based natural-language summary |
| F7 | Colour-coded results display |
| F8 | Report export to file and clipboard |
| F9 | Manual correction of any OCR-extracted field |
| F10 | Reset to initial state |

## 12. MVP (P0) — must work before Evaluation Round 1

F1, F2, F3, F4, F5, F6, F7, F10.

## 13. Stretch

- **P1:** F8 (report export), F9 (manual correction)
- **P2:** On-device LLM phrasing via flutter_gemma; OCR confidence indicators
- **P3:** Second assembly type; report history

## 14. Non-goals

User accounts, login, cloud sync, backend server, scan history, settings screen,
onboarding, object detection, multiple simultaneous assembly types, styled PDF export,
dark mode, animations beyond default transitions, any runtime cloud API dependency.

## 15. Functional requirements

| ID | Requirement | Test |
|----|-------------|------|
| FR1 | App captures a photograph via device camera | Photo file exists on device |
| FR2 | OCR extracts text blocks with bounding boxes | Non-empty block list from test image |
| FR3 | Parser groups blocks into rows by Y-coordinate proximity | 4 rows from 4-row test image |
| FR4 | Parser pairs leftmost block as position, next as component | Correct SpecItem list |
| FR5 | Unreadable component yields empty string, never null | Assert on partial-read fixture |
| FR6 | compare() returns missing, unexpected, mismatched | All 3 unit tests pass |
| FR7 | compare() contains no model calls | Code review + no network permission needed |
| FR8 | phraseWithRules() produces a sentence for every DiffResult | Test all 4 diff states |
| FR9 | Results screen colours: missing red, unexpected amber, mismatched orange | Visual check |
| FR10 | Reset clears all state | Two consecutive runs, no bleed |
| FR11 | Any extracted field is editable before comparison | Tap, edit, verify |
| FR12 | Report writes to app documents dir and system clipboard | File exists, paste succeeds |

## 16. Non-functional requirements

| ID | Requirement | Test |
|----|-------------|------|
| NFR1 | Full pipeline completes under 15 seconds on iQOO 15 | Stopwatch, 5 runs |
| NFR2 | App functions fully in aeroplane mode | Radios off, full run |
| NFR3 | No crash on: blurry photo, no text found, zero discrepancies | 3 negative tests |
| NFR4 | No API keys or secrets in the repository | grep + .gitignore review |
| NFR5 | App requests only CAMERA permission | Manifest review |
| NFR6 | Repository clones and runs on a clean machine | Laptop 2 clone test |
| NFR7 | Min SDK 26, target SDK 36 (Android 16, iQOO 15) | Build succeeds |

## 17. Data model

```dart
class SpecItem {
  final String position;    // "P1".."P4" — from fixed breadboard label
  final String component;   // "NE555" etc. Empty string if unread. NEVER null.
  final double confidence;  // 0.0-1.0 from OCR
}

enum DiffType { missing, unexpected, mismatched }

class Discrepancy {
  final DiffType type;
  final String position;
  final String? expected;   // null for unexpected
  final String? found;      // null for missing
}

class DiffResult {
  final List<Discrepancy> discrepancies;
  final bool isMatch;       // true when discrepancies is empty
}
```

## 18. Comparison logic — deterministic, no AI

Index both lists by position. For each position present in either list:

| Expected | Observed | Result |
|----------|----------|--------|
| present | absent | `missing` |
| absent | present | `unexpected` |
| present | present, same component | no discrepancy |
| present | present, different component | `mismatched` |
| present | present, component empty (unread) | `unread` — prompt user, never assume match |

Comparison is case-insensitive and whitespace-trimmed. Nothing else is normalised —
"NE555" and "NE 555" are a mismatch, and that is correct behaviour for this domain.

**A false match is dangerous. An unread field is only a retake.** When uncertain, the
system reports uncertainty rather than guessing.

## 19. OCR strategy

- **Engine:** `google_mlkit_text_recognition`, Latin script, fully on-device
- **Input design:** printed sticker labels, minimum 1cm text height, black on white
- **Spatial pairing:** sort text blocks by bounding-box Y-centre into rows (tolerance =
  half the median block height); within each row sort by X; first block is position,
  second is component
- **Failure handling:** any block failing to match the position pattern is surfaced in the
  correction UI rather than silently dropped
- **Recovery:** F9 manual correction lets the user fix any field before comparison

**Testing:** must be validated on the actual iQOO 15 against the actual breadboard under
venue lighting. Desktop or Google Lens results do not transfer.

## 20. AI strategy

**On-device ML for perception, deterministic code for judgement.**

- ML Kit text recognition (on-device model) handles perception
- `compare()` handles judgement — pure Dart, no model, unit-tested
- `phraseWithRules()` produces the summary sentence

**P2 stretch:** flutter_gemma may phrase the already-computed DiffResult. It never
computes it. If unavailable or unstable, the rules path is the product.

**Prohibited:** any runtime cloud API call. OpenRouter credits are for development
tooling only and no key ships in the application.

**NPU:** no acceleration claim is made. ML Kit does not expose NPU selection on Android.
Any claim would require measured verification we cannot perform in this window.

## 21. Offline strategy

After first launch (ML Kit model bundling), the app requires no network. Aeroplane-mode
operation is a demo requirement (NFR2), not just a capability.

## 22. Office Kit workflow

**No public third-party Office Kit developer API was found. UNVERIFIED — confirm with
organisers. The application makes no Office Kit API calls.**

Workflow:
1. App writes `parity_report_<timestamp>.txt` to the app documents directory
2. App copies the summary to the Android system clipboard
3. Operator uses Office Kit File EasyShare to access the file from the laptop, and
   Office Kit clipboard sync to paste the summary

Verification happens at the equipment; resolution happens at the desk.

## 23. Error states

| Condition | Behaviour |
|-----------|-----------|
| Camera permission denied | Explain and offer settings link |
| No text detected | "No labels found — retake with more light" + retake button |
| Fewer than 2 rows detected | Warn, offer retake or manual entry |
| Component unread | Highlight field, require confirmation before comparing |
| Zero discrepancies | Explicit success state — never a blank screen |
| File write fails | Show summary on screen; clipboard still populated |

## 24. Testing plan

- **Unit:** `compare()` against 3 fixtures in `test/` — missing, unexpected, mismatched
- **Unit:** `parser` against a saved OCR block fixture
- **Manual device:** full pipeline on iQOO 15, 5 consecutive runs
- **Manual device:** aeroplane mode full run
- **Manual device:** 3 negative cases from section 23
- **Integration:** clean clone on Laptop 2 builds and runs

## 25. Judging strategy

| Dimension | Weight | How Parity earns it |
|-----------|--------|---------------------|
| End product quality | 30% | Complete working loop, error states handled, no crashes |
| Novelty and impact | 20% | Comparison rather than identification; honest competitive positioning |
| Creative phone use | 15% | Camera as measuring instrument; dogfooded on the phone all event |
| Technical depth | 15% | Deterministic-diff architecture; unit tests; explicit uncertainty handling |
| Office Kit usage | 10% | File + clipboard bridge used throughout the build |
| Demo and presentation | 10% | Judge-authored tamper demo, repeated in aeroplane mode |

## 26. 30-hour priorities

P0 → P1 → P2. Never begin P1 before all P0 acceptance criteria pass.
See CLAUDE.md build order and stop rules.

## 27. Acceptance criteria

- [ ] Two photographs produce two structured lists on-device
- [ ] All 3 unit tests pass
- [ ] All three discrepancy types display correctly
- [ ] Summary sentence appears with no model present
- [ ] Full aeroplane-mode run succeeds
- [ ] No crash on all 3 negative cases
- [ ] Pipeline under 15 seconds, measured
- [ ] Reset gives a clean run
- [ ] Report file written and clipboard populated
- [ ] Clean clone builds on another laptop
- [ ] No secrets in repository