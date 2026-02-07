function Get-TakeControlRunningAV {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )
    # Checks for common EDR processes defined in Config
    $detected = @()
    foreach ($proc in $Config.SecurityProcesses) {
        if (Get-Process $proc -ErrorAction SilentlyContinue) { $detected += $proc }
    }
    return $detected -join ", "
}
