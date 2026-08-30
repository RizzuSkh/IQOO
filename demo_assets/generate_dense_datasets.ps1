# Generates the LARGE, dense specification sheets that broke the app during
# mentor evaluation: a 20-circuit hospital distribution board and a 12-item
# school equipment inventory, each with a spec sheet and a tampered assembly
# counterpart.
#
# These exist specifically to be the hard case. The earlier demo sheets were
# 3-8 sparse rows, which OCR happened to return as one text block per row.
# A dense sheet is returned as a couple of large blocks containing many
# lines, which is what exposed the block-vs-line bug in ocr.dart. Keeping
# real dense datasets in the repo means that regression stays testable
# against something realistic rather than only against synthetic fixtures.
#
# Layout still follows the rules that make OCR reliable — bare-digit position
# column at a fixed left margin, component column at a fixed wide offset,
# bold black on white, a border frame for the crop sliders — but with tighter
# row spacing and many more rows, which is the honest shape of a real
# schedule.

Add-Type -AssemblyName System.Drawing

function New-DenseSheet {
    param(
        [string]$Path,
        [string]$Title,
        [string]$Subtitle,
        [string]$ColB,
        [string]$ColC,
        [array]$Rows
    )

    $w = 1700
    $rowGap = 96
    $rowsTop = 300
    $h = $rowsTop + ($Rows.Count * $rowGap) + 130

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)

    $titleFont   = New-Object System.Drawing.Font 'Arial', 36, ([System.Drawing.FontStyle]::Bold)
    $subFont     = New-Object System.Drawing.Font 'Arial', 22, ([System.Drawing.FontStyle]::Regular)
    $colHeadFont = New-Object System.Drawing.Font 'Arial', 20, ([System.Drawing.FontStyle]::Bold)
    $rowFont     = New-Object System.Drawing.Font 'Arial', 40, ([System.Drawing.FontStyle]::Bold)
    $descFont    = New-Object System.Drawing.Font 'Arial', 30, ([System.Drawing.FontStyle]::Regular)

    $black = [System.Drawing.Brushes]::Black
    $grey  = [System.Drawing.Brushes]::Gray
    $rule  = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 3

    $xPos  = 100
    $xComp = 300
    $xDesc = 780

    $g.DrawString($Title, $titleFont, $black, 90, 70)
    $g.DrawString($Subtitle, $subFont, $grey, 90, 128)
    $g.DrawLine($rule, 90, 185, $w - 90, 185)

    $g.DrawString('POS', $colHeadFont, $grey, $xPos, 225)
    $g.DrawString($ColB, $colHeadFont, $grey, $xComp, 225)
    $g.DrawString($ColC, $colHeadFont, $grey, $xDesc, 225)

    $y = $rowsTop
    foreach ($r in $Rows) {
        $g.DrawString($r[0], $rowFont, $black, $xPos, $y)
        $g.DrawString($r[1], $rowFont, $black, $xComp, $y)
        $g.DrawString($r[2], $descFont, $black, $xDesc, ($y + 9))
        $y += $rowGap
    }

    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::LightGray), 2
    $g.DrawRectangle($pen, 36, 36, $w - 72, $h - 72)

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "wrote $Path ($w x $h, $($Rows.Count) rows)"
}

# ---------------------------------------------------------------------------
# Hospital: 20-circuit ward-block distribution board.
# ---------------------------------------------------------------------------
$hospital = @(
    , @('1',  'C63', 'MAIN INCOMER')
    , @('2',  'C32', 'OPERATING THEATRE 1')
    , @('3',  'C32', 'OPERATING THEATRE 2')
    , @('4',  'C32', 'ICU BED BAY 1-4')
    , @('5',  'C32', 'ICU BED BAY 5-8')
    , @('6',  'C20', 'X-RAY IMAGING')
    , @('7',  'C20', 'CT SCANNER ANTEROOM')
    , @('8',  'C20', 'DIALYSIS UNIT')
    , @('9',  'C16', 'VENTILATOR SUPPLY A')
    , @('10', 'C16', 'VENTILATOR SUPPLY B')
    , @('11', 'C16', 'NURSE CALL SYSTEM')
    , @('12', 'C16', 'PHARMACY REFRIGERATION')
    , @('13', 'C16', 'PATHOLOGY LAB SOCKETS')
    , @('14', 'C10', 'CORRIDOR LIGHTING EAST')
    , @('15', 'C10', 'CORRIDOR LIGHTING WEST')
    , @('16', 'C10', 'WARD LIGHTING LEVEL 2')
    , @('17', 'C10', 'STAFF ROOM SOCKETS')
    , @('18', 'C6',  'EMERGENCY LIGHTING')
    , @('19', 'C6',  'FIRE ALARM PANEL')
    , @('20', 'C6',  'EXIT SIGN CIRCUIT')
)
New-DenseSheet -Path "$PSScriptRoot\dense_spec_hospital.png" `
    -Title 'DISTRIBUTION BOARD SCHEDULE' `
    -Subtitle 'DB-HOSP-03  |  Ward Block B, Level 2  |  240/415V  |  20 CIRCUITS' `
    -ColB 'RATING' -ColC 'CIRCUIT DESCRIPTION' -Rows $hospital

# Tampered: 3 downrated (C32 -> C16), 8 removed entirely, 21 added.
$hospitalTampered = @()
foreach ($r in $hospital) {
    if ($r[0] -eq '8') { continue }
    if ($r[0] -eq '3') { $hospitalTampered += , @('3', 'C16', 'OPERATING THEATRE 2'); continue }
    $hospitalTampered += , $r
}
$hospitalTampered += , @('21', 'C32', 'UNLOGGED CIRCUIT')
New-DenseSheet -Path "$PSScriptRoot\dense_assembly_hospital_tampered.png" `
    -Title 'AS-INSTALLED SURVEY' `
    -Subtitle 'DB-HOSP-03  |  Ward Block B, Level 2  |  FIELD RECORD' `
    -ColB 'RATING' -ColC 'CIRCUIT DESCRIPTION' -Rows $hospitalTampered

# ---------------------------------------------------------------------------
# School: 12-item IT equipment inventory. Different domain, different
# component format (hyphenated part codes, no breaker ratings at all).
# ---------------------------------------------------------------------------
$school = @(
    , @('1',  'PROJECTOR-EPSON', 'LAB A')
    , @('2',  'SWITCH-CISCO2960', 'SERVER RACK')
    , @('3',  'UPS-APC1500', 'SERVER RACK')
    , @('4',  'PRINTER-HPM404', 'STAFF ROOM')
    , @('5',  'ROUTER-TPLINK', 'LAB B')
    , @('6',  'MONITOR-DELL', 'LAB B')
    , @('7',  'AP-UBIQUITI', 'CORRIDOR')
    , @('8',  'NAS-SYNOLOGY', 'SERVER RACK')
    , @('9',  'SCANNER-CANON', 'LIBRARY')
    , @('10', 'SPEAKER-JBL', 'MAIN HALL')
    , @('11', 'CAMERA-HIKVISION', 'ENTRANCE')
    , @('12', 'LAPTOP-LENOVO', 'STAFF ROOM')
)
New-DenseSheet -Path "$PSScriptRoot\dense_spec_school.png" `
    -Title 'IT EQUIPMENT INVENTORY' `
    -Subtitle 'SCH-BLOCK-C  |  Annual Audit  |  12 ITEMS' `
    -ColB 'ASSET' -ColC 'LOCATION' -Rows $school

# Tampered: 5 swapped, 9 removed, 13 added.
$schoolTampered = @()
foreach ($r in $school) {
    if ($r[0] -eq '9') { continue }
    if ($r[0] -eq '5') { $schoolTampered += , @('5', 'ROUTER-NETGEAR', 'LAB B'); continue }
    $schoolTampered += , $r
}
$schoolTampered += , @('13', 'TABLET-SAMSUNG', 'LAB A')
New-DenseSheet -Path "$PSScriptRoot\dense_assembly_school_tampered.png" `
    -Title 'PHYSICAL AUDIT RECORD' `
    -Subtitle 'SCH-BLOCK-C  |  Annual Audit  |  FIELD RECORD' `
    -ColB 'ASSET' -ColC 'LOCATION' -Rows $schoolTampered

Write-Output ''
Write-Output 'Expected results:'
Write-Output '  Hospital (dense_spec_hospital + dense_assembly_hospital_tampered):'
Write-Output '    3 discrepancies - 3 mismatched (C32->C16), 8 missing (C20), 21 unexpected (C32)'
Write-Output '  School (dense_spec_school + dense_assembly_school_tampered):'
Write-Output '    3 discrepancies - 5 mismatched, 9 missing, 13 unexpected'
