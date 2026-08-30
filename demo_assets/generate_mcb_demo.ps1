# Generates an MCB (Miniature Circuit Breaker) distribution-board demo pair:
# a blueprint/specification sheet and an illustrated panel with position
# labels baked in from the start.
#
# Why illustrated rather than a photo: a real photo of an MCB panel (like the
# Havells board photo shared in chat) has the same problem the breadboard
# photo had — current ratings are printed in tiny text directly on each
# switch, with no separate position label anywhere, and reusing someone
# else's product photo risks showing text that doesn't match whatever rating
# we'd need to overlay (exactly the NE555-vs-7805 mismatch caught last time).
# Drawing the panel ourselves means the labels are correct by construction
# and large enough to photograph reliably off a laptop screen.
#
# Same layout rules that are now proven reliable three times over (spec
# sheet, breadboard label panel): bold black-on-white, positions stacked
# vertically with a real gap between rows, wide column gap between position
# and rating so they always arrive as separate OCR blocks.

Add-Type -AssemblyName System.Drawing

function Draw-Panel {
    param($g, [int]$PanelTop, [int]$Width)
    $panelH = 520
    $bodyColor = [System.Drawing.Color]::FromArgb(255, 235, 235, 238)
    $bodyBrush = New-Object System.Drawing.SolidBrush $bodyColor
    $border = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 90, 90, 95)), 4
    $g.FillRectangle($bodyBrush, 60, $PanelTop, $Width - 120, $panelH)
    $g.DrawRectangle($border, 60, $PanelTop, $Width - 120, $panelH)

    # Din-rail strip
    $railBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 200, 200, 205))
    $g.FillRectangle($railBrush, 90, ($PanelTop + 90), ($Width - 180), 30)

    # 5 breaker switches, evenly spaced
    $switchW = 110
    $switchH = 220
    $switchY = $PanelTop + 150
    $gap = (($Width - 180) - (5 * $switchW)) / 4
    $switchBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 40, 40, 45))
    $toggleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 210, 30, 30))
    for ($i = 0; $i -lt 5; $i++) {
        $x = 90 + $i * ($switchW + $gap)
        $g.FillRectangle($switchBrush, $x, $switchY, $switchW, $switchH)
        $g.FillRectangle($toggleBrush, ($x + $switchW/2 - 14), ($switchY + 20), 28, 60)
    }
    return $PanelTop + $panelH
}

function New-McbSheet {
    param([string]$Path, [string]$Heading, [array]$Rows, [bool]$DrawPanelGraphic)

    $w = 1400
    $panelTop = 100
    $panelBottomPad = 40
    $rowsTop = if ($DrawPanelGraphic) { 700 } else { 220 }
    $h = $rowsTop + 120 + ($Rows.Count * 190) + 60

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)

    $headingFont = New-Object System.Drawing.Font 'Arial', 34, ([System.Drawing.FontStyle]::Bold)
    $rowFont = New-Object System.Drawing.Font 'Arial', 62, ([System.Drawing.FontStyle]::Bold)
    $black = [System.Drawing.Brushes]::Black
    $grey = [System.Drawing.Brushes]::Gray

    $g.DrawString($Heading, $headingFont, $grey, 60, 20)

    if ($DrawPanelGraphic) {
        Draw-Panel -g $g -PanelTop $panelTop -Width $w | Out-Null
        $labelHeadingFont = New-Object System.Drawing.Font 'Arial', 28, ([System.Drawing.FontStyle]::Bold)
        $g.DrawString('POSITION LABELS', $labelHeadingFont, $grey, 60, ($rowsTop - 50))
    }

    $y = $rowsTop
    foreach ($r in $Rows) {
        $g.DrawString($r[0], $rowFont, $black, 90, $y)
        if ($r[1] -ne '') { $g.DrawString($r[1], $rowFont, $black, 420, $y) }
        $y += 190
    }

    # Border frame near the true edge, so the crop UI has a visible target.
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::LightGray), 2
    $g.DrawRectangle($pen, 30, 30, $w - 60, $h - 60)

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "wrote $Path ($w x $h)"
}

# Realistic 5-way distribution board, positions 1-5.
$specRows = @(
    , @('1', '32A')
    , @('2', '20A')
    , @('3', '16A')
    , @('4', '6A')
    , @('5', '32A')
)
New-McbSheet -Path "$PSScriptRoot\demo_spec_mcb.png" -Heading 'SPECIFICATION - MCB PANEL DB-01' -Rows $specRows -DrawPanelGraphic $false

# Matching assembly: identical ratings -> MATCH.
New-McbSheet -Path "$PSScriptRoot\demo_assembly_mcb_match.png" -Heading 'ASSEMBLY - MCB PANEL' -Rows $specRows -DrawPanelGraphic $true

# Tampered assembly: position 2 mismatched (20A -> 16A), position 4 missing,
# position 6 an unauthorised extra breaker added to a spare slot.
$tamperedRows = @(
    , @('1', '32A')
    , @('2', '16A')
    , @('3', '16A')
    , @('5', '32A')
    , @('6', '20A')
)
New-McbSheet -Path "$PSScriptRoot\demo_assembly_mcb_tampered.png" -Heading 'ASSEMBLY - MCB PANEL (TAMPERED)' -Rows $tamperedRows -DrawPanelGraphic $true

Write-Output ''
Write-Output 'Expected results:'
Write-Output '  Match scenario (demo_spec_mcb + demo_assembly_mcb_match): MATCH, zero discrepancies'
Write-Output '  Tampered scenario (demo_spec_mcb + demo_assembly_mcb_tampered): 3 discrepancies -'
Write-Output '    2 mismatched (20A -> 16A), 4 missing (6A), 6 unexpected (20A)'
