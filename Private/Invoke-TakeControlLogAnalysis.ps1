function Invoke-TakeControlLogAnalysis {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )
    Write-TakeControlLog -Message "Starting Diagnostic Log Analysis..." -Level Info -LogPath $Config.LogPath

    # System Log (SCM Errors)
    Write-TakeControlLog -Message "Scanning System Event Log for Service Failures (Last 24 Hours)..." -Level Info -LogPath $Config.LogPath
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Service Control Manager'; Level = 2; StartTime = (Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'BASupport' }

        if ($events) {
            foreach ($ev in $events | Select-Object -First 3) {
                Write-TakeControlLog -Message "EVENT LOG ERROR: $($ev.TimeCreated) - $($ev.Message)" -Level Diagnosis -LogPath $Config.LogPath
            }
        }
        else {
            Write-TakeControlLog -Message "No recent Service Control Manager errors found." -Level Info -LogPath $Config.LogPath
        }
    }
    catch {}

    # Application Log (Crashes)
    Write-TakeControlLog -Message "Scanning Application Event Log for App Crashes..." -Level Info -LogPath $Config.LogPath
    try {
        $appEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'; Level = 2; StartTime = (Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue | Where-Object { $_.Message -like "*BASupSrvc*" }

        if ($appEvents) {
            foreach ($ev in $appEvents | Select-Object -First 3) {
                Write-TakeControlLog -Message "APP CRASH DETECTED: $($ev.TimeCreated) - $($ev.Message)" -Level Diagnosis -LogPath $Config.LogPath
            }
        }
    }
    catch {}

    # Installer Logs
    if (Test-Path $Config.InstallerLogPath) {
        Write-TakeControlLog -Message "Scanning Installer Log..." -Level Info -LogPath $Config.LogPath
        $installErrors = Select-String -Path $Config.InstallerLogPath -Pattern "Error|Failed|Denied|Exit Code" -Context 0, 1
        if ($installErrors) {
            foreach ($err in $installErrors | Select-Object -Last 5) {
                Write-TakeControlLog -Message "INSTALLER LOG: $($err.Line.Trim())" -Level Diagnosis -LogPath $Config.LogPath
            }
        }
    }
}
