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

## Primary scenario: MCB distribution board (recommended)

| File | Use as | Content |
|---|---|---|
| `demo_spec_mcb.png` | Specification | Blueprint: 5 positions, ratings 32A/20A/16A/6A/32A |
| `demo_assembly_mcb_match.png` | Assembly (clean run) | Illustrated panel + matching labels — proves MATCH |
| `demo_assembly_mcb_tampered.png` | Assembly (tamper run) | Position 2 mismatched, 4 missing, 6 an unauthorised extra breaker |

Regenerate with:
```powershell
powershell -File demo_assets\generate_mcb_demo.ps1
```

### Why an illustration instead of a photo of a real MCB panel

The Havells panel photo shared in chat has the same problem the original
breadboard photo had: current ratings are printed in tiny text directly on
each switch, with no separate position label anywhere on the board. Reusing
someone else's product photo also risks the exact mismatch caught last
time — labelling a picture with text that doesn't match what's actually
printed on it, which a technically literate judge would notice immediately.

So this panel is drawn from scratch: a distribution-board illustration with
five breaker switches, followed by a clean label panel with position and
rating baked in from the start. It's not trying to pass as a photograph — it
reads as a technical diagram, which is arguably a better fit for a
"blueprint" anyway, and the labels are correct and legible by construction.

If you'd rather use a real device photo of a real object for extra
authenticity, that's exactly what section 19 of the PRD already recommends:
print small physical position labels (bold, black on white, ≥1cm tall) and
tape one next to each breaker on an actual panel, then photograph that
directly — no laptop screen needed at that point.

## Alternate scenario: electronics breadboard (still available)

| File | Use as | Content |
|---|---|---|
| `demo_spec_A.png` | Specification | Matches `Breadboard_Bill_of_Materials.pdf` exactly: 1 NE555, 2 7805, 3 LM358 |
| `demo_assembly_A_match.png` | Assembly (clean run) | identical to spec — MATCH |
| `demo_assembly_B_tampered.png` | Assembly (tamper run) | 2 mismatched, 3 missing, 4 unexpected |
| `demo_spec_realistic.png` / `demo_assembly_realistic_*.png` | — | An AI-generated breadboard photo + label panel — illustrative only, does not match the official BOM's actual parts (see comments in `overlay_labels_on_breadboard.ps1`) |

Regenerate with `generate_demo_screens.ps1` / `overlay_labels_on_breadboard.ps1`.

`lib/main.dart`'s `_demoSpecAsset` / `_demoAssemblyTamperedAsset` constants
control which scenario the in-app "Run Demo Sample" button uses — currently
the MCB set. Swap them to point at the breadboard files if you want that
story instead.

## Position format — worth knowing

The parser accepts **both** `P1` style and a bare digit like `1`. Your real
`Breadboard_Bill_of_Materials.pdf` uses bare digits, and the MCB blueprint
above follows the same convention. The parser used to reject bare digits,
which is why OCR failed even on perfectly legible printed text early on — see
`PROGRESS.md` Session 5 for the full story. Fixed and covered by
`test/parser_test.dart`'s "bare-digit positions" group.

## How to run the demo — real camera, step by step

1. Open `demo_spec_mcb.png` on the laptop, **full-screen** (an image viewer's
   fullscreen mode, or a browser tab with F11 — anything that removes
   toolbars and other on-screen text). Max screen brightness, and angle the
   screen slightly away from overhead lights to kill glare.
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
5. Tap **Next**. Swap the laptop display to `demo_assembly_mcb_match.png` (or
   `_tampered.png` for the discrepancy story) and repeat step 2 onward for
   Capture Assembly.
6. On the Review screen, glance at both lists — this is also where you'd
   catch and fix anything OCR got wrong before comparing. Tap **Compare &
   Show Results**.

Expected results, so you know a run went correctly before you're on stage:

- **MCB match** (`demo_spec_mcb` + `demo_assembly_mcb_match`): **MATCH**,
  zero discrepancies.
- **MCB tampered** (`demo_spec_mcb` + `demo_assembly_mcb_tampered`): **3
  discrepancies** — position 2 mismatched (20A → 16A), position 4 missing
  (6A), position 6 unexpected (20A) — an unauthorised breaker in a spare
  slot, mirroring exactly how a judge could plausibly "tamper" a real panel.
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
