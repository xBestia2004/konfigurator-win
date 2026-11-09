<#
.SYNOPSIS
  Orkiestracja: pobranie info o obrazie, customize, instalacja aplikacji.

.DESCRIPTION
  Domyślnie tryb podglądu. Nie publikuje nic w sieci poza tym, co sam zrobisz
  w przeglądarce przy oficjalnym pobieraniu Windows.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('10', '11')]
    [string]$WindowsVersion = '11',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Home', 'Pro')]
    [string]$Edition = 'Pro',

    [Parameter(Mandatory = $false)]
    [switch]$SkipDownload,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCustomize,

    [Parameter(Mandatory = $false)]
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
    $WhatIfPreference = $true
}

$root = $PSScriptRoot
$downloadScript = Join-Path $root 'download\Get-WindowsImage.ps1'
$editionScript = Join-Path $root 'customize\Get-WindowsEdition.ps1'
$customizeScript = Join-Path $root 'customize\Invoke-Customize.ps1'
$installScript = Join-Path $root 'install\Install-Apps.ps1'

Write-Host "=== konfigurator-win ==="
Write-Host "Katalog: $root"
if ($WhatIfPreference) {
    Write-Host "Tryb podglądu (domyślny). Żadne trwałe zmiany Appx/winget."
}
else {
    Write-Host "Tryb wykonawczy. Customize i install mogą zmieniać system."
}
Write-Host ""

if (-not $SkipDownload) {
    Write-Host "--- Krok 1: download ---"
    & $downloadScript -Version $WindowsVersion -Edition $Edition
    Write-Host ""
}
else {
    Write-Host "--- Krok 1: download pominięty ---"
}

Write-Host "--- Rozpoznanie edycji ---"
try {
    & $editionScript | Out-Null
}
catch {
    Write-Warning "Rozpoznanie edycji nieudane (normalne poza Windows): $($_.Exception.Message)"
}
Write-Host ""

if (-not $SkipCustomize) {
    Write-Host "--- Krok 2: customize ---"
    if ($WhatIfPreference) {
        & $customizeScript -WhatIf
    }
    else {
        & $customizeScript -WhatIf:$false
    }
    Write-Host ""
}
else {
    Write-Host "--- Krok 2: customize pominięty ---"
}

if (-not $SkipInstall) {
    Write-Host "--- Krok 3: install ---"
    if ($WhatIfPreference) {
        & $installScript -DryRun:$true
    }
    else {
        & $installScript -DryRun:$false
    }
    Write-Host ""
}
else {
    Write-Host "--- Krok 3: install pominięty ---"
}

Write-Host "bootstrap: koniec."
