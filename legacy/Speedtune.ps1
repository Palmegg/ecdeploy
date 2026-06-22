Add-Type -AssemblyName System.Windows.Forms
function Write-ToLog ($LogMsg, $LogColor = "White") {
    # Få dato og tidspunkt
    $DateTime = Get-Date -UFormat "%d-%m-%Y %T"
    $Log = "$DateTime - $LogMsg"
    Add-Content -Path $LogFile -Value $Log
}

# Definer logfil
$LogPath = "C:\SpeedTune"
$LogFile = "$LogPath\SpeedTune.log"

#Opret mappe til ScriptPath
$ScriptPath = "C:\SpeedTune"
    if (-Not (Test-Path $ScriptPath )) {
        #Opret SpeedTune mappe
        New-Item -ItemType Directory -Path $ScriptPath
    }
    else {
        try {
            #Slet mappen, hvis den findes
            Remove-Item -Path $ScriptPath -Force -Recurse
 
            #Opret SpeedTune mappe på ny
            New-Item -ItemType Directory -Path $ScriptPath
        }
        catch {
            Write-Log -Message "Kunne ikke slette $ScriptPath $_"
                }
    }

Write-ToLog "SpeedTune blev startet"
 
$url = "https://ast.oo.dk/SpeedTune/M365.ico"

$iconPath = "$ScriptPath\M365.ico"

if (!(Test-Path -Path $iconPath)) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $iconPath
    }
    catch {
        Write-Error "Fejl i download af $url"
        exit
    }
}

#Opret den primære form
$form = New-Object System.Windows.Forms.Form
$form.Text = "SpeedPrep"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.icon = $iconPath

    #Indsæt SpeedTune baggrundsbillede
    $BackgroundUrl = "https://ast.oo.dk/SpeedTune/SpeedTune.png"
    $IMGOutputPath = "$ScriptPath\SpeedTune.png"
    Invoke-WebRequest -Uri $BackgroundUrl -OutFile $IMGOutputPath
    $logoPath = "$ScriptPath\SpeedTune.png"

$form.BackgroundImage = [System.Drawing.Image]::FromFile($logoPath)
$form.BackgroundImageLayout = "stretch"

$choices = @("Start automatiseret proces", "Re-evaluer GRS", "Anti-Dvale")

$checkedListBox = New-Object System.Windows.Forms.CheckedListBox
$checkedListBox.Location = New-Object System.Drawing.Point(260, 130)
$checkedListBox.Size = New-Object System.Drawing.Size(250, 190)
$checkedListBox.CheckOnClick = $true
$checkedListBox.Items.AddRange($choices)


$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Location = New-Object System.Drawing.Point(340, 380)
$exitButton.Size = New-Object System.Drawing.Size(100, 30)
$exitButton.Text = "Afslut"
$exitButton.Add_Click({
    $form.Close()
    Write-ToLog "SpeedTune blev afsluttet - Sletter SpeedTune Mappen"
    Remove-Item -Path $ScriptPath -Force -Recurse
    Stop-Process -Id $PID
})
$form.Controls.Add($exitButton)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Location = New-Object System.Drawing.Point(680, 480)
$exitButton.Size = New-Object System.Drawing.Size(100, 40)
$exitButton.Text = "Åben logfil placering"
$exitButton.Add_Click({
    Invoke-Item "C:\Programdata\microsoft\intunemanagementextension\logs" -ErrorAction SilentlyContinue
    invoke-item "C:\User logs" -ErrorAction SilentlyContinue
})
$form.Controls.Add($exitButton)

$InstalledProgramsButton = New-Object System.Windows.Forms.Button
$InstalledProgramsButton.Location = New-Object System.Drawing.Point(680, 430)
$InstalledProgramsButton.Size = New-Object System.Drawing.Size(100, 40)
$InstalledProgramsButton.Text = "Installeret programmer"
$InstalledProgramsButton.Add_Click({
    appwiz.cpl
})
$form.Controls.Add($InstalledProgramsButton)

$WiFiSettingsButton = New-Object System.Windows.Forms.Button
$WiFiSettingsButton.Location = New-Object System.Drawing.Point(680, 380)
$WiFiSettingsButton.Size = New-Object System.Drawing.Size(100, 40)
$WiFiSettingsButton.Text = "Start Jobliste"
$WiFiSettingsButton.Add_Click({
    Start-Process taskmgr
})
$form.Controls.Add($WiFiSettingsButton)

$StartJob_Button = New-Object System.Windows.Forms.Button
$StartJob_Button.Location = New-Object System.Drawing.Point(340, 340)
$StartJob_Button.Size = New-Object System.Drawing.Size(100, 30)
$StartJob_Button.Text = "Start jobs"
$StartJob_Button.Add_Click({

    $selectedSegments = @()
    foreach ($item in $checkedListBox.CheckedItems) {
        $selectedSegments += $item.ToString()
    }
    switch ($selectedSegments) {
        "Start automatiseret proces" {

            #Download script til udførsel
            $BackgroundUrl = "https://ast.oo.dk/SpeedTune/Countdown_GRS.ps1"
            $IMGOutputPath = "$ScriptPath\Countdown_GRS.ps1"
            Invoke-WebRequest -Uri $BackgroundUrl -OutFile $IMGOutputPath
            Start-Process PowerShell -ArgumentList "-NoExit", "-File `"$scriptPath\Countdown_GRS.ps1`""
        }
        "Re-evaluer GRS" {  
            $BackgroundUrl = "https://ast.oo.dk/SpeedTune/GRS.ps1"
            $IMGOutputPath = "$ScriptPath\GRS.ps1"
            Invoke-WebRequest -Uri $BackgroundUrl -OutFile $IMGOutputPath
            Start-Process PowerShell -ArgumentList "-NoExit", "-File `"$scriptPath\GRS.ps1`""
        }
        "Anti-Dvale"{
            $BackgroundUrl = "https://ast.oo.dk/SpeedTune/Countdown.ps1"
            $IMGOutputPath = "$ScriptPath\Countdown.ps1"
            Invoke-WebRequest -Uri $BackgroundUrl -OutFile $IMGOutputPath
            Start-Process PowerShell -ArgumentList "-NoExit", "-File `"$scriptPath\Countdown.ps1`""
        }
                }
            })
            $form.Controls.Add($checkedListBox)
            $form.Controls.Add($StartJob_Button)

            $result = $form.ShowDialog()
            if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                $form.Dispose()
                Remove-Variable form, checkedListBox, StartJob_Button -ErrorAction SilentlyContinue
                Remove-Item -Path $ScriptPath -Force -Recurse
                exit 0
            } 
            else {
                Remove-Item -Path $ScriptPath -Force -Recurse                
                exit 1
            }
            