<#
.SYNOPSIS
  Dostosowuje system Windows: usuwa zbędne pakiety Appx (bloatware) oraz konfiguruje ustawienia rejestru.

.DESCRIPTION
  Skrypt czyta listę pakietów z pliku tekstowego (bloatware.txt) oraz preferencje
  z pliku JSON (settings.json lub settings.example.json).
  Domyślnie działa w bezpiecznym trybie podglądu (-WhatIf).
  Wspiera zarówno uruchomienie z wiersza poleceń / bootstrap.ps1, jak i integrację z kreatorem GUI.

.PARAMETER SettingsPath
  Ścieżka do pliku JSON z konfiguracją użytkownika. Domyślnie: settings.json.

.PARAMETER BloatwareListPath
  Ścieżka do pliku z listą nazw pakietów Appx. Domyślnie: bloatware.txt.

.PARAMETER ExampleSettingsPath
  Ścieżka awaryjna do przykładowego pliku konfiguracji. Domyślnie: settings.example.json.

.PARAMETER PackageNames
  Opcjonalna lista pakietów Appx (np. zaznaczonych w kreatorze graficznym GUI).

.PARAMETER RestartExplorer
  Przełącznik wymuszający restart procesu explorer.exe po zakończeniu zmian interfejsu.

.EXAMPLE
  .\Invoke-Customize.ps1
  # Uruchomienie w trybie podglądu (domyślnie WhatIf)

.EXAMPLE
  .\Invoke-Customize.ps1 -WhatIf:$false -RestartExplorer
  # Wykonanie rzeczywistych zmian w systemie i odświeżenie Eksploratora
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),

    [Parameter(Mandatory = $false)]
    [string]$BloatwareListPath = (Join-Path $PSScriptRoot 'bloatware.txt'),

    [Parameter(Mandatory = $false)]
    [string]$ExampleSettingsPath = (Join-Path $PSScriptRoot 'settings.example.json'),

    [Parameter(Mandatory = $false)]
    [string[]]$PackageNames = @(),

    [Parameter(Mandatory = $false)]
    [switch]$RestartExplorer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
    $WhatIfPreference = $true
}

function Test-IsWindows {
    if ($PSVersionTable.ContainsKey('Platform')) {
        return ($PSVersionTable.Platform -eq 'Win32NT')
    }
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Test-IsAdmin {
    if (-not (Test-IsWindows)) { return $false }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-SettingValue {
    param(
        [object]$SettingsObject,
        [string]$PropertyName,
        $DefaultValue = $null
    )
    if ($null -ne $SettingsObject -and $null -ne $SettingsObject.PSObject.Properties[$PropertyName]) {
        return $SettingsObject.$PropertyName
    }
    return $DefaultValue
}

function Get-CustomizationSettings {
    param(
        [string]$Path,
        [string]$ExamplePath
    )

    $targetPath = $Path
    if (-not (Test-Path -LiteralPath $targetPath)) {
        if (Test-Path -LiteralPath $ExamplePath) {
            Write-Warning "Brak lokalnego '$Path'. Używam szablonu: '$ExamplePath'."
            $targetPath = $ExamplePath
        }
        else {
            throw "Brak pliku ustawień: '$Path' oraz szablonu: '$ExamplePath'."
        }
    }

    $raw = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8
    return ($raw | ConvertFrom-Json)
}

function Get-BloatwareNames {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Nie odnaleziono pliku z listą bloatware: '$Path'."
    }

    Get-Content -LiteralPath $Path -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Set-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$PropertyType = 'DWord'
    )

    $actionDesc = "Ustawienie rejestru: $Path\$Name = $Value ($PropertyType)"
    $doWhatIf = $WhatIfPreference
    if (-not $doWhatIf -and $null -ne $PSCmdlet) {
        $doWhatIf = -not $PSCmdlet.ShouldProcess($actionDesc, "Zapisz w rejestrze")
    }

    if ($doWhatIf) {
        Write-Host "  [WhatIf] $actionDesc" -ForegroundColor DarkCyan
        return
    }

    if (-not (Test-IsWindows)) {
        Write-Host "  [Symulacja] $actionDesc" -ForegroundColor DarkGray
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force -ErrorAction Stop | Out-Null
    Write-Host "  [OK] Zastosowano: $Name = $Value" -ForegroundColor Green
}

function Remove-BloatwareAppx {
    param(
        [string[]]$PackageNames
    )

    Write-Host "`n--- Usuwanie niechcianych aplikacji (Appx) ---" -ForegroundColor Cyan
    $isAdmin = Test-IsAdmin

    if (-not (Test-IsWindows)) {
        Write-Warning "Środowisko inne niż Windows - symulacja sprawdzania $( $PackageNames.Count ) pakietów."
        foreach ($pkg in $PackageNames) {
            Write-Host "  [Symulacja] Usunięcie Appx: $pkg" -ForegroundColor DarkGray
        }
        return
    }

    foreach ($name in $PackageNames) {
        $userPackages = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)

        # 1. Profil bieżącego użytkownika
        if ($userPackages.Count -gt 0) {
            foreach ($pkg in $userPackages) {
                $targetDesc = "$($pkg.Name) ($($pkg.Version))"
                $doWhatIf = $WhatIfPreference
                if (-not $doWhatIf -and $null -ne $PSCmdlet) {
                    $doWhatIf = -not $PSCmdlet.ShouldProcess($targetDesc, "Remove-AppxPackage")
                }

                if ($doWhatIf) {
                    Write-Host "  [WhatIf] Usunięto by Appx użytkownika: $targetDesc" -ForegroundColor DarkCyan
                }
                else {
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                        Write-Host "  [OK] Usunięto pakiet użytkownika: $($pkg.Name)" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "  [Błąd] Nie udało się usunąć $($pkg.Name): $($_.Exception.Message)"
                    }
                }
            }
        }
        else {
            Write-Host "  [pomijam] Brak zainstalowanego pakietu użytkownika: $name" -ForegroundColor DarkGray
        }

        # 2. Rejestr aprowizacji systemu (All Users)
        if ($isAdmin) {
            $provPackages = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $name })
            foreach ($prov in $provPackages) {
                $provDesc = "Provisioned Appx: $($prov.DisplayName)"
                $doWhatIf = $WhatIfPreference
                if (-not $doWhatIf -and $null -ne $PSCmdlet) {
                    $doWhatIf = -not $PSCmdlet.ShouldProcess($provDesc, "Remove-AppxProvisionedPackage")
                }

                if ($doWhatIf) {
                    Write-Host "  [WhatIf] Usunięto by pakiet aprowizowany: $($prov.DisplayName)" -ForegroundColor DarkCyan
                }
                else {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                        Write-Host "  [OK] Usunięto pakiet aprowizowany: $($prov.DisplayName)" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "  [Błąd] Nie udało się usunąć aprowizacji dla $($prov.DisplayName): $($_.Exception.Message)"
                    }
                }
            }
        }
    }
}

function Set-WallpaperSetting {
    param($Settings)

    $wallpaperPath = Get-SettingValue -SettingsObject $Settings -PropertyName 'wallpaper'
    if (-not $wallpaperPath) { return }

    Write-Host "`n--- Konfiguracja tapety pulpitu ---" -ForegroundColor Cyan
    Write-Host "Ścieżka do tapety: $wallpaperPath"

    if (-not (Test-Path -LiteralPath $wallpaperPath)) {
        Write-Warning "Wskazany plik tapety nie istnieje na dysku: '$wallpaperPath'. Pomijam."
        return
    }

    $actionDesc = "Ustawienie tapety: $wallpaperPath"
    $doWhatIf = $WhatIfPreference
    if (-not $doWhatIf -and $null -ne $PSCmdlet) {
        $doWhatIf = -not $PSCmdlet.ShouldProcess($actionDesc, "Zastosuj tapetę")
    }

    if ($doWhatIf) {
        Write-Host "  [WhatIf] $actionDesc" -ForegroundColor DarkCyan
        return
    }

    if (-not (Test-IsWindows)) {
        Write-Host "  [Symulacja] $actionDesc" -ForegroundColor DarkGray
        return
    }

    try {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -Value $wallpaperPath -Force
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force

        $code = @"
using System;
using System.Runtime.InteropServices;
public class WallpaperHelper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
        if (-not ([System.Management.Automation.PSTypeName]'WallpaperHelper').Type) {
            Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
        }
        [WallpaperHelper]::SystemParametersInfo(0x0014, 0, $wallpaperPath, 0x01 -bor 0x02) | Out-Null
        Write-Host "  [OK] Tapeta została pomyślnie zaktualizowana." -ForegroundColor Green
    }
    catch {
        Write-Warning "Nie udało się zaktualizować tapety: $($_.Exception.Message)"
    }
}

function Set-ThemeSetting {
    param($Settings)

    $theme = Get-SettingValue -SettingsObject $Settings -PropertyName 'theme'
    if (-not $theme) { return }

    Write-Host "`n--- Konfiguracja motywu systemu ---" -ForegroundColor Cyan
    $themeVal = if ($theme -eq 'light') { 1 } else { 0 }
    $themeName = if ($theme -eq 'light') { 'Jasny (Light)' } else { 'Ciemny (Dark)' }
    Write-Host "Wybrany motyw: $themeName"

    $regTheme = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-RegistryValueSafe -Path $regTheme -Name 'AppsUseLightTheme' -Value $themeVal -PropertyType 'DWord'
    Set-RegistryValueSafe -Path $regTheme -Name 'SystemUsesLightTheme' -Value $themeVal -PropertyType 'DWord'
    Set-RegistryValueSafe -Path $regTheme -Name 'EnableTransparency' -Value 1 -PropertyType 'DWord'
}

function Set-DefaultBrowserSetting {
    param($Settings)

    $browser = Get-SettingValue -SettingsObject $Settings -PropertyName 'defaultBrowser'
    if (-not $browser) { return }

    Write-Host "`n--- Domyślna przeglądarka internetowa ---" -ForegroundColor Cyan
    Write-Host "Zgodnie z wytycznymi bezpieczeństwa Windows 10/11, domyślna przeglądarka ($browser)"
    Write-Host "wymaga zatwierdzenia przez użytkownika w aplecie Ustawień systemowych (ms-settings:defaultapps)." -ForegroundColor Yellow
}

function Apply-TaskbarSettings {
    param($Settings)

    Write-Host "`n--- Konfiguracja paska zadań i Eksploratora ---" -ForegroundColor Cyan
    $regExplorerAdvanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    $alignLeft = Get-SettingValue -SettingsObject $Settings -PropertyName 'taskbarAlignLeft'
    if ($null -ne $alignLeft) {
        $alignVal = if ($alignLeft) { 0 } else { 1 }
        Set-RegistryValueSafe -Path $regExplorerAdvanced -Name 'TaskbarAl' -Value $alignVal -PropertyType 'DWord'
    }

    $showExt = Get-SettingValue -SettingsObject $Settings -PropertyName 'showFileExtensions'
    if ($null -ne $showExt) {
        $hideExtVal = if ($showExt) { 0 } else { 1 }
        Set-RegistryValueSafe -Path $regExplorerAdvanced -Name 'HideFileExt' -Value $hideExtVal -PropertyType 'DWord'
    }

    $showHidden = Get-SettingValue -SettingsObject $Settings -PropertyName 'showHiddenFiles'
    if ($null -ne $showHidden) {
        $hiddenVal = if ($showHidden) { 1 } else { 2 }
        Set-RegistryValueSafe -Path $regExplorerAdvanced -Name 'Hidden' -Value $hiddenVal -PropertyType 'DWord'
    }

    $disableWidgets = Get-SettingValue -SettingsObject $Settings -PropertyName 'disableWidgets'
    if ($null -ne $disableWidgets -and $disableWidgets) {
        Set-RegistryValueSafe -Path $regExplorerAdvanced -Name 'TaskbarDa' -Value 0 -PropertyType 'DWord'
    }
}

function Apply-PrivacySettings {
    param($Settings)

    Write-Host "`n--- Prywatność i wyszukiwanie ---" -ForegroundColor Cyan

    $disableBing = Get-SettingValue -SettingsObject $Settings -PropertyName 'disableBingSearch'
    if ($null -ne $disableBing -and $disableBing) {
        $policyExplorer = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
        Set-RegistryValueSafe -Path $policyExplorer -Name 'DisableSearchBoxSuggestions' -Value 1 -PropertyType 'DWord'

        $searchReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
        Set-RegistryValueSafe -Path $searchReg -Name 'BingSearchEnabled' -Value 0 -PropertyType 'DWord'
    }

    $disableTelemetry = Get-SettingValue -SettingsObject $Settings -PropertyName 'disableTelemetry'
    if ($null -ne $disableTelemetry -and $disableTelemetry -and (Test-IsAdmin)) {
        $telemetryReg = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        Set-RegistryValueSafe -Path $telemetryReg -Name 'AllowTelemetry' -Value 0 -PropertyType 'DWord'
    }
}

function Restart-WindowsExplorerProcess {
    if (-not (Test-IsWindows)) { return }

    $doWhatIf = $WhatIfPreference
    if (-not $doWhatIf -and $null -ne $PSCmdlet) {
        $doWhatIf = -not $PSCmdlet.ShouldProcess("Eksplorator Windows (explorer.exe)", "Restart procesu")
    }

    if ($doWhatIf) {
        Write-Host "  [WhatIf] Nastąpiłby restart explorer.exe w celu odświeżenia paska zadań." -ForegroundColor DarkCyan
        return
    }

    Write-Host "`n--- Restart Eksploratora Windows ---" -ForegroundColor Cyan
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Write-Host "  [OK] Pomyślnie zrestartowano explorer.exe" -ForegroundColor Green
    }
    catch {
        Write-Warning "Nie udało się zrestartować explorer.exe: $($_.Exception.Message)"
    }
}

function Invoke-CustomizeMain {
    param(
        [string]$SettingsPath,
        [string]$BloatwareListPath,
        [string]$ExampleSettingsPath,
        [string[]]$PackageNames,
        [switch]$RestartExplorer
    )

    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Invoke-Customize: Konfiguracja & Debloat Windows" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    if ($WhatIfPreference) {
        Write-Host "STATUS: TRYB PODGLĄDU (-WhatIf)." -ForegroundColor Yellow
        Write-Host "Żadne trwałe zmiany w systemie ani pakietach nie zostaną wykonane.`n" -ForegroundColor Yellow
    }
    else {
        Write-Host "STATUS: TRYB WYKONAWCZY." -ForegroundColor Red
        Write-Host "Wprowadzanie realnych modyfikacji w systemie Windows...`n" -ForegroundColor Red
    }

    $settings = Get-CustomizationSettings -Path $SettingsPath -ExamplePath $ExampleSettingsPath

    $bloat = @()
    if ($PackageNames -and $PackageNames.Count -gt 0) {
        $bloat = @($PackageNames)
        Write-Host "Pakiety: lista przekazana z zewnątrz ($($bloat.Count))"
    }
    else {
        $bloat = @(Get-BloatwareNames -Path $BloatwareListPath)
        Write-Host "Pakiety z pliku: $BloatwareListPath ($($bloat.Count))"
    }

    Remove-BloatwareAppx -PackageNames $bloat
    Set-WallpaperSetting -Settings $settings
    Set-ThemeSetting -Settings $settings
    Set-DefaultBrowserSetting -Settings $settings
    Apply-TaskbarSettings -Settings $settings
    Apply-PrivacySettings -Settings $settings

    if ($RestartExplorer -and -not $WhatIfPreference) {
        Restart-WindowsExplorerProcess
    }

    Write-Host "`n[Koniec] Konfiguracja systemu zakończona pomyślnie." -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-CustomizeMain -SettingsPath $SettingsPath -BloatwareListPath $BloatwareListPath -ExampleSettingsPath $ExampleSettingsPath -PackageNames $PackageNames -RestartExplorer:$RestartExplorer
}
