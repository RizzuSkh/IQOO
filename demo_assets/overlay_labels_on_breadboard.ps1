# Takes the user's realistic AI-generated breadboard photo and appends a
# clean label panel below it with real P1/P2/P3 position labels, stacked
# vertically like the working generate_demo_screens.ps1 sheets.
#
# Why not overlay labels directly on the photo, side by side: a first attempt
# placed three label boxes touching edge-to-edge in one horizontal strip.
# Same Y for all three means the parser's row-grouping treats them as one row,
# and edge-to-edge boxes risk ML Kit merging them into a single OCR block
# spanning "P1 NE555 P2 LM358 P3 LM393" -- which fails ^P\d+$ entirely and
# reproduces the exact "no valid labels found" bug this is meant to fix.
# Stacking rows vertically with a real gap (like a printed spec sheet) is the
# layout already proven to parse correctly.
#
# The photo alone has no position labels anywhere (only each chip's own tiny
# etched part code), which is why the ORIGINAL image reported "no valid labels
# found" no matter how tightly it was cropped -- nothing in it matches ^P\d+$.
#
# Source: Downloads\based\ChatGPT Image Aug 29, 2026, 11_54_02 PM.png (1536x1024)

Add-Type -AssemblyName System.Drawing

$sourcePath = 'C:\Users\91740\Downloads\based\ChatGPT Image Aug 29, 2026, 11_54_02 PM.png'

function New-LabeledBreadboard {
    param([string]$OutPath, [array]$Rows)  # each row: @(position, component-or-'')

    $photo = [System.Drawing.Image]::FromFile($sourcePath)
    $photoWidth = $photo.Width
    $photoHeight = $photo.Height
    $panelHeight = 140 + ($Rows.Count * 180)
    $canvas = New-Object System.Drawing.Bitmap $photoWidth, ($photoHeight + $panelHeight)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($photo, 0, 0, $photoWidth, $photoHeight)
    $photo.Dispose()

    $headingFont = New-Object System.Drawing.Font 'Arial', 32, ([System.Drawing.FontStyle]::Bold)
    $rowFont = New-Object System.Drawing.Font 'Arial', 70, ([System.Drawing.FontStyle]::Bold)
    $black = [System.Drawing.Brushes]::Black
    $grey = [System.Drawing.Brushes]::Gray

    $panelTop = $photoHeight
    $g.DrawString('ASSEMBLY - position labels', $headingFont, $grey, 80, $panelTop + 30)

    $y = $panelTop + 110
    foreach ($r in $Rows) {
        $g.DrawString($r[0], $rowFont, $black, 100, $y)
        if ($r[1] -ne '') { $g.DrawString($r[1], $rowFont, $black, 550, $y) }
        $y += 180
    }

    $g.Dispose()
    $canvas.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    Write-Output "wrote $OutPath"
}

# Matching assembly: all three components exactly as printed on the chips
# (suffix letters dropped to keep them simple, consistent OCR targets).
New-LabeledBreadboard -OutPath "$PSScriptRoot\demo_assembly_realistic_match.png" -Rows @(
    , @('P1', 'NE555')
    , @('P2', 'LM358')
    , @('P3', 'LM393')
)

# Tampered assembly: P2 mismatched (reads NE555 instead of LM358), P3 missing
# entirely (row omitted) -- same tamper story as demo_assets/demo_assembly_B.
New-LabeledBreadboard -OutPath "$PSScriptRoot\demo_assembly_realistic_tampered.png" -Rows @(
    , @('P1', 'NE555')
    , @('P2', 'NE555')
)

Write-Output ''
Write-Output 'Matching spec: demo_spec_realistic.png (P1 NE555, P2 LM358, P3 LM393)'
