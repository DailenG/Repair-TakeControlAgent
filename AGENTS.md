# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview
Repair-TakeControlAgent is a PowerShell module that diagnoses, repairs, and reinstalls the N-able Take Control (N-central) Agent. It addresses "Phantom Agent" scenarios where the service appears installed but fails to start or communicate. The module is published to the PowerShell Gallery.

## Common Development Commands

### Testing
Run Pester tests:
```powershell
Invoke-Pester -Path "C:\Code\GitHub\daileng\Repair-TakeControlAgent\Tests\Repair-TakeControlAgent.Tests.ps1"
```

Run crash diagnostic on a machine (standalone, no module required):
```powershell
.\Test-CrashDiagnostic.ps1
```

### Module Development
Import the module during development:
```powershell
Import-Module "C:\Code\GitHub\daileng\Repair-TakeControlAgent\Repair-TakeControlAgent.psd1" -Force
```

Test the repair function in audit mode (non-destructive):
```powershell
Repair-TakeControlAgent -OperationMode Audit
```

Test chaos engineering scenarios:
```powershell
Invoke-TakeControlChaos -Scenario ZombieConfig
Invoke-TakeControlChaos -Scenario BreakServices
```

### Publishing
Publish to PowerShell Gallery:
```powershell
.\publish.ps1 -ApiKey <YourApiKey>
```

## Architecture

### Module Structure
The module follows standard PowerShell module conventions:
- **Repair-TakeControlAgent.psm1**: Root module that dot-sources all functions from Public/ and Private/ directories
- **Repair-TakeControlAgent.psd1**: Module manifest defining metadata, version (currently 1.0.5), and exported functions
- **Public/**: Contains the two exported functions (Repair-TakeControlAgent, Invoke-TakeControlChaos)
- **Private/**: Contains 13 internal helper functions not exposed to users
- **Tests/**: Contains Pester tests

### Core Workflow
The repair process follows this pattern:
1. **Health Check** (Get-TakeControlAgentHealth): Performs forensic analysis detecting:
   - Missing binaries (AV quarantine)
   - Corrupt configuration files (Zombie Agent)
   - Service states
   - File signature validation
   - Disk space availability
   - Security product interference
2. **Decision Matrix**: Determines if action is needed based on OperationMode and health status
3. **Cleanup** (Invoke-TakeControlCleanup): Stops services, kills processes, removes registry keys, optionally wipes files
4. **Download**: Asynchronously downloads installer from N-able CDN with visual animation
5. **Installation** (Invoke-TakeControlInstaller): Executes silent installer with preserved MSPID if config is healthy
6. **Verification**: Waits for services to start with timeout-based polling
7. **Provisioning**: Optionally restarts N-central Agent to force configuration reprovisioning

### Key Architectural Patterns

#### Configuration-Driven Design
Get-TakeControlConfig returns a hashtable containing all paths, service names, registry locations, and security product process names. This config is passed to all private functions, making paths and settings centralized.

#### Async UX Pattern
Long-running operations (downloads, service verification) use Start-Job for async execution combined with Wait-TakeControlAnimation, which provides a KITT Scanner visual feedback. The animation automatically falls back to simple logging in headless/RMM environments (detected via [Console]::IsOutputRedirected).

#### Forensic Detection States
The health check detects multiple failure scenarios:
- **Quarantine**: Services registered but binary missing (AV removed executable)
- **Zombie Agent**: INI file exists but lacks valid MSPID or ServerUniqueID
- **Config Corrupt**: Configuration file is malformed or incomplete
- **File Lock**: Security products (SentinelOne, Defender, ThreatLocker) holding file locks
- **Crash History**: Access violations and runtime crashes detected in Windows Event Log (Application Error events) for BASupSrvc.exe and BASupSrvCnfg.exe within the last 7 days

#### Logging Strategy
Write-TakeControlLog function handles all output with severity levels (Info, Warning, Error, Success). Logs are timestamped and written to %TEMP% with format: TakeControl_Recovery_YYYYMMDD-HHmm.log

#### Security & EDR Awareness
The module explicitly handles:
- Application control products (ThreatLocker, AppLocker)
- RMM interference detection (Blackpoint SnapAgent)
- Code signature validation (expects "CN=N-ABLE TECHNOLOGIES LTD")
- Installer is downloaded to %TEMP% which may trigger security alerts

### Integration Points
- **N-central Agent Service**: "Windows Agent Service" - restarted to force configuration reprovisioning
- **Config File**: %ProgramData%\GetSupportService_N-Central\BASupSrvc.ini - contains MSPID and ServerUniqueID
- **CDN Manifest**: https://swi-rc.cdn-sw.net/n-central/updates/json/TakeControlCheckAndReinstall.json
- **Gateway Connectivity**: gw-tcp-test.global.mspa.n-able.com - used for connectivity testing

### Operation Modes
- **Audit**: Read-only health check, log analysis, and gateway connectivity test
- **Repair** (default): Smart repair that only reinstalls if health check fails
- **ForceReinstall**: Always reinstalls but preserves MSPID if config is valid
- **CleanInstall**: Scorched earth - wipes registry and files before fresh install

## Important Notes
- This module requires Administrator privileges (validated via Test-TakeControlIsAdmin)
- Minimum requirement: PowerShell 5.1
- TLS 1.2 is explicitly enabled at runtime for compatibility with older systems
- The module uses ShouldProcess for all destructive operations
- In non-interactive mode ([Console]::IsOutputRedirected), confirmation prompts are automatically suppressed
- Chaos Monkey (Invoke-TakeControlChaos) deliberately breaks the agent for testing - scenarios marked as destructive require -AllowDestruction switch
