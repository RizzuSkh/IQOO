Add-Type -AssemblyName System.Drawing
function New-LabelImage {
  param([string]$Path, [array]$Rows)
  $w = 1200; $h = 1600
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::White)
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $font = New-Object System.Drawing.Font 'Arial', 90, ([System.Drawing.FontStyle]::Bold)
  $black = [System.Drawing.Brushes]::Black
  $y = 220
  foreach ($r in $Rows) {
    $g.DrawString($r[0], $font, $black, 90, $y)
    if ($r[1] -ne '') { $g.DrawString($r[1], $font, $black, 700, $y) }
    $y += 330
  }
  $g.Dispose()
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "wrote $Path"
}
New-LabelImage -Path 'D:\tmp_flutter\parity_spec.png' -Rows @(
  @('P1','NE555'), @('P2','7805'), @('P3','LM358'))
New-LabelImage -Path 'D:\tmp_flutter\parity_assembly.png' -Rows @(
  @('P1','NE555'), @('P2','LM358'), @('P4','NE555'))
