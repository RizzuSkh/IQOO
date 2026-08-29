# Parity — Engineering Context for Claude Code

Read PRD.md for WHAT. This file is HOW. Both are authoritative.
Antigravity does not read this automatically — paste it into Rules manually.

---

## 1. Project identity
Parity — offline Android app comparing a physical assembly to its written specification.
iQOO Hackathon 2026, City Battle Bengaluru, Productivity track. Team of 3.

## 2. Product goal
READ → STRUCTURE → COMPARE → REPORT. Report only what differs.

## 3. Non-negotiable requirements
1. `lib/logic/compare.dart` is pure and deterministic. **No model calls, ever.**
2. No cloud API calls at runtime. No API keys in the repository.
3. Full functionality in aeroplane mode.
4. Unread never equals matched. Report uncertainty instead of guessing.

## 4. Official hackathon constraints
- Original work only; all code written during the event window
- Must run and pitch on the iQOO 15 (Android 16 / OriginOS 6)
- Red Light: phone only, laptop reachable via Office Kit Remote PC
- Repo and demo assets submitted before the hard cutoff; repos lock before pitches
- Scoring: end product 30, novelty 20, phone use 15, technical depth 15,
  Office Kit 10, demo 10

## 5. Architecture

```
Camera -> ML Kit OCR -> text blocks with bounding boxes
                            |
                    parser.dart  (rows by Y, columns by X)
                            |
              List<SpecItem>  (expected)   List<SpecItem>  (observed)
                            |
                    compare.dart  <- PURE. NO MODEL.
                            |
                       DiffResult
                            |
                  phraseWithRules()   [P2: phraseWithModel()]
                            |
                   Results screen -> report.dart -> file + clipboard
```

## 6. Technology stack
- Flutter, Dart, Android SDK. minSdk 26, targetSdk 36
- `image_picker` — camera capture
- `google_mlkit_text_recognition` — on-device OCR, Latin
- `path_provider` — documents directory
- Flutter `Clipboard` — system clipboard
- No other dependencies without approval

## 7. Folder structure
```
lib/
  main.dart
  screens/
    capture_spec.dart
    capture_assembly.dart
    review_extraction.dart
    results.dart
  logic/
    ocr.dart          # ML Kit wrapper only
    parser.dart       # blocks -> List<SpecItem>
    compare.dart      # PURE. NO MODEL CALLS.
    phrase.dart        # DiffResult -> sentence
  io/
    report.dart        # file write + clipboard
  models/
    spec_item.dart
    diff_result.dart
test/
  compare_test.dart
  parser_test.dart
  fixtures/
```

## 8. Data contracts
See PRD.md section 17. Do not change these without team agreement — all three
laptops code against them.

- `component` is `""` when unread, never `null`
- `position` is uppercase, trimmed
- Comparison is case-insensitive, whitespace-trimmed, nothing else normalised

## 9. Coding rules
- `flutter format` before every commit
- Every public function has a one-line doc comment
- No `print()` in committed code — use a single debug helper
- Null safety enforced; no `!` without a comment justifying it
- Any function that could fail returns a result or throws a typed exception

## 10. Dependency rules
Do not add a package without stating why and getting approval. Every new dependency is
download time on contested venue wifi and a possible build break.

## 11. AI rules
- The model NEVER decides what differs. `compare.dart` does.
- The model only phrases an already-computed DiffResult.
- If a prompt contains "compare these" or "what's different" — it is wrong.
- No runtime cloud calls. OpenRouter is development tooling only.
- **Never claim NPU acceleration.** ML Kit does not expose NPU selection on Android.

## 12. Offline rules
No network calls in application code. If a feature needs a network, it is out of scope.
Aeroplane mode is a test case, not a hope.

## 13. Phone-first rules
Camera, OCR, comparison, and report generation all happen on the phone. The laptop is a
development machine and a report destination, never part of the runtime pipeline.

## 14. Office Kit rules
**No public third-party API. Make no Office Kit API calls.** Write a file to the
documents directory and set the system clipboard. A human bridges via Office Kit.
If anyone proposes an Office Kit SDK call, it is fabricated — reject it.

## 15. Testing rules
- `compare.dart` and `parser.dart` have unit tests before they are called done
- Every feature is tested on the physical device before being marked complete
- "Works on the emulator" and "the code looks right" are not test results

## 16. Git rules
See the team workflow document. Summary:
- `main` must always run
- Small commits after every working state
- Feature branches per person, merge via pull request
- Pull `main` before starting any new task

## 17. Team ownership
| Person | Branch | Owns |
|--------|--------|------|
| P1 | `main`, `feat/core` | models/, logic/, main.dart, test/ |
| P2 | `feat/capture` | screens/capture_*.dart, review_extraction.dart |
| P3 | `feat/results` | screens/results.dart, io/report.dart |

**Do not edit a file you do not own.** Ask the owner.

## 18. Definition of Done
A task is done when: code compiles, unit tests pass (where applicable), it has been run
on the physical device, it is committed, it is pushed, and the owner has said so.

## 19. Forbidden shortcuts
- Calling a model to decide what differs
- Treating an unread field as a match
- Adding a cloud API "just for now"
- Committing an API key
- Marking done without device testing
- Rewriting a file you do not own
- Adding a dependency without approval
- Claiming something works without running it

## 20. Known risks
| Risk | Severity | Mitigation |
|------|----------|------------|
| Claude Code + OpenRouter setup fails | HIGH | Test in first 15 min; fall back to Antigravity |
| OCR misreads under venue lighting | HIGH | Large printed labels; manual correction UI (P1) |
| Row-pairing fails on skewed photos | MEDIUM | Tripod; retake button; manual correction |
| flutter_gemma native linking fails | MEDIUM | P2 only; rules path is the product |
| Merge conflicts | MEDIUM | Disjoint file ownership |
| Model download over venue wifi | LOW | Bundle ML Kit at build; download early |

## 21. Fallback strategies
- OCR unreliable -> manual correction UI, demo continues
- Model fails -> `phraseWithRules()`, nobody notices
- Office Kit fails -> show report on phone screen, explain the laptop path
- App crashes on stage -> recorded backup demo, clearly labelled as a replay
- Total device failure -> backup APK on a second device

## 22. Build order — do not reorder
```
P0: F1 capture spec -> F2 OCR+parse -> F3 capture assembly -> F4 OCR+parse
    -> F5 compare -> F6 phrase -> F7 results -> F10 reset
P1: F9 manual correction -> F8 report export
P2: on-device LLM phrasing -> confidence indicators
```
Each step gates the next. No P1 work before every P0 acceptance criterion passes.

## 23. Stop rules
- **T+6h:** if OCR is not extracting real text from a real photo, switch to manual entry
  as the primary input and treat OCR as an enhancement
- **T+10h:** if the P0 pipeline is not end-to-end working, stop all feature work; three
  people fix the core path
- **T+13h (before Evaluation 1):** whatever works, freeze and demo it
- **Any single bug, 45 minutes:** stop debugging, take the documented fallback
- **Sun 04:00:** if the P2 model is not working, revert to rules and stop
- **Sun 08:00:** hard code freeze. No new features regardless of who thinks otherwise
