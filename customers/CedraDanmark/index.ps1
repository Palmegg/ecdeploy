<#
    CedraDanmark — customer bootstrap, served at cdr.palme3.dk.

        irm cdr.palme3.dk | iex

    Downloads the shared ecDeploy.ps1 and launches it in CedraDeploy mode:
      - normal launch  -> CedraStandard flow (anti-sleep + Windows Update, GRS @45 min, restart @90 min)
      - resume (the next-logon scheduled task sets $env:ECDEPLOY_RESUME=1)
                       -> CedraResume flow (anti-sleep only + Windows Update)
#>

$ErrorActionPreference = 'Stop'

# ecDeploy.ps1 is shared across customers — pull it from the main host (public first, internal fallback).
$hosts  = @('https://ecd.qwe.dk', 'http://ecd.palme3.dk')
$target = Join-Path $env:TEMP 'ecDeploy.ps1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ok = $false
foreach ($h in $hosts) {
    try { Invoke-WebRequest -Uri "$h/ecDeploy.ps1" -OutFile $target -UseBasicParsing -TimeoutSec 20; $ok = $true; break } catch { }
}
if (-not $ok) { Write-Host 'Kunne ikke hente ecDeploy.' -ForegroundColor Red; return }

$flow = if ($env:ECDEPLOY_RESUME) { 'CedraResume' } else { 'CedraStandard' }
$psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
            '-File', "`"$target`"", '-Customer', 'CedraDanmark', '-Flow', $flow)
Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs
