<#
    index.ps1 — served at https://ecd.qwe.dk/  (primary entry point)

    Usage by the technician on a freshly deployed machine:
        irm ecd.qwe.dk | iex

    Pulls the real app to disk (so it can self-elevate / run STA) and launches it.
    Keep this tiny — it's piped straight into iex.
#>

$ErrorActionPreference = 'Stop'
$base   = 'https://ecd.qwe.dk'
$target = Join-Path $env:TEMP 'ecDeploy.ps1'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "$base/ecDeploy.ps1" -OutFile $target -UseBasicParsing
} catch {
    Write-Host "Kunne ikke hente ecDeploy: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Launch STA so WPF works; ecDeploy.ps1 self-elevates from there (one UAC prompt).
Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$target`"")
