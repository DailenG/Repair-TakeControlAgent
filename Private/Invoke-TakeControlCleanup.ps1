function Invoke-TakeControlCleanup {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [string]$OperationMode
    )
    Write-TakeControlLog -Message "Starting cleanup of existing agent..." -LogPath $Config.LogPath
    
    # 1. Graceful Stop
    $servicesToStop = Get-Service -Name $Config.Services -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Stopped' }
    if ($servicesToStop) {
        $servicesToStop | Stop-Service -Force -ErrorAction SilentlyContinue -NoWait
        Wait-TakeControlAnimation -Activity "Stopping Services" -TimeoutSeconds 30 -Condition {
            return ((Get-Service -Name $Config.Services -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count -eq 0)
        } -Config $Config | Out-Null
    }

    # 2. Force Kill
    foreach ($svcName in $Config.Services) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped') {
            Write-TakeControlLog -Message "Service $svcName stuck. Force Killing..." -Level Warning -LogPath $Config.LogPath
            # Use WMI to find PID because ServiceController in PS5.1 can be limited
            $proc = Get-CimInstance Win32_Service -Filter "Name='$svcName'" | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
            if ($proc) { Stop-Process -InputObject $proc -Force -ErrorAction SilentlyContinue }
        }
    }

    # 3. Registry Wipe
    if (Test-Path $Config.AgentRegPath) {
        try { Remove-Item -Path $Config.AgentRegPath -Recurse -Force -ErrorAction Stop } catch {}
    }

    # 4. File Wipe (Only in CleanInstall mode)
    if ($OperationMode -eq 'CleanInstall') {
        $folders = @($Config.AgentInstallPath, (Join-Path $env:ProgramData "GetSupportService_N-Central"))
        foreach ($folder in $folders) {
            if (Test-Path $folder) {
                try { Remove-Item $folder -Recurse -Force -ErrorAction Stop }
                catch [System.IO.IOException] {
                    $av = Get-TakeControlRunningAV -Config $Config
                    Write-TakeControlLog -Message "FILE LOCK DETECTED: Could not delete $folder. Active Security Tools: $av" -Level Warning -LogPath $Config.LogPath
                }
                catch {}
            }
        }
    }
}
