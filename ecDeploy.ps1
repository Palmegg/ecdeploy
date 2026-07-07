<#
    ecDeploy.ps1 — provisioning utility (WPF / Windows PowerShell 5.1)

    A technician runs this on a freshly deployed Windows machine after signing in, to keep the
    machine awake during provisioning and to unstick stalled Intune Win32 app installs.

    See DESIGN.md for the full design. Next-gen rebuild of SpeedTune.
    User-facing text is Danish; code/identifiers/comments are English.

    -AutoSequence : start the automatic sequence immediately on launch (preserved across the
    self-elevation relaunch). The bootstrap adds it when $env:ECDEPLOY_AUTOSEQUENCE is set.

    -Customer <name> : apply a customer profile (branding) from the $script:Customers table.
    -Flow <name>     : run a customer flow on launch (e.g. CedraStandard, CedraResume).
    Customer entry points live under customers/<name>/ and are served from their own host.
#>
param(
    [switch]$AutoSequence,
    [string]$Customer,
    [string]$Flow
)

$ErrorActionPreference = 'Stop'
$script:Version = '1.6.0'

# Startup error trap: any terminating error is written to a log and shown in a dialog that
# stays put, so a launch failure can't vanish with the window. Place before anything risky.
trap {
    $__chain = @()
    $__ex = $_.Exception
    while ($__ex) {
        $__chain += ($__ex.GetType().Name + ': ' + $__ex.Message)
        if ($__ex.StackTrace) { $__chain += ('   @ ' + (($__ex.StackTrace -split "`r?`n")[0]).Trim()) }
        $__ex = $__ex.InnerException
    }
    $detail = @(
        ($__chain -join "`r`n--> ")
        $_.InvocationInfo.PositionMessage
        '--- stack ---'
        $_.ScriptStackTrace
    ) -join "`r`n"
    try {
        $dir = Join-Path $env:ProgramData 'ecDeploy'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path (Join-Path $dir 'startup-error.log') -Value ((Get-Date).ToString('s') + "`r`n" + $detail) -Encoding UTF8
    } catch {}
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [void][System.Windows.MessageBox]::Show($detail, 'ecDeploy — opstartsfejl')
    } catch {
        Write-Host $detail -ForegroundColor Red
        Read-Host 'Tryk Enter for at lukke'
    }
    break
}

# Hide our own console window — the WPF UI is the only thing the tech should see. The launchers
# also pass -WindowStyle Hidden; this is the reliable belt-and-suspenders (and covers direct runs).
try {
    Add-Type -Name EcWin -Namespace Ec -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
    $__console = [Ec.EcWin]::GetConsoleWindow()
    if ($__console -ne [System.IntPtr]::Zero) { [void][Ec.EcWin]::ShowWindow($__console, 0) }  # 0 = SW_HIDE
} catch {}

#region ---------------------------------------------------------- bootstrap: STA + elevation
# WPF requires an STA thread; the privileged actions require an elevated process.
# The bootstrap normally launches us -STA already, and we self-elevate here with one UAC prompt.
# If the script has a path on disk (it does when launched via -File), we can relaunch ourselves.

function Restart-Self {
    param([switch]$Elevated)
    if (-not $PSCommandPath) { return $false }   # running in-memory (irm|iex) — cannot relaunch
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($AutoSequence) { $argList += '-AutoSequence' }   # preserve auto-start across the relaunch
    if ($Customer)     { $argList += @('-Customer', $Customer) }
    if ($Flow)         { $argList += @('-Flow', $Flow) }
    if ($Elevated) {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    } else {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList | Out-Null
    }
    return $true
}

# Ensure STA (rarely needed — the bootstrap launches us -STA).
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    if (Restart-Self) { return }
}

# Ensure elevation. One UAC prompt; if declined, fall through and run degraded.
$script:Identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$script:Principal = New-Object Security.Principal.WindowsPrincipal($script:Identity)
$script:IsAdmin   = $script:Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $script:IsAdmin) {
    try {
        if (Restart-Self -Elevated) { return }   # elevated instance takes over
    } catch {
        # User declined the UAC prompt — continue in degraded (non-admin) mode.
    }
}
#endregion

#region ---------------------------------------------------------- assemblies + interop
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class EcPower {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
$script:ES_CONTINUOUS       = [uint32]2147483648  # 0x80000000
$script:ES_SYSTEM_REQUIRED  = [uint32]1           # 0x00000001
$script:ES_DISPLAY_REQUIRED = [uint32]2           # 0x00000002
#endregion

#region ---------------------------------------------------------- branding (embedded logo)
# App icon, embedded as a base64 PNG so the script stays self-contained (no extra download).
# Used for the window/taskbar icon and the header wordmark. Regenerate with tools\make-icon.ps1.
$script:LogoB64 = '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'
$script:LogoImage = $null
try {
    $__logoBytes = [Convert]::FromBase64String($script:LogoB64)
    $__logoStream = New-Object System.IO.MemoryStream(, $__logoBytes)
    $img = New-Object System.Windows.Media.Imaging.BitmapImage
    $img.BeginInit()
    $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $img.StreamSource = $__logoStream
    $img.EndInit()
    $img.Freeze()
    $script:LogoImage = $img
} catch {}
#endregion

#region ---------------------------------------------------------- customers (branding profiles)
# Per-customer branding. Entry points live under customers/<name>/ on the site and launch the
# shared ecDeploy.ps1 with -Customer/-Flow. Logos are embedded (regenerate with tools\make-cedra-icon.ps1).
function ConvertFrom-B64Image {
    param([string]$B64)
    if (-not $B64 -or $B64 -like '__*__') { return $null }
    try {
        $bytes = [Convert]::FromBase64String($B64)
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $im = New-Object System.Windows.Media.Imaging.BitmapImage
        $im.BeginInit(); $im.CacheOption = 'OnLoad'; $im.StreamSource = $ms; $im.EndInit(); $im.Freeze()
        return $im
    } catch { return $null }
}

$script:CedraLogoB64 = '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'
$script:Customers = @{
    CedraDanmark = @{
        Brand       = 'CedraDeploy'
        Wordmark    = 'CedraDanmark'
        DevelopedBy = 'Developed by Jonas Palme'
        Accent      = '#14B8A6'
        AccentHover = '#0D9488'
        LogoB64     = $script:CedraLogoB64
        # ecFleet status board. This script is served publicly, so NO secret goes here — the
        # safeguard is that /agent/report is internal-only and you must hit a valid in-progress S/N.
        # EcfBaseUrl er en intern URL. EcfApiKey er en BLOED delt noegle (dette script er offentligt),
        # der matcher AGENT_API_KEY paa ecFleet-serveren. Rigtig beskyttelse = netvaerks-isolation.
        EcfBaseUrl  = 'http://10.234.8.107:5173/api'
        EcfApiKey   = 'INjAxOrFYiaPlExpIniIysUZh36pLEP0'
        # GUID -> friendly name for Intune Win32 apps (the registry only exposes GUIDs). Keyed by the
        # base GUID (the IME app id without any "_1" revision suffix), lowercase.
        EcfAppNames = @{
            '3b61435b-92b3-400b-99d9-5e710244ae7b' = '7-Zip'
            '92680d28-18b2-47b8-9acd-21c0c35f3abf' = 'AdminRemover'
            'e621fc1f-a00a-4e67-9d32-734e59303bc3' = 'Adobe Reader'
            '3859ac67-a6e9-426b-a79a-368c306702bc' = 'DeviceRenamer'
            '8d8ff2c8-9e91-464a-b2c7-ea8e92546caa' = 'Firmaportal'
            '67391164-7e55-47cb-8ca5-5fa9116d85f8' = 'Jabra Direct'
            '4e1fefc1-8986-48ba-ad18-d57251e23bc9' = 'Logitech Options+'
        }
        # Apps installed directly by CedraDeploy (not via Intune) — checked via Get-AppxPackage by
        # friendly name instead of the IME/registry, and excluded from the Intune-app badges.
        # Map: friendly name -> appx package family name.
        EcfAppxChecks = @{
            'Firmaportal' = 'Microsoft.CompanyPortal'
        }
    }
}
$script:Profile = $null
if ($Customer -and $script:Customers.ContainsKey($Customer)) { $script:Profile = $script:Customers[$Customer] }
#endregion

#region ---------------------------------------------------------- paths + state
$script:Win32AppsKey = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
$script:ImeLogsPath  = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$script:ImeLogFile   = Join-Path $script:ImeLogsPath 'IntuneManagementExtension.log'
$script:LogDir       = Join-Path $env:ProgramData 'ecDeploy'
$script:LogFile      = Join-Path $script:LogDir 'ecDeploy.log'

$script:NoSleepActive = $false
$script:SeqRunning    = $false
$script:SeqGrsFired   = $false
$script:AutoStart     = [bool]$AutoSequence   # auto-start the sequence once the window is loaded
$script:FlowName      = $Flow                 # customer flow to run on load (CedraStandard/CedraResume)
$script:CedraRunning  = $false
$script:CedraResuming = $false   # true while the post-login resume flow is active (ecFleet reporting)
$script:WuDriveBusy   = $false
# App-fejl: sæt når mindst én tracked app er FEJLET. Blokerer auto-genstart og
# udløser (én gang pr. fejl-transition) en popup + GRS-ryd for retry.
$script:AppFailed          = $false
$script:AppFailureNotified = $false
$script:UI            = @{}
$script:LogQueue      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'

try { if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null } } catch {}
#endregion

#region ---------------------------------------------------------- XAML
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ecDeploy" Height="600" Width="820" MinHeight="480" MinWidth="700"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize"
        Background="#15161A" FontFamily="Segoe UI" FontSize="12" UseLayoutRounding="True">
    <Window.Resources>
        <SolidColorBrush x:Key="Accent"      Color="#3B82F6"/>
        <SolidColorBrush x:Key="AccentHover" Color="#2F6FE0"/>
        <SolidColorBrush x:Key="Panel"  Color="#232429"/>
        <SolidColorBrush x:Key="Text"   Color="#E6E7EA"/>
        <SolidColorBrush x:Key="Muted"  Color="#9AA0AA"/>
        <SolidColorBrush x:Key="Border" Color="#2E2F36"/>

        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Foreground" Value="#E6E7EA"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Padding" Value="14,10"/>
            <Setter Property="Margin" Value="8,2"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#2A2B31"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="{DynamicResource Accent}"/>
            <Setter Property="Padding" Value="18,9"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource AccentHover}"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="GhostButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="#2B2C33"/>
            <Setter Property="Foreground" Value="#E6E7EA"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}" BorderBrush="#3A3B43" BorderThickness="1">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#34353D"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#1C1D22" BorderBrush="{StaticResource Border}" BorderThickness="0,0,0,1">
            <Grid Margin="18,12">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image x:Name="LogoImg" Width="24" Height="24" VerticalAlignment="Center" SnapsToDevicePixels="True"/>
                    <StackPanel Orientation="Vertical" Margin="8,0,0,0" VerticalAlignment="Center">
                        <TextBlock x:Name="TxtWordmark" Text="ecDeploy" Foreground="{StaticResource Text}" FontSize="18" FontWeight="SemiBold"/>
                        <TextBlock x:Name="TxtDevelopedBy" Text="" Foreground="{StaticResource Muted}" FontSize="10" Visibility="Collapsed"/>
                    </StackPanel>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Border x:Name="ChipAdmin"   CornerRadius="11" Padding="10,4" Margin="5,0" Background="#3A2A2A"><TextBlock x:Name="TxtAdmin"   Foreground="#E6E7EA" FontSize="12"/></Border>
                    <Border x:Name="ChipOnline"  CornerRadius="11" Padding="10,4" Margin="5,0" Background="#2B2C33"><TextBlock x:Name="TxtOnline"  Foreground="#E6E7EA" FontSize="12"/></Border>
                    <Border x:Name="ChipNoSleep" CornerRadius="11" Padding="10,4" Margin="5,0" Background="#2B2C33"><TextBlock x:Name="TxtNoSleep" Foreground="#E6E7EA" FontSize="12"/></Border>
                    <TextBlock x:Name="TxtVersion" Foreground="{StaticResource Muted}" FontSize="12" Margin="10,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Reminder banner (visible while No Sleep is active) -->
        <Border x:Name="BannerNoSleep" Grid.Row="1" Background="#3A2F12" BorderBrush="#7A5E16" BorderThickness="0,0,0,1" Visibility="Collapsed">
            <TextBlock Foreground="#F4D58A" Margin="18,8" FontSize="12"
                       Text="No Sleep er aktiv — ecDeploy skal forblive åben for at maskinen ikke går i dvale. Minimer vinduet i stedet for at lukke det."/>
        </Border>

        <!-- Body -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="186"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Left rail -->
            <Border Grid.Column="0" Background="#1C1D22" BorderBrush="{StaticResource Border}" BorderThickness="0,0,1,0">
                <DockPanel Margin="0,12" LastChildFill="True">
                    <Button x:Name="BtnViewLog" DockPanel.Dock="Bottom" Style="{StaticResource NavButton}" Content="Vis logfil"/>
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel>
                            <TextBlock Text="HANDLINGER" Foreground="{StaticResource Muted}" FontSize="10" Margin="22,4,0,4"/>
                            <Button x:Name="NavAuto"    Style="{StaticResource NavButton}" Content="Automatisk sekvens"/>
                            <Button x:Name="NavNoSleep" Style="{StaticResource NavButton}" Content="No Sleep"/>
                            <Button x:Name="NavGrs"     Style="{StaticResource NavButton}" Content="Opdater GRS"/>
                            <Button x:Name="NavIme"     Style="{StaticResource NavButton}" Content="Genstart IME"/>
                            <Border Height="1" Background="{StaticResource Border}" Margin="14,12"/>
                            <TextBlock Text="DIAGNOSTIK" Foreground="{StaticResource Muted}" FontSize="10" Margin="22,0,0,4"/>
                            <Button x:Name="NavWu"      Style="{StaticResource NavButton}" Content="Windows Update"/>
                            <Button x:Name="NavApps"    Style="{StaticResource NavButton}" Content="App-status"/>
                            <Button x:Name="NavImeLog"  Style="{StaticResource NavButton}" Content="Live IME-log"/>
                            <Button x:Name="NavInfo"    Style="{StaticResource NavButton}" Content="Enheds-info"/>
                            <Border Height="1" Background="{StaticResource Border}" Margin="14,12"/>
                            <TextBlock Text="VÆRKTØJER" Foreground="{StaticResource Muted}" FontSize="10" Margin="22,0,0,4"/>
                            <Button x:Name="BtnImeLogs"  Style="{StaticResource NavButton}" Content="IME-logs"/>
                            <Button x:Name="BtnPrograms" Style="{StaticResource NavButton}" Content="Programmer"/>
                            <Button x:Name="BtnTaskMgr"  Style="{StaticResource NavButton}" Content="Jobliste"/>
                        </StackPanel>
                    </ScrollViewer>
                </DockPanel>
            </Border>

            <!-- Main panel -->
            <Grid Grid.Column="1" Margin="22,18">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <TextBlock x:Name="TxtPanelTitle" Grid.Row="0" Text="Velkommen" Foreground="{StaticResource Text}" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,14"/>

                <Grid Grid.Row="1">
                    <!-- Welcome -->
                    <StackPanel x:Name="PanelWelcome">
                        <TextBlock Foreground="{StaticResource Muted}" TextWrapping="Wrap"
                                   Text="Vælg en handling i menuen til venstre. ecDeploy holder maskinen vågen under klargøring og kan tvinge Intune til at geninstallere apps med det samme."/>
                    </StackPanel>

                    <!-- Automatic sequence -->
                    <StackPanel x:Name="PanelAuto" Visibility="Collapsed">
                        <TextBlock Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,0,0,12"
                                   Text="Holder maskinen vågen med det samme, tæller ned, og kører derefter Opdater GRS + genstart af IME én gang. Maskinen holdes vågen indtil du stopper sekvensen."/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                            <TextBlock Text="Nedtælling (minutter):" Foreground="{StaticResource Text}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <TextBox x:Name="TxtAutoMinutes" Text="45" Width="60" Background="#15161A" Foreground="#E6E7EA" BorderBrush="#3A3B43" Padding="6,4"/>
                        </StackPanel>
                        <ProgressBar x:Name="BarAuto" Height="8" Minimum="0" Maximum="100" Value="0" Background="#15161A" Foreground="#3B82F6" BorderThickness="0" Margin="0,0,0,10"/>
                        <TextBlock x:Name="TxtAutoStatus" Foreground="{StaticResource Muted}" Margin="0,0,0,14"/>
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="BtnStartAuto" Style="{StaticResource PrimaryButton}" Content="Start sekvens"/>
                            <Button x:Name="BtnStopAuto"  Style="{StaticResource GhostButton}" Content="Stop" Margin="10,0,0,0" IsEnabled="False"/>
                        </StackPanel>
                    </StackPanel>

                    <!-- No Sleep -->
                    <StackPanel x:Name="PanelNoSleep" Visibility="Collapsed">
                        <TextBlock Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,0,0,12"
                                   Text="Forhindrer maskinen i at gå i dvale og holder skærmen tændt. Aktiv så længe ecDeploy er åben."/>
                        <CheckBox x:Name="ChkNoSleep24" Foreground="{StaticResource Text}" Margin="0,0,0,14" Content="Deaktiver no sleep efter 24 timer"/>
                        <TextBlock x:Name="TxtNoSleepStatus" Foreground="{StaticResource Muted}" Margin="0,0,0,14"/>
                        <Button x:Name="BtnToggleNoSleep" Style="{StaticResource PrimaryButton}" Content="Aktiver No Sleep" HorizontalAlignment="Left"/>
                    </StackPanel>

                    <!-- GRS -->
                    <StackPanel x:Name="PanelGrs" Visibility="Collapsed">
                        <TextBlock Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,0,0,12"
                                   Text="Rydder GRS-nøglerne for alle kontekster, så Intune genevaluerer app-installationer med det samme, og genstarter derefter IME-tjenesten én gang."/>
                        <TextBlock Foreground="#F4B36A" TextWrapping="Wrap" Margin="0,0,0,14"
                                   Text="Bemærk: dette genstarter IME-tjenesten. Undgå at køre det midt i en igangværende installation."/>
                        <TextBlock x:Name="TxtGrsStatus" Foreground="{StaticResource Muted}" Margin="0,0,0,14"/>
                        <Button x:Name="BtnRunGrs" Style="{StaticResource PrimaryButton}" Content="Opdater GRS nu" HorizontalAlignment="Left"/>
                    </StackPanel>

                    <!-- IME restart -->
                    <StackPanel x:Name="PanelIme" Visibility="Collapsed">
                        <TextBlock Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,0,0,12"
                                   Text="Genstarter Intune Management Extension-tjenesten (IME) — bruges til hurtigt at få Intune til at genoptage app-installationer."/>
                        <TextBlock Foreground="#F4B36A" TextWrapping="Wrap" Margin="0,0,0,14"
                                   Text="Bemærk: undgå at genstarte midt i en igangværende installation."/>
                        <TextBlock x:Name="TxtImeStatus" Foreground="{StaticResource Muted}" Margin="0,0,0,14"/>
                        <Button x:Name="BtnRunIme" Style="{StaticResource PrimaryButton}" Content="Genstart IME nu" HorizontalAlignment="Left"/>
                    </StackPanel>

                    <!-- Windows Update status -->
                    <StackPanel x:Name="PanelWu" Visibility="Collapsed">
                        <Border x:Name="WuBanner" Background="#3A2F12" BorderBrush="#7A5E16" BorderThickness="1" CornerRadius="6" Margin="0,0,0,10" Visibility="Collapsed">
                            <TextBlock Foreground="#F4D58A" Margin="12,8" Text="Genstart påkrævet — opdateringer afventer en genstart."/>
                        </Border>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <Button x:Name="BtnWuRefresh" Style="{StaticResource GhostButton}" Content="Opdater"/>
                            <TextBlock x:Name="TxtWuSummary" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="14,0,0,0" TextWrapping="Wrap"/>
                        </StackPanel>
                        <Border Background="#101114" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6">
                            <ScrollViewer MaxHeight="210" VerticalScrollBarVisibility="Auto">
                                <StackPanel x:Name="WuList" Margin="10"/>
                            </ScrollViewer>
                        </Border>
                        <TextBlock x:Name="TxtWuUpdated" Foreground="{StaticResource Muted}" FontSize="11" Margin="0,8,0,0"/>
                    </StackPanel>

                    <!-- App status -->
                    <StackPanel x:Name="PanelApps" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <Button x:Name="BtnAppsRefresh" Style="{StaticResource GhostButton}" Content="Opdater"/>
                            <TextBlock x:Name="TxtAppsSummary" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="14,0,0,0"/>
                        </StackPanel>
                        <Border Background="#101114" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6">
                            <ScrollViewer MaxHeight="210" VerticalScrollBarVisibility="Auto">
                                <StackPanel x:Name="AppsList" Margin="8"/>
                            </ScrollViewer>
                        </Border>
                    </StackPanel>

                    <!-- Live IME log -->
                    <StackPanel x:Name="PanelImeLog" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <CheckBox x:Name="ChkImeErrorsOnly" Foreground="{StaticResource Text}" Content="Kun fejl/advarsler" VerticalAlignment="Center"/>
                            <Button x:Name="BtnImeLogRefresh" Style="{StaticResource GhostButton}" Content="Opdater" Margin="16,0,0,0"/>
                            <TextBlock x:Name="TxtImeLogStatus" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="16,0,0,0"/>
                        </StackPanel>
                        <Border Background="#101114" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6">
                            <TextBox x:Name="ImeLogBox" Height="200" Margin="8" Background="Transparent" Foreground="#C8CBD2"
                                     BorderThickness="0" IsReadOnly="True" FontFamily="Consolas" FontSize="11"
                                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"/>
                        </Border>
                    </StackPanel>

                    <!-- Device info + diagnostics -->
                    <StackPanel x:Name="PanelInfo" Visibility="Collapsed">
                        <Border Background="#101114" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Margin="0,0,0,12">
                            <TextBox x:Name="InfoBox" Height="180" Margin="8" Background="Transparent" Foreground="#C8CBD2"
                                     BorderThickness="0" IsReadOnly="True" FontFamily="Consolas" FontSize="12" VerticalScrollBarVisibility="Auto"/>
                        </Border>
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="BtnInfoRefresh" Style="{StaticResource GhostButton}" Content="Opdater"/>
                            <Button x:Name="BtnDiag" Style="{StaticResource PrimaryButton}" Content="Saml diagnostik (.cab)" Margin="10,0,0,0"/>
                        </StackPanel>
                        <TextBlock x:Name="TxtInfoStatus" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,12,0,0"/>
                    </StackPanel>
                </Grid>

                <!-- Live log -->
                <Border Grid.Row="2" Background="#101114" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Margin="0,16,0,0">
                    <DockPanel>
                        <TextBlock DockPanel.Dock="Top" Text="Status / log" Foreground="{StaticResource Muted}" FontSize="11" Margin="12,8,0,0"/>
                        <TextBox x:Name="LogBox" DockPanel.Dock="Bottom" Margin="10,6,10,10" Background="Transparent" Foreground="#C8CBD2"
                                 BorderThickness="0" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                                 VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
                    </DockPanel>
                </Border>
            </Grid>
        </Grid>
    </Grid>
</Window>
'@
#endregion

#region ---------------------------------------------------------- load window + grab controls
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$script:Window = [Windows.Markup.XamlReader]::Load($reader)

foreach ($name in @(
    'LogoImg','TxtWordmark','TxtDevelopedBy','TxtAdmin','ChipAdmin','TxtOnline','ChipOnline','TxtNoSleep','ChipNoSleep','TxtVersion','BannerNoSleep',
    'NavAuto','NavNoSleep','NavGrs','BtnImeLogs','BtnPrograms','BtnTaskMgr','BtnViewLog',
    'TxtPanelTitle','PanelWelcome','PanelAuto','PanelNoSleep','PanelGrs',
    'TxtAutoMinutes','BarAuto','TxtAutoStatus','BtnStartAuto','BtnStopAuto',
    'ChkNoSleep24','TxtNoSleepStatus','BtnToggleNoSleep',
    'TxtGrsStatus','BtnRunGrs','NavIme','PanelIme','TxtImeStatus','BtnRunIme',
    'NavApps','PanelApps','BtnAppsRefresh','TxtAppsSummary','AppsList',
    'NavImeLog','PanelImeLog','ChkImeErrorsOnly','BtnImeLogRefresh','TxtImeLogStatus','ImeLogBox',
    'NavInfo','PanelInfo','InfoBox','BtnInfoRefresh','BtnDiag','TxtInfoStatus',
    'NavWu','PanelWu','WuBanner','BtnWuRefresh','TxtWuSummary','WuList','TxtWuUpdated','LogBox'
)) { $script:UI[$name] = $script:Window.FindName($name) }

$script:UI.TxtVersion.Text = "v$script:Version"

# Apply the embedded logo to the window/taskbar icon and the header wordmark.
if ($script:LogoImage) {
    $script:Window.Icon = $script:LogoImage
    if ($script:UI.LogoImg) { $script:UI.LogoImg.Source = $script:LogoImage }
}

# Customer rebrand: title, wordmark, "Developed by", logo (when launched with -Customer).
if ($script:Profile) {
    $script:Window.Title = $script:Profile.Brand
    $script:UI.TxtWordmark.Text = $script:Profile.Wordmark
    if ($script:Profile.DevelopedBy) {
        $script:UI.TxtDevelopedBy.Text = $script:Profile.DevelopedBy
        $script:UI.TxtDevelopedBy.Visibility = 'Visible'
    }
    $custImg = ConvertFrom-B64Image $script:Profile.LogoB64
    if ($custImg) { $script:Window.Icon = $custImg; $script:UI.LogoImg.Source = $custImg }
    # Recolour the accent. Buttons use DynamicResource Accent/AccentHover (Background); the
    # ProgressBar Foreground is set directly in code (some ProgressBar templates reject a
    # DynamicResource brush swap on its Foreground).
    # Cast to [Brush] so the resource is a real .NET Brush, never a PSObject-wrapped one
    # (a PSObject in a DynamicResource throws "PSObject cannot be converted to Brush" on render).
    if ($script:Profile.AccentHover) {
        try {
            $hoverColor = [System.Windows.Media.ColorConverter]::ConvertFromString($script:Profile.AccentHover)
            $script:Window.Resources['AccentHover'] = [System.Windows.Media.Brush]([System.Windows.Media.SolidColorBrush]::new($hoverColor))
        } catch {}
    }
    if ($script:Profile.Accent) {
        try {
            $accentColor = [System.Windows.Media.ColorConverter]::ConvertFromString($script:Profile.Accent)
            $accentBrush = [System.Windows.Media.Brush]([System.Windows.Media.SolidColorBrush]::new($accentColor))
            $script:Window.Resources['Accent'] = $accentBrush
            $script:UI.BarAuto.Foreground = $accentBrush
        } catch {}
    }
}
#endregion

#region ---------------------------------------------------------- logging + UI helpers
function Write-LogLine {
    param([string]$Message, [string]$Level = 'INFO')
    # Must run on the UI thread (it touches LogBox). Background work enqueues to $LogQueue instead.
    $now = Get-Date
    $line = '{0}  {1}' -f $now.ToString('HH:mm:ss'), $Message
    try { Add-Content -Path $script:LogFile -Value ('{0}  [{1}] {2}' -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message) } catch {}
    $script:UI.LogBox.AppendText($line + "`r`n")
    $script:UI.LogBox.ScrollToEnd()
}

function Update-Chips {
    if ($script:IsAdmin) { $script:UI.TxtAdmin.Text = 'Admin'; $script:UI.ChipAdmin.Background = '#1F3A24' }
    else                 { $script:UI.TxtAdmin.Text = 'Ikke admin'; $script:UI.ChipAdmin.Background = '#3A2424' }

    if ($script:NoSleepActive) { $script:UI.TxtNoSleep.Text = 'No Sleep: TIL'; $script:UI.ChipNoSleep.Background = '#1F3A24' }
    else                       { $script:UI.TxtNoSleep.Text = 'No Sleep: FRA'; $script:UI.ChipNoSleep.Background = '#2B2C33' }

    $script:UI.BannerNoSleep.Visibility = if ($script:NoSleepActive) { 'Visible' } else { 'Collapsed' }
}

function Set-OnlineChip {
    param([string]$State)   # 'checking' | 'online' | 'offline'
    switch ($State) {
        'checking' { $script:UI.TxtOnline.Text = 'Tjekker...'; $script:UI.ChipOnline.Background = '#2B2C33' }
        'online'   { $script:UI.TxtOnline.Text = 'Online';     $script:UI.ChipOnline.Background = '#1F3A24' }
        'offline'  { $script:UI.TxtOnline.Text = 'Offline';    $script:UI.ChipOnline.Background = '#3A2424' }
    }
}

# Run a scriptblock on a background runspace. $Work may call $Queue.Enqueue("...") for log lines
# and should return a single value (its result). $OnComplete receives that result on the UI thread.
function Start-BackgroundWork {
    param([scriptblock]$Work, [scriptblock]$OnComplete, [object]$Data)

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Queue', $script:LogQueue)
    # Valgfri datapakke til Work-scriptblokken (fx tracked apps at detektere).
    if ($PSBoundParameters.ContainsKey('Data')) { $rs.SessionStateProxy.SetVariable('Data', $Data) }

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Work)
    $handle = $ps.BeginInvoke()

    # Carry per-run state on the timer's Tag (not a closure) so the Tick handler runs in script
    # scope, where Write-LogLine / the OnComplete callback are visible. $this is the timer.
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ Handle = $handle; PS = $ps; RS = $rs; OnComplete = $OnComplete }
    $timer.Add_Tick({
        $s = $this.Tag
        # Drain queued log lines onto the UI.
        $msg = $null
        while ($script:LogQueue.TryDequeue([ref]$msg)) { Write-LogLine $msg }

        if ($s.Handle.IsCompleted) {
            $this.Stop()
            $result = $null
            try { $result = $s.PS.EndInvoke($s.Handle) | Select-Object -Last 1 }
            catch { Write-LogLine ("Baggrundsfejl: {0}" -f $_.Exception.Message) 'ERROR' }
            try { $s.PS.Dispose(); $s.RS.Dispose() } catch {}
            if ($s.OnComplete) { & $s.OnComplete $result }
        }
    })
    $timer.Start()
}
#endregion

#region ---------------------------------------------------------- ecFleet reporting
# Report provisioning status to ecFleet so this machine's serial number is tied to a
# station and shown live on a board. Strictly fire-and-forget: a 404 (no active prep for this
# S/N) or any network error is harmless and must never block the UI thread or throw.
#
# ecFleet-integration er KUN aktiv under en customer-profil med EcfBaseUrl (p.t. CedraDanmark).
# Den generiske ecDeploy (irm ecd.qwe.dk | iex, ingen -Customer) aktiverer intet af dette — alle
# funktioner returnerer straks når $script:EcfEnabled er $false. Hooks i generiske handlinger
# (fx Opdater GRS) er rene no-ops uden en Cedra-profil.

# Capture the BIOS serial once at startup (tolerate failure — leave $null).
$script:DeviceSerial = $null
try {
    $sn = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
    if ($sn) { $script:DeviceSerial = "$sn".Trim() }
} catch {}

# A fresh session id per ecDeploy run. The server resets this machine's board badges whenever the
# id changes, so a new run (e.g. after a reinstall) clears stale badges from the previous run.
$script:EcfSessionId = [guid]::NewGuid().ToString()

# Read endpoint config from the active customer profile (null-safe).
$script:EcfBaseUrl  = $null
$script:EcfApiKey   = $null
$script:EcfAppNames = @{}
$script:EcfAppxChecks = @{}
if ($script:Profile) {
    if ($script:Profile.ContainsKey('EcfBaseUrl')) { $script:EcfBaseUrl = $script:Profile.EcfBaseUrl }
    if ($script:Profile.ContainsKey('EcfApiKey'))  { $script:EcfApiKey  = $script:Profile.EcfApiKey }
    if ($script:Profile.ContainsKey('EcfAppNames')) { $script:EcfAppNames = $script:Profile.EcfAppNames }
    if ($script:Profile.ContainsKey('EcfAppxChecks')) { $script:EcfAppxChecks = $script:Profile.EcfAppxChecks }
}

# Central master switch: ecFleet is only ever active when a customer profile supplied a EcfBaseUrl
# (i.e. CedraDanmark). Generic ecDeploy leaves this $false and every ecFleet function no-ops.
$script:EcfEnabled = [bool]$script:EcfBaseUrl

# Sand når app-navnene er hentet fra ecFleet (trackedApps) mindst én gang.
$script:EcfAppNamesSynced = $false
# Non-Win32 tracked apps (Store/M365/LOB) der detekteres lokalt pr. type:
# array af @{ Gid; Name; Kind; Detect }. Win32 håndteres via IME-registret som før.
$script:EcfExtraApps = @()

# Hent app-navne (GUID -> navn) fra de trackedApps kunden har gemt i ecFleet
# (Admin -> Applikationer) og overstyr den indbyggede liste, så board'et navngiver
# præcis de apps kunden har valgt. Best-effort: beholder den indbyggede liste hvis
# kaldet fejler eller intet er gemt. Resolves server-side ud fra maskinens serial.
function Sync-EcfAppNames {
    if (-not $script:EcfEnabled -or -not $script:DeviceSerial) { return }
    try {
        $uri = "$script:EcfBaseUrl/agent/tracked-apps?serial=$([uri]::EscapeDataString($script:DeviceSerial))"
        $headers = @{}
        if ($script:EcfApiKey) { $headers['X-Api-Key'] = $script:EcfApiKey }
        $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 4
        if ($resp -and $resp.apps) {
            $map = @{}
            $extra = @()
            foreach ($a in $resp.apps) {
                if (-not $a.id -or -not $a.name) { continue }
                $gid = "$($a.id)".ToLower()
                if ("$($a.id)" -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                    $gid = $matches[1].ToLower()
                }
                $map[$gid] = "$($a.name)"
                # Kind mangler på ældre gemte apps -> antag win32 (bagudkompatibelt).
                $kind = if ($a.PSObject.Properties['kind'] -and $a.kind) { "$($a.kind)".ToLower() } else { 'win32' }
                if ($kind -ne 'win32') {
                    $detect = if ($a.PSObject.Properties['detect']) { "$($a.detect)" } else { '' }
                    $extra += @{ Gid = $gid; Name = "$($a.name)"; Kind = $kind; Detect = $detect }
                }
            }
            if ($map.Count -gt 0) {
                $script:EcfAppNames  = $map
                $script:EcfExtraApps = $extra
                $script:EcfAppNamesSynced = $true
                Write-LogLine ("ecFleet: {0} app-navne hentet ({1} ikke-Win32 til lokal detektion)" -f $map.Count, $extra.Count)
            } elseif ($resp.ok) {
                # Serveren svarede, men kunden har ikke gemt nogen apps endnu.
                $script:EcfAppNamesSynced = $true
            }
        }
    } catch {
        Write-LogLine 'ecFleet: kunne ikke hente app-navne fra server (bruger indbygget liste)' 'WARN'
    }
}
if ($script:EcfEnabled) { Sync-EcfAppNames }

# POST a batch of checks to ecFleet on a background runspace. The server merges checks by 'key'.
function Send-EcfReport {
    param([object[]]$Checks)
    if (-not $script:EcfEnabled) { return }
    if (-not $script:EcfBaseUrl -or -not $script:DeviceSerial -or -not $Checks -or $Checks.Count -eq 0) { return }

    try {
        $body = @{ serialNumber = $script:DeviceSerial; session = $script:EcfSessionId; checks = $Checks } | ConvertTo-Json -Depth 6
        $uri  = "$script:EcfBaseUrl/agent/report"
        $headers = @{}
        if ($script:EcfApiKey) { $headers['X-Api-Key'] = $script:EcfApiKey }

        # Fire on a background runspace so the HTTP call never touches the UI thread and never
        # blocks it. Only runspace-safe objects ($script:LogQueue, plain values) cross over. A
        # short DispatcherTimer reaps the runspace once the call completes (mirrors Start-BackgroundWork).
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'MTA'
        $rs.ThreadOptions  = 'ReuseThread'
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('Queue',   $script:LogQueue)
        $rs.SessionStateProxy.SetVariable('Uri',     $uri)
        $rs.SessionStateProxy.SetVariable('Body',    $body)
        $rs.SessionStateProxy.SetVariable('Headers', $headers)

        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            try {
                # Send as UTF-8 bytes — PS 5.1's Invoke-RestMethod otherwise encodes the string as
                # Latin1, mangling danske tegn (æ/ø/å) into invalid UTF-8 (e.g. "Klargøring" -> "Klarg?ring").
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
                [void](Invoke-RestMethod -Method Post -Uri $Uri -Body $bytes -ContentType 'application/json; charset=utf-8' -Headers $Headers -TimeoutSec 5)
            } catch {
                # Log ÅRSAGEN så man kan skelne: HTTP 404 (S/N matcher ingen aktiv klargøring
                # / backend ikke opdateret), HTTP 401 (forkert API-nøgle), eller netværksfejl
                # (kan ikke nå serveren — typisk IP/firewall). Best-effort.
                $detail = $_.Exception.Message
                try {
                    $r = $_.Exception.Response
                    if ($r -and $r.StatusCode) { $detail = "HTTP $([int]$r.StatusCode) $($r.StatusCode)" }
                } catch {}
                try { $Queue.Enqueue("ecFleet: kunne ikke sende status ($detail)") } catch {}
            }
        })
        $handle = $ps.BeginInvoke()

        # Reap on completion. State on the timer's Tag (not a closure), like Start-BackgroundWork.
        $reaper = New-Object System.Windows.Threading.DispatcherTimer
        $reaper.Interval = [TimeSpan]::FromMilliseconds(250)
        $reaper.Tag = @{ Handle = $handle; PS = $ps; RS = $rs }
        $reaper.Add_Tick({
            $s = $this.Tag
            # Note: a best-effort failure line is enqueued to $script:LogQueue and drained by the
            # existing Start-BackgroundWork timer's log pump; we don't drain here so we never
            # mislabel another round's INFO lines. This reaper only disposes the runspace.
            if ($s.Handle.IsCompleted) {
                $this.Stop()
                try { $s.PS.EndInvoke($s.Handle) } catch {}
                try { $s.PS.Dispose(); $s.RS.Dispose() } catch {}
            }
        })
        $reaper.Start()
    } catch {
        # Never throw from a status report.
        try { $script:LogQueue.Enqueue('ecFleet: kunne ikke sende status') } catch {}
    }
}

# Convenience: report a single check.
function Set-EcfCheck {
    param([string]$Key, [string]$Label, [string]$Status, [string]$Message)
    if (-not $script:EcfEnabled) { return }
    Send-EcfReport @(@{ key = $Key; label = $Label; status = $Status; message = $Message })
}

# App-fejl-håndtering: vis en popup til teknikeren, ryd GRS så Intune forsøger
# installationen igen, og spring auto-genstart over (håndteres i Start-RestartCountdown
# via $script:AppFailed). Kaldes fra Report-EcfStatus ved en fejl-transition.
function Notify-AppFailure {
    param([string[]]$Names)
    $list = (@($Names) | Select-Object -Unique) -join ', '
    Write-LogLine "App(s) fejlede: $list — rydder GRS for retry, springer auto-genstart over" 'WARN'
    try {
        [System.Windows.MessageBox]::Show(
            "Én eller flere apps fejlede under installationen:`n`n$list`n`nGRS-nøglerne ryddes nu, så Intune forsøger installationen igen.`nMaskinen bliver IKKE genstartet automatisk.",
            'ecDeploy — app-installation fejlede',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
    } catch {}
    try { Invoke-GrsRefresh } catch { Write-LogLine "GRS-ryd efter app-fejl fejlede: $($_.Exception.Message)" 'ERROR' }
}

# Detektér install-status for IKKE-Win32 tracked apps (Store/M365/LOB) on-device,
# pr. type. Kører i en baggrunds-runspace via Start-BackgroundWork -Data. Input
# ($Data) = array af @{ Gid; Name; Kind; Detect }; output = @{ Gid; Name; Installed }.
$script:ExtraAppWork = {
    $out = @()
    foreach ($app in @($Data)) {
        $installed = $false
        try {
            switch ("$($app.Kind)".ToLower()) {
                'msi' {
                    # LOB MSI: installeret hvis ProductCode findes i Uninstall-registret.
                    $pc = "$($app.Detect)".Trim()
                    if ($pc) {
                        foreach ($p in @(
                            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$pc",
                            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$pc")) {
                            if (Test-Path $p) { $installed = $true; break }
                        }
                    }
                }
                'm365' {
                    # Microsoft 365 Apps: installeret hvis Click-to-Run har produkter registreret.
                    $cfg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
                    if ($cfg -and $cfg.ProductReleaseIds) { $installed = $true }
                }
                default {
                    # store / appx: match på package family name / navn (best-effort).
                    $d = "$($app.Detect)".Trim()
                    if ($d) {
                        $pkg = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                            Where-Object { $_.PackageFamilyName -like "*$d*" -or $_.Name -like "*$d*" } |
                            Select-Object -First 1
                        if ($pkg) { $installed = $true }
                    }
                }
            }
        } catch {}
        $out += [pscustomobject]@{ Gid = $app.Gid; Name = $app.Name; Installed = $installed }
    }
    return ,$out
}

# Gather named app + Windows Update status and report them as ecFleet badges. Each part runs on
# its own background runspace via Start-BackgroundWork (same pattern as Update-AppStatus /
# Update-WuStatus); the checks are built in the OnComplete callback (UI thread — safe) and each
# part sends its own batch. Non-blocking and best-effort: returns immediately when not configured.
function Report-EcfStatus {
    if (-not $script:EcfEnabled) { return }
    if (-not $script:DeviceSerial) { return }

    # Hent app-navne fra ecFleet hvis det ikke lykkedes ved opstart (fx fordi S/N
    # endnu ikke var registreret). Prøver igen hvert tick indtil det lykkes én gang.
    if (-not $script:EcfAppNamesSynced) { Sync-EcfAppNames }

    # Apps: one badge per PRE-DEFINED Intune Win32 app (EcfAppNames), by friendly name.
    # Undefined apps (and the GRS key) are skipped entirely.
    Start-BackgroundWork -Work $script:AppStatusWork -OnComplete {
        param($res)
        if (-not ($res -is [hashtable]) -or -not $res.Apps) { return }
        $checks = @()
        $failedNames = @()
        foreach ($a in $res.Apps) {
            # Prefer a configured friendly name: derive the base GUID from the IME app id (the "_1"
            # revision suffix is ignored) and look it up; otherwise fall back to $a.Name (IME-log map / GUID).
            # Vis KUN apps vi har pre-defineret i EcfAppNames — skip alt andet (GRS-nøglen og
            # udefinerede apps som fx en ny BitLocker-app). Kun rigtige app-GUID'er i tabellen.
            $gid = $null
            if ("$($a.Id)" -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $gid = $matches[1].ToLower()
            }
            if (-not $gid -or -not $script:EcfAppNames.ContainsKey($gid)) { continue }
            $name = $script:EcfAppNames[$gid]
            # Apps der dækkes af et Appx-check rapporteres derfra (ikke via Intune-registret).
            if ($script:EcfAppxChecks.ContainsKey($name)) { continue }
            # Vis KUN apps der ER installeret (grønt navn) eller er FEJLET (rødt navn).
            # Pending/ukendt skjules — board'et viser kun færdige resultater.
            switch ($a.Cat) {
                'Installed' { $checks += @{ key = "app:$($a.Id)"; label = "$name"; status = 'ok';   message = '' } }
                'Failed'    { $checks += @{ key = "app:$($a.Id)"; label = "$name"; status = 'fail'; message = "fejlkode $($a.Err)" }; $failedNames += $name }
                default     { }   # Pending/ukendt: vis ikke
            }
        }
        if ($checks.Count -gt 0) { Send-EcfReport $checks }

        # Fejl-håndtering: mindst én app fejlede -> popup + GRS-ryd (retry) + ingen
        # auto-genstart. Udløses kun ved fejl-transition (ikke hvert 60-sek-tick).
        if ($failedNames.Count -gt 0) {
            $script:AppFailed = $true
            if (-not $script:AppFailureNotified) {
                $script:AppFailureNotified = $true
                Notify-AppFailure $failedNames
            }
        } else {
            $script:AppFailed = $false
            $script:AppFailureNotified = $false
        }
    }

    # Apps installed directly by CedraDeploy (e.g. Company Portal) — report from the actual appx
    # package via Get-AppxPackage, not the Intune/IME registry (which never sees a direct install).
    if ($script:EcfAppxChecks.Count -gt 0) {
        $appxChecks = @()
        foreach ($entry in $script:EcfAppxChecks.GetEnumerator()) {
            $installed = $false
            try { if (Get-AppxPackage -Name $entry.Value -ErrorAction SilentlyContinue) { $installed = $true } } catch {}
            # Vis kun når den ER installeret (grønt navn); ellers ingen badge.
            if ($installed) { $appxChecks += @{ key = "appx:$($entry.Value)"; label = "$($entry.Key)"; status = 'ok'; message = '' } }
        }
        if ($appxChecks.Count -gt 0) { Send-EcfReport $appxChecks }
    }

    # Ikke-Win32 tracked apps (Store/M365/LOB): detektér lokalt pr. type i baggrunden.
    # Vises kun når de ER installeret (grønt navn) — samme princip som Win32.
    if ($script:EcfExtraApps -and $script:EcfExtraApps.Count -gt 0) {
        Start-BackgroundWork -Data $script:EcfExtraApps -Work $script:ExtraAppWork -OnComplete {
            param($res)
            if (-not $res) { return }
            $checks = @()
            foreach ($r in @($res)) {
                if ($r.Installed) { $checks += @{ key = "app:$($r.Gid)"; label = "$($r.Name)"; status = 'ok'; message = '' } }
            }
            if ($checks.Count -gt 0) { Send-EcfReport $checks }
        }
    }

    # Windows Update + reboot: read-only status snapshot ($script:WuWork). 'running' when a WU drive
    # is live ($script:WuDriveBusy) OR the history shows a recent InProgress entry — so the badge
    # doesn't say "OK" while the panel still shows "I gang".
    Start-BackgroundWork -Work $script:WuWork -OnComplete {
        param($res)
        if (-not ($res -is [hashtable])) { return }
        $checks = @()
        if ($script:WuDriveBusy -or $res.InProgress -gt 0) {
            $checks += @{ key = 'windows_update'; label = 'Windows Update kører'; status = 'running'; message = '' }
        } elseif ($res.Pending -gt 0) {
            $checks += @{ key = 'windows_update'; label = 'Windows Update'; status = 'warn'; message = ("{0} afventer" -f $res.Pending) }
        } else {
            $checks += @{ key = 'windows_update'; label = 'Windows Update OK'; status = 'ok'; message = '' }
        }
        # (Reboot-badge fjernet — "Mangler genstart" er irrelevant på board'et.)
        Send-EcfReport $checks
    }
}

# Report ecFleet status on a cadence (60 s) while a Cedra flow is active.
function Start-EcfCadence {
    if (-not $script:EcfEnabled) { return }
    if (-not $script:EcfCadenceTimer) {
        $script:EcfCadenceTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:EcfCadenceTimer.Interval = [TimeSpan]::FromSeconds(60)
        $script:EcfCadenceTimer.Add_Tick({ Report-EcfStatus })
    }
    $script:EcfCadenceTimer.Start()
}

function Stop-EcfCadence {
    if ($script:EcfCadenceTimer) { $script:EcfCadenceTimer.Stop() }
}
#endregion

#region ---------------------------------------------------------- No Sleep
function Set-KeepAwake {
    param([bool]$On)
    if ($On) {
        [void][EcPower]::SetThreadExecutionState($script:ES_CONTINUOUS -bor $script:ES_SYSTEM_REQUIRED -bor $script:ES_DISPLAY_REQUIRED)
    } else {
        [void][EcPower]::SetThreadExecutionState($script:ES_CONTINUOUS)
        if ($script:NoSleep24Timer) { $script:NoSleep24Timer.Stop(); $script:NoSleep24Timer = $null }
    }
    $script:NoSleepActive = $On
    Update-Chips
}

function Switch-NoSleep {
    if ($script:NoSleepActive) {
        Set-KeepAwake $false
        $script:UI.BtnToggleNoSleep.Content = 'Aktiver No Sleep'
        $script:UI.TxtNoSleepStatus.Text = 'No Sleep er slået fra.'
        Write-LogLine 'No Sleep slået fra'
    } else {
        Set-KeepAwake $true
        $script:UI.BtnToggleNoSleep.Content = 'Deaktiver No Sleep'
        if ($script:UI.ChkNoSleep24.IsChecked) {
            $script:NoSleep24Timer = New-Object System.Windows.Threading.DispatcherTimer
            $script:NoSleep24Timer.Interval = [TimeSpan]::FromHours(24)
            $script:NoSleep24Timer.Add_Tick({
                $script:NoSleep24Timer.Stop(); $script:NoSleep24Timer = $null
                Set-KeepAwake $false
                $script:UI.BtnToggleNoSleep.Content = 'Aktiver No Sleep'
                $script:UI.TxtNoSleepStatus.Text = 'No Sleep udløb efter 24 timer.'
                Write-LogLine 'No Sleep udløb automatisk efter 24 timer'
            })
            $script:NoSleep24Timer.Start()
            $script:UI.TxtNoSleepStatus.Text = 'No Sleep er aktiv (slipper automatisk efter 24 timer).'
            Write-LogLine 'No Sleep slået til (24-timers grænse)'
        } else {
            $script:UI.TxtNoSleepStatus.Text = 'No Sleep er aktiv (indtil du slår det fra eller lukker ecDeploy).'
            Write-LogLine 'No Sleep slået til (ubegrænset)'
        }
    }
}
#endregion

#region ---------------------------------------------------------- GRS refresh
# Returns a hashtable: @{ Cleared; ImeRestarted; ImeMissing; Win32Missing }
$script:GrsWork = {
    $base = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
    $Queue.Enqueue('Opdater GRS startet')
    $res = @{ Cleared = 0; ImeRestarted = $false; ImeMissing = $false; Win32Missing = $false }

    if (-not (Test-Path $base)) {
        $Queue.Enqueue('Win32Apps-nøglen findes ikke endnu — intet at rydde')
        $res.Win32Missing = $true
        return $res
    }

    foreach ($ctx in (Get-ChildItem -Path $base -ErrorAction SilentlyContinue)) {
        $grs = Join-Path $ctx.PSPath 'GRS'
        if (Test-Path $grs) {
            try {
                Remove-Item -Path $grs -Recurse -Force -ErrorAction Stop
                $res.Cleared++
                $Queue.Enqueue("GRS ryddet for kontekst: $($ctx.PSChildName)")
            } catch {
                $Queue.Enqueue("FEJL ved sletning af GRS ($($ctx.PSChildName)): $($_.Exception.Message)")
            }
        }
    }
    if ($res.Cleared -eq 0) { $Queue.Enqueue('Ingen GRS-nøgler fundet — intet at rydde') }

    # Restart IME (by service name, then display name as fallback).
    $svc = Get-Service -Name 'IntuneManagementExtension' -ErrorAction SilentlyContinue
    if (-not $svc) { $svc = Get-Service -DisplayName '*Intune Management Extension*' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $svc) {
        $Queue.Enqueue('IME-tjenesten findes ikke — springer genstart over')
        $res.ImeMissing = $true
    } else {
        try {
            Restart-Service -InputObject $svc -Force -ErrorAction Stop
            $res.ImeRestarted = $true
            $Queue.Enqueue('IME-tjenesten genstartet')
        } catch {
            $Queue.Enqueue("FEJL ved genstart af IME: $($_.Exception.Message)")
        }
    }
    return $res
}

function Invoke-GrsRefresh {
    param([switch]$FromSequence)

    if (-not $script:IsAdmin) {
        $script:UI.TxtGrsStatus.Text = 'Kræver administrator. Genstart ecDeploy som administrator.'
        Write-LogLine 'Opdater GRS afvist: ikke administrator' 'WARN'
        return
    }

    $script:UI.BtnRunGrs.IsEnabled = $false
    if (-not $FromSequence) { $script:UI.TxtGrsStatus.Text = 'Arbejder...' }

    Start-BackgroundWork -Work $script:GrsWork -OnComplete {
        param($res)
        if ($res -is [hashtable]) {
            $summary = "Færdig: $($res.Cleared) GRS ryddet"
            if ($res.ImeRestarted) { $summary += ', IME genstartet' }
            elseif ($res.ImeMissing) { $summary += ', IME ikke fundet' }
            $script:UI.TxtGrsStatus.Text = $summary
            if ($script:SeqRunning) { $script:UI.TxtAutoStatus.Text = "GRS udført kl. $((Get-Date).ToString('HH:mm')) — holder maskinen vågen. Tryk Stop for at afslutte." }
        } else {
            $script:UI.TxtGrsStatus.Text = 'Færdig (se log).'
        }
        if (-not $script:SeqRunning) { $script:UI.BtnRunGrs.IsEnabled = $true }
        Report-EcfStatus   # GRS just re-evaluated apps — refresh the board now
    }
}
#endregion

#region ---------------------------------------------------------- IME restart
# Returns a hashtable: @{ Restarted; Missing }
$script:ImeRestartWork = {
    $Queue.Enqueue('Genstart af IME startet')
    $res = @{ Restarted = $false; Missing = $false }
    $svc = Get-Service -Name 'IntuneManagementExtension' -ErrorAction SilentlyContinue
    if (-not $svc) { $svc = Get-Service -DisplayName '*Intune Management Extension*' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $svc) {
        $Queue.Enqueue('IME-tjenesten findes ikke på denne maskine')
        $res.Missing = $true
    } else {
        try {
            Restart-Service -InputObject $svc -Force -ErrorAction Stop
            $res.Restarted = $true
            $Queue.Enqueue('IME-tjenesten genstartet')
        } catch {
            $Queue.Enqueue("FEJL ved genstart af IME: $($_.Exception.Message)")
        }
    }
    return $res
}

function Invoke-ImeRestart {
    if (-not $script:IsAdmin) {
        $script:UI.TxtImeStatus.Text = 'Kræver administrator. Genstart ecDeploy som administrator.'
        Write-LogLine 'Genstart IME afvist: ikke administrator' 'WARN'
        return
    }
    $script:UI.BtnRunIme.IsEnabled = $false
    $script:UI.TxtImeStatus.Text = 'Genstarter IME...'

    Start-BackgroundWork -Work $script:ImeRestartWork -OnComplete {
        param($res)
        if ($res -is [hashtable] -and $res.Restarted) {
            $script:UI.TxtImeStatus.Text = "Færdig: IME-tjenesten genstartet kl. $((Get-Date).ToString('HH:mm'))"
        } elseif ($res -is [hashtable] -and $res.Missing) {
            $script:UI.TxtImeStatus.Text = 'IME-tjenesten findes ikke på denne maskine.'
        } else {
            $script:UI.TxtImeStatus.Text = 'Genstart fejlede (se log).'
        }
        if (-not $script:SeqRunning) { $script:UI.BtnRunIme.IsEnabled = $true }
    }
}
#endregion

#region ---------------------------------------------------------- diagnostics: apps / IME log / device info
# Enumerate Intune Win32 app enforcement states from the registry. Best-effort: state codes are
# mapped to Installed/Failed/Pending; app ids are GUIDs (friendly names aren't in the registry).
$script:AppStatusWork = {
    $base = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
    $res = @{ Apps = @(); Installed = 0; Failed = 0; Pending = 0; Unknown = 0; Note = '' }
    if (-not (Test-Path $base)) { $res.Note = 'Win32Apps-nøglen findes ikke (maskinen er måske ikke Intune-managed endnu).'; return $res }

    # Best-effort GUID -> friendly name map from the IME log (format varies by IME version).
    $nameMap = @{}
    $imeLog = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log'
    if (Test-Path $imeLog) {
        try {
            $fs = [System.IO.File]::Open($imeLog, 'Open', 'Read', 'ReadWrite')
            $rdr = New-Object System.IO.StreamReader($fs); $logText = $rdr.ReadToEnd(); $rdr.Close(); $fs.Close()
            $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
            $patterns = @(
                [regex]("(?i)name[`"']?\s*[:=]\s*[`"'](?<name>[^`"']+)[`"'].{0,160}?(?<id>$guid)"),
                [regex]("(?i)(?<id>$guid).{0,160}?name[`"']?\s*[:=]\s*[`"'](?<name>[^`"']+)[`"']")
            )
            foreach ($rx in $patterns) {
                foreach ($m in $rx.Matches($logText)) {
                    $gid = $m.Groups['id'].Value.ToLower(); $nm = $m.Groups['name'].Value.Trim()
                    if ($gid -and $nm -and -not $nameMap.ContainsKey($gid)) { $nameMap[$gid] = $nm }
                }
            }
        } catch {}
    }

    $skip = @('GRS','Reporting','OperationalState','GRSStore')
    foreach ($ctx in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
        if ($skip -contains $ctx.PSChildName) { continue }
        foreach ($app in (Get-ChildItem $ctx.PSPath -ErrorAction SilentlyContinue)) {
            $esm = $null
            $p = Get-ItemProperty $app.PSPath -ErrorAction SilentlyContinue
            if ($p -and ($p.PSObject.Properties.Name -contains 'EnforcementStateMessage')) { $esm = $p.EnforcementStateMessage }
            if (-not $esm) {
                foreach ($sub in (Get-ChildItem $app.PSPath -ErrorAction SilentlyContinue)) {
                    $ps = Get-ItemProperty $sub.PSPath -ErrorAction SilentlyContinue
                    if ($ps -and ($ps.PSObject.Properties.Name -contains 'EnforcementStateMessage')) { $esm = $ps.EnforcementStateMessage; break }
                }
            }
            $code = $null; $err = $null
            if ($esm) { try { $j = $esm | ConvertFrom-Json; $code = $j.EnforcementState; $err = $j.ErrorCode } catch {} }
            $cat = 'Unknown'; $label = 'Ukendt'
            if ($null -ne $code) {
                $n = [int]$code
                if ($n -eq 1000 -or $n -eq 1003) { $cat = 'Installed'; $label = 'Installeret' }
                elseif ($n -ge 3000) { $cat = 'Failed'; $label = 'Fejlet' }
                elseif ($n -ge 2000) { $cat = 'Pending'; $label = 'I gang' }
                else { $label = "Kode $n" }
            }
            switch ($cat) { 'Installed' { $res.Installed++ } 'Failed' { $res.Failed++ } 'Pending' { $res.Pending++ } default { $res.Unknown++ } }
            $id = $app.PSChildName
            $name = $id
            if ($id -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $g = $matches[1].ToLower()
                if ($nameMap.ContainsKey($g)) { $name = $nameMap[$g] }
            }
            $res.Apps += [pscustomobject]@{ Id = $id; Name = $name; Label = $label; Cat = $cat; Code = $code; Err = $err }
        }
    }
    return $res
}

function Update-AppStatus {
    $script:UI.AppsList.Children.Clear()
    $script:UI.TxtAppsSummary.Text = 'Indlæser...'
    Start-BackgroundWork -Work $script:AppStatusWork -OnComplete {
        param($res)
        $script:UI.AppsList.Children.Clear()
        if (-not ($res -is [hashtable])) { $script:UI.TxtAppsSummary.Text = 'Fejl (se log).'; return }
        if ($res.Note) { $script:UI.TxtAppsSummary.Text = $res.Note; return }
        if ($res.Apps.Count -eq 0) { $script:UI.TxtAppsSummary.Text = 'Ingen Win32-apps fundet.'; return }
        $script:UI.TxtAppsSummary.Text = ('{0} installeret · {1} fejlet · {2} i gang · {3} ukendt' -f $res.Installed, $res.Failed, $res.Pending, $res.Unknown)
        $colors = @{ Installed = '#22C55E'; Failed = '#EF4444'; Pending = '#F59E0B'; Unknown = '#9AA0AA' }
        $order = @{ Failed = 0; Pending = 1; Unknown = 2; Installed = 3 }
        foreach ($a in ($res.Apps | Sort-Object @{ Expression = { $order[$_.Cat] } })) {
            $row = New-Object System.Windows.Controls.DockPanel
            $row.Margin = '0,2'
            $chip = New-Object System.Windows.Controls.TextBlock
            $chip.Text = $a.Label; $chip.Width = 90; $chip.Foreground = $colors[$a.Cat]
            $id = New-Object System.Windows.Controls.TextBlock
            $id.Text = $a.Name + $(if ($null -ne $a.Err -and $a.Err -ne 0) { "   fejlkode: $($a.Err)" } else { '' })
            $id.Foreground = '#C8CBD2'; $id.FontSize = 12; $id.TextTrimming = 'CharacterEllipsis'
            if ($a.Name -eq $a.Id) { $id.FontFamily = 'Consolas'; $id.FontSize = 11 }   # GUID fallback: monospace
            [void]$row.Children.Add($chip); [void]$row.Children.Add($id)
            [void]$script:UI.AppsList.Children.Add($row)
        }
    }
}

# Read the tail of the IME log (shared read so it works while IME has it open).
function Read-ImeLogTail {
    param([int]$Lines = 250, [bool]$ErrorsOnly = $false)
    if (-not (Test-Path $script:ImeLogFile)) { return 'IME-loggen findes ikke på denne maskine.' }
    try {
        $fs = [System.IO.File]::Open($script:ImeLogFile, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
    } catch { return "Kunne ikke læse IME-loggen: $($_.Exception.Message)" }
    $arr = $text -split "`r?`n"
    if ($ErrorsOnly) { $arr = @($arr | Where-Object { $_ -match '(?i)error|fail|exception|warning' }) }
    return (($arr | Select-Object -Last $Lines) -join "`r`n")
}

function Update-ImeLog {
    $script:UI.ImeLogBox.Text = Read-ImeLogTail -ErrorsOnly ([bool]$script:UI.ChkImeErrorsOnly.IsChecked)
    $script:UI.ImeLogBox.ScrollToEnd()
    $script:UI.TxtImeLogStatus.Text = "Opdateret kl. $((Get-Date).ToString('HH:mm:ss'))"
}

# Device info (WMI + dsregcmd) gathered on a background runspace.
$script:DeviceInfoWork = {
    $lines = @()
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $lines += "Computernavn : $env:COMPUTERNAME"
    $lines += "Bruger       : $env:USERNAME"
    if ($cs)   { $lines += "Producent    : $($cs.Manufacturer)"; $lines += "Model        : $($cs.Model)" }
    if ($bios) { $lines += "Serienummer  : $($bios.SerialNumber)" }
    if ($os)   { $lines += "OS           : $($os.Caption)" }
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        if ($cv) { $lines += "Build        : $($cv.DisplayVersion) ($($cv.CurrentBuild).$($cv.UBR))" }
    } catch {}
    try {
        $ds = & dsregcmd /status 2>$null
        foreach ($k in 'AzureAdJoined', 'DomainJoined', 'TenantName', 'DeviceId') {
            $m = $ds | Select-String -Pattern ("\b{0}\s*:\s*(.+)$" -f $k)
            if ($m) { $lines += ('{0,-12} : {1}' -f $k, $m.Matches[0].Groups[1].Value.Trim()) }
        }
    } catch {}
    return ($lines -join "`r`n")
}

function Update-DeviceInfo {
    $script:UI.InfoBox.Text = 'Indlæser...'
    Start-BackgroundWork -Work $script:DeviceInfoWork -OnComplete { param($txt) $script:UI.InfoBox.Text = [string]$txt }
}

# Collect an MDM diagnostics .cab for escalation.
$script:DiagWork = {
    $out = Join-Path $env:TEMP 'ecDeploy-MDMDiag.cab'
    $tool = Join-Path $env:WINDIR 'system32\mdmdiagnosticstool.exe'
    if (-not (Test-Path $tool)) { $Queue.Enqueue('mdmdiagnosticstool.exe findes ikke på denne maskine'); return @{ Ok = $false; Path = $null } }
    $Queue.Enqueue('Samler MDM-diagnostik...')
    try {
        & $tool -area 'Autopilot;DeviceEnrollment;DeviceProvisioning;TPM' -cab $out 2>&1 | Out-Null
        if (Test-Path $out) { $Queue.Enqueue("Diagnostik gemt: $out"); return @{ Ok = $true; Path = $out } }
        $Queue.Enqueue('Diagnostik-cab blev ikke oprettet')
    } catch { $Queue.Enqueue("FEJL ved diagnostik: $($_.Exception.Message)") }
    return @{ Ok = $false; Path = $null }
}

function Invoke-Diagnostics {
    $script:UI.BtnDiag.IsEnabled = $false
    $script:UI.TxtInfoStatus.Text = 'Samler diagnostik (kan tage et øjeblik)...'
    Start-BackgroundWork -Work $script:DiagWork -OnComplete {
        param($res)
        $script:UI.BtnDiag.IsEnabled = $true
        if ($res -is [hashtable] -and $res.Ok) {
            $script:UI.TxtInfoStatus.Text = "Diagnostik gemt: $($res.Path)"
            try { Start-Process 'explorer.exe' -ArgumentList "/select,`"$($res.Path)`"" } catch {}
        } else {
            $script:UI.TxtInfoStatus.Text = 'Kunne ikke samle diagnostik (se log).'
        }
    }
}
#endregion

#region ---------------------------------------------------------- Windows Update status (in-panel)
# Windows Update status is shown in the main window's "Windows Update" panel (not a separate window).
# Reads state via the Windows Update Agent COM API — it only *observes*; updates are driven by the WU drive.
$script:WuTimer = $null

# Background COM query — fast (offline pending search + local history + reboot flag).
$script:WuWork = {
    $res = @{ Pending = 0; History = @(); Reboot = $false; InProgress = 0; Error = $null }
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        try { $searcher.Online = $false } catch {}
        try { $res.Pending = $searcher.Search('IsInstalled=0 and IsHidden=0').Updates.Count } catch {}
        try {
            $cutoff = (Get-Date).AddMinutes(-30)
            $total = $searcher.GetTotalHistoryCount()
            if ($total -gt 0) {
                foreach ($e in $searcher.QueryHistory(0, [math]::Min($total, 25))) {
                    $date = $null
                    try { $date = [datetime]$e.Date } catch {}
                    $res.History += @{ Title = [string]$e.Title; Result = [int]$e.ResultCode; Date = $date }
                    # Count "InProgress" (ResultCode 1) entries seen within the last 30 minutes; a
                    # missing/invalid date is not counted (tolerate it rather than guess).
                    if ([int]$e.ResultCode -eq 1 -and $date -and $date -ge $cutoff) { $res.InProgress++ }
                }
            }
        } catch {}
        try { $res.Reboot = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired } catch {}
    } catch { $res.Error = $_.Exception.Message }
    return $res
}

function Update-WuStatus {
    if ($script:UI.WuList.Children.Count -eq 0 -and -not $script:UI.TxtWuSummary.Text) {
        $script:UI.TxtWuSummary.Text = 'Indlæser Windows Update-status...'
    }
    Start-BackgroundWork -Work $script:WuWork -OnComplete {
        param($res)
        if (-not ($res -is [hashtable])) { return }
        if ($res.Error) { $script:UI.TxtWuSummary.Text = "Kunne ikke læse Windows Update: $($res.Error)"; return }
        $script:UI.WuBanner.Visibility = if ($res.Reboot) { 'Visible' } else { 'Collapsed' }
        $ok = 0; $fail = 0
        foreach ($h in $res.History) { if ($h.Result -eq 2 -or $h.Result -eq 3) { $ok++ } elseif ($h.Result -ge 4) { $fail++ } }
        $script:UI.TxtWuSummary.Text = ('{0} afventer · {1} installeret · {2} fejlet (seneste historik)' -f $res.Pending, $ok, $fail)
        $map = @{ 0 = 'Ikke startet'; 1 = 'I gang'; 2 = 'Installeret'; 3 = 'Installeret (advarsler)'; 4 = 'Fejlet'; 5 = 'Afbrudt' }
        $col = @{ 0 = '#9AA0AA'; 1 = '#3B82F6'; 2 = '#22C55E'; 3 = '#F59E0B'; 4 = '#EF4444'; 5 = '#EF4444' }
        $script:UI.WuList.Children.Clear()
        foreach ($h in $res.History) {
            $row = New-Object System.Windows.Controls.DockPanel; $row.Margin = '0,3'
            $chip = New-Object System.Windows.Controls.TextBlock
            $chip.Text = $(if ($map.ContainsKey($h.Result)) { $map[$h.Result] } else { "Kode $($h.Result)" })
            $chip.Width = 150
            $chip.Foreground = $(if ($col.ContainsKey($h.Result)) { $col[$h.Result] } else { '#9AA0AA' })
            $t = New-Object System.Windows.Controls.TextBlock
            $t.Text = $h.Title; $t.Foreground = '#C8CBD2'; $t.TextTrimming = 'CharacterEllipsis'
            [void]$row.Children.Add($chip); [void]$row.Children.Add($t)
            [void]$script:UI.WuList.Children.Add($row)
        }
        if ($res.History.Count -eq 0) {
            $empty = New-Object System.Windows.Controls.TextBlock
            $empty.Text = 'Ingen Windows Update-historik endnu.'; $empty.Foreground = '#9AA0AA'
            [void]$script:UI.WuList.Children.Add($empty)
        }
        $script:UI.TxtWuUpdated.Text = "Opdateret kl. $((Get-Date).ToString('HH:mm:ss'))"
    }
}

# Drive Windows Update: search + download + install via COM (used by the customer flows).
$script:WuDriveWork = {
    $res = @{ Searched = 0; Installed = 0; Failed = 0; Reboot = $false; Error = $null }
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        # Opt into Microsoft Update (Office, drivers, other MS products) — like PSWindowsUpdate -MicrosoftUpdate.
        $muId = '7971f918-a847-4430-9279-4a52d1efe18d'
        try {
            $sm = New-Object -ComObject Microsoft.Update.ServiceManager
            [void]$sm.AddService2($muId, 7, '')   # 7 = pending|online|registerWithAU
            $searcher.ServerSelection = 3         # 3 = ssOthers
            $searcher.ServiceID = $muId
            $Queue.Enqueue('Windows Update: Microsoft Update aktiveret')
        } catch { $Queue.Enqueue('Windows Update: Microsoft Update ikke tilgængelig, bruger standard') }
        $Queue.Enqueue('Windows Update: søger...')
        $sr = $searcher.Search('IsInstalled=0 and IsHidden=0')
        $res.Searched = $sr.Updates.Count
        if ($sr.Updates.Count -eq 0) { $Queue.Enqueue('Windows Update: ingen opdateringer at installere'); return $res }
        $dl = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $sr.Updates) { try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch {}; [void]$dl.Add($u) }
        $Queue.Enqueue("Windows Update: downloader $($dl.Count) opdateringer...")
        $downloader = $session.CreateUpdateDownloader(); $downloader.Updates = $dl; [void]$downloader.Download()
        $inst = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $sr.Updates) { if ($u.IsDownloaded) { [void]$inst.Add($u) } }
        if ($inst.Count -eq 0) { $Queue.Enqueue('Windows Update: intet blev downloadet'); return $res }
        $Queue.Enqueue("Windows Update: installerer $($inst.Count) opdateringer...")
        $installer = $session.CreateUpdateInstaller(); $installer.Updates = $inst
        $ir = $installer.Install()
        $res.Reboot = [bool]$ir.RebootRequired
        for ($i = 0; $i -lt $inst.Count; $i++) {
            if ($ir.GetUpdateResult($i).ResultCode -eq 2) { $res.Installed++ } else { $res.Failed++ }
        }
        $Queue.Enqueue("Windows Update: $($res.Installed) installeret, $($res.Failed) fejlet" + $(if ($res.Reboot) { ', genstart påkrævet' } else { '' }))
    } catch { $res.Error = $_.Exception.Message; $Queue.Enqueue("Windows Update FEJL: $($_.Exception.Message)") }
    return $res
}

function Start-WuDrive {
    if ($script:WuDriveBusy) { Write-LogLine 'Windows Update kører allerede — springer denne runde over'; return }
    if ($script:UI.TxtWuSummary) { $script:UI.TxtWuSummary.Text = 'Starter Windows Update...' }
    $script:WuDriveBusy = $true
    Start-BackgroundWork -Work $script:WuDriveWork -OnComplete {
        param($res)
        $script:WuDriveBusy = $false
        if ($res -is [hashtable]) {
            if ($res.Error) {
                Write-LogLine "Windows Update fejlede: $($res.Error)" 'ERROR'
            }
            else {
                Write-LogLine ("Windows Update-runde: {0} installeret, {1} fejlet" -f $res.Installed, $res.Failed)
                # In the resume (post-login) flow a clean WU round means provisioning has settled.
                if ($script:CedraResuming) { Set-EcfCheck 'provisioning' 'CedraDeploy klar' 'ok' 'Klar' }
            }
        }
        Update-WuStatus
        # WU/reboot/app badges are driven entirely by Report-EcfStatus — refresh now for a quick update.
        Report-EcfStatus
    }
}

# Re-run the WU drive on a cadence so failed/transient updates get retried and newly-applicable
# ones (revealed after others install) get picked up. The busy guard prevents overlapping runs.
function Start-WuCadence {
    $min = 5
    if ($env:CEDRA_WU_MIN) { [void][int]::TryParse($env:CEDRA_WU_MIN, [ref]$min) }
    if ($min -lt 1) { $min = 1 }
    if (-not $script:WuCadenceTimer) {
        $script:WuCadenceTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:WuCadenceTimer.Add_Tick({ Start-WuDrive })
    }
    $script:WuCadenceTimer.Interval = [TimeSpan]::FromMinutes($min)
    $script:WuCadenceTimer.Start()
    Write-LogLine ("Windows Update gentages hvert {0}. minut" -f $min)
}

function Stop-WuCadence {
    if ($script:WuCadenceTimer) { $script:WuCadenceTimer.Stop() }
}
#endregion

#region ---------------------------------------------------------- customer flows (CedraDeploy)
$script:RestartXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Genstart" Height="220" Width="470" WindowStartupLocation="CenterScreen"
        Background="#15161A" FontFamily="Segoe UI" FontSize="13" ResizeMode="NoResize" Topmost="True">
    <StackPanel Margin="24">
        <TextBlock Text="Maskinen genstarter for at fuldføre provisioneringen." Foreground="#E6E7EA" FontSize="15" TextWrapping="Wrap"/>
        <TextBlock x:Name="TxtCountdown" Foreground="#F59E0B" FontSize="26" FontWeight="SemiBold" Margin="0,16"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCancelRestart" Content="Annuller" Padding="16,6" Margin="0,0,10,0"
                    Background="#2B2C33" Foreground="#E6E7EA" BorderBrush="#3A3B43" BorderThickness="1" Cursor="Hand"/>
            <Button x:Name="BtnRestartNow" Content="Genstart nu" Padding="16,6"
                    Background="#EF4444" Foreground="White" BorderThickness="0" Cursor="Hand"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

function Invoke-DeviceRestart {
    if ($script:RestartTimer) { $script:RestartTimer.Stop() }
    Write-LogLine 'CedraDeploy: genstarter enheden'
    Set-EcfCheck 'reboot' 'Genstart' 'running' 'Genstarter'
    try { Restart-Computer -Force } catch { Write-LogLine "Genstart fejlede: $($_.Exception.Message)" 'ERROR' }
}

function Start-RestartCountdown {
    param([int]$Seconds = 60)
    # Spring auto-genstart over hvis en app er fejlet — GRS er ryddet for retry, og
    # maskinen skal blive kørende så installationen kan lykkes uden reboot-loop.
    if ($script:AppFailed) {
        Write-LogLine 'Auto-genstart sprunget over: en app er fejlet (GRS ryddet for retry)' 'WARN'
        return
    }
    Set-EcfCheck 'reboot' 'Genstart' 'running' 'Genstarter'
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$script:RestartXaml)
    $w = [Windows.Markup.XamlReader]::Load($reader)
    try { $w.Owner = $script:Window } catch {}
    if ($script:LogoImage) { $w.Icon = $script:Window.Icon }
    $script:RestartWindow = $w
    $script:RestartRemaining = $Seconds
    $w.FindName('TxtCountdown').Text = "Genstart om $Seconds sekunder..."
    $w.FindName('BtnRestartNow').Add_Click({ Invoke-DeviceRestart })
    $w.FindName('BtnCancelRestart').Add_Click({
        if ($script:RestartTimer) { $script:RestartTimer.Stop() }
        Write-LogLine 'CedraDeploy: genstart annulleret (resume-opgave bevaret)'
        if ($script:RestartWindow) { $script:RestartWindow.Close() }
    })
    $w.Add_Closed({ if ($script:RestartTimer) { $script:RestartTimer.Stop() } })
    if (-not $script:RestartTimer) {
        $script:RestartTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:RestartTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:RestartTimer.Add_Tick({
            $script:RestartRemaining--
            if ($script:RestartRemaining -le 0) {
                try { $script:RestartWindow.FindName('TxtCountdown').Text = 'Genstarter...' } catch {}
                Invoke-DeviceRestart
            } else {
                try { $script:RestartWindow.FindName('TxtCountdown').Text = "Genstart om $($script:RestartRemaining) sekunder..." } catch {}
            }
        })
    }
    $w.Show(); $w.Topmost = $true; [void]$w.Activate()
    $script:RestartTimer.Start()
}

function New-CedraResumeTask {
    try {
        $cmd = '$env:ECDEPLOY_RESUME=1; irm cdr.palme3.dk | iex'
        $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' + $cmd + '"'
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName 'CedraDeploy-Resume' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-LogLine 'Resume-opgave oprettet (kører ved næste logon)'
    } catch { Write-LogLine "Kunne ikke oprette resume-opgave: $($_.Exception.Message)" 'ERROR' }
}

function Remove-CedraResumeTask {
    try { Unregister-ScheduledTask -TaskName 'CedraDeploy-Resume' -Confirm:$false -ErrorAction SilentlyContinue; Write-LogLine 'Resume-opgave fjernet' } catch {}
}

# Pre-install Company Portal from a hosted MSIX set (no winget dependency). The package set + a
# manifest.json live under /assets/companyportal/ on the ecDeploy host (binaries are server-only,
# gitignored). Installs for the current user (immediate) + provisions for all users (best-effort),
# so the tech can open Company Portal and click "Sign in" to kick off the Intune sync.
$script:CompanyPortalWork = {
    $res = @{ Already = $false; Installed = $false; Provisioned = $false; Error = $null }
    try { if (Get-AppxPackage -Name 'Microsoft.CompanyPortal' -ErrorAction SilentlyContinue) { $res.Already = $true; $Queue.Enqueue('Firmaportal er allerede installeret'); return $res } } catch {}
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    $manifest = $null; $base = $null
    foreach ($h in @('https://ecd.qwe.dk', 'http://ecd.palme3.dk')) {
        try { $manifest = Invoke-RestMethod "$h/assets/companyportal/manifest.json" -TimeoutSec 20 -UseBasicParsing; $base = "$h/assets/companyportal"; break } catch {}
    }
    if (-not $manifest -or -not $manifest.bundle) { $Queue.Enqueue('Firmaportal: pakker er ikke hostet endnu (manifest mangler)'); $res.Error = 'no-manifest'; return $res }

    $tmp = Join-Path $env:TEMP 'ecd-companyportal'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $bundle = Join-Path $tmp $manifest.bundle
        $Queue.Enqueue('Firmaportal: henter pakker...')
        Invoke-WebRequest "$base/$($manifest.bundle)" -OutFile $bundle -UseBasicParsing -TimeoutSec 180

        # Only fetch/install dependencies that are MISSING. Reinstalling a framework that's already
        # present (and in use by e.g. WebExperience) triggers 0x80073D02 "resources in use".
        $deps = @()
        foreach ($d in $manifest.deps) {
            $depName = ($d -split '_')[0]
            if (Get-AppxPackage -Name $depName -ErrorAction SilentlyContinue) { $Queue.Enqueue("Dependency findes allerede, springer over: $depName"); continue }
            $dp = Join-Path $tmp $d; Invoke-WebRequest "$base/$d" -OutFile $dp -UseBasicParsing -TimeoutSec 180; $deps += $dp
        }

        $Queue.Enqueue('Firmaportal: installerer for nuværende bruger...')
        try {
            $p = @{ Path = $bundle; ForceApplicationShutdown = $true; ErrorAction = 'Stop' }
            if ($deps.Count -gt 0) { $p.DependencyPath = $deps }
            Add-AppxPackage @p
            $res.Installed = $true; $Queue.Enqueue('Firmaportal installeret for brugeren')
        } catch { $Queue.Enqueue("Firmaportal (bruger) fejl: $($_.Exception.Message)") }

        try {
            $pp = @{ Online = $true; PackagePath = $bundle; SkipLicense = $true; ErrorAction = 'Stop' }
            if ($deps.Count -gt 0) { $pp.DependencyPackagePath = $deps }
            Add-AppxProvisionedPackage @pp | Out-Null
            $res.Provisioned = $true; $Queue.Enqueue('Firmaportal provisioneret (alle brugere)')
        } catch { $Queue.Enqueue("Firmaportal (alle brugere) sprunget over: $($_.Exception.Message)") }
    } catch { $res.Error = $_.Exception.Message; $Queue.Enqueue("Firmaportal FEJL: $($_.Exception.Message)") }
    return $res
}

function Install-CompanyPortal {
    Write-LogLine 'Firmaportal: starter pre-installation...'
    Start-BackgroundWork -Work $script:CompanyPortalWork -OnComplete {
        param($res)
        if ($res -isnot [hashtable]) { Write-LogLine 'Firmaportal: ukendt resultat' 'WARN'; return }
        $present = $false
        if ($res.Already)        { Write-LogLine 'Firmaportal var allerede installeret'; $present = $true }
        elseif ($res.Installed)  { Write-LogLine 'Firmaportal installeret'; $present = $true }
        elseif ($res.Error)      { Write-LogLine 'Firmaportal kunne ikke installeres (se log)' 'WARN' }
        if ($present) { Start-IntuneSync }   # kick off an Intune/MDM sync now Company Portal is in place
    }
}

# Trigger an Intune/MDM device sync (same as Company Portal's "Sync") by starting the device's
# EnterpriseMgmt "PushLaunch" scheduled task — no Company Portal sign-in required.
$script:IntuneSyncWork = {
    $res = @{ Triggered = $false; Count = 0; Error = $null }
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '\Microsoft\Windows\EnterpriseMgmt\*' }
        $push = @($tasks | Where-Object { $_.TaskName -eq 'PushLaunch' })
        if ($push.Count -eq 0) { $push = @($tasks) }   # fallback: all enrollment tasks
        foreach ($t in $push) { try { Start-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop; $res.Count++ } catch {} }
        $res.Triggered = $res.Count -gt 0
        if ($res.Triggered) { $Queue.Enqueue("Intune-sync startet ($($res.Count) opgave(r))") }
        else { $Queue.Enqueue('Intune-sync: ingen MDM-enrollment-opgaver fundet (enheden er måske ikke Intune-enrolled endnu)') }
    } catch { $res.Error = $_.Exception.Message; $Queue.Enqueue("Intune-sync FEJL: $($_.Exception.Message)") }
    return $res
}

function Start-IntuneSync {
    Write-LogLine 'Starter Intune-sync...'
    Start-BackgroundWork -Work $script:IntuneSyncWork -OnComplete {
        param($res)
        if ($res -is [hashtable] -and $res.Triggered) { Write-LogLine "Intune-sync startet ($($res.Count) opgave(r))" }
        else { Write-LogLine 'Intune-sync kunne ikke startes (se log)' 'WARN' }
    }
}

# CedraStandard: anti-sleep + Windows Update now, GRS after 45 min, restart after 90 min,
# and a one-shot resume task so the next logon resumes (anti-sleep only + Windows Update).
function Start-CedraFlow {
    if (-not $script:IsAdmin) { $script:UI.TxtAutoStatus.Text = 'Kræver administrator.'; Write-LogLine 'CedraDeploy kræver administrator' 'WARN'; return }
    $grsMin = 45; $restartMin = 90
    if ($env:CEDRA_GRS_MIN) { [void][int]::TryParse($env:CEDRA_GRS_MIN, [ref]$grsMin) }
    if ($env:CEDRA_RESTART_MIN) { [void][int]::TryParse($env:CEDRA_RESTART_MIN, [ref]$restartMin) }

    $script:CedraRunning = $true
    $script:CedraStart = Get-Date
    $script:CedraGrsAt = $script:CedraStart.AddMinutes($grsMin)
    $script:CedraRestartAt = $script:CedraStart.AddMinutes($restartMin)
    $script:CedraGrsDone = $false
    $script:CedraRestartStarted = $false

    Set-KeepAwake $true
    Update-Chips
    Show-Panel 'PanelAuto' $(if ($script:Profile) { $script:Profile.Brand } else { 'CedraDeploy' })
    $script:UI.BtnStartAuto.IsEnabled = $false
    $script:UI.BtnStopAuto.IsEnabled = $true     # let the tech abort the Cedra flow
    $script:UI.TxtAutoMinutes.IsEnabled = $false
    $script:UI.BarAuto.Maximum = $restartMin * 60
    Write-LogLine ("CedraDeploy startet (anti-sleep, Windows Update, GRS om {0} min, genstart om {1} min)" -f $grsMin, $restartMin)
    Set-EcfCheck 'provisioning' 'CedraDeploy kører' 'running' 'CedraStandard'
    Start-WuDrive
    Start-WuCadence
    Install-CompanyPortal   # pre-install Company Portal so the tech can sign in (kicks off Intune sync)
    Report-EcfStatus      # immediate first board update
    Start-EcfCadence      # then refresh app/WU badges every 60 s

    if (-not $script:CedraTimer) {
        $script:CedraTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:CedraTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:CedraTimer.Add_Tick({
            $now = Get-Date
            $script:UI.BarAuto.Value = [math]::Max(0, [math]::Min($script:UI.BarAuto.Maximum, ($now - $script:CedraStart).TotalSeconds))
            if (-not $script:CedraGrsDone -and $now -ge $script:CedraGrsAt) {
                $script:CedraGrsDone = $true
                Write-LogLine 'CedraDeploy: GRS-tidspunkt nået — rydder GRS + genstarter IME'
                Invoke-GrsRefresh
            }
            if (-not $script:CedraRestartStarted -and $now -ge $script:CedraRestartAt) {
                $script:CedraRestartStarted = $true
                $script:CedraTimer.Stop()
                Write-LogLine 'CedraDeploy: genstarts-tidspunkt nået'
                # No resume task: the user must re-authenticate (admin/TAP) at next logon anyway,
                # so CedraDeploy is NOT auto-started after the restart.
                Start-RestartCountdown 60
                return
            }
            $g = if (($script:CedraGrsAt - $now).TotalSeconds -gt 0) { '{0:hh\:mm\:ss}' -f ($script:CedraGrsAt - $now) } else { 'udført' }
            $r = if (($script:CedraRestartAt - $now).TotalSeconds -gt 0) { '{0:hh\:mm\:ss}' -f ($script:CedraRestartAt - $now) } else { 'nu' }
            $script:UI.TxtAutoStatus.Text = "CedraDeploy kører · GRS: $g · genstart: $r"
        })
    }
    $script:CedraTimer.Start()
}

function Stop-CedraFlow {
    if ($script:CedraTimer) { $script:CedraTimer.Stop() }
    Stop-WuCadence
    Stop-EcfCadence
    $script:CedraRunning = $false
    Set-KeepAwake $false
    $script:UI.BarAuto.Value = 0
    $script:UI.TxtAutoStatus.Text = 'CedraDeploy stoppet.'
    Write-LogLine 'CedraDeploy stoppet af tekniker'
    Update-Chips
    Update-SequenceControls   # back to an idle, usable Auto panel
}

# CedraResume: runs at the next logon (via the scheduled task) — anti-sleep only + Windows Update.
function Start-CedraResume {
    Remove-CedraResumeTask   # one-shot: never run again
    if (-not $script:IsAdmin) { $script:UI.TxtNoSleepStatus.Text = 'Kræver administrator.'; Write-LogLine 'CedraDeploy resume kræver administrator' 'WARN'; return }
    $script:CedraResuming = $true   # let the shared WU OnComplete mark provisioning "Klar" after a good round
    Set-KeepAwake $true
    Update-Chips
    Show-Panel 'PanelNoSleep' $(if ($script:Profile) { $script:Profile.Brand } else { 'CedraDeploy' })
    $script:UI.TxtNoSleepStatus.Text = 'CedraDeploy genoptagelse — anti-sleep aktiv, Windows Update kører.'
    Write-LogLine 'CedraDeploy resume: anti-sleep + Windows Update'
    Set-EcfCheck 'provisioning' 'CedraDeploy kører' 'running' 'Genoptager efter login'
    Start-WuDrive
    Start-WuCadence
    Report-EcfStatus      # immediate first board update
    Start-EcfCadence      # then refresh app/WU badges every 60 s
}
#endregion

#region ---------------------------------------------------------- Automatic sequence
function Update-SequenceControls {
    $running = $script:SeqRunning
    $script:UI.BtnStartAuto.IsEnabled = -not $running
    $script:UI.BtnStopAuto.IsEnabled  = $running
    $script:UI.TxtAutoMinutes.IsEnabled = -not $running
    # While the sequence owns No Sleep + GRS, disable the manual controls.
    $script:UI.BtnToggleNoSleep.IsEnabled = -not $running
    $script:UI.BtnRunGrs.IsEnabled = (-not $running) -and $script:IsAdmin
    $script:UI.BtnRunIme.IsEnabled = (-not $running) -and $script:IsAdmin
    if ($running) {
        $script:UI.TxtNoSleepStatus.Text = 'Styret af den automatiske sekvens.'
        $script:UI.TxtGrsStatus.Text = 'Styret af den automatiske sekvens.'
        $script:UI.TxtImeStatus.Text = 'Styret af den automatiske sekvens.'
    }
}

function Start-AutoSequence {
    if (-not $script:IsAdmin) {
        $script:UI.TxtAutoStatus.Text = 'Kræver administrator. Genstart ecDeploy som administrator.'
        Write-LogLine 'Automatisk sekvens afvist: ikke administrator' 'WARN'
        return
    }
    $min = 45.0
    [void][double]::TryParse(($script:UI.TxtAutoMinutes.Text -replace ',', '.'), [ref]$min)
    if ($min -le 0) { $min = 45 }

    $script:SeqRunning  = $true
    $script:SeqGrsFired = $false
    $script:SeqTotalSec = [int]($min * 60)
    $script:SeqEnd      = (Get-Date).AddMinutes($min)
    $script:UI.BarAuto.Maximum = $script:SeqTotalSec
    $script:UI.BarAuto.Value   = 0

    Set-KeepAwake $true
    Update-Chips
    Update-SequenceControls
    Write-LogLine ("Automatisk sekvens startet (nedtælling {0} min, derefter GRS + IME-genstart)" -f $min)

    if (-not $script:SeqTimer) {
        $script:SeqTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:SeqTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:SeqTimer.Add_Tick({
            $remaining = ($script:SeqEnd - (Get-Date)).TotalSeconds
            if ($remaining -le 0 -and -not $script:SeqGrsFired) {
                $script:SeqGrsFired = $true
                $script:SeqTimer.Stop()
                $script:UI.BarAuto.Value = $script:SeqTotalSec
                $script:UI.TxtAutoStatus.Text = 'Nedtælling færdig — kører Opdater GRS + IME-genstart...'
                Invoke-GrsRefresh -FromSequence
            } elseif (-not $script:SeqGrsFired) {
                $elapsed = $script:SeqTotalSec - $remaining
                $script:UI.BarAuto.Value = [math]::Max(0, [math]::Min($script:SeqTotalSec, $elapsed))
                $ts = [TimeSpan]::FromSeconds([math]::Ceiling($remaining))
                $script:UI.TxtAutoStatus.Text = ('Holder maskinen vågen | GRS om {0:hh\:mm\:ss}' -f $ts)
            }
        })
    }
    $script:SeqTimer.Start()
}

function Stop-AutoSequence {
    if ($script:SeqTimer) { $script:SeqTimer.Stop() }
    $script:SeqRunning = $false
    Set-KeepAwake $false
    $script:UI.BarAuto.Value = 0
    $script:UI.TxtAutoStatus.Text = 'Sekvens stoppet.'
    Write-LogLine 'Automatisk sekvens stoppet'
    Update-Chips
    Update-SequenceControls
}
#endregion

#region ---------------------------------------------------------- navigation + tools
function Show-Panel {
    param([string]$Name, [string]$Title)
    foreach ($p in 'PanelWelcome','PanelAuto','PanelNoSleep','PanelGrs','PanelIme','PanelWu','PanelApps','PanelImeLog','PanelInfo') {
        $script:UI[$p].Visibility = if ($p -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
    $script:UI.TxtPanelTitle.Text = $Title

    # Load/refresh diagnostics panels when shown; run the auto-refresh timers only while visible.
    if ($Name -eq 'PanelImeLog') { Update-ImeLog; if ($script:ImeLogTimer) { $script:ImeLogTimer.Start() } }
    elseif ($script:ImeLogTimer) { $script:ImeLogTimer.Stop() }
    if ($Name -eq 'PanelWu') { Update-WuStatus; if ($script:WuTimer) { $script:WuTimer.Start() } }
    elseif ($script:WuTimer) { $script:WuTimer.Stop() }
    if ($Name -eq 'PanelApps') { Update-AppStatus }
    if ($Name -eq 'PanelInfo') { Update-DeviceInfo }
}

function Open-FolderSafe {
    param([string]$Path, [string]$Label)
    Write-LogLine "Åbner $Label..."
    if (-not (Test-Path $Path)) { Write-LogLine "Mappen findes ikke endnu: $Path" 'WARN'; return }
    # explorer.exe routes to the existing user shell, which opens far faster than a new elevated
    # Explorer instance (Invoke-Item from an elevated process is slow).
    try { Start-Process 'explorer.exe' -ArgumentList "`"$($Path)`"" }
    catch { Write-LogLine "Kunne ikke åbne $Label : $($_.Exception.Message)" 'ERROR' }
}
#endregion

#region ---------------------------------------------------------- wire up events
$script:UI.NavAuto.Add_Click(    { Show-Panel 'PanelAuto'    'Automatisk sekvens' })
$script:UI.NavNoSleep.Add_Click( { Show-Panel 'PanelNoSleep' 'No Sleep' })
$script:UI.NavGrs.Add_Click(     { Show-Panel 'PanelGrs'     'Opdater GRS' })
$script:UI.NavIme.Add_Click(     { Show-Panel 'PanelIme'     'Genstart IME' })
$script:UI.NavWu.Add_Click(      { Show-Panel 'PanelWu'      'Windows Update' })
$script:UI.NavApps.Add_Click(    { Show-Panel 'PanelApps'    'App-status' })
$script:UI.NavImeLog.Add_Click(  { Show-Panel 'PanelImeLog'  'Live IME-log' })
$script:UI.NavInfo.Add_Click(    { Show-Panel 'PanelInfo'    'Enheds-info' })

$script:UI.BtnWuRefresh.Add_Click({ Update-WuStatus })
$script:UI.BtnAppsRefresh.Add_Click({ Update-AppStatus })
$script:UI.BtnImeLogRefresh.Add_Click({ Update-ImeLog })
$script:UI.ChkImeErrorsOnly.Add_Click({ Update-ImeLog })
$script:UI.BtnInfoRefresh.Add_Click({ Update-DeviceInfo })
$script:UI.BtnDiag.Add_Click({ Invoke-Diagnostics })

$script:UI.BtnToggleNoSleep.Add_Click({ Switch-NoSleep })
$script:UI.BtnStartAuto.Add_Click({ Start-AutoSequence })
$script:UI.BtnStopAuto.Add_Click({ if ($script:CedraRunning) { Stop-CedraFlow } else { Stop-AutoSequence } })

$script:UI.BtnRunGrs.Add_Click({
    $answer = [System.Windows.MessageBox]::Show(
        'Dette rydder GRS og genstarter IME-tjenesten. Undgå at køre det midt i en installation. Fortsæt?',
        'Opdater GRS', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') { Invoke-GrsRefresh }
})

$script:UI.BtnRunIme.Add_Click({
    $answer = [System.Windows.MessageBox]::Show(
        'Dette genstarter IME-tjenesten. Undgå at køre det midt i en installation. Fortsæt?',
        'Genstart IME', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') { Invoke-ImeRestart }
})

$script:UI.BtnImeLogs.Add_Click({ Open-FolderSafe $script:ImeLogsPath 'IME-logs' })
$script:UI.BtnPrograms.Add_Click({ Write-LogLine 'Åbner Programmer...'; try { Start-Process 'control.exe' -ArgumentList 'appwiz.cpl' } catch { Write-LogLine "Kunne ikke åbne Programmer: $($_.Exception.Message)" 'ERROR' } })
$script:UI.BtnTaskMgr.Add_Click({ Write-LogLine 'Åbner Jobliste...'; try { Start-Process 'taskmgr.exe' } catch { Write-LogLine "Kunne ikke åbne Jobliste: $($_.Exception.Message)" 'ERROR' } })
$script:UI.BtnViewLog.Add_Click({ Write-LogLine 'Åbner logfil...'; try { if (Test-Path $script:LogFile) { Start-Process 'notepad.exe' -ArgumentList "`"$($script:LogFile)`"" } else { Write-LogLine 'Logfilen findes ikke endnu' 'WARN' } } catch { Write-LogLine "Kunne ikke åbne logfil: $($_.Exception.Message)" 'ERROR' } })

# Bring the window to the foreground — it launches from a hidden background process, so Windows
# won't give it focus automatically (it would otherwise open behind the tech's terminal).
$script:Window.Add_Loaded({
    $this.Topmost = $true
    [void]$this.Activate()
    $this.Topmost = $false
    # Customer flow takes priority, then -AutoSequence.
    if ($script:FlowName -eq 'CedraStandard') { Start-CedraFlow }
    elseif ($script:FlowName -eq 'CedraResume') { Start-CedraResume }
    elseif ($script:AutoStart) {
        Show-Panel 'PanelAuto' 'Automatisk sekvens'
        Write-LogLine 'Auto-start: starter automatisk sekvens'
        Start-AutoSequence
    }
})

# Confirm-on-close while No Sleep / sequence is active.
$script:Window.Add_Closing({
    param($src, $e)
    if ($script:NoSleepActive -or $script:SeqRunning) {
        $answer = [System.Windows.MessageBox]::Show(
            'No Sleep er aktiv — hvis du lukker ecDeploy kan maskinen gå i dvale. Luk alligevel?',
            'Luk ecDeploy', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $e.Cancel = $true; return }
    }
    # Release the keep-awake flag on the way out.
    try { [void][EcPower]::SetThreadExecutionState($script:ES_CONTINUOUS) } catch {}
})
#endregion

#region ---------------------------------------------------------- startup
Update-Chips
Set-OnlineChip 'checking'
Write-LogLine "ecDeploy v$script:Version startet"
if ($script:IsAdmin) { Write-LogLine 'Kører som administrator' }
else { Write-LogLine 'Kører IKKE som administrator — privilegerede handlinger er deaktiveret' 'WARN' }
Update-SequenceControls

# Timer that refreshes the live IME-log view (started only while that panel is visible).
$script:ImeLogTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ImeLogTimer.Interval = [TimeSpan]::FromSeconds(3)
$script:ImeLogTimer.Add_Tick({ Update-ImeLog })

# Timer that refreshes the Windows Update panel (started only while that panel is visible).
$script:WuTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:WuTimer.Interval = [TimeSpan]::FromSeconds(10)
$script:WuTimer.Add_Tick({ Update-WuStatus })

# Async connectivity check for the Online chip.
Start-BackgroundWork -Work {
    try { Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue } catch { $false }
} -OnComplete { param($ok) Set-OnlineChip $(if ([bool]$ok) { 'online' } else { 'offline' }) }

[void]$script:Window.ShowDialog()
#endregion
