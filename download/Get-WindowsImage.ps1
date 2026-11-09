<#
.SYNOPSIS
  Szkielet pobierania oficjalnego obrazu Windows 10/11 (Pro lub Home).

.DESCRIPTION
  Nie pobiera jeszcze pliku ISO. Wypisuje oficjalny adres Microsoft
  i opisuje zamierzony przepływ (Media Creation Tool / strona software-download).
  Żadnych nieoficjalnych mirrorów.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('10', '11')]
    [string]$Version = '11',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Home', 'Pro')]
    [string]$Edition = 'Pro',

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\downloads')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OfficialDownloadPage {
    param(
        [ValidateSet('10', '11')]
        [string]$Version
    )

    switch ($Version) {
        '11' { return 'https://www.microsoft.com/software-download/windows11' }
        '10' { return 'https://www.microsoft.com/software-download/windows10' }
        default { throw "Nieobsługiwana wersja: $Version" }
    }
}

function Show-IntendedFlow {
    param(
        [string]$Version,
        [string]$Edition,
        [string]$OfficialUrl,
        [string]$OutputDirectory
    )

    Write-Host "=== Get-WindowsImage (szkielet) ==="
    Write-Host "Docelowa wersja : Windows $Version"
    Write-Host "Docelowa edycja : $Edition"
    Write-Host "Oficjalna strona: $OfficialUrl"
    Write-Host "Katalog wyjściowy (planowany): $OutputDirectory"
    Write-Host ""
    Write-Host "Zamierzony przepływ (TODO):"
    Write-Host "  1. Otworzyć oficjalną stronę Microsoft (powyższy URL)."
    Write-Host "  2. Użyć Media Creation Tool albo oficjalnego pobierania ISO z tej strony."
    Write-Host "  3. Zapisać obraz tylko do lokalnego katalogu (np. downloads)."
    Write-Host "  4. Zweryfikować sumę kontrolną, jeśli Microsoft ją opublikuje."
    Write-Host "  5. Nie korzystać z nieoficjalnych mirrorów ani zewnętrznych hostów ISO."
}

function Start-WindowsImageDownload {
    param(
        [string]$Version,
        [string]$Edition,
        [string]$OutputDirectory
    )

    # TODO: zaimplementować bezpieczne pobieranie wyłącznie przez oficjalny kanał Microsoft
    # (Media Creation Tool / software-download). Na razie tylko informacja.
    Write-Warning "Pobieranie nie jest jeszcze zaimplementowane. To szkielet."
    return $null
}

function Invoke-GetWindowsImage {
    param(
        [ValidateSet('10', '11')]
        [string]$Version = '11',
        [ValidateSet('Home', 'Pro')]
        [string]$Edition = 'Pro',
        [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\downloads')
    )

    $officialUrl = Get-OfficialDownloadPage -Version $Version
    Show-IntendedFlow -Version $Version -Edition $Edition -OfficialUrl $officialUrl -OutputDirectory $OutputDirectory
    Start-WindowsImageDownload -Version $Version -Edition $Edition -OutputDirectory $OutputDirectory | Out-Null
    Write-Host ""
    Write-Host "Gotowe (tryb informacyjny). Otwórz oficjalny URL w przeglądarce, gdy będziesz gotowy do pobrania."
    return $officialUrl
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-GetWindowsImage -Version $Version -Edition $Edition -OutputDirectory $OutputDirectory
}
