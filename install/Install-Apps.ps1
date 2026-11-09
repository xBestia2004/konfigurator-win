<#
.SYNOPSIS
  Instaluje ulubione aplikacje przez winget (szkielet).

.DESCRIPTION
  Domyślnie tryb podglądu (-DryRun). Wymaga winget przy realnej instalacji.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AppsPath = (Join-Path $PSScriptRoot 'apps.json'),

    [Parameter(Mandatory = $false)]
    [string]$ExampleAppsPath = (Join-Path $PSScriptRoot 'apps.example.json'),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Jeśli ktoś poda -DryRun:$false, to jest tryb wykonawczy
if ($PSBoundParameters.ContainsKey('DryRun') -and -not $DryRun) {
    $script:IsDryRun = $false
}
elseif (-not $PSBoundParameters.ContainsKey('DryRun')) {
    $script:IsDryRun = $true
}
else {
    $script:IsDryRun = [bool]$DryRun
}

function Test-WingetAvailable {
    $cmd = Get-Command -Name winget -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Get-AppList {
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
            throw "Brak listy aplikacji: $Path"
        }
    }

    $json = Get-Content -LiteralPath $usePath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($json.apps)
}

function Install-WingetApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $false)]
        [string]$Name = $Id
    )

    $display = if ($Name) { "$Name ($Id)" } else { $Id }

    if ($script:IsDryRun) {
        Write-Host "[DryRun] winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements"
        return
    }

    Write-Host "[install] $display"
    & winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget zwrócił kod $LASTEXITCODE dla $Id"
    }
}

Write-Host "=== Install-Apps ==="
if ($script:IsDryRun) {
    Write-Host "Tryb podglądu (DryRun). Nic nie zostanie zainstalowane."
}

if (-not (Test-WingetAvailable)) {
    if ($script:IsDryRun) {
        Write-Warning "winget nie jest dostępny w PATH. W podglądzie kontynuuję; przy realnej instalacji będzie wymagany."
    }
    else {
        throw "winget nie jest dostępny. Zainstaluj App Installer (Microsoft Store) i spróbuj ponownie."
    }
}
else {
    Write-Host "winget: znaleziony"
}

$apps = Get-AppList -Path $AppsPath -ExamplePath $ExampleAppsPath
Write-Host "Aplikacji na liście: $($apps.Count)"

foreach ($app in $apps) {
    $id = [string]$app.id
    $name = [string]$app.name
    if (-not $id) {
        Write-Warning "Pomijam wpis bez id: $($app | ConvertTo-Json -Compress)"
        continue
    }
    Install-WingetApp -Id $id -Name $name
}

Write-Host "Install-Apps: koniec."
