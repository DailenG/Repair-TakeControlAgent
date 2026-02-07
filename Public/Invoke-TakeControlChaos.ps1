function Invoke-TakeControlChaos {
    <#
    .SYNOPSIS
        A "Chaos Monkey" script to break the Take Control agent for testing repair logic.
    
    .DESCRIPTION
        Deliberately induces failure states in the N-able Take Control installation to validate 
        recovery scripts. 
    
        AVAILABLE SCENARIOS (-Scenario):
        -------------------------------------------------------------------------
        * ZombieConfig  : Removes MSPID from BASupSrvc.ini (Simulates Orphaned Agent).
        * Quarantine    : Deletes binary but leaves service (Simulates AV Quarantine).
                          [!] High Risk - Requires -AllowDestruction.
        * BreakServices : Stops and Disables the Take Control services.
        * LockFile      : Spawns a hidden process locking the install folder.
                          [!] High Risk - Requires -AllowDestruction.
        * RestoreBinary : Restores the binary from .bak (Undo Quarantine).
        -------------------------------------------------------------------------
        
        WARNING: THIS IS DESTRUCTIVE.
        High-Risk scenarios mimic malware behavior and may trigger EDRs.
    
    .PARAMETER Scenario
        Selects the failure state to induce. See DESCRIPTION for list.
    
    .PARAMETER AllowDestruction
        Required ONLY for 'LockFile' and 'Quarantine' scenarios.
    
    .EXAMPLE
        Invoke-TakeControlChaos -Scenario ZombieConfig
        (Prompts for confirmation)
    
    .EXAMPLE
        Invoke-TakeControlChaos -Scenario LockFile -AllowDestruction
        (Prompts for confirmation AND checks for switch)
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ZombieConfig', 'Quarantine', 'BreakServices', 'LockFile', 'RestoreBinary')]
        [string]$Scenario,
    
        [Parameter(Mandatory = $false)]
        [switch]$AllowDestruction
    )
    
    # Configuration mapping (Matches Repair Script)
    $Config = Get-TakeControlConfig
    
    # --- Safety Checks ---
    if (-not (Test-TakeControlIsAdmin)) {
        Write-Error "Must run as Administrator."
        return
    }
    
    Write-TakeControlLog -Message "Starting Chaos Monkey - Scenario: $Scenario" -LogPath $Config.LogPath
    
    # --- Execution ---
    switch ($Scenario) {
        'ZombieConfig' {
            if ($PSCmdlet.ShouldProcess("BASupSrvc.ini", "Corrupt MSPID (Simulate Zombie)")) {
                if (Test-Path $Config.IniPath) {
                    Write-TakeControlLog -Message "Reading INI file..." -LogPath $Config.LogPath
                    $content = Get-Content $Config.IniPath -Raw
                    
                    if ($content -match "MSPID=") {
                        Write-TakeControlLog -Message "Removing MSPID to simulate Zombie state..." -LogPath $Config.LogPath
                        $newContent = $content -replace "MSPID=.*", "MSPID="
                        Set-Content -Path $Config.IniPath -Value $newContent -Force
                        Write-TakeControlLog -Message "Corruption applied. Agent is now orphaned." -Level Warning -LogPath $Config.LogPath
                    }
                    else {
                        Write-TakeControlLog -Message "MSPID not found or already empty." -Level Warning -LogPath $Config.LogPath
                    }
                }
                else {
                    Write-Error "INI file not found at $($Config.IniPath)"
                }
            }
        }
    
        'Quarantine' {
            # High Risk Check
            if (-not $AllowDestruction) {
                Write-Warning "Scenario 'Quarantine' manipulates trusted binaries and may trigger EDR heuristics."
                Write-Error "You must specify -AllowDestruction to proceed with this scenario."
                return
            }
    
            if ($PSCmdlet.ShouldProcess("BASupSrvc.exe", "Delete Binary (Simulate Quarantine)")) {
                $binPath = Join-Path $Config.AgentInstallPath $Config.Binary
                
                $Config.Services | ForEach-Object { Stop-Service $_ -Force -ErrorAction SilentlyContinue }
                
                if (Test-Path $binPath) {
                    Write-TakeControlLog -Message "Renaming binary to .bak to simulate AV quarantine..." -LogPath $Config.LogPath
                    Rename-Item -Path $binPath -NewName "$($Config.Binary).bak" -Force
                    Write-TakeControlLog -Message "Binary removed. Services are still registered." -Level Warning -LogPath $Config.LogPath
                }
                else {
                    Write-TakeControlLog -Message "Binary already missing." -LogPath $Config.LogPath
                }
            }
        }
    
        'BreakServices' {
            if ($PSCmdlet.ShouldProcess("Services", "Disable and Stop")) {
                foreach ($svc in $Config.Services) {
                    if (Get-Service $svc -ErrorAction SilentlyContinue) {
                        Write-TakeControlLog -Message "Breaking service: $svc" -LogPath $Config.LogPath
                        Stop-Service $svc -Force -ErrorAction SilentlyContinue
                        Set-Service $svc -StartupType Disabled
                    }
                }
                Write-TakeControlLog -Message "Services disabled and stopped." -Level Warning -LogPath $Config.LogPath
            }
        }
    
        'LockFile' {
            # High Risk Check
            if (-not $AllowDestruction) {
                Write-Warning "Scenario 'LockFile' uses encoded commands and background processes. This WILL trigger EDR heuristics."
                Write-Error "You must specify -AllowDestruction to proceed with this scenario."
                return
            }
    
            if ($PSCmdlet.ShouldProcess("File Lock", "Start Background PowerShell Process (HEURISTIC TRIGGER)")) {
                Write-Warning "Spawning hidden PowerShell process with -EncodedCommand."
                Write-Warning "This is a known IoC (Indicator of Compromise) for EDRs."
                
                $lockScript = @"
                `$path = '$($Config.AgentInstallPath)'
                `$file = Join-Path `$path 'locktest.dat'
                if (-not (Test-Path `$path)) { New-Item -ItemType Directory -Path `$path -Force }
                `$fs = [System.IO.File]::Open(`$file, 'OpenOrCreate', 'ReadWrite', 'None')
                Write-Host 'Locking ' `$file
                while (`$true) { Start-Sleep -Seconds 1 }
"@
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($lockScript))
                Start-Process PowerShell.exe -ArgumentList "-NoProfile -EncodedCommand $encoded" -WindowStyle Minimized
                
                Write-TakeControlLog -Message "Launched background process to lock folder: $($Config.AgentInstallPath)" -Level Warning -LogPath $Config.LogPath
                Write-TakeControlLog -Message "Run repair script to see if it kills the locker." -LogPath $Config.LogPath
            }
        }
    
        'RestoreBinary' {
            if ($PSCmdlet.ShouldProcess("BASupSrvc.exe", "Restore from .bak")) {
                $bak = Join-Path $Config.AgentInstallPath "$($Config.Binary).bak"
                if (Test-Path $bak) {
                    Rename-Item $bak -NewName $Config.Binary -Force
                    Write-TakeControlLog -Message "Binary restored." -Level Success -LogPath $Config.LogPath
                }
                else {
                    Write-TakeControlLog -Message "Backup file not found." -LogPath $Config.LogPath
                }
            }
        }
    }
}
