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
                    $FirstSubKeyPath = Join-Path -Path $BasePath -ChildPath $FirstSubKey.Name.Split('\')[-1]
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
                    $GRSSubKeyPath = Join-Path -Path $FirstSubKeyPath -ChildPath "GRS"
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
                            #Terminate the PowerShell session
                            Stop-Process -Id $PID
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
                    # Terminate the PowerShell session
                    Stop-Process -Id $PID
                }
            } else {
                Write-Host "Applikation kører ikke som Administrator" -ForegroundColor Red
                Start-sleep -seconds 5
                #Terminate the PowerShell session
                Stop-Process -Id $PID
            }