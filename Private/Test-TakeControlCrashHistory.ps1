function Test-TakeControlCrashHistory {
    <#
    .SYNOPSIS
        Detects application crashes and access violations in Take Control binaries.
    
    .DESCRIPTION
        Checks Windows Event Logs and crash dumps for evidence of Take Control 
        runtime failures, including access violations in BASupSrvCnfg.exe and BASupSrvc.exe.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [int]$LookbackDays = 7,
        [switch]$Silent
    )
    
    $crashDetected = $false
    $crashDetails = @()
    
    # 1. Check Application Event Log for Application Errors
    if (-not $Silent) { Write-TakeControlLog -Message "Scanning for Take Control crashes (Last $LookbackDays days)..." -Level Info -LogPath $Config.LogPath }
    
    try {
        $appErrors = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            ProviderName = 'Application Error', 'Windows Error Reporting'
            StartTime = (Get-Date).AddDays(-$LookbackDays)
        } -ErrorAction SilentlyContinue | Where-Object { 
            $_.Message -match 'BASupSrv(c|Cnfg)\.exe' 
        }
        
        if ($appErrors) {
            $crashDetected = $true
            foreach ($event in $appErrors | Select-Object -First 5) {
                $detail = [PSCustomObject]@{
                    Timestamp   = $event.TimeCreated
                    Source      = $event.ProviderName
                    EventID     = $event.Id
                    Message     = $event.Message
                    Type        = 'EventLog'
                }
                $crashDetails += $detail
                
                # Parse access violation details
                if ($event.Message -match 'exception code (0x[0-9a-fA-F]+)') {
                    $exCode = $matches[1]
                    if ($exCode -eq '0xc0000005') {
                        if (-not $Silent) { 
                            Write-TakeControlLog -Message "CRASH DETECTED: Access Violation ($exCode) at $($event.TimeCreated)" -Level Warning -LogPath $Config.LogPath 
                        }
                    }
                }
                
                if ($event.Message -match 'BASupSrvCnfg\.exe') {
                    if (-not $Silent) { 
                        Write-TakeControlLog -Message "DETECTION: BASupSrvCnfg.exe (Configuration Tool) crashed. This binary manages agent settings." -Level Warning -LogPath $Config.LogPath 
                    }
                }
            }
        }
    }
    catch {
        if (-not $Silent) { Write-TakeControlLog -Message "WARNING: Could not access Application Event Log: $_" -Level Warning -LogPath $Config.LogPath }
    }
    
    # 2. Check for Crash Dumps
    try {
        $dumpPath = Join-Path $env:LOCALAPPDATA 'CrashDumps'
        if (Test-Path $dumpPath) {
            $dumps = Get-ChildItem $dumpPath -Filter "BASupSrv*.dmp" -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-$LookbackDays) }
            
            if ($dumps) {
                $crashDetected = $true
                foreach ($dump in $dumps) {
                    $crashDetails += [PSCustomObject]@{
                        Timestamp = $dump.LastWriteTime
                        Source    = 'CrashDump'
                        EventID   = 0
                        Message   = "Crash dump found: $($dump.Name) ($([math]::Round($dump.Length/1KB, 2)) KB)"
                        Type      = 'DumpFile'
                    }
                }
                if (-not $Silent) { 
                    Write-TakeControlLog -Message "CRASH DUMP DETECTED: Found $($dumps.Count) dump file(s) in $dumpPath" -Level Warning -LogPath $Config.LogPath 
                }
            }
        }
    }
    catch {
        if (-not $Silent) { Write-TakeControlLog -Message "WARNING: Could not check crash dumps: $_" -Level Warning -LogPath $Config.LogPath }
    }
    
    # 3. Validate Critical Binaries
    $binaries = @(
        (Join-Path $Config.AgentInstallPath 'BASupSrvc.exe'),
        (Join-Path $Config.AgentInstallPath 'BASupSrvCnfg.exe')
    )
    
    foreach ($binPath in $binaries) {
        if (Test-Path $binPath) {
            $fileInfo = Get-Item $binPath
            
            # Check for suspiciously small file size (corruption indicator)
            if ($fileInfo.Length -lt 50KB) {
                $crashDetected = $true
                if (-not $Silent) { 
                    Write-TakeControlLog -Message "CORRUPTION SUSPECTED: $($fileInfo.Name) is only $([math]::Round($fileInfo.Length/1KB, 2)) KB (expected >50KB)" -Level Warning -LogPath $Config.LogPath 
                }
            }
            
            # Validate signature
            try {
                $sig = Get-AuthenticodeSignature $binPath -ErrorAction Stop
                if ($sig.Status -ne 'Valid') {
                    $crashDetected = $true
                    if (-not $Silent) { 
                        Write-TakeControlLog -Message "SIGNATURE INVALID: $($fileInfo.Name) signature status is '$($sig.Status)'" -Level Warning -LogPath $Config.LogPath 
                    }
                }
            }
            catch {
                if (-not $Silent) { Write-TakeControlLog -Message "WARNING: Could not validate signature for $($fileInfo.Name): $_" -Level Warning -LogPath $Config.LogPath }
            }
        }
        else {
            # Binary missing entirely
            if ($binPath -like '*BASupSrvc.exe') {
                # BASupSrvc.exe is critical and already checked elsewhere
                continue
            }
            if (-not $Silent) { 
                Write-TakeControlLog -Message "MISSING BINARY: $([System.IO.Path]::GetFileName($binPath)) not found" -Level Warning -LogPath $Config.LogPath 
            }
        }
    }
    
    return [PSCustomObject]@{
        CrashDetected = $crashDetected
        CrashCount    = $crashDetails.Count
        Details       = $crashDetails
    }
}
