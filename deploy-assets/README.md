# deploy-assets — filer til Windows-installations-USB'en

Hjælpere der køres UNDER Windows-installationen (før CedraDeploy overhovedet
starter), så maskinen er bedre stillet fra første boot.

## SetupComplete.cmd — strøm-fix mod USB-C→Ethernet-drops

Slår **USB selective suspend** fra (+ strømstyring på netværkskort), så
USB-C→Ethernet-adaptere (fx Realtek på Lenovo X1) ikke "sover" og taber
forbindelsen. Samme fix som CedraDeploy laver ved opstart — men her sker det
allerede under installationen.

**Placering på USB'en:**
```
<USB>\sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd
```
`$$` = `%WINDIR%`, så filen ender som `C:\Windows\Setup\Scripts\SetupComplete.cmd`
på maskinen, og Windows Setup kører den automatisk (som SYSTEM) i slutningen af
installationen — før første login/OOBE. Ingen ændringer i `autounattend.xml`
nødvendige for dette.

## Ethernet-driver i imaget (den permanente løsning)

`SetupComplete.cmd` fjerner strømstyringen, men hvis adapteren slet ikke
genkendes ved OOBE, skal driverens **.inf** med i imaget. Vælg én:

- **DISM ind i install.wim** (mest robust):
  ```
  dism /Mount-Image /ImageFile:...\sources\install.wim /Index:1 /MountDir:C:\mount
  dism /Image:C:\mount /Add-Driver /Driver:C:\drivers\ethernet /Recurse
  dism /Unmount-Image /MountDir:C:\mount /Commit
  ```
- **`$WinPEDriver$`-mappe** i roden af USB'en (`<USB>\$WinPEDriver$\ethernet\`) —
  Windows Setup scanner alle drev og installerer .inf'erne automatisk.
- **autounattend.xml** — `Microsoft-Windows-PnpCustomizationsNonWinPE` i
  `offlineServicing`-passet med `DriverPaths` (drev-bogstav på USB er dog
  uforudsigeligt, så DISM/`$WinPEDriver$` er mere pålidelige).

Find det rigtige driver-.inf ud fra adapterens hardware-id (Enhedshåndtering →
adapter → Detaljer → Hardware-id'er, fx `USB\VID_0BDA&PID_8153` = Realtek RTL8153).
