<#
    index.ps1 — bootstrapper, served at the site root (primary entry point).

    Usage by the technician on a freshly deployed machine:
        irm ecd.qwe.dk    | iex     (public)
        irm ecd.palme3.dk | iex     (internal mirror)

    Pulls the real app to disk (so it can self-elevate / run STA) and launches it.
    Keep this tiny — it's piped straight into iex.
#>

$ErrorActionPreference = 'Stop'

# Download ecDeploy.ps1 from whichever host is reachable — public first, internal http fallback —
# so the same one-liner works from either entry point.
$hosts  = @('https://ecd.qwe.dk', 'http://ecd.palme3.dk')
$target = Join-Path $env:TEMP 'ecDeploy.ps1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ok = $false
foreach ($h in $hosts) {
    try {
        Invoke-WebRequest -Uri "$h/ecDeploy.ps1" -OutFile $target -UseBasicParsing -TimeoutSec 20
        $ok = $true
        break
    } catch { }
}
if (-not $ok) {
    Write-Host "Kunne ikke hente ecDeploy fra nogen kendt host." -ForegroundColor Red
    return
}

# Launch STA so WPF works; ecDeploy.ps1 self-elevates from there (one UAC prompt).
# -WindowStyle Hidden keeps the host console invisible — only the WPF UI should show.
Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$target`"")
