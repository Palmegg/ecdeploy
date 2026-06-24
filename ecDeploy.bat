@echo off
setlocal

:: ecDeploy fallback launcher. Primary entry is:  irm ecd.qwe.dk | iex
:: This .bat keeps SpeedTune's offline guard for machines that aren't online yet.

:: Vi bruger CloudFlare til at teste internetforbindelsen.
ping -n 1 1.1.1.1 >nul
if errorlevel 1 (
    echo Ingen internetforbindelse fundet. Programmet lukker.
    msg * "Ingen internetforbindelse fundet. Programmet lukker."
    goto :end
)

echo Internetforbindelse fundet.
echo Henter ecDeploy...

set "downloadPath=%TEMP%\ecDeploy.ps1"

:: curl.exe er indbygget i Windows 10 1803+ / Windows 11 og er mere robust end Invoke-WebRequest.
curl.exe -fsSL -o "%downloadPath%" "https://ecd.qwe.dk/ecDeploy.ps1"
if errorlevel 1 (
    echo Kunne ikke hente ecDeploy.
    msg * "Kunne ikke hente ecDeploy."
    goto :end
)

:: Autostart af den automatiske sekvens via env-flag (ECDEPLOY_AUTOSEQUENCE=1) eller "auto"-argument.
set "AUTO="
if defined ECDEPLOY_AUTOSEQUENCE set "AUTO=-AutoSequence"
if /I "%~1"=="auto" set "AUTO=-AutoSequence"

:: -STA er paakraevet for WPF. ecDeploy self-elevater selv ( et enkelt UAC-prompt).
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%downloadPath%" %AUTO%

:end
endlocal
