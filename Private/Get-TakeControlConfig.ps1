function Get-TakeControlConfig {
    [CmdletBinding()]
    param()

    # Detect 32-bit vs 64-bit paths
    $is64Bit = [Environment]::Is64BitOperatingSystem
    $pf = if ($is64Bit) { ${Env:ProgramFiles(x86)} } else { ${Env:ProgramFiles} }
    
    # Global Configuration
    @{
        LogPath           = Join-Path $env:TEMP "TakeControl_Recovery_$(Get-Date -Format 'yyyyMMdd-HHmm').log"
        InstallerLogPath  = Join-Path $env:TEMP "TakeControl_Installer_$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
        
        AgentInstallPath  = "$pf\Beanywhere Support Express\GetSupportService_N-central"
        # 'Multiplicar Negocios' is a legacy vendor path required for the agent settings
        AgentRegPath      = if ($is64Bit) { "HKLM:\SOFTWARE\WOW6432Node\Multiplicar Negocios\BACE_N-Central\Settings" } else { "HKLM:\SOFTWARE\Multiplicar Negocios\BACE_N-Central\Settings" }
        
        ExpectedSubject   = "CN=N-ABLE TECHNOLOGIES LTD, O=N-ABLE TECHNOLOGIES LTD, L=Dundee, C=GB"
        Services          = @('BASupportExpressStandaloneService_N_Central', 'BASupportExpressSrvcUpdater_N_Central')
        ManifestUrl       = "https://swi-rc.cdn-sw.net/n-central/updates/json/TakeControlCheckAndReInstall.json"
        
        NcentralService   = "Windows Agent Service"
        NcentralLogPath   = "$pf\N-able Technologies\Windows Agent\log\agent.log"
        NcentralConfig    = "$pf\N-able Technologies\Windows Agent\config\RCConfig.xml"
        NcentralBin       = "$pf\N-able Technologies\Windows Agent\bin"
        
        # Security Products / EDRs / Application Control
        SecurityProcesses = @(
            'MsSense',              # Defender ATP
            'SentinelAgent',        # SentinelOne
            'CSFalconService',      # CrowdStrike
            'mcshield',             # McAfee
            'ekrn',                 # ESET
            'SnapAgent',            # Blackpoint Cyber
            'ThreatLockerService',  # ThreatLocker
            'ThreatLockerTray',
            'AEService',            # AutoElevate
            'AirlockEnforcement'    # Airlock Digital
        ) 
        
        # Connectivity Test Endpoints
        GatewayHost       = "gw-tcp-test.global.mspa.n-able.com"

        # Chaos Monkey Extra Fields (Derived for compatibility)
        IniPath           = Join-Path $env:ProgramData "GetSupportService_N-Central\BASupSrvc.ini"
        Binary            = "BASupSrvc.exe"
    }
}
