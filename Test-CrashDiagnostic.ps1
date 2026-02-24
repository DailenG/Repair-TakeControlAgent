<#
.SYNOPSIS
    Quick diagnostic script to detect BASupSrvCnfg.exe access violations.

.DESCRIPTION
    Run this script on the affected machine to check for crash evidence.
    This is a standalone diagnostic that doesn't require the full module.

.EXAMPLE
    .\Test-CrashDiagnostic.ps1
    
.EXAMPLE
    .\Test-CrashDiagnostic.ps1 -LookbackDays 14
#>

[CmdletBinding()]
param(
    [int]$LookbackDays = 7
)

$ErrorActionPreference = 'Continue'

Write-Host "`n=== Take Control Crash Diagnostic ===" -ForegroundColor Cyan
Write-Host "Scanning for crashes in the last $LookbackDays days...`n" -ForegroundColor Gray

$foundIssues = $false

# 1. Check Application Event Log
Write-Host "[1/4] Checking Application Event Log for crashes..." -ForegroundColor Yellow
try {
    $appErrors = Get-WinEvent -FilterHashtable @{
        LogName      = 'Application'
        ProviderName = 'Application Error', 'Windows Error Reporting'
        StartTime    = (Get-Date).AddDays(-$LookbackDays)
    } -ErrorAction SilentlyContinue | Where-Object { 
        $_.Message -match 'BASupSrv(c|Cnfg)\.exe' 
    }
    
    if ($appErrors) {
        $foundIssues = $true
        Write-Host "  [!] Found $($appErrors.Count) crash event(s)" -ForegroundColor Red
        
        foreach ($event in $appErrors | Select-Object -First 5) {
            Write-Host "  ---" -ForegroundColor DarkGray
            Write-Host "  Time: $($event.TimeCreated)" -ForegroundColor White
            
            # Extract key details
            if ($event.Message -match 'Faulting application name: ([^\s,]+)') {
                Write-Host "  App:  $($matches[1])" -ForegroundColor White
            }
            if ($event.Message -match 'exception code (0x[0-9a-fA-F]+)') {
                $exCode = $matches[1]
                Write-Host "  Code: $exCode" -ForegroundColor White
                if ($exCode -eq '0xc0000005') {
                    Write-Host "       ^^ ACCESS VIOLATION (Memory corruption)" -ForegroundColor Red
                }
            }
            if ($event.Message -match 'Faulting module name: ([^\s,]+)') {
                Write-Host "  Module: $($matches[1])" -ForegroundColor White
            }
            if ($event.Message -match 'Fault offset: (0x[0-9a-fA-F]+)') {
                Write-Host "  Offset: $($matches[1])" -ForegroundColor DarkGray
            }
        }
        
        if ($appErrors.Count -gt 5) {
            Write-Host "  ... and $($appErrors.Count - 5) more event(s)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  [✓] No crashes found in Application Event Log" -ForegroundColor Green
    }
}
catch {
    Write-Host "  [X] Could not access Application Event Log: $_" -ForegroundColor Red
}

# 2. Check for Crash Dumps
Write-Host "`n[2/4] Checking for crash dump files..." -ForegroundColor Yellow
try {
    $dumpPath = Join-Path $env:LOCALAPPDATA 'CrashDumps'
    if (Test-Path $dumpPath) {
        $dumps = Get-ChildItem $dumpPath -Filter "BASupSrv*.dmp" -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-$LookbackDays) }
        
        if ($dumps) {
            $foundIssues = $true
            Write-Host "  [!] Found $($dumps.Count) crash dump(s)" -ForegroundColor Red
            foreach ($dump in $dumps) {
                Write-Host "  - $($dump.Name) ($([math]::Round($dump.Length/1KB, 2)) KB) - $($dump.LastWriteTime)" -ForegroundColor White
            }
        }
        else {
            Write-Host "  [✓] No recent crash dumps found" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  [i] CrashDumps folder does not exist (normal if no crashes)" -ForegroundColor Gray
    }
}
catch {
    Write-Host "  [X] Could not check crash dumps: $_" -ForegroundColor Red
}

# 3. Check Binary Integrity
Write-Host "`n[3/4] Validating Take Control binaries..." -ForegroundColor Yellow
$is64Bit = [Environment]::Is64BitOperatingSystem
$pf = if ($is64Bit) { ${Env:ProgramFiles(x86)} } else { ${Env:ProgramFiles} }
$installPath = "$pf\Beanywhere Support Express\GetSupportService_N-central"

$binaries = @(
    (Join-Path $installPath 'BASupSrvc.exe'),
    (Join-Path $installPath 'BASupSrvCnfg.exe')
)

foreach ($binPath in $binaries) {
    $binName = [System.IO.Path]::GetFileName($binPath)
    
    if (Test-Path $binPath) {
        $fileInfo = Get-Item $binPath
        Write-Host "  Checking $binName..." -ForegroundColor Gray
        
        # Size check
        if ($fileInfo.Length -lt 50KB) {
            $foundIssues = $true
            Write-Host "    [!] SUSPICIOUS SIZE: $([math]::Round($fileInfo.Length/1KB, 2)) KB (expected >50KB)" -ForegroundColor Red
        }
        else {
            Write-Host "    [✓] Size: $([math]::Round($fileInfo.Length/1KB, 2)) KB" -ForegroundColor Green
        }
        
        # Signature check
        try {
            $sig = Get-AuthenticodeSignature $binPath -ErrorAction Stop
            if ($sig.Status -ne 'Valid') {
                $foundIssues = $true
                Write-Host "    [!] SIGNATURE INVALID: $($sig.Status)" -ForegroundColor Red
            }
            else {
                Write-Host "    [✓] Signature: Valid ($($sig.SignerCertificate.Subject.Split(',')[0]))" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "    [X] Could not validate signature: $_" -ForegroundColor Red
        }
        
        # Version
        Write-Host "    [i] Version: $($fileInfo.VersionInfo.FileVersion)" -ForegroundColor Gray
    }
    else {
        if ($binName -eq 'BASupSrvc.exe') {
            $foundIssues = $true
            Write-Host "  [!] $binName NOT FOUND (Critical)" -ForegroundColor Red
        }
        else {
            Write-Host "  [!] $binName NOT FOUND" -ForegroundColor Yellow
        }
    }
}

# 4. Check Service Status
Write-Host "`n[4/4] Checking service status..." -ForegroundColor Yellow
$services = @('BASupportExpressStandaloneService_N_Central', 'BASupportExpressSrvcUpdater_N_Central')
foreach ($svcName in $services) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        $statusColor = if ($svc.Status -eq 'Running') { 'Green' } else { 'Yellow' }
        Write-Host "  $svcName : $($svc.Status)" -ForegroundColor $statusColor
    }
    else {
        Write-Host "  $svcName : NOT INSTALLED" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
if ($foundIssues) {
    Write-Host "ISSUES DETECTED: The Take Control agent has crash history or corruption." -ForegroundColor Red
    Write-Host "`nRECOMMENDATION: Run Repair-TakeControlAgent to reinstall the agent:" -ForegroundColor Yellow
    Write-Host "  Repair-TakeControlAgent -OperationMode ForceReinstall" -ForegroundColor White
}
else {
    Write-Host "No crash evidence found. The agent appears healthy." -ForegroundColor Green
    Write-Host "If you're seeing runtime errors, they may be transient or environment-specific." -ForegroundColor Gray
}

Write-Host ""
