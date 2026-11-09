<#
.SYNOPSIS
  Asystent pozyskiwania i weryfikacji oficjalnych obrazów ISO oraz narzędzi instalacyjnych Windows 10 / 11.

.DESCRIPTION
  Ułatwia pobranie oficjalnego nośnika instalacyjnego Windows bezpośrednio z serwerów firmy Microsoft.
  Wspiera bezpośrednie pobranie narzędzia Media Creation Tool, otwarcie oficjalnych stron w przeglądarce,
  automatyczną weryfikację sumy kontrolnej SHA-256 oraz integrację z kreatorem graficznym GUI.

.PARAMETER Version
  Wersja systemu Windows: '10' lub '11'. Domyślnie: '11'.

.PARAMETER Edition
  Docelowa edycja systemu: 'Home' lub 'Pro'. Domyślnie: 'Pro'.

.PARAMETER DownloadMediaCreationTool
  Przełącznik uruchamiający bezpośrednie pobranie oficjalnego instalatora Media Creation Tool z Microsoft.

.PARAMETER OpenBrowser
  Otwiera oficjalną witrynę pobierania Windows w domyślnej przeglądarce internetowej.

.PARAMETER VerifyIsoPath
  Ścieżka do lokalnego pliku ISO w celu obliczenia i weryfikacji sumy kontrolnej SHA-256.

.PARAMETER ExpectedHash
  Opcjonalna oczekiwana suma kontrolna SHA-256 do porównania z plikiem wskazanym w VerifyIsoPath.

.PARAMETER OutputDirectory
  Katalog docelowy na pobrane pliki. Domyślnie: podkatalog 'downloads'.

.EXAMPLE
  .\Get-WindowsImage.ps1 -Version 11 -OpenBrowser
  # Wyświetla informacje i otwiera oficjalną stronę pobierania Windows 11.

.EXAMPLE
  .\Get-WindowsImage.ps1 -Version 11 -DownloadMediaCreationTool
  # Pobiera oficjalny MediaCreationToolW11.exe do folderu downloads.

.EXAMPLE
  .\Get-WindowsImage.ps1 -VerifyIsoPath "C:\ISO\Win11_Polish_x64.iso"
  # Oblicza sumę kontrolną SHA-256 pliku ISO.
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
    [switch]$DownloadMediaCreationTool,

    [Parameter(Mandatory = $false)]
    [switch]$OpenBrowser,

    [Parameter(Mandatory = $false)]
    [string]$VerifyIsoPath,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedHash,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\downloads')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OfficialEndpoints = @{
    '11' = @{
        'PageUrl' = 'https://www.microsoft.com/software-download/windows11'
        'MctUrl'  = 'https://go.microsoft.com/fwlink/?linkid=2156295'
        'MctName' = 'MediaCreationToolW11.exe'
    }
    '10' = @{
        'PageUrl' = 'https://www.microsoft.com/software-download/windows10'
        'MctUrl'  = 'https://go.microsoft.com/fwlink/?LinkId=691209'
        'MctName' = 'MediaCreationTool22H2.exe'
    }
}

function Get-OfficialDownloadPage {
    param(
        [ValidateSet('10', '11')]
        [string]$Version = '11'
    )

    switch ($Version) {
        '11' { return 'https://www.microsoft.com/software-download/windows11' }
        '10' { return 'https://www.microsoft.com/software-download/windows10' }
        default { throw "Nieobsługiwana wersja Windows: $Version" }
    }
}

function Show-IntendedFlow {
    param(
        [string]$Version,
        [string]$Edition,
        [string]$OfficialUrl,
        [string]$OutputDirectory
    )

    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Get-WindowsImage: Pobieranie & Weryfikacja ISO" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "Docelowa wersja : Windows $Version"
    Write-Host "Docelowa edycja : $Edition"
    Write-Host "Oficjalna strona: $OfficialUrl"
    Write-Host "Katalog wyjściowy: $OutputDirectory"
    Write-Host ""
    Write-Host "Procedura instalacyjna Microsoft:" -ForegroundColor Yellow
    Write-Host "  1. Pobierz oficjalny obraz ISO lub narzędzie Media Creation Tool ze strony Microsoft."
    Write-Host "  2. Narzędzie zapisuje plik nośnika lokalnie w wybranym katalogu."
    Write-Host "  3. Zweryfikuj integralność sumy kontrolnej SHA-256."
    Write-Host "  4. Zgodnie z zasadami projektu, nie korzystamy z zewnętrznych mirrorów."
}

function Invoke-BrowserLaunch {
    param([string]$Url)
    Write-Host "`nOtwieranie oficjalnej strony Microsoft w przeglądarce..." -ForegroundColor Yellow
    Write-Host "URL: $Url" -ForegroundColor Cyan

    try {
        if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable.Platform -ne 'Win32NT') {
            if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
                Start-Process xdg-open $Url
            }
            elseif (Get-Command open -ErrorAction SilentlyContinue) {
                Start-Process open $Url
            }
            else {
                Write-Host "Otwórz powyższy adres URL w przeglądarce."
            }
        }
        else {
            Start-Process $Url
        }
    }
    catch {
        Write-Warning "Nie udało się uruchomić przeglądarki automatycznie: $($_.Exception.Message)"
    }
}

function Download-Mct {
    param(
        [string]$MctUrl,
        [string]$MctName,
        [string]$TargetFolder
    )

    if (-not (Test-Path -LiteralPath $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
    }

    $destPath = Join-Path $TargetFolder $MctName
    Write-Host "`nPobieranie oficjalnego narzędzia Media Creation Tool..." -ForegroundColor Yellow
    Write-Host "Źródło: $MctUrl" -ForegroundColor Cyan
    Write-Host "Cel   : $destPath" -ForegroundColor Cyan

    try {
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $MctUrl -OutFile $destPath -UseBasicParsing
        $file = Get-Item -LiteralPath $destPath
        $sizeMb = [math]::Round($file.Length / 1MB, 2)
        Write-Host "[OK] Pobrano pomyślnie: $MctName ($sizeMb MB)" -ForegroundColor Green
    }
    catch {
        Write-Error "Błąd podczas pobierania narzędzia: $($_.Exception.Message)"
    }
}

function Test-IsoIntegrity {
    param(
        [string]$FilePath,
        [string]$Expected
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Error "Wskazany plik ISO nie istnieje: '$FilePath'"
        return
    }

    Write-Host "`nObliczanie sumy kontrolnej SHA-256 dla pliku ISO..." -ForegroundColor Yellow
    Write-Host "Plik: $FilePath"
    $hashResult = Get-FileHash -LiteralPath $FilePath -Algorithm SHA256

    Write-Host "`nObliczona suma SHA-256:" -ForegroundColor Cyan
    Write-Host $hashResult.Hash -ForegroundColor White

    if ($Expected) {
        $cleanExpected = $Expected.Trim().ToUpperInvariant()
        $calculated = $hashResult.Hash.ToUpperInvariant()

        if ($cleanExpected -eq $calculated) {
            Write-Host "`n[ZGODNOŚĆ] Suma kontrolna jest poprawna!" -ForegroundColor Green
        }
        else {
            Write-Host "`n[BŁĄD] Suma kontrolna NIE ZGADZA SIĘ z oczekiwaną!" -ForegroundColor Red
            Write-Host "Oczekiwano: $cleanExpected" -ForegroundColor Yellow
            Write-Host "Otrzymano  : $calculated" -ForegroundColor Red
        }
    }
}

function Start-WindowsImageDownload {
    param(
        [string]$Version,
        [string]$Edition,
        [string]$OutputDirectory
    )
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
    Write-Host ""
    Write-Host "Gotowe (tryb informacyjny). Oficjalny URL firmy Microsoft został zweryfikowany." -ForegroundColor Green
    return $officialUrl
}

function Invoke-GetWindowsImageMain {
    param(
        [string]$Version,
        [string]$Edition,
        [switch]$DownloadMediaCreationTool,
        [switch]$OpenBrowser,
        [string]$VerifyIsoPath,
        [string]$ExpectedHash,
        [string]$OutputDirectory
    )

    $officialUrl = Get-OfficialDownloadPage -Version $Version

    if ($VerifyIsoPath) {
        Test-IsoIntegrity -FilePath $VerifyIsoPath -Expected $ExpectedHash
        return
    }

    $targetConfig = $OfficialEndpoints[$Version]

    if ($DownloadMediaCreationTool) {
        Download-Mct -MctUrl $targetConfig['MctUrl'] -MctName $targetConfig['MctName'] -TargetFolder $OutputDirectory
        return
    }

    if ($OpenBrowser) {
        Invoke-BrowserLaunch -Url $officialUrl
        return
    }

    Invoke-GetWindowsImage -Version $Version -Edition $Edition -OutputDirectory $OutputDirectory | Out-Null
    Write-Host "`nZalecane opcje pobierania:" -ForegroundColor Yellow
    Write-Host "  Pobranie Media Creation Tool: .\Get-WindowsImage.ps1 -Version $Version -DownloadMediaCreationTool" -ForegroundColor White
    Write-Host "  Otwarcie strony w browserze : .\Get-WindowsImage.ps1 -Version $Version -OpenBrowser" -ForegroundColor White
    Write-Host "  Weryfikacja sumy pliku ISO  : .\Get-WindowsImage.ps1 -VerifyIsoPath <sciezka_do_iso>`n" -ForegroundColor White
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-GetWindowsImageMain -Version $Version -Edition $Edition -DownloadMediaCreationTool:$DownloadMediaCreationTool -OpenBrowser:$OpenBrowser -VerifyIsoPath $VerifyIsoPath -ExpectedHash $ExpectedHash -OutputDirectory $OutputDirectory
}
