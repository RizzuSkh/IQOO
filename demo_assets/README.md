# Demo images — how to use them

**Do not download a random image off Google for this.** A web photo of a
breadboard carries a watermark, an arbitrary font, JPEG compression noise, and
someone else's lighting — every one of those hurts OCR consistency, and you'd
be rehearsing against an input you can't reproduce twice. These three PNGs are
generated locally with a known, exact correct answer, so you can rehearse the
same result over and over and trust it on stage.

## What's here

| File | Use as | Content |
|---|---|---|
| `demo_spec_A.png` | Specification | P1 NE555, P2 7805, P3 LM358, P4 CD4017 |
| `demo_assembly_A_match.png` | Assembly (clean run) | identical to spec — proves the MATCH state |
| `demo_assembly_B_tampered.png` | Assembly (tamper run) | P2 swapped, P3 removed, P5 added |

Regenerate them any time with:
```powershell
powershell -File demo_assets\generate_demo_screens.ps1
```

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
4. Confirm the status line reads "4 text blocks read, 4 row(s) parsed" (or
   close — if a row lands in "unparsed", the review screen will show you
   which one, and you can add it manually in two taps).
5. Tap **Next**, then swap the laptop display to `demo_assembly_A_match.png`
   (or `demo_assembly_B_tampered.png` for the discrepancy story) and repeat
   Capture Assembly.
6. On the Review screen, check both lists look right, then **Compare & Show
   Results**.

Expected results, so you know a run went correctly before you're on stage:

- **Scenario A** (`demo_spec_A` + `demo_assembly_A_match`): **MATCH**, zero
  discrepancies.
- **Scenario B** (`demo_spec_A` + `demo_assembly_B_tampered`): **3
  discrepancies** — P2 mismatched (7805 → LM358), P3 missing (LM358), P5
  unexpected (NE555).

## Why a laptop screen instead of a printout

A monitor is bright, flat, and perfectly reproducible between rehearsals — no
ink running low, no paper glare, no crumpled sheet. The one risk is screen
glare from overhead lighting: angle the laptop screen slightly down/away from
the brightest light in the room, and keep the phone perpendicular to the
screen rather than off to one side.

If you'd rather have a physical fallback in case the laptop isn't available
at the pitch table, print the same PNGs at full size (they're already
1920×1080 — print landscape, fit to page) instead of hand-writing labels;
that reproduces the same font size and layout on paper.

## The real assembly demo

These label sheets are a *rehearsal and fallback* tool — they prove the OCR →
parser → compare → phrase pipeline is solid under controlled input, which is
what "it gives random values sometimes" was actually about (see the analysis
in `PROGRESS.md` / chat history: it was two code bugs, not the OCR model).

For the live judge-tampers-the-board moment from PRD section 10, print small
physical label cards in this same style (bold, black on white, ≥1cm tall) and
tape one at each breadboard position instead of relying on the chip's own
tiny factory print — that is what PRD section 19 specifies, and it's the
difference between reliable and unreliable OCR on a real object.
