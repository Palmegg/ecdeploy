<#
    make-icon.ps1 — generate the ecDeploy app icon and embed it into ecDeploy.ps1.

    Draws a lightning bolt on a dark rounded square (matches the app theme), then injects the
    base64 PNG into the `$script:LogoB64 = '...'` line in ../ecDeploy.ps1 (preserving its BOM).
    Run this whenever you want to change the icon (edit the colours/shape below, then run).

        powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-icon.ps1
#>
Add-Type -AssemblyName System.Drawing

$size = 256
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
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
    [System.Drawing.ColorTranslator]::FromHtml('#242730'), `
    [System.Drawing.ColorTranslator]::FromHtml('#141519'), 90)
$g.FillPath($bg, $path)

$pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#3B82F6'), 9)
$g.DrawPath($pen, $path)

$accent = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#3B82F6'))
$pts = @(
    [System.Drawing.PointF]::new(150, 58),
    [System.Drawing.PointF]::new(86,  148),
    [System.Drawing.PointF]::new(122, 148),
    [System.Drawing.PointF]::new(104, 210),
    [System.Drawing.PointF]::new(176, 112),
    [System.Drawing.PointF]::new(138, 112),
    [System.Drawing.PointF]::new(160, 58)
)
$g.FillPolygon($accent, $pts)
$g.Dispose()

$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$b64 = [Convert]::ToBase64String($ms.ToArray())

# Inject into ../ecDeploy.ps1, preserving its UTF-8 BOM.
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'ecDeploy.ps1'
$code = [System.IO.File]::ReadAllText($target)
$new = [System.Text.RegularExpressions.Regex]::Replace($code, "(?m)^\`$script:LogoB64 = '.*'$", "`$script:LogoB64 = '$b64'")
[System.IO.File]::WriteAllText($target, $new, (New-Object System.Text.UTF8Encoding($true)))

Write-Host ("Icon embedded into {0} ({1} base64 chars)" -f $target, $b64.Length)
