# deploy-assets — filer til Windows-installations-USB'en

Hjælpere der køres UNDER Windows-installationen (før CedraDeploy overhovedet
starter), så maskinen er bedre stillet fra første boot.

## Strøm-fix mod USB-C→Ethernet-drops (2 metoder)

Slår **USB selective suspend** fra (+ strømstyring på netværkskort), så
USB-C→Ethernet-adaptere (fx Realtek på Lenovo X1) ikke "sover" og taber
forbindelsen. Samme fix som CedraDeploy laver ved opstart — men her under selve
installationen.

### ✅ Anbefalet: `autounattend-power-snippet.xml` (direkte i autounattend.xml)

Kopiér `<settings pass="specialize">`-blokken fra `autounattend-power-snippet.xml`
ind i din `autounattend.xml`. Kommandoerne kører som SYSTEM under installationen
(specialize-passet, før OOBE). **Kræver hverken `$OEM$`-mapper eller
SetupComplete.cmd** — den mest robuste vej.

### Alternativ: `SetupComplete.cmd`

`<USB>\sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd` → ender som
`C:\Windows\Setup\Scripts\SetupComplete.cmd`, som Windows Setup kører automatisk.

⚠ To hager:
- `$OEM$`-mappen findes **ikke** som standard — du skal selv oprette den (mapper
  med de LITERALE navne `$OEM$` og `$$`), og den kræver et "configuration set".
- **SetupComplete.cmd er slået FRA hvis der bruges en OEM-produktnøgle** (undtagen
  Enterprise/Server). Bruger I OEM-nøgler, så brug autounattend-metoden ovenfor.

Mest robuste SetupComplete-vej er at bage den ind i `install.wim`:
```
dism /Mount-Image /ImageFile:...\sources\install.wim /Index:1 /MountDir:C:\mount
copy SetupComplete.cmd C:\mount\Windows\Setup\Scripts\
dism /Unmount-Image /MountDir:C:\mount /Commit
```

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
