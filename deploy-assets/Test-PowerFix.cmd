@echo off
REM ============================================================================
REM  TEST-version af strøm-fix'et - til at koere I HAANDEN og se resultatet.
REM  (Har log-linjer + pause. Brug IKKE denne paa USB'en - SetupComplete.cmd
REM   maa ikke have "pause", ellers haenger Windows Setup.)
REM  Hoejreklik -> "Kor som administrator".
REM ============================================================================
echo.
echo === Cedra power-fix test (USB-C ethernet drops) ===
echo.

REM --- Admin-tjek (powercfg kraever administrator) ---
net session >nul 2>&1
if errorlevel 1 (
  echo [FEJL] Koeres IKKE som administrator.
  echo Luk vinduet, hoejreklik filen og vaelg "Kor som administrator".
  echo.
  pause
  exit /b 1
)
echo [OK] Administrator-rettigheder bekraeftet.
echo.

set "USBSUB=2a737441-1930-4402-8d77-b2bebba308a3"
set "USBSET=48e6b7a6-50f5-4782-a5d4-53bb8f07e226"

echo [1] USB selective suspend fra (AC)
powercfg /setacvalueindex SCHEME_CURRENT %USBSUB% %USBSET% 0
if errorlevel 1 (echo     RESULTAT: FEJL) else (echo     RESULTAT: OK)
echo.

echo [2] USB selective suspend fra (DC)
powercfg /setdcvalueindex SCHEME_CURRENT %USBSUB% %USBSET% 0
if errorlevel 1 (echo     RESULTAT: FEJL) else (echo     RESULTAT: OK)
echo.

echo [3] Aktiver power plan
powercfg /setactive SCHEME_CURRENT
if errorlevel 1 (echo     RESULTAT: FEJL) else (echo     RESULTAT: OK)
echo.

echo [4] NIC-stroemstyring fra (PnPCapabilities=24)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$n=0; Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' | Where-Object { $_.PSChildName -match '^[0-9]{4}$' } | ForEach-Object { try { New-ItemProperty -Path $_.PSPath -Name PnPCapabilities -PropertyType DWord -Value 24 -Force | Out-Null; $n++ } catch {} }; Write-Host ('     RESULTAT: sat paa ' + $n + ' netvaerkskort')"
echo.

echo === Verificering: begge linjer skal vise 0x00000000 ===
powercfg /query SCHEME_CURRENT %USBSUB% %USBSET% | findstr /i "Current"
echo.
echo === Test faerdig - tryk en tast for at lukke ===
pause
