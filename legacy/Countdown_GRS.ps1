# Description: Dette script er designet til at køre en nedtælling i 30 minutter, og derefter slette GRS-nøglen fra registreringsdatabasen og genstarte IME-tjenesten.
# Version: 1.0
# Date: 2021-05-25
# Author: Jonas Wilner

# Tilføj System.Windows.Forms assembly
Add-Type -AssemblyName System.Windows.Forms

# Funktion til at forhindre dvale i 24 timer
function PreventSleep-24Hours {


    $Design1 = {
        Write-Host "`n"
        write-host "" 
        write-host " █████  ███    ██ ████████ ██       ██████  ██    ██  █████  ██      ███████  " -ForegroundColor GREEN
        write-host " ██   ██ ████   ██    ██    ██       ██   ██ ██    ██ ██   ██ ██      ██      " -ForegroundColor GREEN
        write-host " ███████ ██ ██  ██    ██    ██ █████ ██   ██ ██    ██ ███████ ██      █████   " -ForegroundColor GREEN
        write-host " ██   ██ ██  ██ ██    ██    ██       ██   ██  ██  ██  ██   ██ ██      ██      " -ForegroundColor GREEN
        write-host " ██   ██ ██   ████    ██    ██       ██████    ████   ██   ██ ███████ ███████ " -ForegroundColor GREEN
        Write-Host "`n"
        write-host "     █████  ██   ██ ████████ ██ ██    ██ ███████ ██████  ███████ ████████ " -ForegroundColor GREEN
        write-host "     ██   ██ ██  ██     ██    ██ ██    ██ ██      ██   ██ ██         ██   " -ForegroundColor GREEN
        write-host "     ███████ █████      ██    ██ ██    ██ █████   ██████  █████      ██   " -ForegroundColor GREEN 
        write-host "     ██   ██ ██  ██     ██    ██  ██  ██  ██      ██   ██ ██         ██   " -ForegroundColor GREEN
        write-host "     ██   ██ ██   ██    ██    ██   ████   ███████ ██   ██ ███████    ██   " -ForegroundColor GREEN   
    }
    # Opret en ny tidsvarighed på 24 timer
    $duration = New-TimeSpan -Hours 24

    # Starttidspunkt
    $startTime = Get-Date

    # Vis tekst art
    & $Design1

    # Opdater "Tid tilbage" på samme linje
    while ((New-TimeSpan -Start $startTime -End (Get-Date)) -lt $duration) {
        $timeLeft = $duration - (New-TimeSpan -Start $startTime -End (Get-Date))
        $timeLeftMsg = "`rAnti-Dvale aktiveret | Tid tilbage: $($timeLeft.Hours) timer, $($timeLeft.Minutes) minutter, $($timeLeft.Seconds) sekunder"

        # Skriv "Tid tilbage" beskeden
        Write-Progress -Activity $timeLeftMsg

        

        $wsh = New-Object -ComObject WScript.Shell
        #Send F15 keyStroke	
        $wsh.SendKeys('+{F15}')

        # Vent 1 sekund før næste opdatering
        Start-Sleep -Seconds 1
    }

    # Når nedtællingen er færdig, skriv en besked
    Write-Host "Nedtælling afsluttet." -ForegroundColor Green
    exit
}

# Ryd konsollen
cls

# Opret en række af By JW designs
$Design1 = {
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`t888888888     888       888      8888888888   888       888" -ForegroundColor Magenta 
    Write-Host "`t888     888    888     888               88   888       888" -ForegroundColor Cyan
    Write-Host "`t888      888    888   888                88   888   o   888" -ForegroundColor Cyan
    Write-Host "`t888     888      888 888                 88   888  d8b  888" -ForegroundColor Cyan
    Write-Host "`t8888888888         888                   88   888 d888b 888" -ForegroundColor Cyan
    Write-Host "`t888     888        888                  .88   888d88888b888" -ForegroundColor Magenta
    Write-Host "`t888      888       888                 .d88   88888P Y88888" -ForegroundColor Cyan
    Write-Host "`t888     888        888           /b   .d88Y   8888P   Y8888" -ForegroundColor Cyan
    Write-Host "`t888888888          888           Y8888888Y    888P     Y888" -ForegroundColor Magenta      
}
$Design2 = {
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    write-host "__/\\\\\\\\\\\\\________________________________/\\\\\\\\\\\__/\\\______________/\\\_" -ForegroundColor Magenta        
    write-host " _\/\\\/////////\\\_____________________________\/////\\\///__\/\\\_____________\/\\\_" -ForegroundColor Cyan       
    write-host "  _\/\\\_______\/\\\____/\\\__/\\\___________________\/\\\_____\/\\\_____________\/\\\_" -ForegroundColor Cyan      
    write-host "   _\/\\\\\\\\\\\\\\____\//\\\/\\\____________________\/\\\_____\//\\\____/\\\____/\\\__" -ForegroundColor Cyan     
    write-host "    _\/\\\/////////\\\____\//\\\\\_____________________\/\\\______\//\\\__/\\\\\__/\\\___" -ForegroundColor Magenta    
    write-host "     _\/\\\_______\/\\\_____\//\\\______________________\/\\\_______\//\\\/\\\/\\\/\\\____" -ForegroundColor Cyan   
    write-host "      _\/\\\_______\/\\\__/\\_/\\\________________/\\\___\/\\\________\//\\\\\\//\\\\\_____"-ForegroundColor Cyan   
    write-host "       _\/\\\\\\\\\\\\\/__\//\\\\/________________\//\\\\\\\\\__________\//\\\__\//\\\______"-ForegroundColor Cyan  
    write-host "        _\/////////////_____\////___________________\/////////____________\///____\///_______"-ForegroundColor Magenta 
}
$Design3 = {
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    write-host "          _____            _____                            _____                   _____" -ForegroundColor Magenta         
    write-host "         /\    \          |\    \                          /\    \                 /\    \" -ForegroundColor Cyan          
    write-host "        /::\    \         |:\____\                        /::\    \               /::\____\" -ForegroundColor Cyan        
    write-host "       /::::\    \        |::|   |                        \:::\    \             /:::/    /" -ForegroundColor Cyan        
    write-host "      /::::::\    \       |::|   |                         \:::\    \           /:::/   _/__ " -ForegroundColor Cyan     
    write-host "     /:::/\:::\    \      |::|   |                          \:::\    \         /:::/   /\    \"  -ForegroundColor Cyan     
    write-host "    /:::/__\:::\    \     |::|   |                           \:::\    \       /:::/   /::\____\"  -ForegroundColor Cyan    
    write-host "   /::::\   \:::\    \    |::|   |                           /::::\    \     /:::/   /:::/    / "  -ForegroundColor Cyan   
    write-host "  /::::::\   \:::\    \   |::|___|______            _____   /::::::\    \   /:::/   /:::/   _/___" -ForegroundColor Magenta 
    write-host " /:::/\:::\   \:::\ ___\  /::::::::\    \          /\    \ /:::/\:::\    \ /:::/___/:::/   /\    \" -ForegroundColor Magenta
    write-host "/:::/__\:::\   \:::|    |/::::::::::\____\        /::\    /:::/  \:::\____\:::|   /:::/   /::\____\"-ForegroundColor Cyan 
    write-host "\:::\   \:::\  /:::|____/:::/~~~~/~~              \:::\  /:::/    \::/    /:::|__/:::/   /:::/    /"-ForegroundColor Cyan 
    write-host " \:::\   \:::\/:::/    /:::/    /                  \:::\/:::/    / \/____/ \:::\/:::/   /:::/    / "-ForegroundColor Cyan 
    write-host "  \:::\   \::::::/    /:::/    /                    \::::::/    /           \::::::/   /:::/    /  "-ForegroundColor Cyan 
    write-host "   \:::\   \::::/    /:::/    /                      \::::/    /             \::::/___/:::/    /   "-ForegroundColor Cyan 
    write-host "    \:::\  /:::/    /\::/    /                        \::/    /               \:::\__/:::/    /    "-ForegroundColor Cyan 
    write-host "     \:::\/:::/    /  \/____/                          \/____/                 \::::::::/    /     "-ForegroundColor Magenta
    write-host "      \::::::/    /                                                             \::::::/    /      "-ForegroundColor Magenta
    write-host "       \::::/    /                                                               \::::/    /       "-ForegroundColor Magenta
    write-host "        \::/____/                                                                 \::/____/        "-ForegroundColor Cyan 
    write-host "         ~~                                                                        ~~              "-ForegroundColor Cyan 
}     

$Design4 = {
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    Write-Host "`n"
    write-host " .----------------.  .----------------.  .----------------.  .----------------."-ForegroundColor Cyan
    write-host " | .--------------. || .--------------. || .--------------. || .--------------. |"-ForegroundColor Cyan
    write-host " | |   ______     | || |  ____  ____  | || |     _____    | || | _____  _____ | |"-ForegroundColor Cyan
    write-host " | |  |_   _ \    | || | |_  _||_  _| | || |    |_   _|   | || ||_   _||_   _|| |"-ForegroundColor Cyan
    write-host " | |    | |_) |   | || |   \ \  / /   | || |      | |     | || |  | | /\ | |  | |"-ForegroundColor Magenta
    write-host " | |    |  __'.   | || |    \ \/ /    | || |   _  | |     | || |  | |/  \| |  | |"-ForegroundColor Cyan
    write-host " | |   _| |__) |  | || |    _|  |_    | || |  | |_' |     | || |  |   /\   |  | |"-ForegroundColor Cyan
    write-host " | |  |_______/   | || |   |______|   | || |  `.___.'     | || |  |__/  \__|  | |"-ForegroundColor Cyan
    write-host " | |              | || |              | || |              | || |              | |"-ForegroundColor Magenta
    write-host " | '--------------' || '--------------' || '--------------' || '--------------' |"-ForegroundColor Cyan
    write-host "  '----------------'  '----------------'  '----------------'  '----------------' "-ForegroundColor Cyan 
}


# Opret Array til designs
$DesignArray = $Design1, $Design2, $Design3, $Design4

# Vælg Random
$RandomDesign = Get-Random -InputObject $DesignArray

# Kør design
& $RandomDesign

# Sæt total varighed til 30 minutter
$totalMinutes = 30

# Starttidspunkt
$startTime = Get-Date

# Kør et loop, der opdaterer progress bar og timer hvert minut
for ($i = 0; $i -le $totalMinutes; $i++) {
    # Beregn procentdelen af fuldførelse
    $percentComplete = ($i / $totalMinutes) * 100

    # Beregn resterende tid
    $elapsed = (Get-Date) - $startTime
    # Beregn resterende tid
    $remaining = $totalMinutes - $elapsed.TotalMinutes

    $wsh = New-Object -ComObject WScript.Shell
    #Send F15 keyStroke	
    $wsh.SendKeys('+{F15}')

    # Opdater progress bar
    Write-Progress -Activity "`rAnti-Dvale & Re-Evaluer GRS aktiveret" -Status "Tid tilbage: $([math]::Round($remaining, 2)) minutter" -PercentComplete $percentComplete

    # Vent 1 minut før næste opdatering
    Start-Sleep -Seconds 60
}

# Når nedtællingen er færdig, skriv en besked
Write-Host "Nedtælling afsluttet." -ForegroundColor Green
Write-Host "Starter Re-eveluering af GRS" -ForegroundColor Magenta

# Opret et WindowsPrincipal objekt for den aktuelle bruger
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

# Tjek for forhøjede rettigheder
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Skriv en besked, hvis sessionen kører med forhøjede rettigheder
    Write-Host "Administrator session fundet" -ForegroundColor Green
    # Definer basisstien til Win32Apps mappen
    $BasePath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"

    try {
        # Få den første undermappe under Win32Apps
        $FirstSubKey = Get-ChildItem -Path $BasePath | Select-Object -First 1       
        # Byg den fulde sti til den første undermappe
        $FirstSubKeyPath = Join-Path -Path $BasePath -ChildPath $FirstSubKey.Name.Split('\')[-1] -ErrorAction SilentlyContinue
    }
    catch {
        # Hvis der opstår en fejl ved bygning af den fulde mappe til GRS, skriv fejlen og afslut
        Write-Host "Fejl ved bygning af den fulde mappe til GRS -> $_" -ForegroundColor Red
        Start-Sleep -Seconds 5
        #Terminate the PowerShell session
        Stop-Process -Id $PID
    }
    try {       
        # Byg stien til "GRS"-undermappen inden i den første undermappe
        $GRSSubKeyPath = Join-Path -Path $FirstSubKeyPath -ChildPath "GRS" -ErrorAction SilentlyContinue
    }
    catch {
        # Hvis der opstår en fejl ved bygning af stien til GRS, skriv fejlen og afslut
        Write-Host "Fejl ved bygning af sti til GRS -> $_" -ForegroundColor Red
        Start-Sleep -Seconds 5
        #Terminate the PowerShell session
        Stop-Process -Id $PID
    }

    # Tjek om "GRS"-undermappen eksisterer, og slet den hvis den gør
    if (Test-Path $GRSSubKeyPath) {
        try {
            # Slet GRS-nøglen
            Remove-Item -Path $GRSSubKeyPath -Recurse -Force
        }
        catch {
            # Hvis der opstår en fejl ved sletning af GRS-nøglen, skriv fejlen og afslut
            Write-Host "Fejl ved sletning af GRS -> $_" -ForegroundColor Red
            start-sleep -seconds 5
            #Terminate the PowerShell session
            Stop-Process -Id $PID
        }
        if (-not(Test-Path $GRSSubKeyPath)) {
            # Hvis GRS-nøglen blev slettet, skriv en besked og genstart IME-tjenesten
            Write-Host "GRS blev slettet`n`nGenstarter IME..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            try {
                # Genstart IME-tjenesten efter sletning af GRS registry-nøglen
                Restart-Service -Name "Microsoft Intune Management Extension" -Force -ErrorAction Stop
                # Kør nedtælling i 24 timer
                PreventSleep-24Hours
            }
            catch {
                # Hvis der opstår en fejl ved genstart af IME-tjenesten, skriv fejlen og afslut
                Write-Host "Fejl ved genstart af IME $_" -ForegroundColor Red
                start-sleep -seconds 5
                #Terminate the PowerShell session
                Stop-Process -Id $PID
            }
        }

    } else {
        Write-Host "GRS mappen findes ikke" -ForegroundColor Red
        Start-Sleep -Seconds 5
        #Terminate the PowerShell session
        Stop-Process -Id $PID
    }
} else {
    Write-Host "Applikation kører ikke som Administrator" -ForegroundColor Red
    Start-sleep -seconds 5
    #Terminate the PowerShell session
    Stop-Process -Id $PID
}
