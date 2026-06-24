<#
    make-cedra-icon.ps1 — generate the CedraDeploy (CedraDanmark) app icon and print its base64.
    Paste the base64 into the CedraDanmark entry of $script:Customers in ecDeploy.ps1.
#>
Add-Type -AssemblyName System.Drawing

$size = 256
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::Transparent)

function New-RoundedRect($x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$pad = 14
$path = New-RoundedRect $pad $pad ($size - 2*$pad) ($size - 2*$pad) 52
$rect = [System.Drawing.Rectangle]::new($pad, $pad, $size - 2*$pad, $size - 2*$pad)

$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, `
    [System.Drawing.ColorTranslator]::FromHtml('#0E2A2A'), `
    [System.Drawing.ColorTranslator]::FromHtml('#0B1418'), 90)
$g.FillPath($bg, $path)

$accent = [System.Drawing.ColorTranslator]::FromHtml('#14B8A6')   # Cedra teal
$pen = New-Object System.Drawing.Pen($accent, 9)
$g.DrawPath($pen, $path)

# Bold "C" monogram
$font = New-Object System.Drawing.Font('Segoe UI', 150, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$brush = New-Object System.Drawing.SolidBrush($accent)
$g.DrawString('C', $font, $brush, [System.Drawing.RectangleF]::new(0, -6, $size, $size), $sf)
$g.Dispose()

$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$b64 = [Convert]::ToBase64String($ms.ToArray())
$bmp.Save((Join-Path $PSScriptRoot '_cedra_preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot '_cedra.b64'), $b64)
Write-Host ("Cedra icon: {0} base64 chars (preview: tools\_cedra_preview.png)" -f $b64.Length)
