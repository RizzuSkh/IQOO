# Demo images — how to use them

**Do not download a random image off Google for this.** A web photo carries a
watermark, an arbitrary font, JPEG compression noise, and someone else's
lighting — every one of those hurts OCR consistency, and you'd be rehearsing
against an input you can't reproduce twice. Everything here is generated
locally with a known, exact correct answer, so you can rehearse the same
result over and over and trust it on stage.

**Every scenario below is meant to be photographed with the phone's real
camera**, pointed at a laptop screen. There is a separate "Run Demo Sample"
button in the app that loads these images directly with no camera involved —
that exists only as a stage-safety fallback and a way to test the pipeline
without a phone in hand. **The actual demo is the camera.** That's the whole
point of the project: it reads a physical scene, not a file.

## Primary scenario: real MCB distribution board photo (recommended)

| File | Use as | Content |
|---|---|---|
| `demo_spec_mcb_real.png` | Specification | Blueprint: 6 positions (5× C32, 1× DP) — matches the real board exactly |
| `demo_assembly_mcb_real_match.png` | Assembly (clean run) | The **actual Havells board photo** + a matching label panel — MATCH |
| `demo_assembly_mcb_real_tampered.png` | Assembly (tamper run) | Same photo, position 2 mismatched, 4 missing, 7 an unauthorised extra breaker |

Regenerate with:
```powershell
powershell -File demo_assets\overlay_labels_on_mcb_photo.ps1
```
(needs `demo_assets/source_mcb_panel_photo.png` — a PNG conversion of the
team's Havells board photo; GDI+ can't open the original `.webp` directly,
see the script's header comment for the WPF/WIC conversion one-liner if you
need to redo it from a different source photo.)

This is a real photograph of the team's actual board, not an illustration —
this is what "point the camera at the real thing" should mean. The label
panel below the photo exists for the same reason PRD section 19 already
calls for printed labels: the ratings really are printed on each breaker
("C 32"), but at a size that survives being photographed in a close-up
product shot, not at arm's length off a laptop screen during a live demo.
The panel reproduces the same true values in large print so OCR reads them
reliably — it doesn't invent anything: every "C32" in the match scenario is
exactly what's printed on that breaker in the photo.

**One honest limitation:** only one photograph of this board exists, so the
match and tampered demos reuse the identical photo with different label
panels underneath — the tampered scenario's "C16" for position 2 isn't
literally printed anywhere in the photo (it's a claimed value, the same
class of illustrative choice as the breadboard's realistic set). For a demo
moment where a judge should visibly *see* something change, use the fully
illustrated `demo_assembly_mcb_tampered.png` below instead, which is drawn
from scratch precisely so it can show a genuinely different state.

## Alternate scenarios (still bundled, same technique)

| Scenario | Spec | Match | Tampered |
|---|---|---|---|
| Illustrated MCB panel | `demo_spec_mcb.png` | `demo_assembly_mcb_match.png` | `demo_assembly_mcb_tampered.png` |
| Electronics breadboard (matches `Breadboard_Bill_of_Materials.pdf` exactly) | `demo_spec_A.png` | `demo_assembly_A_match.png` | `demo_assembly_B_tampered.png` |
| AI-generated breadboard photo (illustrative, not the official BOM) | `demo_spec_realistic.png` | `demo_assembly_realistic_match.png` | `demo_assembly_realistic_tampered.png` |

Regenerate with `generate_mcb_demo.ps1` / `generate_demo_screens.ps1` /
`overlay_labels_on_breadboard.ps1` respectively.

`lib/main.dart`'s `_demoSpecAsset` / `_demoAssemblyTamperedAsset` constants
control which scenario the in-app "Run Demo Sample" button uses — currently
the real MCB photo. Swap them to point at any of the files above to switch
which story that button tells.

## Position format — worth knowing

The parser accepts **both** `P1` style and a bare digit like `1`. Your real
`Breadboard_Bill_of_Materials.pdf` uses bare digits, and the MCB blueprint
above follows the same convention. The parser used to reject bare digits,
which is why OCR failed even on perfectly legible printed text early on — see
`PROGRESS.md` Session 5 for the full story. Fixed and covered by
`test/parser_test.dart`'s "bare-digit positions" group.

## How to run the demo — real camera, step by step

1. Open `demo_spec_mcb_real.png` on the laptop, **full-screen** (an image
   viewer's fullscreen mode, or a browser tab with F11 — anything that
   removes toolbars and other on-screen text). Max screen brightness, and
   angle the screen slightly away from overhead lights to kill glare.
2. On the phone, open Parity and tap **Start Verification** (not "Run Demo
   Sample" — that one skips the camera). Tap **Take Photo** on the Capture
   Specification screen. Hold the phone steady, perpendicular to the laptop
   screen, about 20–30cm away, filling as much of the frame with the sheet as
   you comfortably can.
3. You'll land on the crop screen with a live preview. Use the **Sides** and
   **Top/Bottom** sliders to trim right up to the thin grey border in the
   image — this is what "ignore the unwanted text" means in practice: you're
   telling the app exactly where to look, the same way you'd point a
   colleague's attention at one line on a page. Tap **Scan Selected Area**.
4. Read the status line under the photo: it tells you exactly what happened —
   "N text block(s) read -> M row(s) parsed", plus a note if anything was
   ignored as stray text or didn't match a position. If something's off,
   **Retake** and crop tighter; if it's close enough, you can also fix
   individual rows by hand on the next screen.
5. Tap **Next**. Swap the laptop display to `demo_assembly_mcb_real_match.png`
   (or `demo_assembly_mcb_real_tampered.png` for the discrepancy story) and
   repeat step 2 onward for Capture Assembly. This image is taller (the real
   board photo plus the label panel below it) — back up a little or scroll
   the viewer so the whole label panel is in frame; that panel is what OCR
   needs to read, the photo above it is what makes the demo look — and
   be — real.
6. On the Review screen, glance at both lists — this is also where you'd
   catch and fix anything OCR got wrong before comparing. Tap **Compare &
   Show Results**.

Expected results, so you know a run went correctly before you're on stage:

- **MCB real-photo match** (`demo_spec_mcb_real` + `demo_assembly_mcb_real_match`):
  **MATCH**, zero discrepancies.
- **MCB real-photo tampered** (`demo_spec_mcb_real` + `demo_assembly_mcb_real_tampered`):
  **3 discrepancies** — position 2 mismatched (C32 → C16), position 4 missing
  (C32), position 7 unexpected (C32) — an unauthorised breaker in a spare
  slot, mirroring exactly how a judge could plausibly tamper a real panel.
- **MCB illustrated match** (`demo_spec_mcb` + `demo_assembly_mcb_match`): **MATCH**.
- **MCB illustrated tampered** (`demo_spec_mcb` + `demo_assembly_mcb_tampered`):
  **3 discrepancies** — 2 mismatched (20A→16A), 4 missing (6A), 6 unexpected (20A).
- **Breadboard match** (`demo_spec_A` + `demo_assembly_A_match`): **MATCH**.
- **Breadboard tampered** (`demo_spec_A` + `demo_assembly_B_tampered`): **3
  discrepancies** — 2 mismatched, 3 missing, 4 unexpected.

## "Can't the app just detect the important text with AI and ignore the rest?"

Short answer: that's what the crop step already is. Training a model to
automatically find "the label region" in an arbitrary photo is a real
computer-vision task — object detection, needing a labelled dataset and
training infrastructure neither exists nor fits in a hackathon window, and it
would still need a human to correct it when it gets the region wrong. A human
drawing a box around the right area, once, in under two seconds, is the
practical version of that same idea, and it's what's already built. The
`ignoredNoise` handling in `lib/logic/parser.dart` is the second line of
defence: anything ML Kit picks up alongside a real row (a stray number, a
column label) gets reported and discarded rather than corrupting the
component text, whether or not the crop was perfect.

## The offline guarantee

Nothing about the demo depends on connectivity — OCR, comparison, and report
generation all run on-device (see CLAUDE.md and PRD section 21). You can
switch the phone to aeroplane mode before either capture and the pipeline
behaves identically; there's no network call anywhere in the app to fail.
