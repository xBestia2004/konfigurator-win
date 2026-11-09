<#
.SYNOPSIS
  Dostosowuje Windows według listy bloatware i pliku ustawień (szkielet).

.DESCRIPTION
  Domyślnie działa w trybie podglądu (-WhatIf). Usuwanie Appx następuje
  tylko gdy -WhatIf:$false. Tapeta, motyw i domyślna przeglądarka: TODO.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),

    [Parameter(Mandatory = $false)]
    [string]$BloatwareListPath = (Join-Path $PSScriptRoot 'bloatware.txt'),

    [Parameter(Mandatory = $false)]
    [string]$ExampleSettingsPath = (Join-Path $PSScriptRoot 'settings.example.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Domyślnie WhatIf, gdy użytkownik nie podał przełącznika
if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
    $WhatIfPreference = $true
}

function Get-CustomizationSettings {
    param(
        [string]$Path,
        [string]$ExamplePath
    )

    $usePath = $Path
    if (-not (Test-Path -LiteralPath $usePath)) {
        if (Test-Path -LiteralPath $ExamplePath) {
            Write-Warning "Brak $usePath. Używam przykładu: $ExamplePath"
            $usePath = $ExamplePath
        }
        else {
            throw "Brak pliku ustawień: $Path (oraz przykładu $ExamplePath)"
        }
    }

    Get-Content -LiteralPath $usePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-BloatwareNames {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Brak listy bloatware: $Path"
    }

    Get-Content -LiteralPath $Path -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Remove-BloatwareAppx {
    param(
        [string[]]$PackageNames
    )

    foreach ($name in $PackageNames) {
        $packages = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
        if ($packages.Count -eq 0) {
            Write-Host "[pomijam] Brak zainstalowanego pakietu: $name"
            continue
        }

        foreach ($pkg in $packages) {
            $target = "$($pkg.Name) ($($pkg.PackageFullName))"
            if ($WhatIfPreference -or -not $PSCmdlet.ShouldProcess($target, 'Remove-AppxPackage')) {
                Write-Host "[WhatIf] Usunięto by Appx: $target"
                continue
            }

            # Realne usunięcie tylko poza trybem podglądu
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
            Write-Host "[ok] Usunięto: $target"
        }
    }
}

function Set-WallpaperSetting {
    param($Settings)
    # TODO: ustawić tapetę z $Settings.wallpaper (SystemParametersInfo / rejestr)
    Write-Host "[TODO] Tapeta: $($Settings.wallpaper)"
}

function Set-ThemeSetting {
    param($Settings)
    # TODO: ustawić motyw light/dark (AppsUseLightTheme / SystemUsesLightTheme)
    Write-Host "[TODO] Motyw: $($Settings.theme)"
}

function Set-DefaultBrowserSetting {
    param($Settings)
    # TODO: ustawić domyślną przeglądarkę ($Settings.defaultBrowser) w obsługiwany sposób na danej edycji Windows
    Write-Host "[TODO] Domyślna przeglądarka: $($Settings.defaultBrowser)"
}

Write-Host "=== Invoke-Customize ==="
if ($WhatIfPreference) {
    Write-Host "Tryb podglądu (WhatIf). Żadne Appx nie zostaną usunięte."
}
else {
    Write-Host "Tryb wykonawczy. Appx z listy mogą zostać usunięte."
}

$settings = Get-CustomizationSettings -Path $SettingsPath -ExamplePath $ExampleSettingsPath
$bloat = @(Get-BloatwareNames -Path $BloatwareListPath)

Write-Host "Ustawienia z: $(if (Test-Path $SettingsPath) { $SettingsPath } else { $ExampleSettingsPath })"
Write-Host "Pozycji bloatware na liście: $($bloat.Count)"

Remove-BloatwareAppx -PackageNames $bloat
Set-WallpaperSetting -Settings $settings
Set-ThemeSetting -Settings $settings
Set-DefaultBrowserSetting -Settings $settings

Write-Host "Customize: koniec."
