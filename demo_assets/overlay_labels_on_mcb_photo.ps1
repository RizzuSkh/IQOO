# Uses the real Havells SPN distribution-board photo the team supplied
# (demo_assets/source_mcb_panel_photo.png, converted from the original .webp
# via PowerShell's WPF/WIC decoder -- GDI+'s System.Drawing cannot open WebP
# directly and throws a generic "Out of memory" error for it) and appends a
# clean label panel below it, exactly like overlay_labels_on_breadboard.ps1
# did for the breadboard photo.
#
# Why a label panel instead of trying to OCR the board's own print: every
# breaker on this board is printed "C 32" / "10000 3" / "DHMGCSPF032" at a
# size that reads fine in a product photo but would not survive being
# photographed off a laptop screen from arm's length -- exactly the
# small-print problem PRD section 19 warns about. The panel makes the
# demo's OCR target reliable by construction while the real photo above it
# still proves this is a genuine physical board, not a generated one.
#
# Honesty note (same class of limitation as the breadboard "realistic" set):
# only one photograph of this board exists, so the match and tampered demos
# reuse the identical photo with different label panels underneath. All five
# single-pole breakers are genuinely printed "C 32" in the photo -- the
# tampered scenario's mismatched rating for position 2 is a claimed value
# that isn't literally printed at readable size anywhere in the photo, the
# same tension already documented for the breadboard's illustrative set. For
# a live tamper demo where a judge should see the change, either physically
# alter a real board between two photographs, or use the fully-illustrated
# demo_assembly_mcb_tampered.png (generate_mcb_demo.ps1), which is drawn from
# scratch precisely so it CAN show a visibly different state.

Add-Type -AssemblyName System.Drawing

$sourcePath = "$PSScriptRoot\source_mcb_panel_photo.png"

function New-LabeledMcbPhoto {
    param([string]$OutPath, [string]$Heading, [array]$Rows)

    $photo = [System.Drawing.Image]::FromFile($sourcePath)
    $photoWidth = $photo.Width
    $photoHeight = $photo.Height
    $panelHeight = 140 + ($Rows.Count * 170)
    $canvas = New-Object System.Drawing.Bitmap $photoWidth, ($photoHeight + $panelHeight)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($photo, 0, 0, $photoWidth, $photoHeight)
    $photo.Dispose()

    $headingFont = New-Object System.Drawing.Font 'Arial', 30, ([System.Drawing.FontStyle]::Bold)
    $rowFont = New-Object System.Drawing.Font 'Arial', 62, ([System.Drawing.FontStyle]::Bold)
    $black = [System.Drawing.Brushes]::Black
    $grey = [System.Drawing.Brushes]::Gray

    $panelTop = $photoHeight
    $g.DrawString($Heading, $headingFont, $grey, 70, $panelTop + 25)

    $y = $panelTop + 100
    foreach ($r in $Rows) {
        $g.DrawString($r[0], $rowFont, $black, 90, $y)
        if ($r[1] -ne '') { $g.DrawString($r[1], $rowFont, $black, 380, $y) }
        $y += 170
    }

    $g.Dispose()
    $canvas.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    Write-Output "wrote $OutPath"
}

# Matches what's actually printed on the board: five C32 single-pole
# breakers, plus the double-pole main isolator (no numeric rating is
# printed on it in the photo, so none is claimed here).
$matchRows = @(
    , @('1', 'C32')
    , @('2', 'C32')
    , @('3', 'C32')
    , @('4', 'C32')
    , @('5', 'C32')
    , @('6', 'DP')
)
New-LabeledMcbPhoto -OutPath "$PSScriptRoot\demo_assembly_mcb_real_match.png" -Heading 'ASSEMBLY - DB-01 (photographed)' -Rows $matchRows

# Tampered: position 2 mismatched, position 4 missing (row omitted),
# position 7 an unauthorised extra entry (unexpected).
$tamperedRows = @(
    , @('1', 'C32')
    , @('2', 'C16')
    , @('3', 'C32')
    , @('5', 'C32')
    , @('6', 'DP')
    , @('7', 'C32')
)
New-LabeledMcbPhoto -OutPath "$PSScriptRoot\demo_assembly_mcb_real_tampered.png" -Heading 'ASSEMBLY - DB-01 (photographed, TAMPERED)' -Rows $tamperedRows

# Matching spec sheet (plain label sheet, no photo -- this is the printed
# document, not the physical board).
function New-SpecSheet {
    param([string]$OutPath, [string]$Heading, [array]$Rows)
    $w = 1200; $h = 220 + ($Rows.Count * 190)
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)
    $headingFont = New-Object System.Drawing.Font 'Arial', 34, ([System.Drawing.FontStyle]::Bold)
    $rowFont = New-Object System.Drawing.Font 'Arial', 70, ([System.Drawing.FontStyle]::Bold)
    $black = [System.Drawing.Brushes]::Black
    $grey = [System.Drawing.Brushes]::Gray
    $g.DrawString($Heading, $headingFont, $grey, 70, 40)
    $y = 180
    foreach ($r in $Rows) {
        $g.DrawString($r[0], $rowFont, $black, 90, $y)
        if ($r[1] -ne '') { $g.DrawString($r[1], $rowFont, $black, 380, $y) }
        $y += 190
    }
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::LightGray), 2
    $g.DrawRectangle($pen, 30, 30, $w - 60, $h - 60)
    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "wrote $OutPath"
}
New-SpecSheet -OutPath "$PSScriptRoot\demo_spec_mcb_real.png" -Heading 'SPECIFICATION - DB-01 (Havells SPN)' -Rows $matchRows

Write-Output ''
Write-Output 'Expected results:'
Write-Output '  Match (demo_spec_mcb_real + demo_assembly_mcb_real_match): MATCH, zero discrepancies'
Write-Output '  Tampered (demo_spec_mcb_real + demo_assembly_mcb_real_tampered): 3 discrepancies -'
Write-Output '    2 mismatched (C32 -> C16), 4 missing (C32), 7 unexpected (C32)'
