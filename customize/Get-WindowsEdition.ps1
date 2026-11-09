<#
.SYNOPSIS
  Rozpoznaje edycję, wersję i build działającego systemu Windows.

.DESCRIPTION
  Odczytuje szczegółowe informacje o systemie z rejestru oraz WMI/CIM,
  w tym wersję funkcjonalną (np. 23H2), numer kompilacji, architekturę
  oraz status uprawnień administratora.

.PARAMETER AsJson
  Zwraca wynik sformatowany jako JSON.

.OUTPUTS
  [PSCustomObject] zawierający dane o systemie operacyjnym.

.EXAMPLE
  .\Get-WindowsEdition.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsWindowsEnvironment {
    if ($PSVersionTable.ContainsKey('Platform')) {
        return ($PSVersionTable.Platform -eq 'Win32NT')
    }
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Test-IsAdministrator {
    if (-not (Test-IsWindowsEnvironment)) {
        return $false
    }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-WindowsSystemInfo {
    if (-not (Test-IsWindowsEnvironment)) {
        Write-Warning "Skrypt uruchomiony w środowisku innym niż Windows ($([System.Environment]::OSVersion.VersionString))."
        return [PSCustomObject]@{
            OSName         = "Non-Windows Platform ($([System.Environment]::OSVersion.Platform))"
            DisplayVersion = "N/A"
            EditionID      = "N/A"
            BuildNumber    = [string][System.Environment]::OSVersion.Version
            Architecture   = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            IsAdmin        = $false
            Environment    = "Testing / Non-Windows"
        }
    }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $editionId = $null
    $displayVer = $null
    $buildNumber = $null
    $ubr = $null
    $productName = $null

    if (Test-Path -LiteralPath $regPath) {
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($reg) {
            $editionId   = $reg.EditionID
            $displayVer  = $reg.DisplayVersion
            if (-not $displayVer) { $displayVer = $reg.ReleaseId }
            $buildNumber = $reg.CurrentBuildNumber
            $ubr         = $reg.UBR
            $productName = $reg.ProductName
        }
    }

    if (-not $productName -and $os) {
        $productName = $os.Caption
    }
    if (-not $buildNumber -and $os) {
        $buildNumber = $os.BuildNumber
    }

    $fullBuild = if ($ubr) { "$buildNumber.$ubr" } else { "$buildNumber" }
    $isAdmin = Test-IsAdministrator

    [PSCustomObject]@{
        OSName         = [string]$productName
        DisplayVersion = [string]$displayVer
        EditionID      = [string]$editionId
        BuildNumber    = [string]$fullBuild
        Architecture   = [string]$(if ($os.OSArchitecture) { $os.OSArchitecture } else { [System.IntPtr]::Size * 8 -replace '$', '-bit' })
        IsAdmin        = [bool]$isAdmin
        Environment    = "Windows"
    }
}

$info = Get-WindowsSystemInfo

if ($AsJson) {
    return ($info | ConvertTo-Json -Depth 3)
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Informacje o systemie Windows" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " System operacyjny : $($info.OSName)"
Write-Host " Wersja (Release)  : $($info.DisplayVersion)"
Write-Host " Identyfikator     : $($info.EditionID)"
Write-Host " Kompilacja (Build): $($info.BuildNumber)"
Write-Host " Architektura      : $($info.Architecture)"
Write-Host " Uprawnienia Admin : $(if ($info.IsAdmin) { 'TAK (Administrator)' } else { 'NIE (Użytkownik zwykły)' })" -ForegroundColor $(if ($info.IsAdmin) { 'Green' } else { 'Yellow' })
Write-Host "==================================================" -ForegroundColor Cyan

return $info
