function Test-TakeControlInstallLock {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )
    # Check for __installing.lock files created by N-central auto-update
    # If < 10 mins old, we should abort to avoid collision
    $lockFile = Join-Path $Config.AgentInstallPath "__installing.lock"
    if (Test-Path $lockFile) {
        $lastWrite = (Get-Item $lockFile).LastWriteTime
        if ((Get-Date).AddMinutes(-10) -lt $lastWrite) {
            Write-TakeControlLog -Message "CRITICAL: Installation Lock File detected ($lastWrite). N-central is actively updating the agent." -Level Error -LogPath $Config.LogPath
            Write-TakeControlLog -Message "Aborting repair to prevent corruption. Please retry in 10 minutes." -Level Error -LogPath $Config.LogPath
            exit 1
        }
    }
}
