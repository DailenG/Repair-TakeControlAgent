function Invoke-TakeControlInstaller {
    [CmdletBinding()]
    param(
        [string]$InstallerPath,
        [hashtable]$Config
    )
    if (-not (Test-Path $InstallerPath)) { throw "Installer not found at $InstallerPath" }
    
    $mspIdArg = ""
    $iniPath = Join-Path $env:ProgramData "GetSupportService_N-Central\BASupSrvc.ini"
    
    # Only preserve MSPID if config is HEALTHY. If corrupt, we want installer to regenerate or stay empty.
    $health = Get-TakeControlAgentHealth -Silent -Config $Config
    if ($health.ConfigCorrupt) {
        Write-TakeControlLog -Message "Config Corrupt. Skipping MSPID preservation." -Level Warning -LogPath $Config.LogPath
    }
    elseif (Test-Path $iniPath) {
        $content = Get-Content $iniPath -Raw
        if ($content -match 'MSPID=(.+)') {
            $mspId = $matches[1].Trim()
            $mspIdArg = " /MSPID $mspId"
        }
    }

    $args = "/S /R /L=`"$($Config.InstallerLogPath)`"$mspIdArg"
    
    Write-TakeControlLog -Message "Executing Installer..." -LogPath $Config.LogPath
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList $args -Wait -PassThru -NoNewWindow
    
    return $proc.ExitCode
}
