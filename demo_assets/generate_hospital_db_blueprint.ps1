# Generates a hospital distribution-board schedule ("blueprint") sized for a
# laptop screen, to be displayed full-screen and photographed with the phone
# camera as the SPECIFICATION side of a verification run.
#
# Layout follows the rules already proven on-device three times over (spec
# sheet, breadboard label panel, MCB label panel):
#   - bare-digit position column at a fixed left margin
#   - rating column at a fixed wide offset, so position and rating always
#     arrive as two separate OCR blocks rather than one merged one
#   - bold black on white, generous row spacing so rows never merge
#   - a thin border frame near the true edge, giving the app's crop sliders
#     a visible target to trim to
#
# The CIRCUIT DESCRIPTION column is deliberately included even though the
# parser does not use it: a real board schedule has one, and parser.dart
# correctly routes any third block in a row to ParseResult.ignoredNoise
# rather than corrupting the component field (pinned by the "real BOM table
# parses correctly, including the DESCRIPTION column as noise" test). Seeing
# the app report "N ignored as noise" while still reading every rating
# correctly is a good thing to show, not a defect.

Add-Type -AssemblyName System.Drawing

function New-HospitalDbBlueprint {
    param([string]$Path, [array]$Rows)

    $w = 1600
    $rowGap = 165
    $rowsTop = 330
    $h = $rowsTop + ($Rows.Count * $rowGap) + 150

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)

    $titleFont   = New-Object System.Drawing.Font 'Arial', 40, ([System.Drawing.FontStyle]::Bold)
    $subFont     = New-Object System.Drawing.Font 'Arial', 26, ([System.Drawing.FontStyle]::Regular)
    $colHeadFont = New-Object System.Drawing.Font 'Arial', 24, ([System.Drawing.FontStyle]::Bold)
    $rowFont     = New-Object System.Drawing.Font 'Arial', 62, ([System.Drawing.FontStyle]::Bold)
    $descFont    = New-Object System.Drawing.Font 'Arial', 44, ([System.Drawing.FontStyle]::Regular)
    $footFont    = New-Object System.Drawing.Font 'Arial', 22, ([System.Drawing.FontStyle]::Regular)

    $black = [System.Drawing.Brushes]::Black
    $grey  = [System.Drawing.Brushes]::Gray
    $rule  = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 3

    # Column x-positions. The 280px gap between position and rating is what
    # keeps them separate OCR blocks; the description sits further right again.
    $xPos  = 110
    $xRate = 390
    $xDesc = 760

    # --- Title block -------------------------------------------------------
    # Separators are plain ASCII on purpose: a middle-dot written into this
    # .ps1 renders as "Â·" when PowerShell reads the file as ANSI rather than
    # UTF-8, which showed up as visible mojibake on the first generated sheet.
    $g.DrawString('DISTRIBUTION BOARD SCHEDULE', $titleFont, $black, 100, 80)
    $g.DrawString('DB-HOSP-03  |  Ward Block B, Level 2  |  240/415V  |  TP&N', $subFont, $grey, 100, 145)
    $g.DrawLine($rule, 100, 205, $w - 100, 205)

    # --- Column headers ----------------------------------------------------
    $g.DrawString('POS', $colHeadFont, $grey, $xPos, 245)
    $g.DrawString('RATING', $colHeadFont, $grey, $xRate, 245)
    $g.DrawString('CIRCUIT DESCRIPTION', $colHeadFont, $grey, $xDesc, 245)

    # --- Rows --------------------------------------------------------------
    $y = $rowsTop
    foreach ($r in $Rows) {
        $g.DrawString($r[0], $rowFont, $black, $xPos, $y)
        $g.DrawString($r[1], $rowFont, $black, $xRate, $y)
        # Description sits slightly lower so its smaller cap-height still
        # centres against the big rating text on the same row.
        $g.DrawString($r[2], $descFont, $black, $xDesc, ($y + 14))
        $y += $rowGap
    }

    # --- Footer ------------------------------------------------------------
    $g.DrawLine($rule, 100, ($h - 120), $w - 100, ($h - 120))
    $g.DrawString('This schedule must remain with the board for inspection.   Team RTI Paradox', $footFont, $grey, 100, ($h - 100))

    # Crop target
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::LightGray), 2
    $g.DrawRectangle($pen, 40, 40, $w - 80, $h - 80)

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "wrote $Path ($w x $h)"
}

# A realistic small hospital ward-block board: a main incomer, then clinical
# loads descending by current rating. Ratings are real IEC 60898 curve-C
# codes, which is what parser.dart's breaker-rating fallback recognises.
$rows = @(
    , @('1', 'C63', 'MAIN INCOMER')
    , @('2', 'C32', 'OPERATING THEATRE 1')
    , @('3', 'C32', 'ICU BED BAY 1-4')
    , @('4', 'C20', 'X-RAY IMAGING')
    , @('5', 'C16', 'VENTILATOR SUPPLY')
    , @('6', 'C16', 'NURSE CALL SYSTEM')
    , @('7', 'C10', 'CORRIDOR LIGHTING')
    , @('8', 'C6',  'EMERGENCY LIGHTING')
)

New-HospitalDbBlueprint -Path "$PSScriptRoot\demo_spec_hospital_db.png" -Rows $rows

Write-Output ''
Write-Output 'Expected parse: 8 rows, positions 1-8, ratings C63/C32/C32/C20/C16/C16/C10/C6'
Write-Output 'The CIRCUIT DESCRIPTION column is expected to land in ignoredNoise.'
