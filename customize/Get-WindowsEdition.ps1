<#
.SYNOPSIS
  Rozpoznaje edycję i build działającego Windows.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RunningWindowsEdition {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $caption = [string]$os.Caption
    $build = [string]$os.BuildNumber
    $version = [string]$os.Version

    $editionId = $null
    try {
        $editionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -ErrorAction Stop).EditionID
    }
    catch {
        Write-Warning "Nie udało się odczytać EditionID z rejestru: $($_.Exception.Message)"
    }

    $productName = $null
    try {
        $productName = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'ProductName' -ErrorAction Stop).ProductName
    }
    catch {
        # opcjonalne
    }

    [pscustomobject]@{
        Caption     = $caption
        ProductName = $productName
        EditionID   = $editionId
        BuildNumber = $build
        Version     = $version
    }
}

$result = Get-RunningWindowsEdition
$result | Format-List | Out-String | Write-Host
return $result
