@echo off
REM ============================================================================
REM  Cedra klargoering - stroem-fix mod USB-C -> Ethernet forbindelses-drops
REM  Placeres paa Windows-installations-USB'en som:
REM      <USB>\sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd
REM  Windows Setup koerer den AUTOMATISK (som SYSTEM) i slutningen af
REM  installationen, FOER foerste login / OOBE-enrollment.
REM
REM  Samme fix som CedraDeploy laver ved opstart - men her sker det allerede
REM  under selve Windows-installationen, saa USB-C-ethernet-adapteren ikke
REM  dropper mens I logger paa foerste gang.
REM ============================================================================

REM --- 1) USB selective suspend FRA (AC + DC) -----------------------------------
REM  Den vigtigste: forhindrer at Windows "sover" USB-enheden (og dropper linket).
REM  Global indstilling -> gaelder ogsaa adaptere der saettes i SENERE (ved OOBE).
powercfg /setacvalueindex SCHEME_CURRENT SUB_USB USBSELECTSUSPEND 0
powercfg /setdcvalueindex SCHEME_CURRENT SUB_USB USBSELECTSUSPEND 0
powercfg /setactive SCHEME_CURRENT

REM --- 2) "Tillad computeren at slukke enheden" FRA paa netvaerkskort -----------
REM  PnPCapabilities = 24 (0x18) slaar stroemstyring fra paa NIC-klassen. Rammer
REM  de kort der er til stede paa installationstidspunktet. (Adaptere der saettes
REM  i senere daekkes af USB selective suspend ovenfor + CedraDeploy ved opstart.)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$k='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'; Get-ChildItem $k -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^[0-9]{4}$' } | ForEach-Object { try { New-ItemProperty -Path $_.PSPath -Name PnPCapabilities -PropertyType DWord -Value 24 -Force | Out-Null } catch {} }"

exit /b 0
