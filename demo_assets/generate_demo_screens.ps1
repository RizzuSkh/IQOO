# Generates landscape label sheets sized for a laptop screen (1920x1080),
# meant to be displayed full-screen and photographed with the phone camera —
# NOT loaded into the app directly. This is the demo input, not a shortcut
# around the camera. See demo_assets/README.md for how to run the demo.
#
# Layout rules that keep OCR reliable (PRD section 19), same as
# test/fixtures/generate_reference_images.ps1 but landscape and bigger:
#   - position column at a fixed left margin, component column at a fixed
#     wide offset, so the two always arrive as separate OCR blocks
#   - bold, black on white, generous line spacing, nothing else on the page
#   - a visible border frame close to the true edge, so the operator can see
#     in the crop UI exactly how much to trim

Add-Type -AssemblyName System.Drawing

function New-DemoScreen {
    param([string]$Path, [string]$Heading, [array]$Rows)
    $w = 1920; $h = 1080
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $headingFont = New-Object System.Drawing.Font 'Arial', 40, ([System.Drawing.FontStyle]::Bold)
    $rowFont = New-Object System.Drawing.Font 'Arial', 80, ([System.Drawing.FontStyle]::Bold)
    $black = [System.Drawing.Brushes]::Black
    $grey = [System.Drawing.Brushes]::Gray

    $g.DrawString($Heading, $headingFont, $grey, 100, 60)

    $y = 220
    foreach ($r in $Rows) {
        $g.DrawString($r[0], $rowFont, $black, 100, $y)
        if ($r[1] -ne '') { $g.DrawString($r[1], $rowFont, $black, 750, $y) }
        $y += 200
    }

    # Thin border a fixed distance from the true edge, so the crop UI's
    # trim sliders have a visible target to align against.
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::LightGray), 2
    $g.DrawRectangle($pen, 40, 40, $w - 80, $h - 80)

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "wrote $Path"
}

# Matches Breadboard_Bill_of_Materials.pdf (BB-01, Assembly A) exactly:
# bare-digit positions (NOT "P1" style -- the real document doesn't use that),
# positions 1/2/3 populated with NE555/7805/LM358, position 4 a real spare
# slot with nothing specified. The tamper scenario puts an unauthorised part
# in that spare slot, which is exactly what "unexpected" means for this board.

# --- Scenario A: everything matches (rehearse the success state) ---
New-DemoScreen -Path "$PSScriptRoot\demo_spec_A.png" -Heading 'SPECIFICATION - BB-01 Assembly A' -Rows @(
    @('1', 'NE555'), @('2', '7805'), @('3', 'LM358'))
New-DemoScreen -Path "$PSScriptRoot\demo_assembly_A_match.png" -Heading 'ASSEMBLY' -Rows @(
    @('1', 'NE555'), @('2', '7805'), @('3', 'LM358'))

# --- Scenario B: three discrepancy types at once (the tamper demo) ---
# vs spec A: position 2 swapped (mismatch), position 3 removed (missing),
# the spare position 4 populated without authorisation (unexpected).
New-DemoScreen -Path "$PSScriptRoot\demo_assembly_B_tampered.png" -Heading 'ASSEMBLY (TAMPERED)' -Rows @(
    @('1', 'NE555'), @('2', 'LM358'), @('4', 'NE555'))

Write-Output ''
Write-Output 'Expected results:'
Write-Output '  Scenario A (demo_spec_A + demo_assembly_A_match): MATCH, zero discrepancies'
Write-Output '  Scenario B (demo_spec_A + demo_assembly_B_tampered): 3 discrepancies -'
Write-Output '    2 mismatched (7805 -> LM358), 3 missing (LM358), 4 unexpected (NE555)'
