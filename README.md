# Repair-TakeControlAgent

A robust PowerShell module designed to diagnose, repair, and reinstall the N-able Take Control (N-central) Agent. This tool addresses "Phantom Agent" scenarios where the service appears installed but fails to start or communicate.

## Features

- **Health Check (Audit Mode)**: Non-destructive analysis of services, binaries, and logs.
- **Smart Repair**: Reinstalls the agent only if issues are detected.
- **Force Reinstall**: Overwrites the existing installation while preserving identity (MSPID).
- **Chaos Monkey**: Includes `Invoke-TakeControlChaos` to deliberately induce failure states for testing repair logic.

## Installation

```powershell
Install-Module -Name Repair-TakeControlAgent
```

## Usage

### Repair Agent (Default)
```powershell
Repair-TakeControlAgent
```

### Audit Only (No Changes)
```powershell
Repair-TakeControlAgent -OperationMode Audit
```

### Force Reinstall
```powershell
Repair-TakeControlAgent -OperationMode ForceReinstall
```

### Chaos Testing (Destructive)
```powershell
Invoke-TakeControlChaos -Scenario BreakServices
```

## Requirements

- Windows PowerShell 5.1 or later
- Administrator privileges

## License

MIT
