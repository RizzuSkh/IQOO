# Demo images — how to use them

**Do not download a random image off Google for this.** A web photo of a
breadboard carries a watermark, an arbitrary font, JPEG compression noise, and
someone else's lighting — every one of those hurts OCR consistency, and you'd
be rehearsing against an input you can't reproduce twice. These are generated
locally with a known, exact correct answer, so you can rehearse the same
result over and over and trust it on stage.

## Position format — read this first

The parser accepts **both** `P1` style and a **bare digit** like `1`. Your
actual verified spec document, `Breadboard_Bill_of_Materials.pdf`, uses bare
digits in its POSITION column (`1`, `2`, `3`, `4`) — not `P1`. The parser used
to reject every bare-digit label, which is why OCR failed even on printed,
perfectly legible text: it wasn't a photo-quality problem, the position format
just didn't match what the code expected. Fixed in `lib/logic/parser.dart`
and pinned down in `test/parser_test.dart`'s "bare-digit positions" group and
`test/demo_realistic_scenario_test.dart`.

## What's here

| File | Use as | Content |
|---|---|---|
| `demo_spec_A.png` | Specification | **Matches the real BOM exactly**: 1 NE555, 2 7805, 3 LM358 |
| `demo_assembly_A_match.png` | Assembly (clean run) | identical to spec — proves the MATCH state |
| `demo_assembly_B_tampered.png` | Assembly (tamper run) | 2 mismatched, 3 removed, 4 (the BOM's real spare slot) populated without authorisation |
| `demo_spec_realistic.png` | Specification | 1 NE555, 2 LM358, 3 LM393 — **illustrative only, see note below** |
| `demo_assembly_realistic_match.png` | Assembly (clean run) | a real-looking AI-generated breadboard photo + a label panel underneath |
| `demo_assembly_realistic_tampered.png` | Assembly (tamper run) | same photo, 2 mismatched, 3 row omitted |

Regenerate the A/B set (the BOM-accurate one) with:
```powershell
powershell -File demo_assets\generate_demo_screens.ps1
```
Regenerate the realistic set (needs the source photo at the path hardcoded in
the script) with:
```powershell
powershell -File demo_assets\overlay_labels_on_breadboard.ps1
```

### Important: the "realistic" photo set is NOT the official BOM

The AI-generated breadboard photo shows three chips etched `NE555P`,
`LM358P`, `LM393N`. Your real BOM's position 2 calls for a **7805 voltage
regulator** — a 3-pin TO-220 part that looks nothing like these 8-pin DIP
chips. Labelling that photo "7805" would show text contradicting the picture
under it to anyone who looks closely, including a judge who knows
electronics. So the realistic set uses the chips' own real part numbers
instead, as a "looks like real hardware" rehearsal aid — use **`demo_spec_A`
+ `demo_assembly_A_match`/`_B_tampered`** whenever you need the demo to match
`Breadboard_Bill_of_Materials.pdf` precisely, which is most of the time.

### Why the realistic set has a label panel glued below the photo

The original AI photo had **zero position labels anywhere** — only each
chip's tiny etched part code (`NE555P` / `93M` / `DN1810`, three lines per
chip). That reproduced the exact "no valid labels found" error, and no amount
of cropping could fix it, because there was nothing in the frame matching a
position pattern. Confirmed with `test/demo_realistic_scenario_test.dart`,
which replays the original photo's actual OCR text through `parseBlocks()`
and asserts it parses to nothing.

The fix is a clean white label panel appended **below** the photo (not
overlaid on top of it) with positions stacked vertically, generous gaps
between rows, and a wide column gap — the same layout already proven to work
in `demo_spec_A.png`. (A first attempt placed labels in one horizontal strip
across the photo; that risked ML Kit merging all three into one unparseable
block, since same-row + touching boxes look like one label to OCR. Fixed by
stacking rows instead.) Also verified in the same test file.

## How to run the demo

1. Open `demo_spec_A.png` on the laptop, **full-screen** (an image viewer's
   fullscreen mode, or a browser tab with F11 — anything that removes toolbars
   and other text from view). Max screen brightness.
2. On the phone, open Parity, tap **Start Verification**, then **Take Photo**
   on the Capture Specification screen. Photograph the laptop screen straight
   on (not at an angle — angled shots distort the text and OCR reads it
   worse), filling as much of the phone's frame with the label sheet as you
   can, from about 20–30cm away.
3. Use the crop sliders to trim right up to the thin grey border in the
   image, cutting out everything outside it — this also cuts out any screen
   bezel, reflection, or desk visible around the edges. Tap **Scan Selected
   Area**.
4. Confirm the status line reads "3 text blocks read, 3 row(s) parsed" (or
   close — if a row lands in "unparsed", the review screen will show you
   which one, and you can add it manually in two taps).
5. Tap **Next**, then swap the laptop display to `demo_assembly_A_match.png`
   (or `demo_assembly_B_tampered.png` for the discrepancy story) and repeat
   Capture Assembly.
6. On the Review screen, check both lists look right, then **Compare & Show
   Results**.

Same steps work for the realistic set — swap in `demo_spec_realistic.png` /
`demo_assembly_realistic_match.png` / `demo_assembly_realistic_tampered.png`.
Only difference: the assembly photo is taller (photo + label panel), so when
photographing it, back up enough that the whole label panel is in frame, or
scroll the image viewer so the panel fills the shot on its own — the panel is
what OCR needs to read, the photo above it is just for looking real.

Expected results, so you know a run went correctly before you're on stage:

- **Scenario A** (`demo_spec_A` + `demo_assembly_A_match`): **MATCH**, zero
  discrepancies.
- **Scenario B** (`demo_spec_A` + `demo_assembly_B_tampered`): **3
  discrepancies** — 2 mismatched (7805 → LM358), 3 missing (LM358), 4
  unexpected (NE555) — a real part turning up in the BOM's real spare slot.
- **Realistic match** (`demo_spec_realistic` + `demo_assembly_realistic_match`):
  **MATCH**, zero discrepancies.
- **Realistic tampered** (`demo_spec_realistic` + `demo_assembly_realistic_tampered`):
  **2 discrepancies** — 2 mismatched (LM358 → NE555), 3 missing (LM393).

## Why a laptop screen instead of a printout

A monitor is bright, flat, and perfectly reproducible between rehearsals — no
ink running low, no paper glare, no crumpled sheet. The one risk is screen
glare from overhead lighting: angle the laptop screen slightly down/away from
the brightest light in the room, and keep the phone perpendicular to the
screen rather than off to one side.

If you'd rather have a physical fallback in case the laptop isn't available
at the pitch table, print the same PNGs at full size (they're already
1920×1080 — print landscape, fit to page) instead of hand-writing labels;
that reproduces the same font size and layout on paper. This also means you
could print `Breadboard_Bill_of_Materials.pdf` itself and photograph that
directly as the specification — it's already the right shape (position,
component, description columns) and the parser now reads its bare-digit
positions correctly.

## The real assembly demo

These label sheets are a *rehearsal and fallback* tool — they prove the OCR →
parser → compare → phrase pipeline is solid under controlled input, which is
what "it gives random/wrong values sometimes" was actually about (see
`PROGRESS.md`: it was code bugs — a noise-appending bug, then a position
format mismatch with your own BOM — never the OCR model).

For the live judge-tampers-the-board moment from PRD section 10, print small
physical label cards in this same style (bold, black on white, ≥1cm tall,
bare-digit position) and tape one at each breadboard position instead of
relying on the chip's own tiny factory print — that is what PRD section 19
specifies, and it's the difference between reliable and unreliable OCR on a
real object.
