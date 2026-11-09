<#
.SYNOPSIS
  Automatyczna instalacja pakietów oprogramowania za pośrednictwem menedżera pakietów Windows Package Manager (winget).

.DESCRIPTION
  Skrypt odczytuje listę aplikacji z pliku JSON (apps.json lub szablonu apps.example.json)
  i instaluje je w trybie cichym (unattended) wraz z automatyczną akceptacją licencji.
  Sprawdza obecność aplikacji przed próbą ponownej instalacji.
  Wspiera uruchomienie bezpośrednie, z orkiestratora bootstrap.ps1 oraz z kreatora GUI (Start-Kreator.ps1).

.PARAMETER AppsPath
  Ścieżka do pliku konfiguracji aplikacji w formacie JSON. Domyślnie: apps.json.

.PARAMETER ExampleAppsPath
  Ścieżka do domyślnego szablonu aplikacji. Domyślnie: apps.example.json.

.PARAMETER DryRun
  Uruchamia skrypt w trybie symulacji (podglądu) - żadne pakiety nie zostaną faktycznie pobrane ani zainstalowane.

.PARAMETER AppIds
  Opcjonalny filtr identyfikatorów pakietów (np. przekazany z zaznaczonych pozycji w GUI).

.PARAMETER UpgradeExisting
  Jeśli pakiet jest już zainstalowany, próbuje zaktualizować go do najnowszej wersji.

.EXAMPLE
  .\Install-Apps.ps1 -DryRun
  # Podgląd listy aplikacji i komend winget bez ich wykonywania.

.EXAMPLE
  .\Install-Apps.ps1
  # Rzeczywista instalacja programów z pliku apps.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AppsPath = (Join-Path $PSScriptRoot 'apps.json'),

    [Parameter(Mandatory = $false)]
    [string]$ExampleAppsPath = (Join-Path $PSScriptRoot 'apps.example.json'),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun = $true,

    [Parameter(Mandatory = $false)]
    [string[]]$AppIds = @(),

    [Parameter(Mandatory = $false)]
    [switch]$UpgradeExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSBoundParameters.ContainsKey('DryRun') -and -not $DryRun) {
    $script:IsDryRun = $false
}
elseif (-not $PSBoundParameters.ContainsKey('DryRun')) {
    $script:IsDryRun = $true
}
else {
    $script:IsDryRun = [bool]$DryRun
}

function Test-IsWindows {
    if ($PSVersionTable.ContainsKey('Platform')) {
        return ($PSVersionTable.Platform -eq 'Win32NT')
    }
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Test-WingetAvailable {
    $cmd = Get-Command -Name winget -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Get-AppList {
    param(
        [string]$Path,
        [string]$ExamplePath
    )

    $targetPath = $Path
    if (-not (Test-Path -LiteralPath $targetPath)) {
        if (Test-Path -LiteralPath $ExamplePath) {
            Write-Warning "Brak lokalnego pliku '$Path'. Używam szablonu: '$ExamplePath'."
            $targetPath = $ExamplePath
        }
        else {
            throw "Nie znaleziono pliku konfiguracji aplikacji: '$Path' ani szablonu '$ExamplePath'."
        }
    }

    $json = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($json.apps)
}

function Test-AppAlreadyInstalled {
    param([string]$PackageId)

    if (-not (Test-IsWindows) -or -not (Test-WingetAvailable)) {
        return $false
    }

    try {
        $check = winget list --id $PackageId --exact --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -and $check -match [regex]::Escape($PackageId)) {
            return $true
        }
    }
    catch {
        # Ignoruj błąd sprawdzania
    }
    return $false
}

function Install-WingetApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $false)]
        [string]$Name = $Id,

        [Parameter(Mandatory = $false)]
        [switch]$UpgradeExisting
    )

    $display = if ($Name) { "$Name ($Id)" } else { $Id }

    if ($script:IsDryRun -or -not (Test-IsWindows)) {
        Write-Host "  [DryRun] winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements" -ForegroundColor DarkCyan
        return
    }

    $alreadyInstalled = Test-AppAlreadyInstalled -PackageId $Id

    if ($alreadyInstalled -and -not $UpgradeExisting) {
        Write-Host "  [pomijam] Program jest już zainstalowany: $display" -ForegroundColor Gray
        return
    }
    elseif ($alreadyInstalled -and $UpgradeExisting) {
        Write-Host "  [aktualizacja] $display" -ForegroundColor Yellow
        & winget upgrade --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "winget zwrócił kod $LASTEXITCODE podczas aktualizacji $Id"
        }
        return
    }

    Write-Host "  [instalacja] $display" -ForegroundColor Yellow
    & winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget zwrócił kod $LASTEXITCODE podczas instalacji $Id"
    }
    else {
        Write-Host "  [OK] Zainstalowano pomyślnie: $display" -ForegroundColor Green
    }
}

function Invoke-InstallAppsMain {
    param(
        [string]$AppsPath,
        [string]$ExampleAppsPath,
        [string[]]$AppIds,
        [switch]$UpgradeExisting
    )

    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Install-Apps: Instalator pakietów winget" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    $isSimulation = [bool]$script:IsDryRun
    if (-not (Test-IsWindows)) {
        Write-Warning "Środowisko inne niż Windows - wymuszenie trybu symulacji (DryRun)."
        $isSimulation = $true
        $script:IsDryRun = $true
    }

    if ($isSimulation) {
        Write-Host "STATUS: TRYB PODGLĄDU (-DryRun)." -ForegroundColor Yellow
        Write-Host "Żadne aplikacje nie zostaną zainstalowane.`n" -ForegroundColor Yellow
    }
    else {
        Write-Host "STATUS: TRYB INSTALACJI." -ForegroundColor Green
        Write-Host "Pakiety zostaną zainstalowane w trybie cichym (silent).`n" -ForegroundColor Green
    }

    $wingetExists = Test-WingetAvailable
    if (-not $wingetExists) {
        if ($isSimulation) {
            Write-Warning "winget nie jest dostępny w bieżącym środowisku. W trybie symulacji kontynuuję."
        }
        else {
            Write-Error "Menedżer pakietów 'winget' nie został odnaleziony w systemie.`nZainstaluj 'App Installer' z Microsoft Store lub pobierz pakiet z: https://github.com/microsoft/winget-cli/releases"
            return
        }
    }

    $apps = Get-AppList -Path $AppsPath -ExamplePath $ExampleAppsPath

    if ($AppIds -and $AppIds.Count -gt 0) {
        $idSet = @{}
        foreach ($id in $AppIds) { $idSet[[string]$id] = $true }
        $apps = @($apps | Where-Object { $idSet.ContainsKey([string]$_.id) })
        Write-Host "Filtrowanie pozycji: $($apps.Count) wybranych pakietów"
    }

    Write-Host "Liczba pakietów na liście do przetworzenia: $($apps.Count)`n" -ForegroundColor Cyan

    foreach ($app in $apps) {
        $id = [string]$app.id
        $name = [string]$app.name
        if (-not $id) {
            Write-Warning "Pomijam wpis bez identyfikatora ID."
            continue
        }
        Install-WingetApp -Id $id -Name $name -UpgradeExisting:$UpgradeExisting
    }

    Write-Host "`nInstall-Apps: proces instalacji zakończony." -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-InstallAppsMain -AppsPath $AppsPath -ExampleAppsPath $ExampleAppsPath -AppIds $AppIds -UpgradeExisting:$UpgradeExisting
}
