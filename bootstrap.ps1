<#
.SYNOPSIS
  Główny skrypt orkiestracji konfigurator-win: automatyzacja przygotowania, debloatingu i konfiguracji systemu Windows.

.DESCRIPTION
  Uruchamia uporządkowany ciąg procedur:
    1. Analiza i rozpoznanie wersji oraz edycji systemu Windows.
    2. Pobieranie / weryfikacja oficjalnego nośnika instalacyjnego ISO.
    3. Usuwanie zbędnego oprogramowania (bloatware) oraz konfiguracja rejestru (motyw, pasek zadań, prywatność).
    4. Cicha instalacja wybranego zestawu oprogramowania za pośrednictwem winget.

  Domyślnie skrypt uruchamia się w bezpiecznym trybie podglądu (-WhatIf), nie wprowadzając trwałych zmian.

.PARAMETER WindowsVersion
  Docelowa wersja systemu Windows ('10' lub '11'). Domyślnie: '11'.

.PARAMETER Edition
  Docelowa edycja systemu ('Home' lub 'Pro'). Domyślnie: 'Pro'.

.PARAMETER SkipDownload
  Pomija krok weryfikacji i pobierania nośnika Windows.

.PARAMETER SkipCustomize
  Pomija procedurę usuwania bloatware oraz zmian w rejestrze.

.PARAMETER SkipInstall
  Pomija instalację programów przez menedżer winget.

.PARAMETER UpgradeApps
  Próbuje zaktualizować już zainstalowane programy podczas kroku instalacji.

.PARAMETER RestartExplorer
  Restartuje proces explorer.exe na koniec personalizacji, aby natychmiast zastosować zmiany wyglądu.

.PARAMETER Log
  Włącza zapis pełnego przebiegu wykonania do pliku dziennika w podkatalogu 'logs'.

.EXAMPLE
  .\bootstrap.ps1
  # Bezpieczny podgląd całego procesu (WhatIf)

.EXAMPLE
  .\bootstrap.ps1 -WhatIf:$false
  # Rzeczywiste wykonanie pełnej konfiguracji systemu

.EXAMPLE
  .\bootstrap.ps1 -SkipDownload -RestartExplorer -WhatIf:$false
  # Konfiguracja systemu i instalacja aplikacji z natychmiastowym odświeżeniem pulpitu
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
    [switch]$SkipInstall,

    [Parameter(Mandatory = $false)]
    [switch]$UpgradeApps,

    [Parameter(Mandatory = $false)]
    [switch]$RestartExplorer,

    [Parameter(Mandatory = $false)]
    [switch]$Log
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Domyślnie włączony tryb WhatIf (ochrona przed przypadkowym wykonaniem)
if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
    $WhatIfPreference = $true
}

$ScriptStartTime = Get-Date

function Show-Banner {
    $banner = @"

====================================================================
  _  ______  _   _ ______ _____ _____ _    _ _____         _______  
 | |/ / __ \| \ | |  ____|_   _/ ____| |  | |  __ \     /\|__   __| 
 | ' / |  | |  \| | |__    | || |  __| |  | | |__) |   /  \  | |    
 |  <| |  | | . ` |  __|   | || | |_ | |  | |  _  /   / /\ \ | |    
 | . \ |__| | |\  | |     _| || |__| | |__| | | \ \  / ____ \| |    
 |_|\_\____/|_| \_|_|    |_____\_____|\____/|_|  \_\/_/    \_\_|    
                     KONFIGURATOR-WIN v1.0.0
        Kompleksowa automatyzacja i debloat systemu Windows
                    Autor: Dariusz Kisiel
====================================================================
"@
    Write-Host $banner -ForegroundColor Cyan
}

function Test-IsWindowsEnvironment {
    if ($PSVersionTable.ContainsKey('Platform')) {
        return ($PSVersionTable.Platform -eq 'Win32NT')
    }
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Test-IsAdminRole {
    if (-not (Test-IsWindowsEnvironment)) { return $false }
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = [Security.Principal.WindowsPrincipal]::new($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

Show-Banner

# Obsługa rejestrowania do pliku dziennika
$isLoggingActive = $false
if ($Log) {
    $logsDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }
    $logFile = Join-Path $logsDir ("konfigurator_{0:yyyyMMdd_HHmmss}.log" -f $ScriptStartTime)
    try {
        Start-Transcript -Path $logFile -Append -IncludeInvocationHeader
        $isLoggingActive = $true
        Write-Host "Zapis dziennika zdarzeń do: $logFile" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "Nie udało się uruchomić Start-Transcript: $($_.Exception.Message)"
    }
}

# Weryfikacja środowiska i uprawnień
$onWindows = Test-IsWindowsEnvironment
$isAdmin = Test-IsAdminRole

Write-Host "Katalog projektu : $PSScriptRoot"
Write-Host "Wersja PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "Platforma        : $(if ($onWindows) { 'System Windows' } else { 'Nie-Windows (' + [System.Environment]::OSVersion.Platform + ')' })"
Write-Host "Uprawnienia      : $(if ($isAdmin) { 'Administrator [OK]' } else { 'Zwykły użytkownik' })" -ForegroundColor $(if ($isAdmin) { 'Green' } else { 'Yellow' })

if ($onWindows -and -not $isAdmin) {
    Write-Warning "Skrypt nie został uruchomiony z uprawnieniami administratora.`nNiektóre zadania (usuwanie pakietów systemowych Provisioned, instalacja winget) mogą wymagać podniesienia uprawnień (UAC)."
}

if ($WhatIfPreference) {
    Write-Host "`n>>> TRYB PODGLĄDU (-WhatIf) AKTYWNY <<<" -ForegroundColor Yellow
    Write-Host "Wszystkie działania zostaną zaprezentowane bez wprowadzania trwałych zmian.`nAby wykonać rzeczywiste zmiany, uruchom: .\bootstrap.ps1 -WhatIf:`$false`n" -ForegroundColor Yellow
}
else {
    Write-Host "`n>>> TRYB WYKONAWCZY AKTYWNY <<<" -ForegroundColor Red
    Write-Host "Rozpoczynam wprowadzanie modyfikacji w systemie...`n" -ForegroundColor Red
}

$tasksReport = [System.Collections.Generic.List[PSCustomObject]]::new()

function Record-TaskStatus {
    param(
        [string]$StepName,
        [string]$Status,
        [string]$Details
    )
    $tasksReport.Add([PSCustomObject]@{
        Krok      = $StepName
        Status    = $Status
        Szczegóły = $Details
    })
}

# --- KROK 1: Rozpoznanie środowiska Windows ---
Write-Host "--------------------------------------------------" -ForegroundColor DarkCyan
Write-Host " [1/4] Rozpoznawanie edycji i kompilacji systemu" -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor DarkCyan
$editionScript = Join-Path $PSScriptRoot 'customize\Get-WindowsEdition.ps1'
try {
    if (Test-Path -LiteralPath $editionScript) {
        & $editionScript | Out-Null
        Record-TaskStatus -StepName "System Info" -Status "OK" -Details "Odczytano informacje o systemie"
    }
    else {
        Record-TaskStatus -StepName "System Info" -Status "Pominięto" -Details "Brak pliku $editionScript"
    }
}
catch {
    Write-Warning "Wystąpił problem podczas pobierania informacji o edycji: $($_.Exception.Message)"
    Record-TaskStatus -StepName "System Info" -Status "Ostrzeżenie" -Details $_.Exception.Message
}

# --- KROK 2: Asystent nośnika instalacyjnego Windows ---
Write-Host "`n--------------------------------------------------" -ForegroundColor DarkCyan
Write-Host " [2/4] Weryfikacja i pobieranie obrazu Windows" -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor DarkCyan
if (-not $SkipDownload) {
    $downloadScript = Join-Path $PSScriptRoot 'download\Get-WindowsImage.ps1'
    try {
        if (Test-Path -LiteralPath $downloadScript) {
            & $downloadScript -Version $WindowsVersion
            Record-TaskStatus -StepName "Pobieranie ISO" -Status "OK" -Details "Zakończono krok weryfikacji nośnika"
        }
        else {
            Record-TaskStatus -StepName "Pobieranie ISO" -Status "Pominięto" -Details "Brak pliku $downloadScript"
        }
    }
    catch {
        Write-Warning "Błąd kroku pobierania: $($_.Exception.Message)"
        Record-TaskStatus -StepName "Pobieranie ISO" -Status "Błąd" -Details $_.Exception.Message
    }
}
else {
    Write-Host "Krok pobierania obrazu został pominięty (-SkipDownload)." -ForegroundColor DarkGray
    Record-TaskStatus -StepName "Pobieranie ISO" -Status "Pominięto" -Details "Flaga -SkipDownload"
}

# --- KROK 3: Personalizacja systemu i Debloat ---
Write-Host "`n--------------------------------------------------" -ForegroundColor DarkCyan
Write-Host " [3/4] Personalizacja systemu & Usuwanie Bloatware" -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor DarkCyan
if (-not $SkipCustomize) {
    $customizeScript = Join-Path $PSScriptRoot 'customize\Invoke-Customize.ps1'
    try {
        if (Test-Path -LiteralPath $customizeScript) {
            $custParams = @{}
            if (-not $WhatIfPreference) {
                $custParams['WhatIf'] = $false
            }
            if ($RestartExplorer) {
                $custParams['RestartExplorer'] = $true
            }

            & $customizeScript @custParams
            Record-TaskStatus -StepName "Personalizacja" -Status "OK" -Details "Ukończono konfigurację i debloat"
        }
        else {
            Record-TaskStatus -StepName "Personalizacja" -Status "Pominięto" -Details "Brak pliku $customizeScript"
        }
    }
    catch {
        Write-Warning "Błąd kroku personalizacji: $($_.Exception.Message)"
        Record-TaskStatus -StepName "Personalizacja" -Status "Błąd" -Details $_.Exception.Message
    }
}
else {
    Write-Host "Krok personalizacji systemu został pominięty (-SkipCustomize)." -ForegroundColor DarkGray
    Record-TaskStatus -StepName "Personalizacja" -Status "Pominięto" -Details "Flaga -SkipCustomize"
}

# --- KROK 4: Instalacja pakietów oprogramowania (winget) ---
Write-Host "`n--------------------------------------------------" -ForegroundColor DarkCyan
Write-Host " [4/4] Instalacja aplikacji przez winget" -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor DarkCyan
if (-not $SkipInstall) {
    $installScript = Join-Path $PSScriptRoot 'install\Install-Apps.ps1'
    try {
        if (Test-Path -LiteralPath $installScript) {
            $instParams = @{}
            if ($WhatIfPreference) {
                $instParams['DryRun'] = $true
            }
            if ($UpgradeApps) {
                $instParams['UpgradeExisting'] = $true
            }

            & $installScript @instParams
            Record-TaskStatus -StepName "Instalacja aplikacji" -Status "OK" -Details "Przetworzono listę winget"
        }
        else {
            Record-TaskStatus -StepName "Instalacja aplikacji" -Status "Pominięto" -Details "Brak pliku $installScript"
        }
    }
    catch {
        Write-Warning "Błąd kroku instalacji aplikacji: $($_.Exception.Message)"
        Record-TaskStatus -StepName "Instalacja aplikacji" -Status "Błąd" -Details $_.Exception.Message
    }
}
else {
    Write-Host "Krok instalacji aplikacji został pominięty (-SkipInstall)." -ForegroundColor DarkGray
    Record-TaskStatus -StepName "Instalacja aplikacji" -Status "Pominięto" -Details "Flaga -SkipInstall"
}

# --- Podsumowanie wykonania ---
$ScriptDuration = (Get-Date) - $ScriptStartTime

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " Podsumowanie wykonania skryptu bootstrap.ps1" -ForegroundColor Cyan
Write-Host " Czas całkowity: $([math]::Round($ScriptDuration.TotalSeconds, 2)) s" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

$tasksReport | Format-Table -AutoSize | Out-String | Write-Host

if ($WhatIfPreference) {
    Write-Host "[Wskazówka] Aby zastosować powyższe modyfikacje na stałe, uruchom:" -ForegroundColor Yellow
    Write-Host "  .\bootstrap.ps1 -WhatIf:`$false`n" -ForegroundColor White
}
else {
    Write-Host "[Gotowe] Wszystkie operacje zostały wykonane pomyślnie.`n" -ForegroundColor Green
}

if ($isLoggingActive) {
    try {
        Stop-Transcript | Out-Null
    }
    catch { }
}
