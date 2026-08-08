@echo off
REM ============================================================================
REM  Apply-PowerFix.bat - samlet, koerbar udgave af stroem-fix'et.
REM  Slaar USB selective suspend + NIC-stroemstyring fra (mod USB-C -> Ethernet
REM  forbindelses-drops). INGEN netkort-genstart.
REM  Dobbeltklik -> selv-eleverer (UAC). Kan koeres paa maskiner der allerede er ude.
REM  (Til Windows-installations-USB'en: brug i stedet SetupComplete.cmd eller
REM   schneegans "System scripts" - denne .bat har en pause og er til haandkoersel.)
REM ============================================================================

REM --- Selv-eleveer hvis ikke administrator ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Beder om administrator-rettigheder...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo === Anvender stroem-fix (USB-C ethernet drops) ===
echo.

set "USBSUB=2a737441-1930-4402-8d77-b2bebba308a3"
set "USBSET=48e6b7a6-50f5-4782-a5d4-53bb8f07e226"

echo [1] USB selective suspend fra (AC + DC)
powercfg /setacvalueindex SCHEME_CURRENT %USBSUB% %USBSET% 0
powercfg /setdcvalueindex SCHEME_CURRENT %USBSUB% %USBSET% 0
powercfg /setactive SCHEME_CURRENT

echo [2] NIC-stroemstyring fra (PnPCapabilities=24)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' | Where-Object { $_.PSChildName -match '^[0-9]{4}$' } | ForEach-Object { New-ItemProperty -Path $_.PSPath -Name PnPCapabilities -PropertyType DWord -Value 24 -Force -ErrorAction SilentlyContinue | Out-Null }"

echo.
echo === Verificering (skal vise 0x00000000 for AC og DC) ===
powercfg /query SCHEME_CURRENT %USBSUB% %USBSET% | findstr /i "Current"
echo.
echo === Faerdig - tryk en tast for at lukke ===
pause
