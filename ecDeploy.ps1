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
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
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

#region ---------------------------------------------------------- paths + state
$script:Win32AppsKey = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
$script:ImeLogsPath  = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$script:ImeLogFile   = Join-Path $script:ImeLogsPath 'IntuneManagementExtension.log'
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
        Title="ecDeploy" Height="680" Width="860"
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
                    <Image x:Name="LogoImg" Width="24" Height="24" VerticalAlignment="Center" SnapsToDevicePixels="True"/>
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
                        <Button x:Name="NavIme"     Style="{StaticResource NavButton}" Content="Genstart IME"/>
                        <Border Height="1" Background="{StaticResource Border}" Margin="14,12"/>
                        <TextBlock Text="DIAGNOSTIK" Foreground="{StaticResource Muted}" FontSize="10" Margin="22,0,0,4"/>
                        <Button x:Name="NavApps"    Style="{StaticResource NavButton}" Content="App-status"/>
                        <Button x:Name="NavImeLog"  Style="{StaticResource NavButton}" Content="Live IME-log"/>
                        <Button x:Name="NavInfo"    Style="{StaticResource NavButton}" Content="Enheds-info"/>
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

                    <!-- IME restart -->
                    <StackPanel x:Name="PanelIme" Visibility="Collapsed">
                        <TextBlock Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,0,0,12"
                                   Text="Genstarter Intune Management Extension-tjenesten (IME) — bruges til hurtigt at få Intune til at genoptage app-installationer."/>
                        <TextBlock Foreground="#F4B36A" TextWrapping="Wrap" Margin="0,0,0,14"
                                   Text="Bemærk: undgå at genstarte midt i en igangværende installation."/>
                        <TextBlock x:Name="TxtImeStatus" Foreground="{StaticResource Muted}" Margin="0,0,0,14"/>
                        <Button x:Name="BtnRunIme" Style="{StaticResource PrimaryButton}" Content="Genstart IME nu" HorizontalAlignment="Left"/>
                    </StackPanel>

                    <!-- App status -->
                    <StackPanel x:Name="PanelApps" Visibility="Collapsed">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <Button x:Name="BtnAppsRefresh" Style="{StaticResource GhostButton}" Content="Opdater"/>
                            <TextBlock x:Name="TxtAppsSummary" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="14,0,0,0"/>
                        </StackPanel>
                        <Border Background="#101114" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6">
                            <ScrollViewer MaxHeight="280" VerticalScrollBarVisibility="Auto">
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
                            <TextBox x:Name="ImeLogBox" Height="280" Margin="8" Background="Transparent" Foreground="#C8CBD2"
                                     BorderThickness="0" IsReadOnly="True" FontFamily="Consolas" FontSize="11"
                                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"/>
                        </Border>
                    </StackPanel>

                    <!-- Device info + diagnostics -->
                    <StackPanel x:Name="PanelInfo" Visibility="Collapsed">
                        <Border Background="#101114" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Margin="0,0,0,12">
                            <TextBox x:Name="InfoBox" Height="250" Margin="8" Background="Transparent" Foreground="#C8CBD2"
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
    'LogoImg','TxtAdmin','ChipAdmin','TxtOnline','ChipOnline','TxtNoSleep','ChipNoSleep','TxtVersion','BannerNoSleep',
    'NavAuto','NavNoSleep','NavGrs','BtnImeLogs','BtnPrograms','BtnTaskMgr','BtnViewLog',
    'TxtPanelTitle','PanelWelcome','PanelAuto','PanelNoSleep','PanelGrs',
    'TxtAutoMinutes','BarAuto','TxtAutoStatus','BtnStartAuto','BtnStopAuto',
    'ChkNoSleep24','TxtNoSleepStatus','BtnToggleNoSleep',
    'TxtGrsStatus','BtnRunGrs','NavIme','PanelIme','TxtImeStatus','BtnRunIme',
    'NavApps','PanelApps','BtnAppsRefresh','TxtAppsSummary','AppsList',
    'NavImeLog','PanelImeLog','ChkImeErrorsOnly','BtnImeLogRefresh','TxtImeLogStatus','ImeLogBox',
    'NavInfo','PanelInfo','InfoBox','BtnInfoRefresh','BtnDiag','TxtInfoStatus','LogBox'
)) { $script:UI[$name] = $script:Window.FindName($name) }

$script:UI.TxtVersion.Text = "v$script:Version"

# Apply the embedded logo to the window/taskbar icon and the header wordmark.
if ($script:LogoImage) {
    $script:Window.Icon = $script:LogoImage
    if ($script:UI.LogoImg) { $script:UI.LogoImg.Source = $script:LogoImage }
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
            $res.Apps += [pscustomobject]@{ Id = $app.PSChildName; Label = $label; Cat = $cat; Code = $code; Err = $err }
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
            $id.Text = $a.Id + $(if ($null -ne $a.Err -and $a.Err -ne 0) { "   fejlkode: $($a.Err)" } else { '' })
            $id.Foreground = '#C8CBD2'; $id.FontFamily = 'Consolas'; $id.FontSize = 11
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
    foreach ($p in 'PanelWelcome','PanelAuto','PanelNoSleep','PanelGrs','PanelIme','PanelApps','PanelImeLog','PanelInfo') {
        $script:UI[$p].Visibility = if ($p -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
    $script:UI.TxtPanelTitle.Text = $Title

    # Load/refresh diagnostics panels when shown; run the IME-log auto-refresh only while visible.
    if ($Name -eq 'PanelImeLog') { Update-ImeLog; if ($script:ImeLogTimer) { $script:ImeLogTimer.Start() } }
    elseif ($script:ImeLogTimer) { $script:ImeLogTimer.Stop() }
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
$script:UI.NavApps.Add_Click(    { Show-Panel 'PanelApps'    'App-status' })
$script:UI.NavImeLog.Add_Click(  { Show-Panel 'PanelImeLog'  'Live IME-log' })
$script:UI.NavInfo.Add_Click(    { Show-Panel 'PanelInfo'    'Enheds-info' })

$script:UI.BtnAppsRefresh.Add_Click({ Update-AppStatus })
$script:UI.BtnImeLogRefresh.Add_Click({ Update-ImeLog })
$script:UI.ChkImeErrorsOnly.Add_Click({ Update-ImeLog })
$script:UI.BtnInfoRefresh.Add_Click({ Update-DeviceInfo })
$script:UI.BtnDiag.Add_Click({ Invoke-Diagnostics })

$script:UI.BtnToggleNoSleep.Add_Click({ Switch-NoSleep })
$script:UI.BtnStartAuto.Add_Click({ Start-AutoSequence })
$script:UI.BtnStopAuto.Add_Click({ Stop-AutoSequence })

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

# Async connectivity check for the Online chip.
Start-BackgroundWork -Work {
    try { Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue } catch { $false }
} -OnComplete { param($ok) Set-OnlineChip $(if ([bool]$ok) { 'online' } else { 'offline' }) }

[void]$script:Window.ShowDialog()
#endregion
