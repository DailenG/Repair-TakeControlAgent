function Repair-TakeControlAgent {
    <#
    .SYNOPSIS
        Diagnoses, repairs, and reinstalls the N-able Take Control (N-central) Agent.
    
    .DESCRIPTION
        The Repair-TakeControlAgent tool is a robust recovery utility designed for MSP environments. 
        It addresses "Phantom Agent" scenarios where the service appears installed but fails to start.
    
        OPERATION MODES (-OperationMode):
        -------------------------------------------------------------------------
        * Audit          : Non-destructive health check, connectivity test, and log analysis.
        * Repair         : (Default) Smart repair. Reinstalls only if health check fails or config is corrupt.
        * ForceReinstall : Reinstalls regardless of state. Preserves config (MSPID) if valid.
        * CleanInstall   : "Scorched Earth". Wipes registry and files before fresh install.
        -------------------------------------------------------------------------
    
        Key Capabilities:
        1. Forensics: Detects missing binaries (AV Quarantine) & corrupt config (Zombie Agent).
        2. Provisioning: Waits for N-central to inject MSPID after restart.
        3. File Locking: Identifies security products (SentinelOne, Defender) locking files.
        4. Connectivity: Validates TCP/TLS connection to N-able global gateways.
    
    .PARAMETER OperationMode
        Selects the repair strategy. See DESCRIPTION for list.
    
    .PARAMETER TargetVersion
        Optional specific version (e.g., '6.00.00'). Defaults to latest manifest.
    
    .PARAMETER RestartNcentralAgent
        Restarts 'Windows Agent Service' AFTER successful install. 
        Recommended for 'ConfigCorrupt' scenarios to force ID reprovisioning.
    
    .NOTES
        SECURITY & APPLICATION CONTROL WARNING:
        ---------------------------------------
        This script downloads the installer to the user's %TEMP% directory.
        
        1. Blackpoint Cyber (SnapAgent): May classify the reinstall behavior as an unauthorized 
           RMM installation. 
        2. ThreatLocker / AppLocker: Will block execution from %TEMP% unless the 
           "N-able Technologies Ltd" certificate is whitelisted or the agent is in Learning Mode.
        
        Ensure your EDR/App Control is configured to allow this activity before running.
    
    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Audit', 'Repair', 'ForceReinstall', 'CleanInstall')]
        [string]$OperationMode = 'Repair',
    
        [Parameter(Mandatory = $false)]
        [string]$TargetVersion,
    
        [Parameter(Mandatory = $false)]
        [switch]$RestartNcentralAgent
    )
    
    # Ensure TLS 1.2 is enabled for current session (Vital for older OS/PS versions)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # Load Configuration
    $Config = Get-TakeControlConfig
    
    # --- Main Execution Block ---
    
    # SMART SILENCE: If non-interactive, suppress prompts.
    if ([Console]::IsOutputRedirected) {
        $PSDefaultParameterValues['*:Confirm'] = $false
    }
    
    if (-not (Test-TakeControlIsAdmin)) { Write-Error "Requires Administrator privileges."; exit 1 }
    
    Write-TakeControlLog -Message "Starting Take Control Maintenance. Mode: $OperationMode" -LogPath $Config.LogPath
    Write-TakeControlLog -Message "Log file: $($Config.LogPath)" -LogPath $Config.LogPath
    
    # LOCK FILE CHECK (Safety First)
    Test-TakeControlInstallLock -Config $Config
    
    try {
        $downloadUrl = Get-TakeControlDownloadUrl -Config $Config -TargetVersion $TargetVersion
        $webReq = Invoke-RestMethod -Uri $downloadUrl -ErrorAction Stop
    }
    catch {
        Write-TakeControlLog -Message "Failed to contact N-able CDN." -Level Error -LogPath $Config.LogPath
        exit 1
    }
    
    $initialHealth = Get-TakeControlAgentHealth -Config $Config # Standard check (VERBOSE)
    Write-Verbose "Initial Health State: $($initialHealth | Out-String)"
    
    if ($OperationMode -eq 'Audit') {
        Write-Host "--- Audit Report ---" -ForegroundColor Cyan
        $initialHealth | Format-List
        Test-TakeControlGatewayConnection -Config $Config
        Invoke-TakeControlLogAnalysis -Config $Config
        return
    }
    
    # Decision Matrix
    $needsAction = $false
    if ($OperationMode -in @('ForceReinstall', 'CleanInstall')) {
        $needsAction = $true
    }
    elseif (-not $initialHealth.ServicesRunning -or -not $initialHealth.SignatureValid -or $initialHealth.QuarantineSuspect -or $initialHealth.ConfigCorrupt) {
        Write-TakeControlLog -Message "Health check failed. Initiating repair." -Level Warning -LogPath $Config.LogPath
        $needsAction = $true
    }
    
    if (-not $needsAction) {
        Write-TakeControlLog -Message "Agent is healthy. No action required." -Level Success -LogPath $Config.LogPath
        return
    }
    
    # --- PROACTIVE RESTART PROMPT ---
    if ($initialHealth.ConfigCorrupt -and -not $RestartNcentralAgent) {
        Write-TakeControlLog -Message "DETECTION: Corrupt Configuration (Zombie Agent). Windows Agent Service (N-central) must be restarted to reprovision ID." -Level Warning -LogPath $Config.LogPath
        if ($PSCmdlet.ShouldProcess("Windows Agent Service (N-central)", "Enable Post-Install Restart to fix corruption")) {
            $RestartNcentralAgent = $true
            Write-TakeControlLog -Message "Windows Agent Service restart enabled." -Level Info -LogPath $Config.LogPath
        }
    }
    
    if ($PSCmdlet.ShouldProcess("Local Machine", "Install Take Control Agent")) {
        
        $tempInstaller = Join-Path $env:TEMP "TC_Installer_$(Get-Random).exe"
        try {
            # ASYNC DOWNLOAD: Using Start-Job to keep UI responsive for Animation.
            # Note: This has overhead but is required for the requested UX.
            # Since Start-Job creates a new process, we need to handle Download inside it carefully.
            # But wait, Start-Job doesn't inherit modules easily.
            # The original script used `Invoke-WebRequest` inside the job block.
            # It didn't depend on helpers.
            
            $job = Start-Job -ScriptBlock {
                param($Url, $Path)
                $ProgressPreference = 'SilentlyContinue'
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
            } -ArgumentList $webReq.url, $tempInstaller
    
            Wait-TakeControlAnimation -Activity "Downloading Installer" -TimeoutSeconds 300 -Condition {
                return ($job.State -ne 'Running')
            } -Config $Config | Out-Null
    
            $jobState = $job.State
            $jobError = Receive-Job -Job $job -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
            
            if ($jobState -ne 'Completed') { throw "Download job failed or timed out: $jobError" }
            if (-not (Test-Path $tempInstaller)) { throw "Installer missing after download." }
            if ((Get-FileHash $tempInstaller).Hash -ne $webReq.expected_hash) { throw "Hash mismatch" }
        }
        catch {
            Write-TakeControlLog -Message "Download failed: $_" -Level Error -LogPath $Config.LogPath
            exit 1
        }
    
        # CRITICAL: If config is corrupt, we MUST delete the file so installer/N-central can regenerate it.
        if ($initialHealth.ConfigCorrupt) {
            Write-TakeControlLog -Message "Detected Corrupt Configuration. Deleting BASupSrvc.ini..." -Level Warning -LogPath $Config.LogPath
            $badIni = Join-Path $env:ProgramData "GetSupportService_N-Central\BASupSrvc.ini"
            if (Test-Path $badIni) { 
                try { Remove-Item -Path $badIni -Force -ErrorAction Stop } 
                catch { Write-TakeControlLog -Message "Failed to delete corrupt INI: $_" -Level Error -LogPath $Config.LogPath }
            }
        }
    
        Invoke-TakeControlCleanup -Config $Config -OperationMode $OperationMode
    
        Wait-TakeControlAnimation -Activity "Installing Agent" -TimeoutSeconds 10 -Condition { $false } -Config $Config | Out-Null
        $exitCode = Invoke-TakeControlInstaller -InstallerPath $tempInstaller -Config $Config
        Remove-Item $tempInstaller -ErrorAction SilentlyContinue
    
        if ($exitCode -ne 0) { 
            Write-TakeControlLog -Message "Installer returned non-zero exit code: $exitCode" -Level Error -LogPath $Config.LogPath
        }
    }
    
    $success = Wait-TakeControlAnimation -Activity "Verifying Services" -TimeoutSeconds 60 -Condition {
        $running = (Get-Service -Name $Config.Services -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count
        return ($running -eq 2)
    } -Config $Config
    
    if ($success) {
        if ($RestartNcentralAgent) {
            Write-TakeControlLog -Message "Take Control Services are running. Restarting Windows Agent Service (N-central)..." -Level Info -LogPath $Config.LogPath
            try {
                Restart-Service -Name $Config.NcentralService -Force -ErrorAction Stop
                Write-TakeControlLog -Message "Windows Agent Service restarted successfully." -Level Success -LogPath $Config.LogPath
                
                # Wait for MSPID provisioning
                # UPDATED: Checks for either MSPID OR ServerUniqueID to prevent false wait loops
                $provisioned = Wait-TakeControlAnimation -Activity "Provisioning Configuration" -TimeoutSeconds 120 -Condition {
                    $iniPath = Join-Path $env:ProgramData "GetSupportService_N-Central\BASupSrvc.ini"
                    if (Test-Path $iniPath) {
                        $c = Get-Content $iniPath -Raw -ErrorAction SilentlyContinue
                        return (($c -match "(?ms)^\[Main\].*?^MSPID=[a-zA-Z0-9\-_]{10,}") -or ($c -match "(?ms)^\[Main\].*?^ServerUniqueID=[a-zA-Z0-9\-_]{10,}"))
                    }
                    return $false
                } -Config $Config
                
                if ($provisioned) {
                    Write-TakeControlLog -Message "Configuration successfully provisioned by N-central." -Level Success -LogPath $Config.LogPath
                }
                else {
                    Write-TakeControlLog -Message "Timed out waiting for Configuration (120s). It may appear after the next Agent check-in." -Level Warning -LogPath $Config.LogPath
                }
            }
            catch {
                Write-TakeControlLog -Message "Failed to restart N-central Agent: $_" -Level Error -LogPath $Config.LogPath
            }
        } 
        else {
            # Case: Services Repaired, but User declined Restart
            Write-TakeControlLog -Message "Take Control Services are running." -Level Success -LogPath $Config.LogPath
            
            $currentHealth = Get-TakeControlAgentHealth -Silent -Config $Config
            if ($currentHealth.ConfigCorrupt) {
                # FINAL UX: Explicit confirmation that the service is up but waiting on N-central
                Write-TakeControlLog -Message "SUCCESS: Services have been repaired and are running." -Level Success -LogPath $Config.LogPath
                Write-TakeControlLog -Message "NOTE: Configuration (MSPID) is currently pending." -Level Info -LogPath $Config.LogPath
                Write-TakeControlLog -Message "      The N-central 'Windows Agent Service' will automatically provision this during its next check-in (approx 10-15 mins)." -Level Info -LogPath $Config.LogPath
                Write-TakeControlLog -Message "      To force this immediately, you can restart the 'Windows Agent Service'." -Level Info -LogPath $Config.LogPath
            }
        }
    }
    else {
        Write-TakeControlLog -Message "Recovery Failed. Services did not start." -Level Error -LogPath $Config.LogPath
        Write-TakeControlLog -Message "Triggering Automatic Log Analysis..." -Level Warning -LogPath $Config.LogPath
        Invoke-TakeControlLogAnalysis -Config $Config
        
        $av = Get-TakeControlRunningAV -Config $Config
        if ($av) { 
            Write-TakeControlLog -Message "POSSIBLE CAUSE: Active Security Software ($av)" -Level Warning -LogPath $Config.LogPath
            if ($av -like "*SnapAgent*" -or $av -like "*ThreatLocker*" -or $av -like "*AEService*" -or $av -like "*AirlockEnforcement*") { Write-TakeControlLog -Message "Application Control Detected. Ensure RMM tools are whitelisted/learning mode is active." -Level Warning -LogPath $Config.LogPath }
        }
    }
    
    # Final Report (SILENT)
    $finalHealth = Get-TakeControlAgentHealth -Silent -Config $Config
    
    return [PSCustomObject]@{
        Timestamp         = Get-Date
        Operation         = $OperationMode
        Success           = $finalHealth.ServicesRunning
        ServicesUp        = $finalHealth.ServicesRunning
        QuarantineSuspect = $finalHealth.QuarantineSuspect
        ConfigCorrupt     = $finalHealth.ConfigCorrupt
        RestartedNcentral = $RestartNcentralAgent
        LogFile           = $Config.LogPath
    }
}
