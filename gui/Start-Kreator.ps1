#requires -Version 5.1
<#
.SYNOPSIS
  Kreator graficzny konfigurator-win (Windows Forms).
.DESCRIPTION
  Asystent krok po kroku. Domyślnie tryb próbny (bez zmian w systemie).
  Wymaga Windows i PowerShell 5.1+ w trybie STA.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = Split-Path -Parent $PSScriptRoot
$script:EditionScript = Join-Path $script:Root 'customize\Get-WindowsEdition.ps1'
$script:DownloadScript = Join-Path $script:Root 'download\Get-WindowsImage.ps1'
$script:CustomizeScript = Join-Path $script:Root 'customize\Invoke-Customize.ps1'
$script:InstallScript = Join-Path $script:Root 'install\Install-Apps.ps1'
$script:BloatwarePath = Join-Path $script:Root 'customize\bloatware.txt'
$script:SettingsExample = Join-Path $script:Root 'customize\settings.example.json'
$script:AppsExample = Join-Path $script:Root 'install\apps.example.json'

$script:State = @{
    PageIndex       = 0
    DryRun          = $true
    WinVersion      = '11'
    WinEdition      = 'Pro'
    DetectedCaption = ''
    DetectedEdition = ''
    DetectedBuild   = ''
    IsAdmin         = $false
    HasWinget       = $false
    SettingsPath    = $script:SettingsExample
    SettingsText    = ''
    StepDone        = @{ Download = $false; Customize = $false; Install = $false }
    Busy            = $false
    CancelRequested = $false
}

$script:Sync = [hashtable]::Synchronized(@{
    Log      = New-Object System.Collections.ArrayList
    Progress = 0
    Done     = $false
    Error    = $null
    Cancel   = $false
})

$script:JobPs = $null
$script:JobHandle = $null
$script:JobRunspace = $null

function Test-IsAdministrator {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-WingetPresent {
    $null -ne (Get-Command -Name winget -ErrorAction SilentlyContinue)
}

function Get-BloatwareListFromFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    Get-Content -LiteralPath $Path -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Get-AppsFromFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($json.apps)
}

function Read-SettingsPreview {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '(brak pliku)' }
    try {
        $obj = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        return ($obj | ConvertTo-Json -Depth 5)
    }
    catch {
        return "Nie można odczytać JSON: $($_.Exception.Message)"
    }
}

function Initialize-Detection {
    $script:State.IsAdmin = Test-IsAdministrator
    $script:State.HasWinget = Test-WingetPresent

    try {
        . $script:EditionScript
        $info = Get-RunningWindowsEdition
        $script:State.DetectedCaption = [string]$info.Caption
        $script:State.DetectedEdition = [string]$info.EditionID
        $script:State.DetectedBuild = [string]$info.BuildNumber

        $cap = $script:State.DetectedCaption
        if ($cap -match 'Windows\s*11') { $script:State.WinVersion = '11' }
        elseif ($cap -match 'Windows\s*10') { $script:State.WinVersion = '10' }

        $ed = $script:State.DetectedEdition
        if ($ed -match 'Professional|Pro') { $script:State.WinEdition = 'Pro' }
        elseif ($ed -match 'Home|Core') { $script:State.WinEdition = 'Home' }
    }
    catch {
        $script:State.DetectedCaption = "(nie wykryto: $($_.Exception.Message))"
        $script:State.DetectedEdition = ''
        $script:State.DetectedBuild = ''
    }

    $script:State.SettingsText = Read-SettingsPreview -Path $script:State.SettingsPath
}

function Append-UiLog {
    param(
        [System.Windows.Forms.TextBox]$Box,
        [string]$Line
    )
    if ($null -eq $Box) { return }
    if ([string]::IsNullOrEmpty($Box.Text)) {
        $Box.Text = $Line
    }
    else {
        $Box.AppendText([Environment]::NewLine + $Line)
    }
}

function Stop-BackgroundWork {
    $script:Sync.Cancel = $true
    $script:State.CancelRequested = $true
    try {
        if ($null -ne $script:JobPs -and $null -ne $script:JobHandle) {
            if (-not $script:JobHandle.IsCompleted) {
                # daj petli chwilę na przerwanie
                Start-Sleep -Milliseconds 200
            }
            try { $script:JobPs.EndInvoke($script:JobHandle) | Out-Null } catch { }
        }
    }
    catch { }
    finally {
        if ($null -ne $script:JobPs) { $script:JobPs.Dispose(); $script:JobPs = $null }
        if ($null -ne $script:JobRunspace) { $script:JobRunspace.Close(); $script:JobRunspace.Dispose(); $script:JobRunspace = $null }
        $script:JobHandle = $null
        $script:State.Busy = $false
    }
}

function Start-BackgroundWork {
    param(
        [scriptblock]$Work,
        [hashtable]$ArgsTable,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.TextBox]$LogBox,
        [scriptblock]$OnComplete
    )

    if ($script:State.Busy) { return }

    $script:Sync.Log = New-Object System.Collections.ArrayList
    $script:Sync.Progress = 0
    $script:Sync.Done = $false
    $script:Sync.Error = $null
    $script:Sync.Cancel = $false
    $script:State.CancelRequested = $false
    $script:State.Busy = $true
    $ProgressBar.Value = 0
    $LogBox.Clear()

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $script:Sync)
    $rs.SessionStateProxy.SetVariable('Root', $script:Root)
    $rs.SessionStateProxy.SetVariable('DryRun', [bool]$script:State.DryRun)
    foreach ($k in $ArgsTable.Keys) {
        $rs.SessionStateProxy.SetVariable($k, $ArgsTable[$k])
    }

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Work)

    $script:JobRunspace = $rs
    $script:JobPs = $ps
    $script:JobHandle = $ps.BeginInvoke()
    $script:OnComplete = $OnComplete
    $script:ActiveProgress = $ProgressBar
    $script:ActiveLog = $LogBox
    $script:LastLogCount = 0
    $timer.Start()
}

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'konfigurator-win - Kreator'
$form.Size = New-Object System.Drawing.Size(720, 560)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(640, 480)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$chkDry = New-Object System.Windows.Forms.CheckBox
$chkDry.Text = 'Tryb próbny (bez zmian w systemie)'
$chkDry.Checked = $true
$chkDry.AutoSize = $true
$chkDry.Location = New-Object System.Drawing.Point(16, 12)
$chkDry.Add_CheckedChanged({
    $script:State.DryRun = $chkDry.Checked
})
$form.Controls.Add($chkDry)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.AutoSize = $true
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(16, 40)
$form.Controls.Add($lblTitle)

$pageHost = New-Object System.Windows.Forms.Panel
$pageHost.Location = New-Object System.Drawing.Point(16, 70)
$pageHost.Size = New-Object System.Drawing.Size(670, 380)
$pageHost.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($pageHost)

$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text = 'Wstecz'
$btnBack.Size = New-Object System.Drawing.Size(100, 30)
$btnBack.Location = New-Object System.Drawing.Point(280, 470)
$btnBack.Anchor = 'Bottom,Right'

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = 'Dalej'
$btnNext.Size = New-Object System.Drawing.Size(100, 30)
$btnNext.Location = New-Object System.Drawing.Point(390, 470)
$btnNext.Anchor = 'Bottom,Right'

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Anuluj'
$btnCancel.Size = New-Object System.Drawing.Size(100, 30)
$btnCancel.Location = New-Object System.Drawing.Point(500, 470)
$btnCancel.Anchor = 'Bottom,Right'

$form.Controls.AddRange(@($btnBack, $btnNext, $btnCancel))

# Page panels
$pages = @{}

# START
$p0 = New-Object System.Windows.Forms.Panel
$p0.Dock = 'Fill'
$lblStart = New-Object System.Windows.Forms.Label
$lblStart.AutoSize = $false
$lblStart.Dock = 'Fill'
$lblStart.Padding = New-Object System.Windows.Forms.Padding(4)
$p0.Controls.Add($lblStart)
$pages[0] = $p0

# DOWNLOAD
$p1 = New-Object System.Windows.Forms.Panel
$p1.Dock = 'Fill'
$lblDl = New-Object System.Windows.Forms.Label
$lblDl.Text = 'Wybierz wersję i edycję obrazu Windows (tylko oficjalne źródło Microsoft).'
$lblDl.AutoSize = $true
$lblDl.Location = New-Object System.Drawing.Point(4, 4)

$grpVer = New-Object System.Windows.Forms.GroupBox
$grpVer.Text = 'Wersja'
$grpVer.Location = New-Object System.Drawing.Point(4, 30)
$grpVer.Size = New-Object System.Drawing.Size(200, 70)
$rb10 = New-Object System.Windows.Forms.RadioButton
$rb10.Text = 'Windows 10'
$rb10.Location = New-Object System.Drawing.Point(10, 20)
$rb10.AutoSize = $true
$rb11 = New-Object System.Windows.Forms.RadioButton
$rb11.Text = 'Windows 11'
$rb11.Location = New-Object System.Drawing.Point(10, 42)
$rb11.AutoSize = $true
$rb11.Checked = $true
$grpVer.Controls.AddRange(@($rb10, $rb11))

$grpEd = New-Object System.Windows.Forms.GroupBox
$grpEd.Text = 'Edycja'
$grpEd.Location = New-Object System.Drawing.Point(220, 30)
$grpEd.Size = New-Object System.Drawing.Size(200, 70)
$rbHome = New-Object System.Windows.Forms.RadioButton
$rbHome.Text = 'Home'
$rbHome.Location = New-Object System.Drawing.Point(10, 20)
$rbHome.AutoSize = $true
$rbPro = New-Object System.Windows.Forms.RadioButton
$rbPro.Text = 'Pro'
$rbPro.Location = New-Object System.Drawing.Point(10, 42)
$rbPro.AutoSize = $true
$rbPro.Checked = $true
$grpEd.Controls.AddRange(@($rbHome, $rbPro))

$btnRunDl = New-Object System.Windows.Forms.Button
$btnRunDl.Text = 'Uruchom krok'
$btnRunDl.Location = New-Object System.Drawing.Point(440, 50)
$btnRunDl.Size = New-Object System.Drawing.Size(120, 28)

$pb1 = New-Object System.Windows.Forms.ProgressBar
$pb1.Location = New-Object System.Drawing.Point(4, 110)
$pb1.Size = New-Object System.Drawing.Size(650, 18)
$pb1.Anchor = 'Top,Left,Right'

$log1 = New-Object System.Windows.Forms.TextBox
$log1.Multiline = $true
$log1.ScrollBars = 'Vertical'
$log1.ReadOnly = $true
$log1.Location = New-Object System.Drawing.Point(4, 136)
$log1.Size = New-Object System.Drawing.Size(650, 220)
$log1.Anchor = 'Top,Bottom,Left,Right'
$log1.Font = New-Object System.Drawing.Font('Consolas', 9)

$p1.Controls.AddRange(@($lblDl, $grpVer, $grpEd, $btnRunDl, $pb1, $log1))
$pages[1] = $p1

# CUSTOMIZE
$p2 = New-Object System.Windows.Forms.Panel
$p2.Dock = 'Fill'
$lblCu = New-Object System.Windows.Forms.Label
$lblCu.Text = 'Zaznacz pakiety Appx do usunięcia i wskaż plik ustawień JSON.'
$lblCu.AutoSize = $true
$lblCu.Location = New-Object System.Drawing.Point(4, 4)

$clBloat = New-Object System.Windows.Forms.CheckedListBox
$clBloat.Location = New-Object System.Drawing.Point(4, 28)
$clBloat.Size = New-Object System.Drawing.Size(320, 160)
$clBloat.CheckOnClick = $true
$clBloat.Anchor = 'Top,Left,Bottom'

$txtSettingsPath = New-Object System.Windows.Forms.TextBox
$txtSettingsPath.Location = New-Object System.Drawing.Point(340, 28)
$txtSettingsPath.Size = New-Object System.Drawing.Size(220, 24)
$txtSettingsPath.ReadOnly = $true
$txtSettingsPath.Anchor = 'Top,Left,Right'

$btnBrowseSettings = New-Object System.Windows.Forms.Button
$btnBrowseSettings.Text = 'Wybierz JSON...'
$btnBrowseSettings.Location = New-Object System.Drawing.Point(570, 26)
$btnBrowseSettings.Size = New-Object System.Drawing.Size(90, 26)
$btnBrowseSettings.Anchor = 'Top,Right'

$txtSettingsPreview = New-Object System.Windows.Forms.TextBox
$txtSettingsPreview.Multiline = $true
$txtSettingsPreview.ScrollBars = 'Vertical'
$txtSettingsPreview.ReadOnly = $true
$txtSettingsPreview.Location = New-Object System.Drawing.Point(340, 58)
$txtSettingsPreview.Size = New-Object System.Drawing.Size(320, 130)
$txtSettingsPreview.Anchor = 'Top,Left,Right'
$txtSettingsPreview.Font = New-Object System.Drawing.Font('Consolas', 8)

$btnRunCu = New-Object System.Windows.Forms.Button
$btnRunCu.Text = 'Uruchom krok'
$btnRunCu.Location = New-Object System.Drawing.Point(4, 196)
$btnRunCu.Size = New-Object System.Drawing.Size(120, 28)

$pb2 = New-Object System.Windows.Forms.ProgressBar
$pb2.Location = New-Object System.Drawing.Point(4, 230)
$pb2.Size = New-Object System.Drawing.Size(650, 18)
$pb2.Anchor = 'Left,Right,Bottom'

$log2 = New-Object System.Windows.Forms.TextBox
$log2.Multiline = $true
$log2.ScrollBars = 'Vertical'
$log2.ReadOnly = $true
$log2.Location = New-Object System.Drawing.Point(4, 254)
$log2.Size = New-Object System.Drawing.Size(650, 110)
$log2.Anchor = 'Left,Right,Bottom'
$log2.Font = New-Object System.Drawing.Font('Consolas', 9)

$p2.Controls.AddRange(@($lblCu, $clBloat, $txtSettingsPath, $btnBrowseSettings, $txtSettingsPreview, $btnRunCu, $pb2, $log2))
$pages[2] = $p2

# INSTALL
$p3 = New-Object System.Windows.Forms.Panel
$p3.Dock = 'Fill'
$lblIn = New-Object System.Windows.Forms.Label
$lblIn.Text = 'Zaznacz aplikacje do instalacji przez winget.'
$lblIn.AutoSize = $true
$lblIn.Location = New-Object System.Drawing.Point(4, 4)

$clApps = New-Object System.Windows.Forms.CheckedListBox
$clApps.Location = New-Object System.Drawing.Point(4, 28)
$clApps.Size = New-Object System.Drawing.Size(650, 160)
$clApps.CheckOnClick = $true
$clApps.Anchor = 'Top,Left,Right'

$btnRunIn = New-Object System.Windows.Forms.Button
$btnRunIn.Text = 'Uruchom krok'
$btnRunIn.Location = New-Object System.Drawing.Point(4, 196)
$btnRunIn.Size = New-Object System.Drawing.Size(120, 28)

$pb3 = New-Object System.Windows.Forms.ProgressBar
$pb3.Location = New-Object System.Drawing.Point(4, 230)
$pb3.Size = New-Object System.Drawing.Size(650, 18)
$pb3.Anchor = 'Left,Right,Bottom'

$log3 = New-Object System.Windows.Forms.TextBox
$log3.Multiline = $true
$log3.ScrollBars = 'Vertical'
$log3.ReadOnly = $true
$log3.Location = New-Object System.Drawing.Point(4, 254)
$log3.Size = New-Object System.Drawing.Size(650, 110)
$log3.Anchor = 'Left,Right,Bottom'
$log3.Font = New-Object System.Drawing.Font('Consolas', 9)

$p3.Controls.AddRange(@($lblIn, $clApps, $btnRunIn, $pb3, $log3))
$pages[3] = $p3

# SUMMARY
$p4 = New-Object System.Windows.Forms.Panel
$p4.Dock = 'Fill'
$lblSum = New-Object System.Windows.Forms.Label
$lblSum.AutoSize = $false
$lblSum.Dock = 'Fill'
$lblSum.Padding = New-Object System.Windows.Forms.Padding(4)
$p4.Controls.Add($lblSum)
$pages[4] = $p4

foreach ($idx in $pages.Keys) {
    $pages[$idx].Visible = $false
    $pageHost.Controls.Add($pages[$idx])
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if ($null -eq $script:JobHandle) { $timer.Stop(); return }

    $count = $script:Sync.Log.Count
    if ($count -gt $script:LastLogCount) {
        for ($i = $script:LastLogCount; $i -lt $count; $i++) {
            Append-UiLog -Box $script:ActiveLog -Line ([string]$script:Sync.Log[$i])
        }
        $script:LastLogCount = $count
    }

    $pv = [int]$script:Sync.Progress
    if ($pv -lt 0) { $pv = 0 }
    if ($pv -gt 100) { $pv = 100 }
    if ($null -ne $script:ActiveProgress) { $script:ActiveProgress.Value = $pv }

    if ($script:Sync.Done -or $script:JobHandle.IsCompleted) {
        $timer.Stop()
        try {
            if ($null -ne $script:JobPs -and $null -ne $script:JobHandle) {
                $script:JobPs.EndInvoke($script:JobHandle) | Out-Null
            }
        }
        catch {
            Append-UiLog -Box $script:ActiveLog -Line ("Błąd zakończenia zadania: " + $_.Exception.Message)
        }
        if ($script:Sync.Error) {
            Append-UiLog -Box $script:ActiveLog -Line ("BLAD: " + $script:Sync.Error)
        }
        elseif ($script:Sync.Cancel) {
            Append-UiLog -Box $script:ActiveLog -Line 'Przerwano na żądanie użytkownika.'
        }
        else {
            Append-UiLog -Box $script:ActiveLog -Line 'Krok zakończony.'
            if ($null -ne $script:OnComplete) { & $script:OnComplete }
        }
        if ($null -ne $script:JobPs) { $script:JobPs.Dispose(); $script:JobPs = $null }
        if ($null -ne $script:JobRunspace) { $script:JobRunspace.Close(); $script:JobRunspace.Dispose(); $script:JobRunspace = $null }
        $script:JobHandle = $null
        $script:State.Busy = $false
        Set-NavEnabled -Enabled $true
    }
})

function Set-NavEnabled {
    param([bool]$Enabled)
    $btnBack.Enabled = $Enabled -and ($script:State.PageIndex -gt 0)
    $btnNext.Enabled = $Enabled
    $chkDry.Enabled = $Enabled
    $btnRunDl.Enabled = $Enabled
    $btnRunCu.Enabled = $Enabled
    $btnRunIn.Enabled = $Enabled
    $btnBrowseSettings.Enabled = $Enabled
}

function Show-Page {
    param([int]$Index)

    foreach ($k in $pages.Keys) { $pages[$k].Visible = $false }
    $pages[$Index].Visible = $true
    $script:State.PageIndex = $Index

    switch ($Index) {
        0 {
            $lblTitle.Text = 'Start'
            $adminTxt = if ($script:State.IsAdmin) { 'tak' } else { 'nie (zalecane uruchomienie jako administrator)' }
            $wingetTxt = if ($script:State.HasWinget) { 'tak' } else { 'nie (potrzebny do instalacji aplikacji)' }
            $lblStart.Text = @"
Witaj w kreatorze konfigurator-win (szkielet / wczesna wersja).

Wykryty system:
  Opis:   $($script:State.DetectedCaption)
  Edycja: $($script:State.DetectedEdition)
  Build:  $($script:State.DetectedBuild)

Uprawnienia administratora: $adminTxt
winget w PATH: $wingetTxt

Domyślnie włączony jest tryb próbny. W tym trybie nic nie jest usuwane ani instalowane.
Kliknij Dalej, aby przejść do kroków.
"@
            $btnNext.Text = 'Dalej'
        }
        1 {
            $lblTitle.Text = 'Krok 1: Pobranie obrazu'
            if ($script:State.WinVersion -eq '10') { $rb10.Checked = $true } else { $rb11.Checked = $true }
            if ($script:State.WinEdition -eq 'Home') { $rbHome.Checked = $true } else { $rbPro.Checked = $true }
            $btnNext.Text = 'Dalej'
        }
        2 {
            $lblTitle.Text = 'Krok 2: Dostosowanie'
            $txtSettingsPath.Text = $script:State.SettingsPath
            $txtSettingsPreview.Text = $script:State.SettingsText
            $btnNext.Text = 'Dalej'
        }
        3 {
            $lblTitle.Text = 'Krok 3: Instalacja aplikacji'
            $btnNext.Text = 'Dalej'
        }
        4 {
            $lblTitle.Text = 'Podsumowanie'
            $dryTxt = if ($script:State.DryRun) { 'TAK (bez zmian w systemie)' } else { 'NIE (tryb wykonawczy)' }
            $d1 = if ($script:State.StepDone.Download) { 'uruchomiony' } else { 'nie uruchamiany' }
            $d2 = if ($script:State.StepDone.Customize) { 'uruchomiony' } else { 'nie uruchamiany' }
            $d3 = if ($script:State.StepDone.Install) { 'uruchomiony' } else { 'nie uruchamiany' }
            $selBloat = @()
            for ($i = 0; $i -lt $clBloat.Items.Count; $i++) {
                if ($clBloat.GetItemChecked($i)) { $selBloat += [string]$clBloat.Items[$i] }
            }
            $selApps = @()
            for ($i = 0; $i -lt $clApps.Items.Count; $i++) {
                if ($clApps.GetItemChecked($i)) { $selApps += [string]$clApps.Items[$i] }
            }
            $lblSum.Text = @"
Podsumowanie wyborów

Tryb próbny: $dryTxt
Obraz: Windows $($script:State.WinVersion) / $($script:State.WinEdition)
Ustawienia: $($script:State.SettingsPath)

Krok 1 (pobranie): $d1
Krok 2 (dostosowanie): $d2
  Zaznaczone pakiety: $($selBloat.Count)
Krok 3 (instalacja): $d3
  Zaznaczone aplikacje: $($selApps.Count)

Konfigurator jest gotowy. Wybrane operacje zostaną zastosowane zgodnie z trybem wykonania.
Możesz zamknąć kreator przyciskiem Zakończ albo wrócić Wstecz.
"@
            $btnNext.Text = 'Zakończ'
        }
    }

    $btnBack.Enabled = (-not $script:State.Busy) -and ($Index -gt 0)
    $btnNext.Enabled = -not $script:State.Busy
}

function Save-PageInputs {
    if ($script:State.PageIndex -eq 1) {
        $script:State.WinVersion = if ($rb10.Checked) { '10' } else { '11' }
        $script:State.WinEdition = if ($rbHome.Checked) { 'Home' } else { 'Pro' }
    }
}

# Populate lists
Initialize-Detection

$clBloat.Items.Clear()
foreach ($name in (Get-BloatwareListFromFile -Path $script:BloatwarePath)) {
    [void]$clBloat.Items.Add($name, $true)
}

$script:AppItems = @()
$clApps.Items.Clear()
$appsPathUse = $script:AppsExample
$appsJsonPath = Join-Path $script:Root 'install\apps.json'
if (Test-Path -LiteralPath $appsJsonPath) { $appsPathUse = $appsJsonPath }
foreach ($app in (Get-AppsFromFile -Path $appsPathUse)) {
    $label = "$($app.name) [$($app.id)]"
    $script:AppItems += $app
    [void]$clApps.Items.Add($label, $true)
}

$txtSettingsPath.Text = $script:State.SettingsPath
$txtSettingsPreview.Text = $script:State.SettingsText

$btnBrowseSettings.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json|Wszystkie pliki (*.*)|*.*'
    $dlg.Title = 'Wybierz plik ustawień'
    $dlg.InitialDirectory = Join-Path $script:Root 'customize'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:State.SettingsPath = $dlg.FileName
        $script:State.SettingsText = Read-SettingsPreview -Path $dlg.FileName
        $txtSettingsPath.Text = $script:State.SettingsPath
        $txtSettingsPreview.Text = $script:State.SettingsText
    }
})

$workDownload = {
    [void]$Sync.Log.Add('Start: weryfikacja i pobieranie informacji o obrazie...')
    $Sync.Progress = 10
    try {
        $dl = Join-Path $Root 'download\Get-WindowsImage.ps1'
        . $dl
        $Sync.Progress = 40
        if ($Sync.Cancel) { $Sync.Done = $true; return }
        $url = Invoke-GetWindowsImage -Version $WinVersion -Edition $WinEdition
        [void]$Sync.Log.Add("Oficjalny URL: $url")
        $Sync.Progress = 100
    }
    catch {
        $Sync.Error = $_.Exception.Message
    }
    $Sync.Done = $true
}

$workCustomize = {
    [void]$Sync.Log.Add('Start: dostosowanie...')
    try {
        $cu = Join-Path $Root 'customize\Invoke-Customize.ps1'
        . $cu
        $WhatIfPreference = [bool]$DryRun
        $total = @($PackageNames).Count
        if ($total -lt 1) {
            [void]$Sync.Log.Add('Brak zaznaczonych pakietów.')
            $Sync.Progress = 100
            $Sync.Done = $true
            return
        }
        $i = 0
        foreach ($name in $PackageNames) {
            if ($Sync.Cancel) { break }
            [void]$Sync.Log.Add("Pakiet: $name")
            Remove-BloatwareAppx -PackageNames @($name)
            $i++
            $Sync.Progress = [int](100 * $i / $total)
        }
        if (-not $Sync.Cancel) {
            $settings = Get-CustomizationSettings -Path $SettingsPath -ExamplePath (Join-Path $Root 'customize\settings.example.json')
            Set-WallpaperSetting -Settings $settings
            Set-ThemeSetting -Settings $settings
            Set-DefaultBrowserSetting -Settings $settings
            Apply-TaskbarSettings -Settings $settings
            Apply-PrivacySettings -Settings $settings
            [void]$Sync.Log.Add('Zastosowano konfigurację wyglądu, paska zadań i prywatności.')
            $Sync.Progress = 100
        }
    }
    catch {
        $Sync.Error = $_.Exception.Message
    }
    $Sync.Done = $true
}

$workInstall = {
    [void]$Sync.Log.Add('Start: instalacja aplikacji...')
    try {
        $ins = Join-Path $Root 'install\Install-Apps.ps1'
        . $ins
        $script:IsDryRun = [bool]$DryRun
        $total = @($AppList).Count
        if ($total -lt 1) {
            [void]$Sync.Log.Add('Brak zaznaczonych aplikacji.')
            $Sync.Progress = 100
            $Sync.Done = $true
            return
        }
        if (-not (Test-WingetAvailable)) {
            if ($DryRun) {
                [void]$Sync.Log.Add('Ostrzeżenie: winget niedostępny (kontynuacja w trybie próbnym).')
            }
            else {
                throw 'winget nie jest dostępny.'
            }
        }
        $i = 0
        foreach ($app in $AppList) {
            if ($Sync.Cancel) { break }
            $id = [string]$app.id
            $name = [string]$app.name
            [void]$Sync.Log.Add("Aplikacja: $name ($id)")
            Install-WingetApp -Id $id -Name $name
            $i++
            $Sync.Progress = [int](100 * $i / $total)
        }
        if (-not $Sync.Cancel) { $Sync.Progress = 100 }
    }
    catch {
        $Sync.Error = $_.Exception.Message
    }
    $Sync.Done = $true
}

$btnRunDl.Add_Click({
    Save-PageInputs
    Set-NavEnabled -Enabled $false
    Start-BackgroundWork -Work $workDownload -ArgsTable @{
        WinVersion = $script:State.WinVersion
        WinEdition = $script:State.WinEdition
    } -ProgressBar $pb1 -LogBox $log1 -OnComplete {
        $script:State.StepDone.Download = $true
    }
})

$btnRunCu.Add_Click({
    $selected = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $clBloat.Items.Count; $i++) {
        if ($clBloat.GetItemChecked($i)) { [void]$selected.Add([string]$clBloat.Items[$i]) }
    }
    Set-NavEnabled -Enabled $false
    Start-BackgroundWork -Work $workCustomize -ArgsTable @{
        PackageNames = @($selected.ToArray())
        SettingsPath = $script:State.SettingsPath
    } -ProgressBar $pb2 -LogBox $log2 -OnComplete {
        $script:State.StepDone.Customize = $true
    }
})

$btnRunIn.Add_Click({
    $selectedApps = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $clApps.Items.Count; $i++) {
        if ($clApps.GetItemChecked($i) -and $i -lt $script:AppItems.Count) {
            [void]$selectedApps.Add($script:AppItems[$i])
        }
    }
    Set-NavEnabled -Enabled $false
    Start-BackgroundWork -Work $workInstall -ArgsTable @{
        AppList = @($selectedApps.ToArray())
    } -ProgressBar $pb3 -LogBox $log3 -OnComplete {
        $script:State.StepDone.Install = $true
    }
})

$btnBack.Add_Click({
    if ($script:State.Busy) { return }
    Save-PageInputs
    if ($script:State.PageIndex -gt 0) {
        Show-Page -Index ($script:State.PageIndex - 1)
    }
})

$btnNext.Add_Click({
    if ($script:State.Busy) { return }
    Save-PageInputs
    if ($script:State.PageIndex -ge 4) {
        $form.Close()
        return
    }
    Show-Page -Index ($script:State.PageIndex + 1)
})

$btnCancel.Add_Click({
    $msg = if ($script:State.Busy) {
        'Trwa krok w tle. Anulować i zamknąć kreator?'
    } else {
        'Zamknąć kreator?'
    }
    $r = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        'Anuluj',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
        if ($script:State.Busy) { Stop-BackgroundWork }
        $form.Close()
    }
})

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:State.Busy) {
        Stop-BackgroundWork
    }
    $timer.Stop()
})

Show-Page -Index 0
[void]$form.ShowDialog()
