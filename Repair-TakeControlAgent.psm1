
# Get public and private function paths
$Public = Get-ChildItem -Path $PSScriptRoot\Public\*.ps1
$Private = Get-ChildItem -Path $PSScriptRoot\Private\*.ps1

# Dot source the files
foreach ($import in @($Public + $Private)) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error "Failed to import function $($import.Name): $_"
    }
}

Export-ModuleMember -Function $Public.BaseName
