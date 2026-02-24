<#
.SYNOPSIS
    Publishes the Repair-TakeControlAgent module to the PowerShell Gallery.

.PARAMETER ApiKey
    The NuGet API Key for the PowerShell Gallery. Required.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApiKey
)

$ErrorActionPreference = 'Stop'
$moduleName = "Repair-TakeControlAgent"
$modulePath = $PSScriptRoot

Write-Host "Starting publication process for '$moduleName'..." -ForegroundColor Cyan

try {
    Write-Host "Publishing module to PowerShell Gallery..." -ForegroundColor Cyan
    Publish-Module -Path $modulePath -NuGetApiKey $ApiKey -Verbose
    Write-Host "Successfully published $moduleName!" -ForegroundColor Green
}
catch {
    Write-Error "Publishing failed: $_"
}
