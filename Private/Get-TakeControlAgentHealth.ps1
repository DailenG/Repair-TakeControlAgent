function Get-TakeControlAgentHealth {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [switch]$Silent # Suppress warnings during Final Report
    )

    $status = [PSCustomObject]@{
        Installed         = $false
        ServicesRunning   = $false
        SignatureValid    = $false
        QuarantineSuspect = $false
        ConfigCorrupt     = $false
        ConfigLegacyWarn  = $false 
        NcentralConfig    = $false
        VulnerableDLL     = $false
        IntegrationMode   = "Unknown"
    }

    $binPath = Join-Path $Config.AgentInstallPath "BASupSrvc.exe"
    $servicesRegistered = (Get-Service -Name $Config.Services -ErrorAction SilentlyContinue).Count -eq 2
    $binaryExists = Test-Path $binPath

    # Forensic Check: Quarantine
    if ($servicesRegistered -and -not $binaryExists) {
        $status.QuarantineSuspect = $true
        if (-not $Silent) { Write-TakeControlLog -Message "DETECTION: Services are registered but binary is missing. Likely AV Quarantine." -Level Warning -LogPath $Config.LogPath }
    }

    if ($binaryExists) {
        $status.Installed = $true
        $status.SignatureValid = Test-TakeControlFileSignature -Path $binPath -Config $Config
    }

    $svcStatus = Get-Service -Name $Config.Services -ErrorAction SilentlyContinue
    if (($svcStatus | Where-Object { $_.Status -eq 'Running' }).Count -eq $Config.Services.Count) {
        $status.ServicesRunning = $true
    }

    # Forensic Check: Vulnerable DLL (CVE check from original script)
    $dllPath = Join-Path $Config.NcentralBin "RemoteControl.dll"
    if (Test-Path $dllPath) {
        $dllVer = [Version](Get-Item $dllPath).VersionInfo.FileVersion
        if ($dllVer -ge [Version]"2024.6.0.0" -and $dllVer -le [Version]"2024.6.0.22") {
            $status.VulnerableDLL = $true
            if (-not $Silent) { Write-TakeControlLog -Message "SECURITY: N-central RemoteControl.dll ($dllVer) is a known vulnerable version." -Level Warning -LogPath $Config.LogPath }
        }
    }

    # Forensic Check: N-central Integration Mode
    if (Test-Path $Config.NcentralConfig) {
        try {
            [xml]$xml = Get-Content $Config.NcentralConfig
            $val = $xml.RCConfig.mspa_install_check_intervall # (sic - n-able typo)
            $status.IntegrationMode = if ($val -le 0) { "Modern (v2)" } else { "Legacy (v1)" }
            if ($status.IntegrationMode -eq "Legacy (v1)" -and -not $Silent) {
                Write-TakeControlLog -Message "CONFIGURATION: N-central is using Legacy Integration (v1). This may cause reinstall loops." -Level Warning -LogPath $Config.LogPath
            }
        }
        catch {}
    }

    # Forensic Check: Config Corruption (Zombie Agent)
    $iniPath = Join-Path $env:ProgramData "GetSupportService_N-Central\BASupSrvc.ini"
    
    if (Test-Path $iniPath) {
        $status.NcentralConfig = $true
        try {
            $iniContent = Get-Content $iniPath -Raw
            
            $hasMspId = $iniContent -match "(?ms)^\[Main\].*?^MSPID=[a-zA-Z0-9\-_]{10,}"
            $hasServerUniqueId = $iniContent -match "(?ms)^\[Main\].*?^ServerUniqueID=[a-zA-Z0-9\-_]{10,}"

            if (-not $hasMspId -and -not $hasServerUniqueId) {
                # Case 1: Total Failure (Zombie) - Neither ID exists
                $status.ConfigCorrupt = $true
                if (-not $Silent) { Write-TakeControlLog -Message "DETECTION: BASupSrvc.ini is missing valid Identity (MSPID or ServerUniqueID). Agent is orphaned." -Level Warning -LogPath $Config.LogPath }
            }
            elseif (-not $hasMspId -and $hasServerUniqueId) {
                # Case 2: Modern State (Working, but INI incomplete)
                $status.ConfigLegacyWarn = $true
                if (-not $Silent) { Write-TakeControlLog -Message "ANALYSIS: Agent has valid ServerUniqueID but missing legacy MSPID. This is functional but indicates a recent repair." -Level Info -LogPath $Config.LogPath }
            }
        }
        catch {
            if (-not $Silent) { Write-TakeControlLog -Message "WARNING: Unable to read BASupSrvc.ini (Locked?). Assuming Config is OK if services are running." -Level Warning -LogPath $Config.LogPath }
        }
    } 
    elseif ($status.ServicesRunning) {
        if (-not $Silent) { Write-TakeControlLog -Message "WARNING: Services are running but BASupSrvc.ini is missing or inaccessible. Configuration state unknown." -Level Warning -LogPath $Config.LogPath }
    }

    return $status
}
