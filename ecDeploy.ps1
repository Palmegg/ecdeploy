<#
    ecDeploy.ps1 — provisioning utility (WPF / Windows PowerShell 5.1)

    A technician runs this on a freshly deployed Windows machine after signing in, to keep the
    machine awake during provisioning and to unstick stalled Intune Win32 app installs.

    See DESIGN.md for the full design. Next-gen rebuild of SpeedTune.
    User-facing text is Danish; code/identifiers/comments are English.
#>

$ErrorActionPreference = 'Stop'
$script:Version = '1.0.0'

# Startup error trap: any terminating error is written to a log and shown in a dialog that
# stays put, so a launch failure can't vanish with the window. Place before anything risky.
trap {
    $detail = @(
        "$($_.Exception.GetType().Name): $($_.Exception.Message)"
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
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
    if ($Elevated) {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList $argList | Out-Null
    } else {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $argList | Out-Null
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

#region ---------------------------------------------------------- paths + state
$script:Win32AppsKey = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
$script:ImeLogsPath  = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$script:LogDir       = Join-Path $env:ProgramData 'ecDeploy'
$script:LogFile      = Join-Path $script:LogDir 'ecDeploy.log'

$script:NoSleepActive = $false
$script:SeqRunning    = $false
$script:SeqGrsFired   = $false
$script:UI            = @{}
$script:LogQueue      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'

try { if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null } } catch {}
#endregion

#region ---------------------------------------------------------- XAML
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ecDeploy" Height="600" Width="860"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#15161A" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
    <Window.Resources>
        <SolidColorBrush x:Key="Accent" Color="#3B82F6"/>
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
            <Setter Property="Background" Value="#3B82F6"/>
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
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#2F6FE0"/></Trigger>
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
                    <TextBlock Text="&#x26AB;" Foreground="#E6E7EA" FontSize="16" VerticalAlignment="Center"/>
                    <TextBlock Text="ecDeploy" Foreground="{StaticResource Text}" FontSize="18" FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"/>
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
                <ColumnDefinition Width="210"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Left rail -->
            <Border Grid.Column="0" Background="#1C1D22" BorderBrush="{StaticResource Border}" BorderThickness="0,0,1,0">
                <DockPanel Margin="0,12">
                    <StackPanel DockPanel.Dock="Top">
                        <TextBlock Text="HANDLINGER" Foreground="{StaticResource Muted}" FontSize="10" Margin="22,4,0,4"/>
                        <Button x:Name="NavAuto"    Style="{StaticResource NavButton}" Content="Automatisk sekvens"/>
                        <Button x:Name="NavNoSleep" Style="{StaticResource NavButton}" Content="No Sleep"/>
                        <Button x:Name="NavGrs"     Style="{StaticResource NavButton}" Content="Opdater GRS"/>
                        <Border Height="1" Background="{StaticResource Border}" Margin="14,12"/>
                        <TextBlock Text="VÆRKTØJER" Foreground="{StaticResource Muted}" FontSize="10" Margin="22,0,0,4"/>
                        <Button x:Name="BtnImeLogs"  Style="{StaticResource NavButton}" Content="IME-logs"/>
                        <Button x:Name="BtnPrograms" Style="{StaticResource NavButton}" Content="Programmer"/>
                        <Button x:Name="BtnTaskMgr"  Style="{StaticResource NavButton}" Content="Jobliste"/>
                    </StackPanel>
                    <Button x:Name="BtnViewLog" DockPanel.Dock="Bottom" Style="{StaticResource NavButton}" Content="Vis logfil" VerticalAlignment="Bottom"/>
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
    'TxtAdmin','ChipAdmin','TxtOnline','ChipOnline','TxtNoSleep','ChipNoSleep','TxtVersion','BannerNoSleep',
    'NavAuto','NavNoSleep','NavGrs','BtnImeLogs','BtnPrograms','BtnTaskMgr','BtnViewLog',
    'TxtPanelTitle','PanelWelcome','PanelAuto','PanelNoSleep','PanelGrs',
    'TxtAutoMinutes','BarAuto','TxtAutoStatus','BtnStartAuto','BtnStopAuto',
    'ChkNoSleep24','TxtNoSleepStatus','BtnToggleNoSleep',
    'TxtGrsStatus','BtnRunGrs','LogBox'
)) { $script:UI[$name] = $script:Window.FindName($name) }

$script:UI.TxtVersion.Text = "v$script:Version"
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
    param([scriptblock]$Work, [scriptblock]$OnComplete)

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Queue', $script:LogQueue)

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
    }
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
    if ($running) {
        $script:UI.TxtNoSleepStatus.Text = 'Styret af den automatiske sekvens.'
        $script:UI.TxtGrsStatus.Text = 'Styret af den automatiske sekvens.'
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
    foreach ($p in 'PanelWelcome','PanelAuto','PanelNoSleep','PanelGrs') {
        $script:UI[$p].Visibility = if ($p -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
    $script:UI.TxtPanelTitle.Text = $Title
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

$script:UI.BtnToggleNoSleep.Add_Click({ Switch-NoSleep })
$script:UI.BtnStartAuto.Add_Click({ Start-AutoSequence })
$script:UI.BtnStopAuto.Add_Click({ Stop-AutoSequence })

$script:UI.BtnRunGrs.Add_Click({
    $answer = [System.Windows.MessageBox]::Show(
        'Dette rydder GRS og genstarter IME-tjenesten. Undgå at køre det midt i en installation. Fortsæt?',
        'Opdater GRS', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') { Invoke-GrsRefresh }
})

$script:UI.BtnImeLogs.Add_Click({ Open-FolderSafe $script:ImeLogsPath 'IME-logs' })
$script:UI.BtnPrograms.Add_Click({ Write-LogLine 'Åbner Programmer...'; try { Start-Process 'control.exe' -ArgumentList 'appwiz.cpl' } catch { Write-LogLine "Kunne ikke åbne Programmer: $($_.Exception.Message)" 'ERROR' } })
$script:UI.BtnTaskMgr.Add_Click({ Write-LogLine 'Åbner Jobliste...'; try { Start-Process 'taskmgr.exe' } catch { Write-LogLine "Kunne ikke åbne Jobliste: $($_.Exception.Message)" 'ERROR' } })
$script:UI.BtnViewLog.Add_Click({ Write-LogLine 'Åbner logfil...'; try { if (Test-Path $script:LogFile) { Start-Process 'notepad.exe' -ArgumentList "`"$($script:LogFile)`"" } else { Write-LogLine 'Logfilen findes ikke endnu' 'WARN' } } catch { Write-LogLine "Kunne ikke åbne logfil: $($_.Exception.Message)" 'ERROR' } })

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

# Async connectivity check for the Online chip.
Start-BackgroundWork -Work {
    try { Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue } catch { $false }
} -OnComplete { param($ok) Set-OnlineChip $(if ([bool]$ok) { 'online' } else { 'offline' }) }

[void]$script:Window.ShowDialog()
#endregion
